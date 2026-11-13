# shellcheck shell=bash
# ホームに残った公式インストーラの Claude Code / Codex / CodeGraph / Kiro CLI の実体を掃除する。bash。
# .chezmoiscripts の run_after_40 が source する（テンプレートの記法は含めず、tests/ からそのまま source できる）。
# 前提: bootstrap/lib.sh を source 済み（note / running_from_any / running_matching）。
#
# 消すのは aqua がそのコマンドを提供しているときだけ。~/.local/bin は aqua の bin より PATH の前に
# あるため、公式インストーラの実体が残ると aqua の版が使われない。設定・認証・履歴（~/.claude、
# ~/.codex の他の中身、~/.codegraph/telemetry.json など）には触れない。

# ai_provided <cmd>
# aqua が <cmd> の実体を提供していれば 0。aqua which は未導入でもパスを返し、aqua 管理外のコマンドも
# PATH から拾って返すため、aqua の pkgs 配下であり、かつ実体が在ることまで確かめる。
# 共有ストアでもホームのフォールバックでも、ホームの pkgs（共有側への symlink を含む）経由で解決される。
ai_provided() {
	local p
	p="$(aqua which "$1" 2>/dev/null)" || return 1
	case "$p" in
	*/aquaproj-aqua/pkgs/*) [ -f "$p" ] ;;
	*) return 1 ;;
	esac
}

# _ai_busy <dir> <link...>
# 動いているプロセスがあれば 0。次のどれかで見る。
#   - 実行ファイルが <dir> の下にある（running_from_any / running_matching）
#   - 実行ファイルのパスが <link> のどれかと完全に一致する（running_exact）
# macOS の ps は PATH 上のリンクで起動したプロセスをリンクのパス（~/.local/bin/claude など）で出し、
# 実体の <dir> を出さない。リンクを外した後も古いプロセスは同じパスを報告するため、外した後も照合する。
_ai_busy() {
	local dir="$1" l
	shift
	running_from_any "$dir" && return 0
	running_matching "${dir%/}/" && return 0
	for l in "$@"; do
		running_exact "$l" && return 0
	done
	return 1
}

# _ai_unlink <path> <実体の場所の部分文字列>
# PATH 上のリンク（または実行ファイル）を外す。aqua の実体を指す symlink と、インストーラの置いた
# 実体を指さない symlink には触れない。部分文字列が空なら、symlink かどうかを問わず外す。
_ai_unlink() {
	local p="$1" sub="$2" t
	[ -e "$p" ] || [ -L "$p" ] || return 0
	if [ -L "$p" ]; then
		t="$(readlink "$p")"
		case "$t" in
		*/aquaproj-aqua/*)
			return 0
			;;
		esac
		if [ -n "$sub" ]; then
			case "$t" in
			*"$sub"*) ;;
			*)
				note "インストーラの実体を指していないため残します: $p"
				return 0
				;;
			esac
		fi
	elif [ -n "$sub" ]; then
		note "リンクではないため残します: $p"
		return 0
	fi
	note "aqua の版を使うため削除: $p"
	rm -f "$p"
}

# _ai_unlink_into <bin_dir> <実体の場所の部分文字列>
# <bin_dir> の symlink のうち、指す先に部分文字列を含むものを全て外す。公式インストーラは本体のほかに
# 補助のコマンド（codex の codex-code-mode-host など）のリンクも置くため、本体の名前だけでは外し漏れる。
_ai_unlink_into() {
	local dir="$1" sub="$2" l
	for l in "$dir"/*; do
		[ -L "$l" ] || continue
		case "$(readlink "$l")" in
		*"$sub"*) _ai_unlink "$l" "$sub" ;;
		esac
	done
}

# _ai_rmdir <path>: 在れば再帰的に消す。
_ai_rmdir() {
	[ -e "$1" ] || [ -L "$1" ] || return 0
	note "aqua の版を使うため削除: $1"
	rm -rf "$1"
}

# ai_cleanup_home <home>
# <home> の公式インストーラの実体を、aqua が提供しているコマンドの分だけ消す。
# 動いているプロセス（実体の下から、またはリンクのパスで起動したもの）がある間は PATH 上のリンクだけ外し、
# 実体は次の apply で消す
# （起動し直しや後から読み込むファイルが壊れないようにする）。
ai_cleanup_home() {
	local home="$1" f

	if ai_provided claude; then
		_ai_unlink "$home/.local/bin/claude" "/.local/share/claude/"
		_ai_unlink_into "$home/.local/bin" "/.local/share/claude/"
		if _ai_busy "$home/.local/share/claude/versions" "$home/.local/bin/claude"; then
			note "古い claude が動いているため ~/.local/share/claude は次の chezmoi apply で消します"
		else
			_ai_rmdir "$home/.local/share/claude"
			_ai_rmdir "$home/.local/state/claude"
			_ai_rmdir "$home/.cache/claude"
		fi
	fi

	if ai_provided codex; then
		_ai_unlink "$home/.local/bin/codex" "/.codex/packages/"
		_ai_unlink_into "$home/.local/bin" "/.codex/packages/"
		if _ai_busy "$home/.codex/packages" "$home/.local/bin/codex" "$home/.agents/bin/codex"; then
			note "古い codex が動いているため ~/.codex/packages は次の chezmoi apply で消します"
		else
			_ai_rmdir "$home/.codex/packages"
		fi
	fi

	if ai_provided codegraph; then
		_ai_unlink "$home/.local/bin/codegraph" "/.codegraph/"
		_ai_unlink_into "$home/.local/bin" "/.codegraph/"
		if _ai_busy "$home/.codegraph/versions" "$home/.local/bin/codegraph"; then
			note "古い codegraph が動いているため ~/.codegraph/versions は次の chezmoi apply で消します"
		else
			_ai_rmdir "$home/.codegraph/current"
			_ai_rmdir "$home/.codegraph/versions"
		fi
	fi

	# macOS の Kiro は aqua が提供しない（linux のみ）ので、ここには来ない。
	if ai_provided kiro-cli; then
		for f in kiro-cli kiro-cli-chat kiro-cli-term; do
			_ai_unlink "$home/.local/bin/$f" ""
		done
	fi
}
