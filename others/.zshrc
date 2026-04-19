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
setopt NULL_GLOB # ワイルドカードをゼロ個の文字列として展開

HISTFILE=$HOME/.zsh_history  # ヒストリーファイルの設定
HISTSIZE=1000000 # ヒストリーサイズ設定
SAVEHIST=1000000 # ヒストリーサイズ設定

HISTTIMEFORMAT="[%Y/%M/%D %H:%M:%S] " # ヒストリの一覧を読みやすい形に変更


# -------------------------------------
# PATH Setting
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
export FPATH=$LOCAL_PREFIX/share/zsh/site-functions:$FPATH

mkdir -p ${LOCAL_PREFIX}/{share,lib,include,bin,share/zsh/site-functions}


# -------------------------------------
# Load profile
# -------------------------------------

if [ -d /etc/profile.d ]; then
  for i in /etc/profile.d/*.sh ; do
    [ -r $i ] && source $i
  done
fi


# -------------------------------------
# Load other scripts
# -------------------------------------

if [ -f /etc/zsh_command_not_found ]; then
  source /etc/zsh_command_not_found
fi


# -------------------------------------
# Zinit setting
# -------------------------------------

ZINIT_HOME="${HOME}/.local/share/zinit/zinit.git"
[ ! -d $ZINIT_HOME ] && mkdir -p "$(dirname $ZINIT_HOME)"
[ ! -d $ZINIT_HOME/.git ] && git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
source "${ZINIT_HOME}/zinit.zsh"

autoload -Uz _zinit
(( ${+_comps} )) && _comps[zinit]=_zinit

# Load powerlevel10k theme
zinit ice depth"1"
zinit light romkatv/powerlevel10k


#-------------------------------------
# Powerlevel10k
#-------------------------------------

if [[ -r "$HOME/.cache/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "$HOME/.cache/p10k-instant-prompt-${(%):-%n}.zsh"
fi

POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true

[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh


#-------------------------------------
# direnv
#-------------------------------------

if command -v direnv &> /dev/null ;then
  eval "$(direnv hook zsh)"
fi


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
export GHQ_ROOT=$GOPATH/src

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
  export TENV_AUTO_INSTALL=true
  export TENV_VALIDATION=sha
fi


#-------------------------------------
# terraform
#-------------------------------------

if command -v terraform &> /dev/null ;then
  complete -o nospace -C $(which terraform) terraform
  alias tf="terraform"
fi


#-------------------------------------
# kubectl
#-------------------------------------

if command -v kubectl > /dev/null 2>&1;then
  source <(kubectl completion zsh)
  alias k="kubectl"
fi


#-------------------------------------
# Rancher Desktop
#-------------------------------------

export PATH=$HOME/.rd/bin:$PATH


#-------------------------------------
# NodeJS (Yarn)
#-------------------------------------

export PATH=$HOME/.yarn/bin:$PATH


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


# -------------------------------------
# Download functions
# -------------------------------------

# Sets os_lower (linux|darwin), os_title (Linux|Darwin),
# arch_go (amd64|arm64), arch_x86 (x86_64|arm64) in the caller's scope.
function _download_platform () {
  case "$(uname -s)" in
    Linux)  os_lower=linux;  os_title=Linux  ;;
    Darwin) os_lower=darwin; os_title=Darwin ;;
    *) print -P "%F{red}Unsupported OS:%f $(uname -s)" >&2; return 1 ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64)  arch_go=amd64; arch_x86=x86_64 ;;
    arm64|aarch64) arch_go=arm64; arch_x86=arm64  ;;
    *) print -P "%F{red}Unsupported arch:%f $(uname -m)" >&2; return 1 ;;
  esac
}

function _download_header () {
  print -P "%F{34}==>%f %F{cyan}$1%f %F{yellow}v$2%f %F{244}(${os_lower}/${arch_go})%f"
}

function _download_step () {
  print -P "  %F{244}->%f $1"
}

function _download_done () {
  print -P "%F{34}==>%f %F{green}Done:%f $1"
}

function download-direnv () {
  local version=$1
  local os_lower os_title arch_go arch_x86
  _download_platform || return 1
  _download_header "direnv" "${version}"

  _download_step "Downloading binary"
  wget -q --show-progress -O ${LOCAL_PREFIX}/bin/direnv \
    https://github.com/direnv/direnv/releases/download/v${version}/direnv.${os_lower}-${arch_go} || return 1

  chmod +x ${LOCAL_PREFIX}/bin/direnv
  _download_done "${LOCAL_PREFIX}/bin/direnv"
}

function download-ghq () {
  local version=$1
  local os_lower os_title arch_go arch_x86
  _download_platform || return 1
  _download_header "ghq" "${version}"

  local archive=/tmp/ghq_${os_lower}_${arch_go}.zip
  local extracted=/tmp/ghq_${os_lower}_${arch_go}

  _download_step "Downloading ${archive:t}"
  wget -q --show-progress -O ${archive} \
    https://github.com/x-motemen/ghq/releases/download/v${version}/ghq_${os_lower}_${arch_go}.zip || return 1

  _download_step "Extracting"
  unzip -oq -d /tmp ${archive}

  _download_step "Installing binary and completion"
  cp ${extracted}/ghq ${LOCAL_PREFIX}/bin/
  cp ${extracted}/misc/zsh/_ghq ${LOCAL_PREFIX}/share/zsh/site-functions/

  rm -r ${extracted} ${archive}
  _download_done "${LOCAL_PREFIX}/bin/ghq"
}

function download-peco () {
  local version=$1
  local os_lower os_title arch_go arch_x86
  _download_platform || return 1
  _download_header "peco" "${version}"

  local archive=/tmp/peco_${os_lower}_${arch_go}.tar.gz
  local extracted=/tmp/peco_${os_lower}_${arch_go}

  _download_step "Downloading ${archive:t}"
  wget -q --show-progress -O ${archive} \
    https://github.com/peco/peco/releases/download/v${version}/peco_${os_lower}_${arch_go}.tar.gz || return 1

  _download_step "Extracting"
  tar -C /tmp -xf ${archive}

  _download_step "Installing binary"
  cp ${extracted}/peco ${LOCAL_PREFIX}/bin/

  rm -r ${extracted} ${archive}
  _download_done "${LOCAL_PREFIX}/bin/peco"
}

function download-tenv () {
  local version=$1
  local os_lower os_title arch_go arch_x86
  _download_platform || return 1
  _download_header "tenv" "${version}"

  local archive=/tmp/tenv_v${version}_${os_title}_${arch_x86}.tar.gz

  _download_step "Downloading ${archive:t}"
  wget -q --show-progress -O ${archive} \
    https://github.com/tofuutils/tenv/releases/download/v${version}/tenv_v${version}_${os_title}_${arch_x86}.tar.gz || return 1

  _download_step "Extracting to ${LOCAL_PREFIX}/share/tenv"
  mkdir -p ${LOCAL_PREFIX}/share/tenv
  tar -C ${LOCAL_PREFIX}/share/tenv -xf ${archive}

  _download_step "Linking tenv/terraform/tf into ${LOCAL_PREFIX}/bin"
  ln -snf ${LOCAL_PREFIX}/share/tenv/{tenv,terraform,tf} ${LOCAL_PREFIX}/bin

  rm ${archive}
  _download_done "${LOCAL_PREFIX}/bin/{tenv,terraform,tf}"
}

function download-tflint () {
  local version=$1
  local os_lower os_title arch_go arch_x86
  _download_platform || return 1
  _download_header "tflint" "${version}"

  local archive=/tmp/tflint_${os_lower}_${arch_go}.zip

  _download_step "Downloading ${archive:t}"
  wget -q --show-progress -O ${archive} \
    https://github.com/terraform-linters/tflint/releases/download/v${version}/tflint_${os_lower}_${arch_go}.zip || return 1

  _download_step "Extracting and installing"
  unzip -oq -d /tmp ${archive}
  cp /tmp/tflint ${LOCAL_PREFIX}/bin/

  rm /tmp/tflint ${archive}
  _download_done "${LOCAL_PREFIX}/bin/tflint"
}

function download-tflint-ruleset () {
  local ruleset=$1
  local version=$2
  local os_lower os_title arch_go arch_x86
  _download_platform || return 1
  _download_header "tflint-ruleset-${ruleset}" "${version}"

  local ruleset_path=$HOME/.tflint.d/plugins/github.com/terraform-linters/tflint-ruleset-${ruleset}/${version}
  local archive=/tmp/tflint-ruleset-${ruleset}_${os_lower}_${arch_go}.zip

  _download_step "Downloading ${archive:t}"
  wget -q --show-progress -O ${archive} \
    https://github.com/terraform-linters/tflint-ruleset-${ruleset}/releases/download/v${version}/tflint-ruleset-${ruleset}_${os_lower}_${arch_go}.zip || return 1

  _download_step "Installing to ${ruleset_path}"
  mkdir -p ${ruleset_path}
  unzip -oq -d ${ruleset_path} ${archive}

  rm ${archive}
  _download_done "${ruleset_path}"
}

function download-tfmigrate () {
  local version=$1
  local os_lower os_title arch_go arch_x86
  _download_platform || return 1
  _download_header "tfmigrate" "${version}"

  local archive=/tmp/tfmigrate_${version}_${os_lower}_${arch_go}.tar.gz

  _download_step "Downloading ${archive:t}"
  wget -q --show-progress -O ${archive} \
    https://github.com/minamijoyo/tfmigrate/releases/download/v${version}/tfmigrate_${version}_${os_lower}_${arch_go}.tar.gz || return 1

  _download_step "Extracting and installing"
  mkdir -p /tmp/tfmigrate
  tar -C /tmp/tfmigrate -xf ${archive}
  cp /tmp/tfmigrate/tfmigrate ${LOCAL_PREFIX}/bin

  rm -r /tmp/tfmigrate ${archive}
  _download_done "${LOCAL_PREFIX}/bin/tfmigrate"
}

function download-terraform-provider () {
  local provider=$1
  local version=$2
  local os_lower os_title arch_go arch_x86
  _download_platform || return 1
  _download_header "terraform-provider-${provider}" "${version}"

  local provider_path=$HOME/.terraform.d/plugins/registry.terraform.io/hashicorp/${provider}/${version}/${os_lower}_${arch_go}
  local archive=/tmp/terraform-provider-${provider}_${version}_${os_lower}_${arch_go}.zip

  _download_step "Downloading ${archive:t}"
  wget -q --show-progress -O ${archive} \
    https://releases.hashicorp.com/terraform-provider-${provider}/${version}/terraform-provider-${provider}_${version}_${os_lower}_${arch_go}.zip || return 1

  _download_step "Installing to ${provider_path}"
  mkdir -p ${provider_path}
  unzip -oq -d ${provider_path} ${archive}

  rm ${archive}
  _download_done "${provider_path}"
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


# -------------------------------------
# Other ENV setting
# -------------------------------------

export EDITOR=vim


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
# ssh agent
#--------------------------------------

if ! [ "$SSH_CONNECTION" ]; then
  if [ -S "${HOME}/.1password/agent.sock" ]; then
    export SSH_AUTH_SOCK="${HOME}/.1password/agent.sock"
  elif [ -n "`which gpg-agent 2> /dev/null`" ];then
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
      ) || true
    fi
  else
    echo "gpg-agent is not exists"
  fi
fi


# -------------------------------------
# Vault setting
# -------------------------------------
export PASSWORD_STORE_DIR=$HOME/.password-store
if [[ ! -d $PASSWORD_STORE_DIR ]]; then
	git clone git@github.com:AkashiSN/vault.git $PASSWORD_STORE_DIR || \
		print -P "%F{160}▓▒░ The clone has failed.%f%b"
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
