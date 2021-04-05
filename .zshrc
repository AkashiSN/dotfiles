# .zshrc

# -------------------------------------
# zshのオプション
# -------------------------------------

export TERM=xterm-256color # 色空間
export WORDCHARS="*?_-.[]~=&;!#$%^(){}<>" # 区切り文字

autoload -Uz compinit && compinit # 補完機能を有効にして、実行する
autoload -Uz colors && colors # 色を有効にして、実行する

zstyle ':completion::complete:*' use-cache true # キャッシュの利用による補完の高速化
zstyle ':completion:*:default' menu select=1 # 補完候補をハイライト
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}' # 大文字、小文字を区別せず補完する
zstyle ':completion:*' list-colors "${LS_COLORS}" # 補完候補に色つける
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([%0-9]#)*=0=01;31' # kill の候補にも色付き表示
zstyle ':completion:*:sudo:*' command-path /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin /usr/X11R6/bin # コマンドにsudoを付けても補完
zstyle ':completion:*:cd:*' ignore-parents parent pwd # ディレクトリスタックの補完をする

LISTMAX=1000 # 補完リストが多いときに尋ねない
DIRSTACKSIZE=100 # ディレクトリスタックの最大サイズ

setopt AUTO_MENU # タブキーの連打で自動的にメニュー補完
setopt AUTO_LIST # 曖昧な補完で、自動的に選択肢をリストアップ
setopt AUTO_PARAM_KEYS # 変数名を補完する
setopt PROMPT_SUBST # プロンプト文字列で各種展開を行なう
setopt AUTO_RESUME # サスペンド中のプロセスと同じコマンド名を実行した場合はリジュームする
setopt RM_STAR_SILENT # rm *で確認を求める機能を無効化する
setopt MARK_DIRS # ファイル名の展開でディレクトリにマッチした場合 末尾に / を付加
setopt list_types # 補完候補一覧でファイルの種別を識別マーク表示(ls -F の記号)
setopt NO_BEEP #BEEPを鳴らさない
setopt ALWAYS_LAST_PROMPT # 補完候補など表示する時はその場に表示し、終了時に画面から消す
setopt AUTO_PARAM_SLASH # ディレクトリ名を補完すると、末尾に / を付加
setopt AUTO_PUSHD # 普通のcdでもディレクトリスタックに入れる
setopt PUSHD_IGNORE_DUPS # ディレクトリスタックに、同じディレクトリを入れない
setopt LIST_PACKED # 補完候補を詰めて表示
unsetopt CORRECT # コマンドのスペルの訂正を使用しない
setopt NOTIFY # ジョブの状態をただちに知らせる
setopt MULTIOS # 複数のリダイレクトやパイプに対応
setopt NUMERIC_GLOB_SORT # ファイル名を数値的にソート
setopt MAGIC_EQUAL_SUBST # =以降でも補完できるようにする
setopt PRINT_EIGHT_BIT # 補完候補リストの日本語を正しく表示
setopt BRACE_CCL # echo {a-z}などを使えるようにする
setopt HIST_IGNORE_SPACE # 余分な空白は詰めて記録
setopt APPEND_HISTORY # ヒストリファイルを上書きするのではなく、追加するようにする
setopt EXTENDED_HISTORY # ヒストリに時刻情報もつける
setopt HIST_EXPIRE_DUPS_FIRST # 履歴がいっぱいの時は最も古いものを先ず削除
setopt HIST_FIND_NO_DUPS #履歴検索中、重複を飛ばす
setopt HIST_NO_FUNCTIONS # ヒストリリストから関数定義を除く
setopt HIST_IGNORE_DUPS # 前のコマンドと同じならヒストリに入れない
setopt HIST_IGNORE_ALL_DUPS # 重複するヒストリを持たない
setopt INC_APPEND_HISTORY # 履歴をインクリメンタルに追加
setopt HIST_NO_STORE # history コマンドをヒストリに入れない
setopt HIST_REDUCE_BLANKS # 履歴から冗長な空白を除く
setopt SHARE_HISTORY # 履歴を共有
setopt HIST_SAVE_NO_DUPS # 古いコマンドと同じものは無視
setopt HIST_EXPAND # 補完時にヒストリを自動的に展開する
setopt NO_PROMPTCR # 改行コードで終らない出力もちゃんと出力する
setopt INTERACTIVE_COMMENTS # コマンドラインでも # 以降をコメントと見なす
setopt COMPLETE_IN_WORD # 語の途中でもカーソル位置で補完

HISTFILE=$HOME/.zsh_history  # ヒストリーファイルの設定
HISTSIZE=1000000 # ヒストリーサイズ設定
SAVEHIST=1000000 # ヒストリーサイズ設定

HISTTIMEFORMAT="[%Y/%M/%D %H:%M:%S] " # ヒストリの一覧を読みやすい形に変更


# -------------------------------------
# Zinit setting
# -------------------------------------

if [[ ! -f $HOME/.zinit/bin/zinit.zsh ]]; then
  print -P "%F{33}▓▒░ %F{220}Installing %F{33}DHARMA%F{220} Initiative Plugin Manager (%F{33}zdharma/zinit%F{220})…%f"
  command mkdir -p "$HOME/.zinit" && command chmod g-rwX "$HOME/.zinit"
  command git clone https://github.com/zdharma/zinit "$HOME/.zinit/bin" && \
    print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
    print -P "%F{160}▓▒░ The clone has failed.%f%b"
fi

source "$HOME/.zinit/bin/zinit.zsh"
autoload -Uz _zinit
(( ${+_comps} )) && _comps[zinit]=_zinit

zinit load momo-lab/zsh-abbrev-alias
zinit ice wait'!0'; zinit load zsh-users/zsh-syntax-highlighting

zinit ice compile'(pure|async).zsh' pick'async.zsh' src'pure.zsh'
zinit light sindresorhus/pure

zinit ice as "completion"; zinit snippet https://github.com/docker/cli/blob/master/contrib/completion/zsh/_docker
zinit ice as "completion"; zinit snippet https://github.com/docker/compose/blob/master/contrib/completion/zsh/_docker-compose

zinit ice blockf
zinit ice wait'!0'; zinit light zsh-users/zsh-completions
zinit ice wait'!0'; zinit load esc/conda-zsh-completion


# -------------------------------------
# anyenv setting
# -------------------------------------

export ANYENV_ROOT="$HOME/.anyenv"
export PATH=$ANYENV_ROOT/bin:$PATH
eval "$(env PATH="$ANYENV_ROOT/libexec:$PATH" $ANYENV_ROOT/libexec/anyenv-init - --no-rehash)"


# -------------------------------------
# Conda setting
# -------------------------------------

__conda_setup="$($PYENV_ROOT/versions/miniconda3-latest/bin/conda shell.zsh hook 2> /dev/null)"
if [ $? -eq 0 ]; then
  eval "$__conda_setup"
else
  if [ -f "$PYENV_ROOT/versions/miniconda3-latest/etc/profile.d/conda.sh" ]; then
    . "$PYENV_ROOT/versions/miniconda3-latest/etc/profile.d/conda.sh"
  else
    export PATH="$PYENV_ROOT/versions/miniconda3-latest/bin:$PATH"
  fi
fi
unset __conda_setup


# -------------------------------------
# Golang setting
# -------------------------------------

# Add GOPATH
export GOENV_DISABLE_GOPATH=1
export GOPATH=$HOME/Project

# Setting for peco
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


#-------------------------------------
# google cloud sdk
#-------------------------------------

if [ -f /usr/share/google-cloud-sdk/completion.zsh.inc ]; then
  source /usr/share/google-cloud-sdk/completion.zsh.inc
fi

if [ -f /opt/google-cloud-sdk/completion.zsh.inc ]; then
  export PATH=/opt/google-cloud-sdk/bin:$PATH
  source /opt/google-cloud-sdk/completion.zsh.inc
fi


#-------------------------------------
# terraform
#-------------------------------------

if [ -f $TFENV_ROOT/bin/terraform ]; then
  autoload -U +X bashcompinit && bashcompinit
  complete -o nospace -C $TFENV_ROOT/bin/terraform terraform
fi


# -------------------------------------
# Functions setting
# -------------------------------------

# build latex in docker
# https://hub.docker.com/r/arkark/latexmk
function latex () {
  docker run --rm -it --name="latexmk" -v `pwd`:/workdir arkark/latexmk:full latexmk-ext "$@"
}

function pdfcrop () {
  docker run --rm -it --name="pdfcrop" -v `pwd`:/workdir arkark/latexmk:full pdfcrop "$@"
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

# https://callanbryant.co.uk/blog/how-to-get-the-best-out-of-your-yubikey-with-gpg/#a-better-solution
# Add below into remote /etc/ssh/sshd_config
#
# StreamLocalBindUnlink yes
#
function gssh () {
  echo "Preparing host for forwarded GPG agent..." >&2
  # prepare remote for agent forwarding, get socket
  # Remove the socket in this pre-command as an alternative to requiring
  # StreamLocalBindUnlink to be set on the remote SSH server.
  # Find the path of the agent socket remotely to avoid manual configuration
  # client side. The location of the socket varies per version of GPG,
  # username, and host OS.
  remote_socket=$(cat <<'EOF' | command \ssh -T "$@" bash
    set -e
    socket=$(gpgconf --list-dirs agent-socket)
    # killing agent works over socket, which might be dangling, so time it out.
    timeout -k 2 1 gpgconf --kill gpg-agent || true
    test -S $socket && rm $socket
    echo $socket
EOF
)
  if [ ! $? -eq 0 ]; then
    echo "Problem with remote GPG. use ssh -A $@ for ssh with agent forwarding only." >&2
    return
  fi

  if [ "$SSH_CONNECTION" ]; then
    # agent on this host is forwarded, allow chaining
    local_socket=$(gpgconf --list-dirs agent-socket)
  else
    # agent on this host is running locally, use special remote socket
    local_socket=$(gpgconf --list-dirs agent-extra-socket)
  fi

  if [ ! -S $local_socket ]; then
    echo "Could not find suitable local GPG agent socket" 2>&1
    return
  fi

  echo "Connecting..." >&2
  tssh -A -R $remote_socket:$local_socket "$@"
}
compdef _ssh gssh=ssh

function qr () {
  qrencode -t ansiutf8 -r $@
}

function serial () {
  screen /dev/tty.usbserial-DN05LT6T 115200
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

function remove () {
  xargs sudo -u www-data rm
}

function move () {
  xargs -i sudo -u www-data mv {} $1
}

# -------------------------------------
# Aliases setting
# -------------------------------------

case "$(uname)" in
Darwin)
  alias ls="ls -G"
  alias ll="ls -lG"
  alias la="ls -laG"
  alias brew="PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin brew"
  export PATH_TO_FX="/Library/Java/JavaVirtualMachines/javafx-sdk/lib"
  ;;
Linux)
  alias ls='ls --color=auto'
  alias ll='ls -alF'
  alias la='ls -A'
  alias l='ls -CF'
  alias docker="sudo docker"
  alias docker-compose="sudo docker-compose"
  export PATH_TO_FX="/usr/share/openjfx/lib"
  ;;
esac

alias rsync="rsync -a -v --delete --progress"
alias conv-utf8='find . -type f -exec nkf --overwrite -w -Lu {} \;'
alias tf="terraform"


# -------------------------------------
# Other Path setting
# -------------------------------------

export MANPATH=$HOME/.local/share/man:$MANPATH
export INFOPATH=$HOME/.local/share/info:$INFOPATH
export LD_LIBRARY_PATH=$HOME/.local/lib:$LD_LIBRARY_PATH
export PATH=$HOME/.local/bin:$PATH
export PATH=$GOPATH/bin:$PATH
export FPATH=$HOME/.local/share/zsh/site-functions:$FPATH

# -------------------------------------
#  WSL 用の調整
# -------------------------------------

if [[ "$(uname -r)" == *microsoft* ]]; then
  export DISPLAY=$(awk '/nameserver / {print $2; exit}' /etc/resolv.conf 2>/dev/null):0
  alias javac="javac -p $PATH_TO_FX --add-modules javafx.controls,javafx.swing,javafx.base,javafx.fxml,javafx.media,javafx.web"
  alias java="java -p $PATH_TO_FX --add-modules javafx.controls,javafx.swing,javafx.base,javafx.fxml,javafx.media,javafx.web"
  alias code="~/winhome/AppData/Local/Programs/Microsoft\ VS\ Code/bin/code"

  gpg-agent-relay status > /dev/null || {
    gpg-agent-relay start
  }
fi


#--------------------------------------
# gpg agent
#--------------------------------------

if ! [ "$SSH_CONNECTION" ]; then
  local_socket=$(gpgconf --list-dirs agent-socket)
  if [ ! -S $local_socket ]; then
    gpg-connect-agent reloadagent /bye > /dev/null
  fi
  local_ssh_socket=$(gpgconf --list-dirs agent-ssh-socket)
  if [ -S $local_ssh_socket ]; then
    export SSH_AUTH_SOCK=$local_ssh_socket
  fi
fi


#--------------------------------------
# Auto compile
#--------------------------------------

if [ ! -f $HOME/.zshrc.zwc -o $HOME/.zshrc -nt $HOME/.zshrc.zwc ]; then
  print -P "%F{34}Recompile .zshrc%f%b"
  zcompile $HOME/.zshrc
fi


# -------------------------------------
# キーバインド
# -------------------------------------

# HOME, DELETE, ENDキーを有効にする
if [[ "$(uname)" == Darwin ]]; then
  bindkey "^[[H"  beginning-of-line
  bindkey "^[[3~" delete-char
  bindkey "^[[F"  end-of-line
else
  bindkey "^[[1~" beginning-of-line
  bindkey "^[[3~" delete-char
  bindkey "^[[4~" end-of-line
fi

if command -v xmodmap &> /dev/null ;then
  if [ -n "$DISPLAY" ]; then
    xmodmap $HOME/.Xmodmap
  fi
fi


# -------------------------------------
# 補完
# -------------------------------------

compinit -i # 補完を再読込
