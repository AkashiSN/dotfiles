#!/usr/bin/env bash
# uv で入れる Python と CLI を共有ストア $SHARED_ROOT/uv に置く。root で実行する。
#   24-shared-uv.sh --check   共有側がソースのピンと一致するか（0 一致 / 1 食い違い）。何も書かない。
#   24-shared-uv.sh           $SHARED_ROOT/uv/<key> に入れ、current をそこへ向け、古い組を掃除して、キーを書く。
# 環境変数: DOTFILES_SRC / SHARED_ROOT（既定 /opt）/ AQUA_BIN（呼び出しユーザの aqua の絶対パス）。
#
# 配置:
#   $SHARED_ROOT/uv/python/                    uv の Python の置き場（UV_PYTHON_INSTALL_DIR）。Python の版ごとの
#                                              ディレクトリで、ツールの版が変わっても動かない。
#   $SHARED_ROOT/uv/<key>/{tools,bin}          1 組。tools は UV_TOOLS の venv、bin は python / python3 /
#                                              python3.N と各ツールのコマンド。
#   $SHARED_ROOT/uv/current -> <key>           向け先だけを原子的に切り替える。
#   $SHARED_ROOT/uv/{tools,bin} -> current/{tools,bin}   固定の symlink。
# uv は venv のシェバンやコマンドの symlink に入れ先の絶対パスを書くので、組は <key> の中へ直接入れる。
# プロジェクトの venv も uv の Python のパスを記録するため、Python を組の外の固定の場所に置き、
# ツールの版を上げても各自の venv が壊れないようにする。Python の版（dot_python-version）を上げたときだけ
# 新しい Python が増え、古い Python は、動いておらず、残る組のどれも使っていないときに消す。
#
# 各ユーザは ~/.config/shell/env.sh が PATH に入れる $SHARED_ROOT/uv/bin から使う。uv は PATH 上の
# python3.N も見つけるので、各ユーザの uv run / uv venv も、版が合えばここの Python を使う。
#
# uv 本体は共有 aqua ストア（aqua.yaml のピン）から引く。Python の版は dot_config/uv/dot_python-version の
# 1 か所、ツールの版は下の UV_TOOLS で固定する（Renovate が上げる）。名前（key）はこの 2 つから決まり、
# どちらかが変わると新しい key へ入れ直して current を向け直す。変わらなければ取得しない。
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"

SHARED_ROOT="${SHARED_ROOT:-/opt}"
DOTFILES_SRC="${DOTFILES_SRC:-$(dirname "$here")}"
ROOT="$SHARED_ROOT/uv"
PYDIR="$ROOT/python"
KEYFILE="$SHARED_ROOT/dotfiles-shared/keys/24"
AQUA_STORE="$SHARED_ROOT/aquaproj-aqua"

# 1 行 1 パッケージで <pkg>==<version> を書く（Renovate の regex manager がこの形を読む）。
# extra は <pkg>[extra,...]==<version>。
UV_TOOLS=""
# Ansible。
UV_TOOLS="$UV_TOOLS ansible==8.7.0"
# graphify（PyPI 上のパッケージ名は graphifyy、コマンド名は graphify）。SQL / HCL のパーサーは
# 必須依存ではなく extra なので明示する（terraform extra が tree-sitter-hcl を連れてくる）。
# 各ユーザの claude への登録（graphify install）は run_after_40-ai-assistants が行う。
UV_TOOLS="$UV_TOOLS graphifyy[sql,terraform]==0.9.70"

py_version() { tr -d '[:space:]' <"$DOTFILES_SRC/dot_config/uv/dot_python-version"; }

# キーは Python の版と UV_TOOLS から決める。
src_key() {
	pins_key <(printf '%s\n%s\n' "$(py_version)" "$UV_TOOLS")
}

if [ "${1:-}" = "--check" ]; then
	[ -f "$KEYFILE" ] && [ "$(cat "$KEYFILE")" = "$(src_key)" ]
	exit
fi

if [ "${BOOTSTRAP_ALLOW_NONROOT:-}" != 1 ] && [ "$(id -u)" -ne 0 ]; then
	echo "root で実行してください" >&2
	exit 1
fi
if [ -z "${AQUA_BIN:-}" ] || [ ! -x "$AQUA_BIN" ]; then
	echo "AQUA_BIN が空か実行できません（呼び出したユーザの aqua の絶対パスを渡す）: '${AQUA_BIN:-}'" >&2
	exit 1
fi
# uv は共有 aqua から引く。揃えるのは 20 の役目なので、揃っていなければここでは進めない。
if [ ! -f "$AQUA_STORE/config/aqua.yaml" ] || [ ! -f "$SHARED_ROOT/dotfiles-shared/keys/20" ]; then
	echo "共有 aqua ストア ($AQUA_STORE) が揃っていません。先に bootstrap/20-shared-aqua.sh を実行してください" >&2
	exit 1
fi

umask 022
owner_group="$(shared_owner_group)"
# root のときだけ所有者を揃える（テストは一般ユーザで流す）。
set_owner() {
	[ "$(id -u)" -ne 0 ] || chown "$owner_group" "$@"
}

# 作業ディレクトリに aqua.yaml があると拾われるため、ルートへ移る。
cd /
export AQUA_ROOT_DIR="$AQUA_STORE"
export AQUA_GLOBAL_CONFIG="$AQUA_STORE/config/aqua.yaml"
export AQUA_POLICY_CONFIG="$AQUA_STORE/config/aqua-policy.yaml"
export AQUA_DISABLE_LAZY_INSTALL=true

UV="$("$AQUA_BIN" which uv 2>/dev/null || true)"
if [ -z "$UV" ] || [ ! -x "$UV" ]; then
	echo "共有 aqua ストアに uv がありません。先に bootstrap/20-shared-aqua.sh を実行し、aqua.yaml に astral-sh/uv があるか確かめてください" >&2
	exit 1
fi

PY_VERSION="$(py_version)"
KEY="$(src_key)"
DEST="$ROOT/$KEY"

log "共有ディレクトリ ${ROOT} を準備 (${owner_group})"
mkdir -p "$ROOT"
# python は実ディレクトリ。固定の symlink だった場合は外す。
[ ! -L "$PYDIR" ] || rm -f "$PYDIR"
mkdir -p "$PYDIR"
set_owner "$ROOT" "$PYDIR"
chmod 755 "$ROOT" "$PYDIR"

# <dir>/bin の下の名前を並べる。
bin_names() {
	local f
	for f in "$1"/bin/*; do
		[ -e "$f" ] || [ -L "$f" ] || continue
		basename "$f"
	done
}

# uv tool list の正規化名（小文字、. と _ は -）。
norm_name() { printf '%s' "$1" | tr '[:upper:]._' '[:lower:]--'; }

# $DEST を消して非 0 を返す。
abort_set() {
	rm -rf "$DEST"
	return 1
}

# $DEST に入れる。途中で失敗したら $DEST を消して非 0 を返す（current とキーには触れない）。
install_set() {
	local cache spec name cmds c rc=0
	cache="$(mktemp -d)" || return 1
	rm -rf "$DEST"
	mkdir -p "$DEST/tools" "$DEST/bin" || {
		rm -rf "$cache"
		return 1
	}
	# 設定ファイル（ユーザや root のもの）を読まず、システムの python も拾わない。
	# uv のキャッシュは一時ディレクトリに置き、終わったら消す（root が誰かのキャッシュに書かない）。
	export UV_CACHE_DIR="$cache" UV_NO_CONFIG=1 UV_PYTHON_PREFERENCE=only-managed
	export UV_PYTHON_INSTALL_DIR="$PYDIR" UV_PYTHON_BIN_DIR="$DEST/bin"
	export UV_TOOL_DIR="$DEST/tools" UV_TOOL_BIN_DIR="$DEST/bin"

	# --default で python / python3 も置く。--default は experimental なので preview を明示する。
	"$UV" python install "$PY_VERSION" --default --preview-features python-install-default || rc=$?
	if [ "$rc" -eq 0 ]; then
		for spec in $UV_TOOLS; do
			"$UV" tool install --python "$PY_VERSION" "$spec" || {
				rc=$?
				break
			}
		done
	fi
	if [ "$rc" -ne 0 ]; then
		rm -rf "$cache"
		abort_set || return "$rc"
	fi

	# 宣言した各ツールのコマンドが 1 つ以上あり、$DEST/bin で実行できることを確かめてから完了にする。
	[ -x "$DEST/bin/python3" ] || {
		echo "python3 が $DEST/bin にありません" >&2
		rm -rf "$cache"
		abort_set
		return 1
	}
	for spec in $UV_TOOLS; do
		name="${spec%%==*}"
		name="$(norm_name "${name%%\[*}")"
		cmds="$("$UV" tool list 2>/dev/null | awk -v n="$name" '$1 != "-" {cur = $1} $1 == "-" && cur == n {print $2}')" || cmds=""
		if [ -z "$cmds" ]; then
			echo "$name のコマンドが見つかりません" >&2
			rm -rf "$cache"
			abort_set
			return 1
		fi
		for c in $cmds; do
			if [ ! -x "$DEST/bin/$c" ]; then
				echo "$c の実行ファイルが $DEST/bin にありません" >&2
				rm -rf "$cache"
				abort_set
				return 1
			fi
		done
	done
	rm -rf "$cache"
	touch "$DEST/.complete" || abort_set
}

if [ -f "$DEST/.complete" ]; then
	log "uv の Python と CLI は配置済み ($KEY)"
else
	log "uv の Python と CLI を入れる ($KEY)"
	if ! install_set; then
		echo "uv の Python と CLI を入れられませんでした。current は変えません" >&2
		exit 1
	fi
fi
set_owner "$DEST"
chmod -R a+rX "$DEST"

prev="$(readlink "$ROOT/current" 2>/dev/null || true)"
log "current を $KEY に向ける"
swap_symlink "$KEY" "$ROOT/current"
# 固定の入口。current の向け先が変わっても、これらは変わらない。
for d in tools bin; do
	swap_symlink "current/$d" "$ROOT/$d"
done
mkdir -p "$(dirname "$KEYFILE")"
src_key >"$KEYFILE"

# 動いているプロセスが <name> の組の下から動いている、そのリンク（共有 bin / 組の bin）で起動された、
# あるいは引数に組のパスを含む（Python が組の下のスクリプトを読んでいる）ときは 0。
# macOS の ps は PATH 上のリンクで起動したプロセスをそのリンクのパスで出し、実体の組は出さない。
# Python のスクリプトは comm がインタプリタで、スクリプトのパスは引数に出る。
set_busy() {
	local d="$1" name n
	name="$(basename "$d")"
	running_from_any "$d" && return 0
	running_matching "/uv/$name/" && return 0
	for n in $(bin_names "$d"); do
		running_exact "$ROOT/bin/$n" && return 0
		running_exact "$d/bin/$n" && return 0
	done
	running_args_matching "/uv/$name/" && return 0
	running_args_matching "$d/" && return 0
	return 1
}

# 動いている MCP サーバーなどが読んでいるかもしれないので、1 つ前の組は残す。
# 同じ key で入れ直した（prev が KEY と同じ）ときは、実際の 1 つ前が分からないため、
# KEY 以外で mtime が最も新しい組を 1 つ前として残す。
if [ "$prev" = "$KEY" ]; then
	prev=""
	best=""
	for d in "$ROOT"/*/; do
		d="${d%/}"
		[ -L "$d" ] && continue
		[ "$(basename "$d")" = "$KEY" ] && continue
		[ "$d" = "$PYDIR" ] && continue
		if [ -z "$best" ] || [ "$d" -nt "$best" ]; then
			best="$d"
		fi
	done
	[ -z "$best" ] || prev="$(basename "$best")"
fi

log "使わなくなった組を削除"
for d in "$ROOT"/*/; do
	d="${d%/}"
	[ -L "$d" ] && continue
	[ "$d" = "$PYDIR" ] && continue
	name="$(basename "$d")"
	[ "$name" = "$KEY" ] && continue
	[ -n "$prev" ] && [ "$name" = "$prev" ] && continue
	if set_busy "$d"; then
		note "使用中のため残します: $d"
		continue
	fi
	note "削除: $d"
	rm -rf "$d"
done

# Python の版ごとのディレクトリ <p> を、残っている組の venv や bin のリンクが使っているか。
# 新しい uv の venv は版ごとのリンク（cpython-3.13-<os>-<arch>-none）経由で記録するので、<p> を指すリンクの名前も見る。
python_used_by_sets() {
	local p="$1" names n l d lk
	names="$(basename "$p")"
	for l in "$PYDIR"/*; do
		[ -L "$l" ] || continue
		[ "$(basename "$(readlink "$l")")" = "$names" ] && names="$names $(basename "$l")"
	done
	for d in "$ROOT"/*/; do
		d="${d%/}"
		[ -L "$d" ] && continue
		[ "$d" = "$PYDIR" ] && continue
		for n in $names; do
			grep -rqsF --include=pyvenv.cfg "/python/$n/" "$d/tools" 2>/dev/null && return 0
			# 組の bin の python3 などのリンクの向け先。
			for lk in "$d"/bin/*; do
				[ -L "$lk" ] || continue
				case "$(readlink "$lk")" in
				*"/python/$n/"*) return 0 ;;
				esac
			done
		done
	done
	return 1
}

# 動いているプロセスが Python <p> の下から動いている（venv のリンク経由も含む）、または引数に含むときは 0。
python_busy() {
	local p="$1"
	running_from_any "$p" && return 0
	running_matching "/uv/python/$(basename "$p")/" && return 0
	running_args_matching "/python/$(basename "$p")/" && return 0
	return 1
}

log "使わなくなった Python を削除"
for p in "$PYDIR"/*/; do
	p="${p%/}"
	[ -L "$p" ] && continue
	pname="$(basename "$p")"
	# 宣言した版（cpython-<版>.* / cpython-<版>-*）は残す。
	case "$pname" in
	"cpython-$PY_VERSION".* | "cpython-$PY_VERSION"-*) continue ;;
	esac
	if python_busy "$p"; then
		note "使用中のため残します: $p"
		continue
	fi
	if python_used_by_sets "$p"; then
		note "残した組が使っているため残します: $p"
		continue
	fi
	note "削除: $p"
	rm -rf "$p"
done
# 消えた Python を指す版ごとのリンクは外す。
for l in "$PYDIR"/*; do
	[ -L "$l" ] && [ ! -e "$l" ] && rm -f "$l"
done

log "完了: uv の Python と CLI を ${ROOT} に置きました"
note "各ユーザは ~/.config/shell/env.sh が PATH に入れる ${ROOT}/bin から使います"
