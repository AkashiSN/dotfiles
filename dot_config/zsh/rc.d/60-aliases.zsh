# 60-aliases.zsh — alias の読み込み。
#
# 実体は ~/.config/shell/aliases.sh（zsh・bash 共通）。bash で走る Claude Code にも
# 同じ alias を届けるため、両シェルから読める POSIX sh の 1 ファイルにまとめてある。
# zsh でしか意味を持たない alias をここへ足すことはできるが、いまは無い。

_shell_aliases="${XDG_CONFIG_HOME:-$HOME/.config}/shell/aliases.sh"
[ -r "$_shell_aliases" ] && source "$_shell_aliases"
unset _shell_aliases
