# shellcheck shell=bash
# ホームに残った uv の Python と、共有へ移したツールを掃除する。bash。
# .chezmoiscripts の run_after_35 が source する（テンプレートの記法は含めず、tests/ からそのまま source できる）。
# 前提: bootstrap/lib.sh を source 済み（note / running_from_any / running_matching / running_exact）。
#
# uv の data ディレクトリ（既定 ~/.local/share/uv）の python と tools の下だけを消す。
# プロジェクトの venv は消さない。次の uv run / uv sync が共有の Python で作り直す。

# _uv_link_into <link> <dir>: <link> の指す先が <dir> の下なら 0。相対リンクも解決して照合する。
_uv_link_into() {
	local link="$1" dir="$2" t d rt pr
	t="$(readlink "$link" 2>/dev/null)" || return 1
	case "$t" in
	/*) ;;
	*) t="$(dirname "$link")/$t" ;;
	esac
	case "$t" in
	"$dir"/*) return 0 ;;
	esac
	d="$(cd "$(dirname "$t")" 2>/dev/null && pwd -P)" || d="$(dirname "$t")"
	rt="$d/$(basename "$t")"
	pr="$(cd "$dir" 2>/dev/null && pwd -P)" || pr="$dir"
	case "$rt" in
	"$pr"/*) return 0 ;;
	esac
	return 1
}

# _uv_remove_links_into <local_bin> <dir>: <local_bin> のうち <dir> の下を指す symlink を消す。
_uv_remove_links_into() {
	local link
	for link in "$1"/*; do
		[ -L "$link" ] || continue
		if _uv_link_into "$link" "$2"; then
			note "共有の uv を使うため削除: $link"
			rm -f "$link"
		fi
	done
}

# _uv_busy <uv_data> <local_bin>: ホームの uv の Python やツールが動いていれば 0。
# macOS の ps は PATH 上のリンク（~/.local/bin/ansible など）で起動したプロセスをそのリンクのパスで出し、
# 実体のディレクトリは出さない。Python のスクリプトは comm がインタプリタで、スクリプトのパスは引数に出る。
_uv_busy() {
	local data="$1" lbin="$2" link args
	running_from_any "$data/python" && return 0
	running_from_any "$data/tools" && return 0
	running_matching "$data/python/" && return 0
	running_matching "$data/tools/" && return 0
	running_matching "/share/uv/python/" && return 0
	running_matching "/share/uv/tools/" && return 0
	for link in "$lbin"/*; do
		[ -L "$link" ] || continue
		if _uv_link_into "$link" "$data/python" || _uv_link_into "$link" "$data/tools"; then
			running_exact "$link" && return 0
		fi
	done
	args="$(ps -axww -o args= 2>/dev/null || true)"
	case "$args" in
	*"$data/python/"* | *"$data/tools/"*) return 0 ;;
	esac
	return 1
}

# uv_cleanup_home <uv_data> <local_bin> <tool...>
# 共有へ移した <tool>（uv tool list の正規化名。ディレクトリ名と同じ）の実体と ~/.local/bin の symlink を消す。
# 残ったツール（ユーザが自分で入れたもの）が無ければ、ホームの Python と python3 などの symlink も消す。
# ホームの uv の Python やツールが動いている間は何も消さず、次の apply へ回す。
uv_cleanup_home() {
	local data="$1" lbin="$2" tool
	shift 2
	[ -d "$data/tools" ] || [ -d "$data/python" ] || return 0
	if _uv_busy "$data" "$lbin"; then
		note "ホームの uv の Python かツールが動いているため、共有へ移した分は次の chezmoi apply で消します"
		return 0
	fi
	for tool in "$@"; do
		[ -d "$data/tools/$tool" ] || continue
		_uv_remove_links_into "$lbin" "$data/tools/$tool"
		note "共有の uv を使うため削除: $data/tools/$tool"
		rm -rf "$data/tools/$tool"
	done
	[ -d "$data/python" ] || return 0
	# ツールは tools の下の venv（ディレクトリ）。uv が置く .gitignore / .lock は数えない。
	if [ -n "$(find "$data/tools" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)" ]; then
		note "ホームに uv のツールが残っているため、$data/python は消しません"
		return 0
	fi
	_uv_remove_links_into "$lbin" "$data/python"
	note "共有の Python を使うため削除: $data/python"
	rm -rf "$data/python"
}
