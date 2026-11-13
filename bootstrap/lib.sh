# bootstrap/*.sh が source する共通関数。単体では実行しない。
# Linux と macOS (bash 3.2 / BSD コマンド) の両方で動く。呼び出し側の set -eu 下でも動く。
# shellcheck shell=bash

# このファイルの置き場（bootstrap/）。source した時点の作業ディレクトリで解決しておく。
_BOOTSTRAP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# gc_defer
# 古い版などを使用中のため消せなかったときに、ステップ（bootstrap/NN-*.sh）が呼ぶ。
# $SHARED_ROOT/dotfiles-shared/pending/<NN> を置き、run-all.sh --check はこれを食い違いとして数える。
# そのため次の apply（どのユーザのものでもよい）で、ピンが変わっていなくてもステップを流し直し、
# 使い終わったものを消す。run-all.sh はステップを流す前にこの印を外す。
gc_defer() {
	local nn dir
	nn="$(basename "$0")"
	nn="${nn%%-*}"
	dir="${SHARED_ROOT:-/opt}/dotfiles-shared/pending"
	mkdir -p "$dir" && : >"$dir/$nn"
}

# shared_lock <file>
# 共有ストアの更新を全ユーザで 1 本に絞る排他ロックを取る。取れるまで待つ（待つときは 1 行案内する）。
# ロックは fd 9 に開いた <file> の flock で、このシェルが終わる（fd 9 が閉じる）と外れる。異常終了でも残らない。
# ステップなどの子プロセスへ fd 9 を渡さないよう、呼び出し側は子を 9>&- で起動する。
# flock(1) が無い macOS は /usr/bin/perl の flock を fd 9 に掛ける（ロックは開いたファイルに付くので、
# perl が終わってもこのシェルが fd 9 を開いている間は保たれる）。
shared_lock() {
	mkdir -p "$(dirname "$1")"
	exec 9>>"$1"
	_flock_fd9 -n && return 0
	note "ほかの共有ストアの更新が終わるのを待ちます ($1)"
	_flock_fd9
}

# _flock_fd9 [-n]: fd 9 に排他の flock を掛ける。-n なら待たず、取れなければ 1。
_flock_fd9() {
	if command -v flock >/dev/null 2>&1; then
		flock ${1:+"$1"} 9
	else
		# shellcheck disable=SC2016
		perl -MFcntl=:flock -e 'open(my $f, ">&=", 9) or exit 2; flock($f, LOCK_EX | ($ARGV[0] ? LOCK_NB : 0)) or exit 1' -- "${1:-}"
	fi
}

# shared_aqua_current
# 共有 aqua ストアが DOTFILES_SRC のピンで揃っているか（config が在り、20-shared-aqua.sh --check が
# 通る）。揃っていれば 0。共有 aqua からツールを引くステップ（21 / 23 / 24 / 25）が、20 が失敗した
# 回に古い aqua で進まないよう、最初に確かめる。
shared_aqua_current() {
	local dir="$_BOOTSTRAP_LIB_DIR"
	[ -f "${SHARED_ROOT:-/opt}/aquaproj-aqua/config/aqua.yaml" ] || return 1
	SHARED_ROOT="${SHARED_ROOT:-/opt}" DOTFILES_SRC="${DOTFILES_SRC:-$(dirname "$dir")}" \
		bash "$dir/20-shared-aqua.sh" --check
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
		# 一時リンクを作って rename で置き換える（ln -sfh は消してから作るので、間にリンクが無い瞬間がある）。
		# mv -h: <link> がディレクトリへの symlink でも、その中へ移さず symlink 自体を置き換える。
		# mv -h の無い古い macOS では ln -sfh で置き換える。PATH 先頭に GNU 版があっても BSD 版を使う。
		tmp="${link}.swap.$$"
		/bin/ln -sfhn "$target" "$tmp" || return 1
		if ! /bin/mv -fh "$tmp" "$link" 2>/dev/null; then
			/bin/rm -f "$tmp"
			/bin/ln -sfhn "$target" "$link"
		fi
		;;
	*)
		tmp="${link}.swap.$$"
		ln -sfn "$target" "$tmp"
		mv -T "$tmp" "$link"
		;;
	esac
}

# _resolve_symlinks <path>
# <path> が symlink なら、実体までたどった絶対パスを出す（相対リンクも解決し、ディレクトリは pwd -P で
# 正規化する。最大 10 段）。symlink でなければそのまま出す。macOS の ps が出す venv のリンク
# （project/.venv/bin/python）から、uv の Python の実体を引くために使う。
_resolve_symlinks() {
	local p="$1" i=0 t d
	while [ -L "$p" ] && [ "$i" -lt 10 ]; do
		t="$(readlink "$p")" || break
		case "$t" in
		/*) p="$t" ;;
		*) p="$(dirname "$p")/$t" ;;
		esac
		d="$(cd "$(dirname "$p")" 2>/dev/null && pwd -P)" || break
		p="$d/$(basename "$p")"
		i=$((i + 1))
	done
	printf '%s\n' "$p"
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
		# ps は PATH 上や venv のリンクのパスをそのまま出す。リンクなら実体のパスでも照合する。
		while IFS= read -r comm; do
			_has_prefix "$comm" "${prefixes[@]}" && return 0
			if [ -L "$comm" ]; then
				_has_prefix "$(_resolve_symlinks "$comm")" "${prefixes[@]}" && return 0
			fi
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
			if [ -L "$comm" ]; then
				case "$(_resolve_symlinks "$comm")" in
				*"$sub"*) return 0 ;;
				esac
			fi
		done < <(ps -axo comm= 2>/dev/null)
	fi
	return 1
}

# running_exact <path>
# 全ユーザのプロセスのうち、実行ファイルのパスが <path> と完全に一致するものが 1 つでもあれば 0、
# 無ければ 1 を返す（末尾まで一致。/x/claude-bedrock は /x/claude に一致しない）。
# macOS の ps は PATH 上のリンク（~/.local/bin/claude）で起動したプロセスを、そのリンクのパスのまま
# 出し、実体のディレクトリは出さない。running_from_any / running_matching では見つからない
# リンク経由の起動を、リンクのパスで照合するために使う。リンクを外した後も古いプロセスは同じパスを報告する。
running_exact() {
	local want="$1" exe comm
	if [ -d /proc/self ]; then
		for exe in /proc/[0-9]*/exe; do
			comm="$(readlink "$exe" 2>/dev/null)" || continue
			[ "$comm" = "$want" ] && return 0
		done
	else
		while IFS= read -r comm; do
			[ "$comm" = "$want" ] && return 0
			if [ -L "$comm" ] && [ "$(_resolve_symlinks "$comm")" = "$want" ]; then
				return 0
			fi
		done < <(ps -axo comm= 2>/dev/null)
	fi
	return 1
}

# running_args_matching <substring>
# 全ユーザのプロセスの引数（ps の args）の行に <substring> を含むものが 1 つでもあれば 0、無ければ 1 を返す。
# Python のスクリプトは comm がインタプリタで、スクリプトのパスは引数に出る。引数の第 1 語が symlink
# （venv の bin/python など）なら、実体のパスでも照合する。
running_args_matching() {
	local sub="$1" line first
	while IFS= read -r line; do
		case "$line" in
		*"$sub"*) return 0 ;;
		esac
		first="${line%% *}"
		if [ -L "$first" ]; then
			case "$(_resolve_symlinks "$first")" in
			*"$sub"*) return 0 ;;
			esac
		fi
	done < <(ps -axww -o args= 2>/dev/null)
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
