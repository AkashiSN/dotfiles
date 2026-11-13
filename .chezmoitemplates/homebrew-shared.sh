# shellcheck shell=sh
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

# homebrew_fs_shared [prefix]
# prefix（既定 /opt/homebrew）のファイルシステムがグループ共有の状態か。
# 真の条件は全部: グループが $BREW_GROUP、グループに書き込み可、ディレクトリが setgid。
homebrew_fs_shared() {
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
	[ -g "$_hs_prefix" ]
}

# homebrew_member_now
# 現在のプロセスが $BREW_GROUP に属するか（グループへ追加した直後の未ログインは偽）。
homebrew_member_now() {
	id -Gn | tr ' ' '\n' | grep -qx "$BREW_GROUP"
}

# homebrew_member_registered
# ユーザがディレクトリサービス上で $BREW_GROUP に登録済みか（再ログイン前でも真）。
homebrew_member_registered() {
	dseditgroup -o checkmember -m "$(id -un)" "$BREW_GROUP" >/dev/null 2>&1
}

# homebrew_shared_ok [prefix]
# ファイルシステムが共有済みで、かつ現在のプロセスが $BREW_GROUP に属するか。
homebrew_shared_ok() {
	homebrew_fs_shared "${1:-/opt/homebrew}" && homebrew_member_now
}
