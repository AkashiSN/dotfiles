# .zshrc

# {{{ Settings
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
setopt SH_WORD_SPLIT # クォートされていない変数拡張が行われたあとで、フィールド分割
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
# }}}

# {{{ Alias
case "${OSTYPE}" in
darwin*)
  alias ls="ls -G"
  alias ll="ls -lG"
  alias la="ls -laG"
  ;;
linux*)
  alias ls='ls --color=auto'
  alias ll='ls -alF'
  alias la='ls -A'
  alias l='ls -CF'
  ;;
esac

for i in /etc/profile.d/*.sh ; do
    [ -r $i ] && source $i
done
# }}}

# {{{ Zinit setting
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

zinit ice as"completion"
zinit snippet https://github.com/docker/cli/blob/master/contrib/completion/zsh/_docker
zinit snippet https://github.com/docker/compose/blob/master/contrib/completion/zsh/_docker-compose

zinit ice blockf
zinit light zsh-users/zsh-completions
# }}}

# {{{ anyenv
if [[ ! -f $HOME/.anyenv/bin/anyenv ]]; then
  print -P "%F{33}▓▒░ %F{220}Installing %F{33}anyenv%F{220} All in one for **env (%F{33}anyenv/anyenv%F{220})…%f"
  command git clone https://github.com/anyenv/anyenv "$HOME/.anyenv" && \
    print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
    print -P "%F{160}▓▒░ The clone has failed.%f%b"
  command mkdir -p $HOME/.anyenv/plugins
  command git clone https://github.com/znz/anyenv-update.git $HOME/.anyenv/plugins/anyenv-update && \
    print -P "%F{33}▓▒░ %F{34}Installation plugin anyenv-update successful.%f%b" || \
    print -P "%F{160}▓▒░ The clone has failed.%f%b"
  command git clone https://github.com/znz/anyenv-git.git $HOME/.anyenv/plugins/anyenv-git && \
    print -P "%F{33}▓▒░ %F{34}Installation plugin anyenv-git successful.%f%b" || \
    print -P "%F{160}▓▒░ The clone has failed.%f%b"
fi

# Initial setting of anyenv.
export PATH="$HOME/.anyenv/bin:$PATH"
export ANYENV_ROOT="$HOME/.anyenv"
eval "$(env PATH="$ANYENV_ROOT/libexec:$PATH" $ANYENV_ROOT/libexec/anyenv-init - --no-rehash)"
# }}}

# {{{ goenv
if [[ ! -f $HOME/.anyenv/envs/goenv/bin/goenv ]]; then
  print -P "%F{33}▓▒░ %F{220}Installing %F{33}goenv%F{220} Go Version Management (%F{33}syndbg/goenv%F{220})…%f"
  command anyenv install goenv && \
    print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
    print -P "%F{160}▓▒░ The clone has failed.%f%b"
  exec $SHELL -l
fi

# Add GOPATH
export GOENV_DISABLE_GOPATH=1
export GOPATH=$HOME/Project
export PATH=$PATH:$GOPATH/bin

# GHQ
if ! [[ -x $(command -v ghq) ]]; then
  command mkdir -p $GOPATH/bin
  command mkdir -p $GOPATH/src
  print -P "%F{33}▓▒░ %F{220}Installing %F{33}ghq%F{220} Manage remote repository clones (%F{33}x-motemen/ghq%F{220})…%f"
  if [[ "$OSTYPE" == "linux-gnu" ]]; then
    command curl -L -o /tmp/ghq.zip https://github.com/x-motemen/ghq/releases/latest/download/ghq_linux_amd64.zip
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    command curl -L -o /tmp/ghq.zip https://github.com/x-motemen/ghq/releases/latest/download/ghq_darwin_amd64.zip
  fi
  command unzip /tmp/ghq.zip -d /tmp/ && \
    mv /tmp/ghq_*/ghq $GOPATH/bin/ && \
    print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
    print -P "%F{160}▓▒░ The clone has failed.%f%b"
  git config --global ghq.root $GOPATH/src
fi

# Peco
if ! [[ -x $(command -v peco) ]]; then
  print -P "%F{33}▓▒░ %F{220}Installing %F{33}peco%F{220} Simplistic interactive filtering tool (%F{33}peco/peco%F{220})…%f"
  if [[ "$OSTYPE" == "linux-gnu" ]]; then
    command curl -L -o /tmp/peco.tar.gz https://github.com/peco/peco/releases/latest/download/peco_linux_amd64.tar.gz
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    command curl -L -o /tmp/peco.tar.gz https://github.com/peco/peco/releases/latest/download/peco_darwin_amd64.tar.gz
  fi
  command tar xzvf /tmp/peco.tar.gz -C /tmp && \
    mv /tmp/peco_*/peco $GOPATH/bin/ && \
    print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
    print -P "%F{160}▓▒░ The clone has failed.%f%b"
fi

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

# }}}

# {{{ zcompile
if [ ! -f $HOME/.zshrc.zwc -o $HOME/.zshrc -nt $HOME/.zshrc.zwc ]; then
   zcompile $HOME/.zshrc
fi
# }}}

# {{{ HOME, DELETE, ENDキーを有効にする
bindkey "^[[1~" beginning-of-line
bindkey "^[[3~" delete-char
bindkey "^[[4~" end-of-line
# }}}

# {{{
compinit -i # 補完を再読込
# }}}