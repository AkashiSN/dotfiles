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
