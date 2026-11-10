# bootstrap/*.sh が source する共通関数。単体では実行しない。
# Linux と macOS (bash 3.2 / BSD コマンド) の両方で動く。呼び出し側の set -eu 下でも動く。
# shellcheck shell=bash

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
note() { printf '  \033[1m%s\033[0m\n' "$1"; }
warn() { printf '  \033[1;33m%s\033[0m\n' "$1"; }

# stdin が TTY なら何もしない。TTY でなければ引数の説明を stderr に出して exit 1 する。
# 対話入力を待つ処理の手前で呼び、無人実行では待たずに失敗させる。
require_tty() {
	[ -t 0 ] && return 0
	printf '%s\n' "$1" >&2
	exit 1
}

# 共有ストアの所有者:グループ。Linux は root:root、macOS は root:wheel。
shared_owner_group() {
	case "$(uname -s)" in
	Darwin) echo "root:wheel" ;;
	*) echo "root:root" ;;
	esac
}

# swap_symlink <target> <link>
# <link> を <target> を指す symlink に原子的に置き換える。<link> が実ディレクトリなら
# 何もせず stderr に理由を出して 1 を返す。
swap_symlink() {
	local target="$1" link="$2" tmp
	if [ -d "$link" ] && [ ! -L "$link" ]; then
		printf 'swap_symlink: %s は実ディレクトリのため置き換えない\n' "$link" >&2
		return 1
	fi
	case "$(uname -s)" in
	Darwin)
		# -h: <link> が既存の symlink ならその先ではなく symlink 自体を置き換える。
		# PATH 先頭に GNU ln があっても BSD 版を使う。
		/bin/ln -sfhn "$target" "$link"
		;;
	*)
		tmp="${link}.swap.$$"
		ln -sfn "$target" "$tmp"
		mv -T "$tmp" "$link"
		;;
	esac
}

# running_from_any <dir>
# 全ユーザのプロセスのうち、実行ファイルが <dir>/ 以下にあるものが 1 つでもあれば 0、
# 無ければ 1 を返す。<dir> は末尾スラッシュを除き、与えられた形と pwd -P の形の両方で照合する。
running_from_any() {
	local dir="${1%/}" real exe comm
	local -a prefixes
	prefixes=("$dir/")
	if real="$(cd "$dir" 2>/dev/null && pwd -P)" && [ "$real" != "$dir" ]; then
		prefixes+=("${real%/}/")
	fi

	if [ -d /proc/self ]; then
		for exe in /proc/[0-9]*/exe; do
			# 他ユーザのプロセスは readlink が権限で失敗する。無視する。
			comm="$(readlink "$exe" 2>/dev/null)" || continue
			_has_prefix "$comm" "${prefixes[@]}" && return 0
		done
	else
		while IFS= read -r comm; do
			_has_prefix "$comm" "${prefixes[@]}" && return 0
		done < <(ps -axo comm= 2>/dev/null)
	fi
	return 1
}

# running_matching <substring>
# 全ユーザのプロセスのうち、実行ファイルのパスに <substring> を含むものが 1 つでもあれば 0、
# 無ければ 1 を返す。macOS の ps は symlink 経由で起動したパス（ホームの pkgs など）を
# そのまま出すため、実体のパスでは照合できない場合の補助に使う。
running_matching() {
	local sub="$1" exe comm
	if [ -d /proc/self ]; then
		for exe in /proc/[0-9]*/exe; do
			comm="$(readlink "$exe" 2>/dev/null)" || continue
			case "$comm" in
			*"$sub"*) return 0 ;;
			esac
		done
	else
		while IFS= read -r comm; do
			case "$comm" in
			*"$sub"*) return 0 ;;
			esac
		done < <(ps -axo comm= 2>/dev/null)
	fi
	return 1
}

# _has_prefix <path> <prefix...>: <path> がいずれかの <prefix> で始まれば 0。
_has_prefix() {
	local path="$1" p
	shift
	for p in "$@"; do
		case "$path" in
		"$p"*) return 0 ;;
		esac
	done
	return 1
}

# pins_key <file...>
# 引数順に連結した内容の SHA-256 の先頭 12 桁を出す。ピン指定ファイルの変化の検出に使う。
pins_key() {
	local hash
	if command -v shasum >/dev/null 2>&1; then
		hash="$(cat "$@" | shasum -a 256)"
	else
		hash="$(cat "$@" | sha256sum)"
	fi
	printf '%s\n' "${hash:0:12}"
}
