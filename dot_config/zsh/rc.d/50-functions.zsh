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

# agmsg Codex monitor(beta): orphan codex-bridge.js の掃除（.meta ベース）。
# 各 bridge は run/ に codex-bridge.<team>.<name>.{pid,meta,appserver,thread,log}
# を残し、.meta に pid= / project= / team= / name= / type= を記録する。live な
# launcher の引数に project が現れない bridge = 孤児だけを安全に kill する
# （起動中の別 Codex セッションの bridge は launcher が生きているので残す）。
function agmsg-bridge-reap () {
  local run_dir="$HOME/.agents/skills/agmsg/run"
  [[ -d $run_dir ]] || return 0
  local launchers
  launchers=$(pgrep -fl 'codex-bridge-launcher\.sh' 2>/dev/null)
  local mf line bpid bproj bargs base killed=0
  local reap_files
  for mf in $run_dir/codex-bridge.*.meta(N); do
    bpid="" bproj=""
    # .meta を key=value で読む（値にスペースを含む project パスも1行なので安全）
    while IFS= read -r line; do
      case $line in
        pid=*)     bpid=${line#pid=} ;;
        project=*) bproj=${line#project=} ;;
      esac
    done < $mf

    base=${mf%.meta}                                   # run/codex-bridge.<team>.<name>
    reap_files=( $base.pid $base.meta $base.appserver $base.thread $base.log )

    # pid 不明 / 既に死んでいる → sidecar ごと掃除
    if [[ -z $bpid ]] || ! kill -0 $bpid 2>/dev/null; then
      rm -f $reap_files; continue
    fi
    # pid 再利用ガード: 実体が codex-bridge.js でなければ触らない
    bargs=$(ps -o args= -p $bpid 2>/dev/null)
    [[ $bargs == *codex-bridge.js* ]] || continue
    # launcher 生存（= その project の Codex セッションが生きている）→ 残す
    [[ -n $bproj && $launchers == *$bproj* ]] && continue
    # 孤児: bridge を止めて sidecar も一緒に掃除
    kill $bpid 2>/dev/null && (( killed++ ))
    rm -f $reap_files
  done
  (( killed )) && print -ru2 -- "agmsg-bridge-reap: 孤児 bridge ${killed} 件を停止しました"
  return 0
}

# 対話シェルの `claude` を claude-wrapper へ渡す。Bedrock かどうかはそこがマーカー
# (~/.config/zsh/no-claude-bedrock) で決める: 無ければ claude-bedrock、有れば素のバイナリ
# (claude.ai 認証)。一度だけマーカーごと迂回したいときは `command claude`(関数ごと素通し
# するので下の --remote-control も付かない)。
#
# SSH 接続先で「引数なしの素の起動」のときだけ --remote-control を付け、claude.ai / モバイル
# 等のリモートからそのインタラクティブセッションを操作できるようにする(claude-bedrock を直接
# 叩く経路も同じ規則を持つ)。引数付き(プロンプト・-p/--print・mcp/update 等のサブコマンド・
# -c/--resume 等)は素通しする。セッション名プレフィックスは claude 既定でホスト名。
#
# 関数なので効くのは対話 zsh だけ。Claude Code 自身のシェル(CLAUDE_CODE_SHELL=/bin/bash)や
# 非対話シェルからの起動には届かない。VS Code 拡張は claudeProcessWrapper で同じ
# claude-wrapper を通す。
# 詳細: ~/.local/share/chezmoi/docs/zsh-cheatsheet.md
function claude () {
  if [[ -n $SSH_CONNECTION && $# -eq 0 ]]; then
    set -- --remote-control
  fi
  local wrapper=$HOME/.local/bin/claude-wrapper
  # ${commands[claude]} は PATH 上の実体(この関数ではなく外部コマンド)。
  if [[ -x $wrapper && -n ${commands[claude]} ]]; then
    $wrapper ${commands[claude]} "$@"
    return
  fi
  command claude "$@"
}

# 対話シェルの `codex` を codex-wrapper へ渡す。Bedrock かどうかはそこがマーカー
# (~/.config/zsh/no-codex-bedrock) で決める: 無ければ codex-bedrock、有れば素のバイナリ
# (OpenAI サブスク認証。その前に codex-appserver-evict で Bedrock 用 app-server を畳む)。
# 一度だけマーカーごと迂回したいときは `command codex`。agmsg で spawn する codex は
# codex-spawn が同じマーカーを見る。
function codex () {
  local wrapper=$HOME/.local/bin/codex-wrapper
  if [[ -x $wrapper ]]; then
    $wrapper "$@"
    return
  fi
  command codex "$@"
}

# 端末のマウストラッキング / フォーカス報告 / 括弧付き貼り付け / 隠れカーソル /
# Kitty keyboard protocol を無効化して端末状態を復旧する。リモート(herdr / ssh 先)で
# 起動した nvim 等が有効化した端末モードは、接続が異常切断(Broken pipe)されると解除
# シーケンスがローカルへ届かず居残り、次のような化けを起こす:
#   - マウス報告(SGR mouse mode)の残置 → クリック/スクロールで `0;129;39M` が出る
#   - Kitty keyboard protocol(CSI u)の残置 → キー入力で `15;1:3u` 等の生エスケープが出る
# 末尾の \e[<u は push 済みの Kitty keyboard スタックを pop、\e[=0;1u は現行フラグを
# 0 に強制してレガシーキー入力へ戻す(素の端末で叩いても空 pop / 既 0 set で無害)。
function term-reset () {
  print -n -- $'\e[?1000l\e[?1002l\e[?1003l\e[?1004l\e[?1005l\e[?1006l\e[?1015l\e[?2004l\e[?25h\e[<u\e[=0;1u'
}

# ローカルから出る herdr / ssh を関数でラップし、戻り際に必ず term-reset する。
# herdr --remote や ssh 先で起動した nvim 等が有効化した端末モードは、接続が異常切断
# されると解除シーケンスがローカルへ届かず端末が化けるため、戻った時点でローカル側を
# 強制復旧する。herdr は内部で自前の ssh を exec するので、ssh ラッパーだけでは
# herdr 経由の切断を拾えない(herdr 自体もラップする)。リモートシェル($SSH_CONNECTION
# あり)では多重ラップやリモートセッションへの干渉を避けるため定義しない。
if [[ -z $SSH_CONNECTION ]]; then
  function herdr () {
    command herdr "$@"
    local r=$?
    term-reset
    return $r
  }
  function ssh () {
    command ssh "$@"
    local r=$?
    term-reset
    return $r
  }
fi

# ログイン(対話)シェル起動時に一度だけ、非ブロッキングで孤児 bridge を回収する。
[[ -d $HOME/.agents/skills/agmsg/run ]] && ( agmsg-bridge-reap & ) 2>/dev/null
