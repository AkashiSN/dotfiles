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

function tssh () {
  $(cat <<'EOF' | command ssh -T "$@" bash &> /dev/null
    command -v tmux &> /dev/null
EOF
)
  if [ ! $? -eq 0 ]; then
    \ssh "$@"
  else
    \ssh -t "$@" "tmux -2u attach -d || tmux -2u"
  fi
}
compdef _ssh tssh=ssh

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
  if tmux has-session -t "=$name" 2>/dev/null; then
    tmux -2u attach -d -t "=$name"               # 既存セッションへ復帰(他端末から奪取)
  else
    local cmd="NVIM_IDE=1 nvim" a
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

# ログイン(対話)シェル起動時に一度だけ、非ブロッキングで孤児 bridge を回収する。
[[ -d $HOME/.agents/skills/agmsg/run ]] && ( agmsg-bridge-reap & ) 2>/dev/null
