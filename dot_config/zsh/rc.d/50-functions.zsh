# 50-functions.zsh — カスタム関数。

# ghq 管理リポジトリを peco で選んで cd（キー: C-]）
function peco-src () {
  local selected_dir=$(ghq list -p | peco --query "$LBUFFER")
  if [ -n "$selected_dir" ]; then
    BUFFER="cd ${selected_dir}"
    zle accept-line
  fi
  zle clear-screen
}
zle -N peco-src
bindkey '^]' peco-src

# build latex in docker — https://hub.docker.com/r/akashisn/latexmk
function latex () {
  docker run --rm -it --name="latexmk" -v `pwd`:/workdir akashisn/latexmk:2023 latexmk-ext "$@"
}

function pdfcrop () {
  docker run --rm -it --name="pdfcrop" -v `pwd`:/workdir akashisn/latexmk:2023 pdfcrop "$@"
}

# 端末のマウストラッキング / フォーカス報告 / 括弧付き貼り付け / 隠れカーソルを
# 無効化して復旧する。SSH 異常切断(client_loop: send disconnect: Broken pipe)で
# リモート tmux が有効化したマウス報告(SGR mouse mode)がローカル端末に居残り、
# クリックやスクロールで `0;129;39M` のような生エスケープが出て操作不能になる現象を
# 解消する。tssh から自動で呼ぶほか、素の ssh で踏んだときも手動で実行できる。
function term-reset () {
  print -n -- $'\e[?1000l\e[?1002l\e[?1003l\e[?1004l\e[?1005l\e[?1006l\e[?1015l\e[?2004l\e[?25h'
}

# ローカルから出る ssh を関数でラップし、戻り際に必ず term-reset する。リモートで
# ide(tmux)を起動したまま Broken pipe で切れると、リモート tmux が有効化した
# マウス報告の解除シーケンスがローカルに届かず端末が化けるため、ssh から戻った
# 時点でローカル側を強制復旧する。リモートシェル($SSH_CONNECTION あり)では多重
# ラップや tmux への余計な干渉を避けるため定義しない。
if [[ -z $SSH_CONNECTION ]]; then
  function ssh () {
    command ssh "$@"
    local r=$?
    term-reset
    return $r
  }
fi

function convert-crlf-to-lf () {
  find . -type f | xargs file | grep CRLF \
    | awk -F: '{print $1}' | xargs nkf -Lu --overwrite
}

function search () {
  local result="$(find . -type f)"
  for arg in "$@"; do
    result="$(echo "$result" | grep -i "$arg")"
  done
  IFS=$'\n'
  local results=($(echo "$result" ))
  for r in "${results[@]}"; do
    printf %q "$r"
    echo
  done
}

# nvim を VSCode ライクな IDE レイアウトで起動する。
# SSH 経由(かつ tmux 外)のときは tmux で包んで切断耐性を付ける。作業ディレクトリ
# 単位の固定名セッションにするので、切断後に同じ場所で再度 ide すれば生きている
# nvim にそのまま復帰できる(:q で終わればセッションも消える)。
function ide () {
  # ローカル / 既に tmux 内 / tmux 無し → 素の nvim
  if [[ -z $SSH_CONNECTION || -n $TMUX ]] || ! command -v tmux &>/dev/null; then
    NVIM_IDE=1 nvim "$@"
    return
  fi
  # SSH 経由 & tmux 外 → 作業ディレクトリ単位の tmux セッションで包む。
  local dir; [[ -n $1 && -d $1 ]] && dir=${1:A} || dir=$PWD
  local hash=$(print -n -- $dir | cksum | cut -d' ' -f1)
  local name=ide-${${dir:t}//[.:]/_}-$hash       # tmux 名に使えない . : を除去
  # nvim の RPC ソケット(決め打ち)。再アタッチ時に外から :IdeRelayout を叩くため。
  # SSH 先の /tmp に作る。hash 由来なので短く一意(ソケットパス長制限に安全)。
  local sock=/tmp/nvim-ide-${hash}.sock
  if tmux has-session -t "=$name" 2>/dev/null; then
    # 別サイズの端末から復帰するとレイアウトが崩れるので、attach 後に IDE レイアウトを
    # 現在の画面サイズで組み直す。attach は前景ブロッキングなので、先にバックグラウンドで
    # 遅延 RPC を仕込む。sleep は attach → tmux がセッションを新クライアントサイズへ
    # resize → nvim が新 columns/lines を受け取る、までの猶予(:IdeRelayout は実行時の
    # 現在サイズで判定する)。--remote-expr は RPC 評価なので nvim がどのモード(通常/端末)
    # でも入力を汚さず実行される。キーボード開閉等の resize は VimResized にしかならず
    # この経路を通らないので、iPad の狭画面フォールバックは従来どおり維持される。
    ( sleep 0.3; nvim --server "$sock" --remote-expr "execute('IdeRelayout')" ) >/dev/null 2>&1 &!
    tmux -2u attach -d -t "=$name"               # 既存セッションへ復帰(他端末から奪取)
  else
    command rm -f -- "$sock" 2>/dev/null          # 前回のクラッシュ等で残った stale ソケットを掃除
    local cmd="NVIM_IDE=1 nvim --listen ${(q)sock}" a
    for a in "$@"; do cmd+=" ${(q)a}"; done       # 引数を安全にクォートして渡す
    tmux -2u new-session -s $name -c $dir $cmd
  fi
}

# agmsg Codex monitor(beta): TUI 終了時に launcher だけが死に codex-bridge.js が
# 残る上流バグの掃除。launcher の生存 ⇔ Codex セッションの生存なので、live な
# launcher の引数にその project が現れない bridge=孤児だけを安全に kill する
# (起動中の別 Codex セッションの bridge は launcher が生きているので残す)。
# 詳細: ~/.local/share/chezmoi/docs/agmsg-cheatsheet.md「Codex monitor モード」。
function agmsg-bridge-reap () {
  local run_dir="$HOME/.agents/skills/agmsg/run"
  [[ -d $run_dir ]] || return 0
  local launchers
  launchers=$(pgrep -fl 'codex-bridge-launcher\.sh' 2>/dev/null)
  local pf bpid bargs bproj killed=0
  for pf in $run_dir/codex-bridge.*.pid(N); do
    bpid=$(<$pf 2>/dev/null)
    if [[ -z $bpid ]] || ! kill -0 $bpid 2>/dev/null; then
      rm -f $pf; continue   # pid 不明 / 既に死んだ pidfile を掃除
    fi
    bargs=$(ps -o args= -p $bpid 2>/dev/null)
    [[ $bargs == *codex-bridge.js* ]] || continue   # pid 再利用ガード
    bproj=${${bargs#*--project }%% --*}              # --project <path> を抽出
    [[ -n $bproj && $launchers == *$bproj* ]] && continue   # launcher 生存→残す
    kill $bpid 2>/dev/null && (( killed++ ))
    rm -f $pf
  done
  (( killed )) && print -ru2 -- "agmsg-bridge-reap: 孤児 bridge ${killed} 件を停止しました"
  return 0
}

# claude.ai 障害時などに Claude Code を Amazon Bedrock(グローバル推論プロファイル)へ
# 切り替えるための共通 env を「現在のシェル」へ export する内部ヘルパー。claude-bedrock /
# ide-bedrock から サブシェル内で呼ぶので、呼び出し元の対話シェルは汚さない(per-invocation)。
# 認証は aws-login(credential_process) + AWS_PROFILE を流用するため追加ログイン不要(トークン
# 期限切れも aws-login が自動更新)。Bedrock 側で対象モデルのアクセス権を有効化しておくこと。
# リージョン/モデルは CLAUDE_BEDROCK_* で上書き可能。AWS_REGION はグローバルプロファイルでも
# SigV4 署名用に具体リージョンが必要(ルーティングはグローバルプロファイルが自動で行う)。
# 認証情報が無ければ非ゼロで返し、呼び出し側を停止させる。
function _claude-bedrock-env () {
  if [[ -z $AWS_PROFILE && -z $AWS_ACCESS_KEY_ID ]]; then
    print -ru2 -- "claude-bedrock: AWS 認証情報が見当たりません。先に aws-switch でプロファイルを選択してください。"
    return 1
  fi
  export CLAUDE_CODE_USE_BEDROCK=1
  export CLAUDE_CODE_USE_MANTLE=1
  export AWS_REGION="${CLAUDE_BEDROCK_REGION:-us-east-1}"
  export ANTHROPIC_DEFAULT_OPUS_MODEL="${CLAUDE_BEDROCK_OPUS_MODEL:-global.anthropic.claude-opus-4-8[1m]}"
  export ANTHROPIC_DEFAULT_SONNET_MODEL="${CLAUDE_BEDROCK_SONNET_MODEL:-global.anthropic.claude-sonnet-5[1m]}"
  export ANTHROPIC_DEFAULT_HAIKU_MODEL="${CLAUDE_BEDROCK_HAIKU_MODEL:-global.anthropic.claude-haiku-4-5-20251001-v1:0}"
  export ANTHROPIC_MODEL="${ANTHROPIC_DEFAULT_OPUS_MODEL}"
}

# Claude Code 単体を Bedrock で起動する。通常の `claude` は claude.ai のまま無変更。
# サブシェルで env を閉じ込めるので、呼び出し後のシェルには設定が残らない。
# 詳細: ~/.local/share/chezmoi/docs/zsh-cheatsheet.md
function claude-bedrock () {
  ( _claude-bedrock-env && command claude "$@" )
}

# ide(nvim IDE レイアウト)を Bedrock 環境で起動する版。env を export してから ide を呼ぶので、
# nvim が継承し、IDE ペインの `zsh -ic claude` 子プロセスもそのまま Bedrock になる
# (ide.lua は NVIM_IDE のみ nil 化し、Claude 用 env は伝播させるため透過)。SSH 経由で tmux に
# 包む場合も new-session が現在の env を引き継ぐ。既存セッションへ復帰する場合は、その claude は
# 起動時の env のままなので、切り替えたいときはセッションを畳んで再度 ide-bedrock する。
function ide-bedrock () {
  ( _claude-bedrock-env && ide "$@" )
}

# ログイン(対話)シェル起動時に一度だけ、非ブロッキングで孤児 bridge を回収する。
[[ -d $HOME/.agents/skills/agmsg/run ]] && ( agmsg-bridge-reap & ) 2>/dev/null
