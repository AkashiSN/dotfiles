# .zshrc

# in ~/.zshenv, executed `unsetopt GLOBAL_RCS` and ignored /etc/zshrc
if [[ "$(uname)" == "Darwin" ]]; then
  [ -r /etc/zshrc ] && . /etc/zshrc
fi

# -------------------------------------
# zshのオプション
# -------------------------------------

export TERM=xterm-256color # 色空間
export WORDCHARS="*?_-.[]~=&;!#$%^(){}<>" # 区切り文字

autoload bashcompinit && bashcompinit
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
# Base PATH
# -------------------------------------

export LOCAL_PREFIX=$HOME/.local
export MANPATH=$LOCAL_PREFIX/share/man:$MANPATH
export INFOPATH=$LOCAL_PREFIX/share/info:$INFOPATH
export LD_LIBRARY_PATH=$LOCAL_PREFIX/lib:$LD_LIBRARY_PATH
export LIBRARY_PATH=$LOCAL_PREFIX/lib:$LIBRARY_PATH
export PKG_CONFIG_PATH=$LOCAL_PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH
export C_INCLUDE_PATH=$LOCAL_PREFIX/include:$C_INCLUDE_PATH
export CPLUS_INCLUDE_PATH=$LOCAL_PREFIX/include:$CPLUS_INCLUDE_PATH
export PATH=$LOCAL_PREFIX/bin:$PATH
export PASSWORD_STORE_DIR=$HOME/.password-store


# -------------------------------------
# Load profile
# -------------------------------------

if [ -d /etc/profile.d ]; then
  for i in /etc/profile.d/*.sh ; do
    [ -r $i ] && source $i
  done
fi


# -------------------------------------
# Zinit setting
# -------------------------------------

if [[ ! -f $HOME/.zinit/bin/zinit.zsh ]]; then
  print -P "%F{33}▓▒░ %F{220}Installing %F{33}DHARMA%F{220} Initiative Plugin Manager (%F{33}zdharma/zinit%F{220})…%f"
  command mkdir -p "$HOME/.zinit" && command chmod g-rwX "$HOME/.zinit"
  command git clone https://github.com/zdharma-continuum/zinit "$HOME/.zinit/bin" && \
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

zinit ice blockf
zinit ice wait'!0'; zinit light zsh-users/zsh-completions


# -------------------------------------
# anyenv setting
# -------------------------------------

export ANYENV_ROOT="$HOME/.anyenv"
export PATH=$ANYENV_ROOT/bin:$PATH
eval "$(env PATH="$ANYENV_ROOT/libexec:$PATH" $ANYENV_ROOT/libexec/anyenv-init - --no-rehash)"


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
# aws cli
#-------------------------------------

if command -v aws_completer &> /dev/null ;then
  complete -C $(which aws_completer) aws
fi


#-------------------------------------
# tenv
#-------------------------------------

if command -v tenv &> /dev/null ;then
  source <(tenv completion zsh)
fi


#-------------------------------------
# terraform
#-------------------------------------

if command -v terraform &> /dev/null ;then
  complete -o nospace -C $(which terraform) terraform
  alias tf="terraform"
fi


#-------------------------------------
# opam
#-------------------------------------

if command -v opam &> /dev/null ;then
  eval $(opam env)
fi


#-------------------------------------
# kubectl
#-------------------------------------

if command -v mk &> /dev/null ;then
  source <(mk completion zsh | sed "s/kubectl/mk/g" | sed "s/__custom_func/__mk_custom_func/g")
  alias microk8s.kubectl=mk
fi

if command -v kubectl > /dev/null 2>&1;then
  source <(kubectl completion zsh)
  alias k="kubectl"
fi

if [[ "$(uname)" == "Linux" ]]; then
  alias docker="sudo docker"
  alias docker-compose="sudo docker compose"
  alias dc-down="sudo docker compose down -t 23"
  if command -v kind &> /dev/null ;then
    alias kind="sudo kind"
    alias kubectl="sudo kubectl"
    alias tkn="sudo tkn"
  fi
fi


#-------------------------------------
# Rancher Desktop
#-------------------------------------

export PATH=$HOME/.rd/bin:$PATH


# -------------------------------------
# Functions setting
# -------------------------------------

# build latex in docker
# https://hub.docker.com/r/akashisn/latexmk
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

function ytdlp () {
  yt-dlp --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36" \
    --referer "https://www.youtube.com/" \
    --extract-audio \
    --format "ba[ext=webm]" \
    --keep-video \
    --audio-format alac \
    --embed-thumbnail \
    --output "~/Music/Youtube/%(uploader)s/%(epoch)s-%(title)s.%(ext)s" $@
}

function extract-opus-from-webm () {
  # foobar2000 "Tagging" -> "Batch Attach Picture" -> `../Artwork/%filename%.png`
  mkdir -p ../Opus
  find -type f -name "*.webm" -print0 \
  | xargs -0 -I {} sh -c 'ffmpeg -y -i "$1" -vn -c:a copy "../Opus/$(basename -s .webm "$1").opus"' _ {}
}

function extract-artwork-from-m4a () {
  mkdir -p ../Artwork
  find -type f -name "*.m4a" -exec AtomicParsley '{}' -E \;
  find -type f -name "*_artwork_1*" -print0 \
  | xargs -0 -I {} sh -c 'mv -v "$1" "../Artwork/$(echo "$1" | sed -e "s/\(.*\)\_artwork_1.\(.*\)/\1\.\2/")"' _ {}
}

function post-process-for-ytdlp () {
  for dir in ~/Music/Youtube/* ;do
    (
      cd $dir
      pwd
      mkdir -p Original
      mkdir -p AAC
      mv *.webm Original/
      mv *.m4a AAC/

      cd Original
      extract-opus-from-webm
      cd ../AAC
      extract-artwork-from-m4a
      cd ..
    )
  done
}


# -------------------------------------
# Aliases setting
# -------------------------------------

case "$(uname)" in
Darwin)
  alias ls="ls -G"
  alias ll="ls -lG"
  alias la="ls -laG"
  alias brew="PATH=/opt/homebrew/bin:/usr/local/sbin:/usr/local/bin:/sbin:/usr/sbin:/bin:/usr/bin brew"
  export PATH_TO_FX="/Library/Java/JavaVirtualMachines/javafx-sdk/lib"
  ;;
Linux)
  alias ls='ls --color=auto'
  alias ll='ls -alF'
  alias la='ls -A'
  alias l='ls -CF'
  alias ffmpeg-qsv="sudo env PATH=$HOME/.local/bin:$PATH env LD_LIBRARY_PATH=$HOME/.local/lib:$LD_LIBRARY_PATH env LIBVA_DRIVERS_PATH=$HOME/.local/lib env LIBVA_DRIVER_NAME=iHD ffmpeg"
  export PATH_TO_FX="/usr/share/openjfx/lib"
  ;;
esac

alias rsync="rsync -azP"
alias conv-utf8='find . -type f -exec nkf --overwrite -w -Lu {} \;'


# -------------------------------------
# Other Path setting
# -------------------------------------

export PATH=$GOPATH/bin:$PATH
export FPATH=$LOCAL_PREFIX/share/zsh/site-functions:$FPATH


# -------------------------------------
#  WSL 用の調整
# -------------------------------------

if [[ "$(uname -r)" == *microsoft* ]]; then
  alias code="/mnt/c/Users/$(whoami)/AppData/Local/Programs/Microsoft\ VS\ Code/bin/code"
  unalias docker
  unalias docker-compose

  result=0
  # Yubikeyが接続されているか確認
  output=$(lsusb | grep -i Yubico 2>&1 > /dev/null) || result=$?
  if [ "$result" = "0" ]; then
    echo "Yubikey is connected. Checking if gpg-agent recognizes Yubikey."
    result=0
    # gpg-agentがYubikeyを認識しているか確認
    output=$(gpg --card-status 2>&1 > /dev/null) || result=$?
    if [ ! "$result" = "0" ]; then
      echo "gpg-agent is not recognizes Yubikey. Restarting pcscd..."
      sudo service pcscd restart
    fi
    echo "OK"
  else
    echo "Yubikey is not connected. Please connect your Yubikey."
  fi
fi


#--------------------------------------
# gpg agent
#--------------------------------------

if ! [ "$SSH_CONNECTION" ]; then
  if [ -n "`which gpg-agent 2> /dev/null`" ];then
    export GPG_TTY=$(tty)
    LANG=C gpg-connect-agent reloadagent /bye 2>&1 > /dev/null
    LANG=C gpg-connect-agent updatestartuptty /bye 2>&1 > /dev/null
    export SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"

    result=0
    # gpg-agentがYubikeyを認識しているか確認
    output=$(gpg --card-status 2>&1 > /dev/null) || result=$?
    if [ "$result" = "0" ]; then
      (
        output=$(ssh git@github.com 2>&1)
        if [[ $output == *"successfully authenticated"* ]]; then
          echo $output | sed -n -r -e "s/(Hi .* authenticated).*/\1./p"
          exit 0
        else
          exit 1
        fi
      ) || (
        output=$(ssh git@isec-github 2>&1)
        if [[ $output == *"successfully authenticated"* ]]; then
          echo $output | sed -n -r -e "s/(Hi .* authenticated).*/\1./p"
          exit 0
        else
          exit 1
        fi
      ) || true
    fi
  else
    echo "gpg-agent is not exists"
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
bindkey "^[[H"  beginning-of-line
bindkey "^[[3~" delete-char
bindkey "^[[F"  end-of-line

if [[ "$(uname)" != Darwin ]]; then
  if command -v xmodmap &> /dev/null ;then
    if [ -n "$DISPLAY" ]; then
      xmodmap $HOME/.Xmodmap
    fi
  fi
fi


# -------------------------------------
# 補完
# -------------------------------------

compinit -i # 補完を再読込
