# zshrc モジュール分割 + aqua ツール補完 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `dot_zshrc` を `~/.config/zsh/rc.d/*.zsh` の機能別モジュールに分割し、aqua 管理ツールの zsh 補完を fpath へ事前生成する。

**Architecture:** `dot_zshrc` を「rc.d を番号順に zcompile して source するローダー」に縮小。実体を 7 つのモジュールへ移動（順序依存: path→plugins(compinit)→tools）。補完は chezmoi の `run_onchange` スクリプトが aqua 更新時に `~/.local/share/zsh/site-functions/_<name>` を生成。

**Tech Stack:** zsh, chezmoi (source 命名規則 + run_onchange テンプレート), aqua, sheldon。

設計書: `docs/superpowers/specs/2026-06-15-zshrc-refactor-completions-design.md`

---

## ファイル構成

| ファイル | 役割 |
| --- | --- |
| `dot_zshrc` | ローダー（macOS /etc/zshrc → rc.d を zcompile+source → 自身を再コンパイル） |
| `dot_config/zsh/rc.d/00-options.zsh` | TERM/WORDCHARS, colors, setopt, HISTORY |
| `dot_config/zsh/rc.d/10-path.zsh` | PATH/FPATH/MANPATH 等, GOPATH, rancher/yarn, profile.d, command-not-found |
| `dot_config/zsh/rc.d/20-completion.zsh` | 補完 zstyle, fzf-tab スタイル, `_load_completion` ヘルパ |
| `dot_config/zsh/rc.d/30-plugins.zsh` | sheldon, starship, direnv, fnm |
| `dot_config/zsh/rc.d/40-tools.zsh` | fzf/gcloud/aws/tenv/terraform/kubectl 連携, ssh-agent |
| `dot_config/zsh/rc.d/50-functions.zsh` | peco-src, latex, pdfcrop, tssh, convert-crlf-to-lf, search, ide |
| `dot_config/zsh/rc.d/60-aliases.zsh` | OS 別 alias, EDITOR/VISUAL, WSL 調整 |
| `dot_config/zsh/rc.d/70-keybindings.zsh` | bindkey, xmodmap |
| `.chezmoiscripts/run_onchange_after_25-zsh-completions.sh.tmpl` | aqua ツールの fpath 補完生成 |
| `docs/zsh-cheatsheet.md` | ドキュメント更新 |

---

## Task 1: 作業ブランチと現状スナップショット

デフォルトブランチ(main)上のため作業ブランチを切り、リファクタ前の挙動を記録する（後で等価性検証に使う）。

**Files:**
- Create: `/tmp/zshrc-baseline.txt`（一時ファイル、コミットしない）

- [ ] **Step 1: 作業ブランチを作成**

```bash
cd ~/.local/share/chezmoi
git switch -c refactor/zshrc-modules
```

- [ ] **Step 2: 現状の挙動スナップショットを取得**

現在の `~/.zshrc`（リファクタ前）をログインシェルで読み込んだ状態の alias / 関数名 / setopt / 補完 zstyle を記録する。

```bash
zsh -ic 'alias; echo "=== FUNCTIONS ==="; print -l ${(ok)functions} | grep -vE "^_"; echo "=== SETOPT ==="; setopt; echo "=== ZSTYLE ==="; zstyle -L ":completion:*"' > /tmp/zshrc-baseline.txt 2>/dev/null
wc -l /tmp/zshrc-baseline.txt
```

Expected: 行数が出力される（数十〜百数十行）。このファイルは Task 8 で比較に使う。

---

## Task 2: モジュール 00/10/20 を作成

**Files:**
- Create: `dot_config/zsh/rc.d/00-options.zsh`
- Create: `dot_config/zsh/rc.d/10-path.zsh`
- Create: `dot_config/zsh/rc.d/20-completion.zsh`

- [ ] **Step 1: `00-options.zsh` を作成**

```zsh
# 00-options.zsh — shell options / history / 表示

export TERM=xterm-256color # 色空間
export WORDCHARS="*?_-.[]~=&;!#$%^(){}<>" # 区切り文字

autoload -Uz colors && colors # 色を有効にして、実行する

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
```

- [ ] **Step 2: `10-path.zsh` を作成**

```zsh
# 10-path.zsh — PATH / FPATH / MANPATH 等。compinit(30) より前に fpath を確定させる。

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

# Golang (go 本体は aqua 管理)
export GOPATH=$HOME/Project
export GHQ_ROOT=$GOPATH/src
export PATH=$GOPATH/bin:$PATH

# Rancher Desktop
export PATH=$HOME/.rd/bin:$PATH

# NodeJS (Yarn)
export PATH=$HOME/.yarn/bin:$PATH

# /etc/profile.d
if [ -d /etc/profile.d ]; then
  for i in /etc/profile.d/*.sh ; do
    [ -r $i ] && source $i
  done
fi

# command not found handler
if [ -f /etc/zsh_command_not_found ]; then
  source /etc/zsh_command_not_found
fi
```

- [ ] **Step 3: `20-completion.zsh` を作成**

```zsh
# 20-completion.zsh — 補完スタイルとキャッシュヘルパ。
# compinit / bashcompinit は sheldon の inline プラグイン（plugins.toml）で実行される。
# zstyle は補完実行時に遅延参照されるため、このファイルが plugins(30) より前でも問題ない。

zstyle ':completion::complete:*' use-cache true # キャッシュの利用による補完の高速化
zstyle ':completion:*:default' menu select=1 # 補完候補をハイライト
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}' # 大文字、小文字を区別せず補完する
zstyle ':completion:*' list-colors "${LS_COLORS}" # 補完候補に色つける
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([%0-9]#)*=0=01;31' # kill の候補にも色付き表示
zstyle ':completion:*:sudo:*' command-path /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin /usr/X11R6/bin # コマンドにsudoを付けても補完
zstyle ':completion:*:cd:*' ignore-parents parent pwd # ディレクトリスタックの補完をする

# fzf-tab 用（上の menu select=1 を上書き）
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls -1 --color=always $realpath'

# complete -C / source 系の補完をキャッシュするヘルパ（fpath 化できないツール用）
_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/completions"
[[ -d $_cache_dir ]] || mkdir -p "$_cache_dir"
_load_completion () {  # name, generate-command, binary-path(for mtime check)
  local name=$1 gen=$2 bin=$3
  local cache="$_cache_dir/${name}.zsh"
  if [[ ! -s $cache || ( -n $bin && $bin -nt $cache ) ]]; then
    eval "$gen" > "$cache" 2>/dev/null
  fi
  [[ -s $cache ]] && source "$cache"
}
```

- [ ] **Step 4: 3 ファイルの構文チェック**

Run:
```bash
cd ~/.local/share/chezmoi
for f in dot_config/zsh/rc.d/00-options.zsh dot_config/zsh/rc.d/10-path.zsh dot_config/zsh/rc.d/20-completion.zsh; do zsh -n "$f" && echo "OK: $f"; done
```
Expected: `OK:` が 3 行。エラー出力なし。

- [ ] **Step 5: コミット**

```bash
git add dot_config/zsh/rc.d/00-options.zsh dot_config/zsh/rc.d/10-path.zsh dot_config/zsh/rc.d/20-completion.zsh
git commit -m "refactor(zsh): rc.d に options/path/completion モジュールを分離"
```

---

## Task 3: モジュール 30/40 を作成

**Files:**
- Create: `dot_config/zsh/rc.d/30-plugins.zsh`
- Create: `dot_config/zsh/rc.d/40-tools.zsh`

- [ ] **Step 1: `30-plugins.zsh` を作成**

```zsh
# 30-plugins.zsh — sheldon / prompt / 各種 hook。
# sheldon の plugins.toml が fpath -> compinit -> fzf-tab -> zsh-autosuggestions の順で展開する。
# autosuggestions の設定はロード前に置く必要がある。

ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_USE_ASYNC=1
ZSH_AUTOSUGGEST_MANUAL_REBIND=1
if command -v sheldon &> /dev/null ;then
  eval "$(sheldon source)"
fi

# starship prompt（aqua 管理。初回起動は aqua proxy の解決で数秒待つことがある）
if command -v starship &> /dev/null ;then
  eval "$(starship init zsh)"
fi

# direnv
if command -v direnv &> /dev/null ;then
  eval "$(direnv hook zsh)"
fi

# fnm (node version manager, aqua 管理) — nvim/mason が node を見つけられるよう初期化
if command -v fnm &> /dev/null ;then
  eval "$(fnm env --use-on-cd)"
fi
```

- [ ] **Step 2: `40-tools.zsh` を作成**

`complete -C`（bash 動的補完）は compinit/bashcompinit 後でないと使えないため、このファイルは plugins(30) の後にロードされる必要がある（番号順で保証）。

```zsh
# 40-tools.zsh — compinit 後に必要なツール連携・補完。
# aqua 管理ツールのネイティブ補完は run_onchange スクリプトが site-functions へ生成し、
# compinit が自動ロードする。ここには fpath 化できないものだけを置く。

# fzf (aqua 管理): キーバインド(C-r/C-t/M-c) + ** 補完。--zsh をキャッシュして source。
if command -v fzf &> /dev/null ;then
  _load_completion fzf 'fzf --zsh' "$(command -v fzf)"
fi

# google cloud sdk（補完スクリプト同梱・source 専用）
if [ -f /usr/share/google-cloud-sdk/completion.zsh.inc ]; then
  source /usr/share/google-cloud-sdk/completion.zsh.inc
fi

if [ -f /opt/google-cloud-sdk/completion.zsh.inc ]; then
  export PATH=/opt/google-cloud-sdk/bin:$PATH
  source /opt/google-cloud-sdk/completion.zsh.inc
fi

# aws cli（bash 動的補完）
if command -v aws_completer &> /dev/null ;then
  complete -C $(which aws_completer) aws
fi

# tenv（補完は site-functions に事前生成。ここでは env のみ）
if command -v tenv &> /dev/null ;then
  export TENV_AUTO_INSTALL=true
  export TENV_VALIDATION=sha
fi

# terraform（bash 動的補完）
if command -v terraform &> /dev/null ;then
  complete -o nospace -C $(which terraform) terraform
  alias tf="terraform"
fi

# kubectl（非 aqua: ランタイム生成をキャッシュ）
if command -v kubectl > /dev/null 2>&1;then
  _load_completion kubectl 'kubectl completion zsh' "$(command -v kubectl)"
  alias k="kubectl"
fi

# ssh agent (1Password)
if ! [ "$SSH_CONNECTION" ]; then
  if [ -S "${HOME}/.1password/agent.sock" ]; then
    export SSH_AUTH_SOCK="${HOME}/.1password/agent.sock"
  fi
fi
```

- [ ] **Step 3: 構文チェック**

Run:
```bash
cd ~/.local/share/chezmoi
for f in dot_config/zsh/rc.d/30-plugins.zsh dot_config/zsh/rc.d/40-tools.zsh; do zsh -n "$f" && echo "OK: $f"; done
```
Expected: `OK:` が 2 行。

- [ ] **Step 4: コミット**

```bash
git add dot_config/zsh/rc.d/30-plugins.zsh dot_config/zsh/rc.d/40-tools.zsh
git commit -m "refactor(zsh): rc.d に plugins/tools モジュールを分離"
```

---

## Task 4: モジュール 50/60/70 を作成

**Files:**
- Create: `dot_config/zsh/rc.d/50-functions.zsh`
- Create: `dot_config/zsh/rc.d/60-aliases.zsh`
- Create: `dot_config/zsh/rc.d/70-keybindings.zsh`

- [ ] **Step 1: `50-functions.zsh` を作成**

```zsh
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

# nvim を VSCode ライクな IDE レイアウトで起動する
function ide () {
  NVIM_IDE=1 nvim "$@"
}
```

- [ ] **Step 2: `60-aliases.zsh` を作成**

```zsh
# 60-aliases.zsh — エイリアスと基本 env。

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

export EDITOR=nvim
export VISUAL=nvim
alias vi=nvim
alias vim=nvim

# WSL 用の調整
if [[ "$(uname -r)" == *microsoft* ]]; then
  alias code="/mnt/c/Users/$(whoami)/AppData/Local/Programs/Microsoft\ VS\ Code/bin/code"
  unalias docker
  unalias docker-compose
fi
```

- [ ] **Step 3: `70-keybindings.zsh` を作成**

```zsh
# 70-keybindings.zsh — キーバインド。

# HOME, DELETE, END キーを有効にする
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
```

- [ ] **Step 4: 構文チェック**

Run:
```bash
cd ~/.local/share/chezmoi
for f in dot_config/zsh/rc.d/50-functions.zsh dot_config/zsh/rc.d/60-aliases.zsh dot_config/zsh/rc.d/70-keybindings.zsh; do zsh -n "$f" && echo "OK: $f"; done
```
Expected: `OK:` が 3 行。

- [ ] **Step 5: コミット**

```bash
git add dot_config/zsh/rc.d/50-functions.zsh dot_config/zsh/rc.d/60-aliases.zsh dot_config/zsh/rc.d/70-keybindings.zsh
git commit -m "refactor(zsh): rc.d に functions/aliases/keybindings モジュールを分離"
```

---

## Task 5: `dot_zshrc` をローダーに置き換え

**Files:**
- Modify: `dot_zshrc`（全置換）

- [ ] **Step 1: `dot_zshrc` を以下の内容で全置換**

```zsh
# .zshrc — ローダー。実体は ~/.config/zsh/rc.d/*.zsh に機能別分割されている。

# in ~/.zshenv, executed `unsetopt GLOBAL_RCS` and ignored /etc/zshrc
if [[ "$(uname)" == "Darwin" ]]; then
  [ -r /etc/zshrc ] && . /etc/zshrc
fi

# rc.d モジュールを番号順に: stale なら zcompile してから source する。
# 依存順: 10-path(FPATH) -> 30-plugins(compinit) -> 40-tools(bashcompinit 後の complete -C)
ZSH_RCD="${XDG_CONFIG_HOME:-$HOME/.config}/zsh/rc.d"
if [[ -d $ZSH_RCD ]]; then
  for _rc in "$ZSH_RCD"/*.zsh(N); do
    if [[ ! -f ${_rc}.zwc || ${_rc} -nt ${_rc}.zwc ]]; then
      zcompile "$_rc"
    fi
    source "$_rc"
  done
  unset _rc
fi

# .zshrc 自身の再コンパイル
if [[ ! -f $HOME/.zshrc.zwc || $HOME/.zshrc -nt $HOME/.zshrc.zwc ]]; then
  print -P "%F{34}Recompile .zshrc%f%b"
  zcompile $HOME/.zshrc
fi
```

- [ ] **Step 2: 構文チェック**

Run:
```bash
cd ~/.local/share/chezmoi
zsh -n dot_zshrc && echo OK
```
Expected: `OK`

- [ ] **Step 3: コミット**

```bash
git add dot_zshrc
git commit -m "refactor(zsh): dot_zshrc を rc.d ローダーに縮小"
```

---

## Task 6: aqua ツール補完生成スクリプトを追加

**Files:**
- Create: `.chezmoiscripts/run_onchange_after_25-zsh-completions.sh.tmpl`

- [ ] **Step 1: スクリプトを作成**

```sh
#!/bin/sh
# Generate zsh completion functions for aqua-managed tools into fpath.
# Runs after aqua install (20) and re-runs whenever the aqua config changes.
# aqua.yaml      hash: {{ include "dot_config/aquaproj-aqua/aqua.yaml" | sha256sum }}
# registry.yaml  hash: {{ include "dot_config/aquaproj-aqua/registry.yaml" | sha256sum }}
set -eu

# Make aqua-managed tools resolvable (aqua proxy/bin + brew).
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
export AQUA_ROOT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/aquaproj-aqua"
export AQUA_GLOBAL_CONFIG="$HOME/.config/aquaproj-aqua/aqua.yaml"
export AQUA_POLICY_CONFIG="$HOME/.config/aquaproj-aqua/aqua-policy.yaml"
export PATH="$AQUA_ROOT_DIR/bin:$PATH"

dest="$HOME/.local/share/zsh/site-functions"
mkdir -p "$dest"

# gen <fnname> <command...> : run the generator if its binary exists; remove file on failure.
gen() {
  fn="$1"; shift
  if command -v "$1" >/dev/null 2>&1; then
    if "$@" > "$dest/_$fn" 2>/dev/null; then
      echo "  generated _$fn"
    else
      rm -f "$dest/_$fn"
    fi
  fi
}

echo "Generating zsh completions -> $dest"
gen gh       gh completion -s zsh
gen uv       uv generate-shell-completion zsh
gen fnm      fnm completions --shell zsh
gen aqua     aqua completion zsh
gen starship starship completions zsh
gen rg       rg --generate=complete-zsh
gen fd       fd --gen-completions zsh
gen tenv     tenv completion zsh

# Force compinit to rebuild its dump so the new/updated functions are picked up.
rm -f "$HOME/.zcompdump" "$HOME/.zcompdump.zwc" 2>/dev/null || true
```

- [ ] **Step 2: テンプレート展開とシェル構文チェック**

chezmoi テンプレートを展開し、生成される sh が構文的に正しいか確認する。

Run:
```bash
cd ~/.local/share/chezmoi
chezmoi execute-template < .chezmoiscripts/run_onchange_after_25-zsh-completions.sh.tmpl | sh -n && echo "SYNTAX OK"
```
Expected: `SYNTAX OK`（テンプレート展開エラー・sh 構文エラーなし）

- [ ] **Step 3: コミット**

```bash
git add .chezmoiscripts/run_onchange_after_25-zsh-completions.sh.tmpl
git commit -m "feat(zsh): aqua ツールの zsh 補完を site-functions へ生成する chezmoi スクリプトを追加"
```

---

## Task 7: ドキュメント更新

**Files:**
- Modify: `docs/zsh-cheatsheet.md`

- [ ] **Step 1: 冒頭の構成説明にモジュール分割を追記**

`docs/zsh-cheatsheet.md` の先頭リスト（`- プラグイン管理: ...` の箇条書き）に次の 1 行を追加する。挿入位置は `- エディタ: ...` の直後。

追加する行:
```markdown
- 構成: `dot_zshrc` はローダー。実体は `~/.config/zsh/rc.d/*.zsh`（`00-options` / `10-path` / `20-completion` / `30-plugins` / `40-tools` / `50-functions` / `60-aliases` / `70-keybindings`）を番号順に zcompile + source
```

- [ ] **Step 2: キーバインド表に fzf のキーを追記**

`## キーバインド` の表（`| C-] | ... |` 等）の末尾に次の 3 行を追加する。

```markdown
| `C-r` | fzf 履歴検索（`fzf --zsh`） |
| `C-t` | fzf でファイル/ディレクトリをコマンドラインへ挿入 |
| `M-c` | fzf でサブディレクトリへ `cd` |
```

そのうえで、表の下の補足段落（`その他、sheldon 経由の ...` の段落）の末尾に次の一文を追加する。

```markdown
さらに **fzf**（aqua 管理）のキーバインドと `**<Tab>` 補完が有効（`fzf --zsh`）。
```

- [ ] **Step 3: 「連携ツール（自動初期化）」表を補完対応に更新**

`## 連携ツール（自動初期化）` の表の `gcloud / aws / kubectl` 行の下に、補完生成対象を示す行を追加する。

```markdown
| gh / uv / rg / fd / fnm / aqua / starship / tenv | zsh ネイティブ補完。aqua 更新時に chezmoi が `~/.local/share/zsh/site-functions/_<name>` を生成 |
```

そのうえで、表の下の注記（`> CLI ツール自体は **aqua** ...`）の直前に次の一文を追加する。

```markdown
> 補完の内訳: `gh`/`uv`/`rg`/`fd`/`fnm`/`aqua`/`starship`/`tenv` は fpath へ事前生成、
> `terraform`/`aws` は bash 動的補完（`complete -C`）、`fzf`/`gcloud`/`kubectl` は source 方式。
```

- [ ] **Step 4: 整合性確認**

Run:
```bash
cd ~/.local/share/chezmoi
grep -nE "rc.d|fzf --zsh|site-functions|C-r" docs/zsh-cheatsheet.md
```
Expected: 追加した各行がヒットする。

- [ ] **Step 5: コミット**

```bash
git add docs/zsh-cheatsheet.md
git commit -m "docs(zsh): rc.d 分割と aqua ツール補完をチートシートに反映"
```

---

## Task 8: 適用と等価性検証

実際に `chezmoi apply` してリファクタ前後の挙動が等価で、補完が生成されることを確認する。

**Files:**
- なし（検証のみ。問題があれば該当モジュールを修正して再コミット）

- [ ] **Step 1: 差分確認**

Run:
```bash
cd ~/.local/share/chezmoi
chezmoi diff
```
Expected: `~/.zshrc` がローダーに、`~/.config/zsh/rc.d/*.zsh` 8 ファイルが新規、`run_onchange_after_25-...` が新規として表示される。意図しない削除・変更がないこと。

- [ ] **Step 2: 適用（補完生成スクリプトも実行される）**

Run:
```bash
chezmoi apply
ls -1 ~/.local/share/zsh/site-functions/
```
Expected: `_gh _uv _fnm _aqua _starship _rg _fd _tenv` が（インストール済みツール分）生成されている。スクリプトの `generated _xxx` ログが出る。

- [ ] **Step 3: 新シェル起動の健全性チェック**

Run:
```bash
zsh -ic 'echo ZSH_OK' 2>&1 | tail -5
```
Expected: 最終行付近に `ZSH_OK`。エラー（`command not found` / `parse error` 等）が出ないこと。

- [ ] **Step 4: リファクタ前後の挙動を比較**

Task 1 で取得したベースラインと、リファクタ後の同じスナップショットを比較する。

Run:
```bash
zsh -ic 'alias; echo "=== FUNCTIONS ==="; print -l ${(ok)functions} | grep -vE "^_"; echo "=== SETOPT ==="; setopt; echo "=== ZSTYLE ==="; zstyle -L ":completion:*"' > /tmp/zshrc-after.txt 2>/dev/null
diff /tmp/zshrc-baseline.txt /tmp/zshrc-after.txt
```
Expected: alias / 関数 / setopt / zstyle に意図しない差分がないこと。許容される差分は「`menu no` 関連の zstyle 重複解消」程度。`tf`/`k` などの alias、`ide`/`tssh` などの関数が前後で存在すること。差分があれば該当モジュールを修正し、当該タスクのコミットを `git commit --amend` せず新規コミットで追従する。

- [ ] **Step 5: 補完の実動作確認（手動）**

新しいインタラクティブシェルを開き、以下を確認する（自動化困難なため手動チェック）。

確認項目:
- `gh <Tab>` → サブコマンド候補（`auth`, `pr`, `repo` 等）が出る
- `rg --<Tab>` → ロングオプション候補が出る
- `terraform <Tab>` / `tf <Tab>` → サブコマンド候補が出る（terraform がある場合）
- `cd <Tab>` → fzf-tab の UI でディレクトリ + ls プレビューが出る
- `C-r` → fzf の履歴検索 UI が開く

Expected: 上記が機能する。

---

## Task 9: 仕上げ（ブランチ統合）

- [ ] **Step 1: 全コミットの確認**

Run:
```bash
cd ~/.local/share/chezmoi
git log --oneline main..refactor/zshrc-modules
git status
```
Expected: Task 2〜7 のコミットが並び、作業ツリーがクリーン（既存の nvim 関連の未コミット変更には触れていないこと）。

- [ ] **Step 2: main へ統合**

ユーザーに統合方法（fast-forward マージ / そのまま main 運用）を確認してから実行する。デフォルトは fast-forward マージ。

```bash
git switch main
git merge --ff-only refactor/zshrc-modules
```
Expected: main が更新される。

---

## Self-Review（計画作成者によるチェック結果）

- **Spec coverage:** 設計書の全項目に対応タスクあり — モジュール 7+1 分割(Task2-5) / fpath 補完生成スクリプト(Task6) / complete -C・source 系の維持(Task3 の 40-tools) / docs 更新(Task7) / 受け入れ基準の検証(Task8)。
- **Placeholder scan:** TBD/TODO/「適宜」等なし。全モジュールの完全な内容を記載済み。
- **Type/名称整合:** `_load_completion`（20 で定義、40 で使用）、`ZSH_RCD`（dot_zshrc 内のみ）、`gen`（スクリプト内のみ）、site-functions パス `~/.local/share/zsh/site-functions`（10-path の FPATH・スクリプトの dest・docs で一致）を確認。
- **既知の挙動差分:** 旧 zshrc は `_load_completion tenv` を実行していたが、tenv 補完は fpath 生成へ移行（40-tools から削除済み）。これは設計どおりの意図的変更。
```
