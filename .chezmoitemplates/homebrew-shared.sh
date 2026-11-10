# Apple Silicon の Homebrew を複数ユーザで共有するための共通定義。POSIX sh。
# .chezmoiscripts の before_05 / before_10 が template "homebrew-shared.sh" で取り込む。
# テンプレートの記法は含めない（tests/ からそのまま source できる）。

# 共有に使う OS グループ。
BREW_GROUP="${BREW_GROUP:-brew}"

# brew を umask 002 で呼ぶ。グループ書き込み可で作らせ、別ユーザが続きの操作をできるようにする。
brew_shared() {
	(
		umask 002
		brew "$@"
	)
}

# prefix（既定 /opt/homebrew）がグループ共有の状態か。
# 真の条件は全部: グループが $BREW_GROUP、グループに書き込み可、ディレクトリが setgid、
# かつ現在のプロセスが $BREW_GROUP に属する（グループへ追加した直後の未ログインは偽）。
homebrew_shared_ok() {
	_hs_prefix="${1:-/opt/homebrew}"
	[ -d "$_hs_prefix" ] || return 1
	# PATH に GNU coreutils があっても書式が変わらないよう、macOS は /usr/bin/stat を使う。
	if [ "$(uname -s)" = Darwin ]; then
		_hs_info="$(/usr/bin/stat -f '%Sg %Sp' "$_hs_prefix")" || return 1
	else
		_hs_info="$(stat -c '%G %A' "$_hs_prefix")" || return 1
	fi
	_hs_group="${_hs_info%% *}"
	_hs_perm="${_hs_info#* }"
	[ "$_hs_group" = "$BREW_GROUP" ] || return 1
	# drwxrwsr-x: 6 文字目がグループの w
	case "$_hs_perm" in
	?????w*) ;;
	*) return 1 ;;
	esac
	[ -g "$_hs_prefix" ] || return 1
	id -Gn | tr ' ' '\n' | grep -qx "$BREW_GROUP"
}
