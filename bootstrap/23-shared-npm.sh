#!/usr/bin/env bash
# npm で配られる CLI を共有ストア $SHARED_ROOT/npm-global に置く。root で実行する。
#   23-shared-npm.sh --check   共有側がソースのピンと一致するか（0 一致 / 1 食い違い）。何も書かない。
#   23-shared-npm.sh           $SHARED_ROOT/npm-global/<key> に入れ、current をそこへ向け、古い組を掃除して、キーを書く。
# 環境変数: DOTFILES_SRC / SHARED_ROOT（既定 /opt）/ AQUA_BIN（呼び出しユーザの aqua の絶対パス）。
#
# Node は共有 aqua ストアの nodejs/node（aqua.yaml のピン）を使う。各ユーザは ~/.config/shell/env.sh が
# PATH に入れる $SHARED_ROOT/npm-global/current/bin から使う。
#
# npm の bin は `#!/usr/bin/env node` で、PATH 上の node で動く。プロジェクトで fnm が古い node に
# 切り替えていると要求する版を満たせないので、<key>/bin には共有の node を絶対パスで指定する
# ラッパーを置く。
#
# 版は下の NPM_GLOBALS で固定する（Renovate が上げる）。名前（key）は node のピンと一覧から決まり、
# どちらかが変わると新しい key へ入れ直して current を向け直す。変わらなければ取得しない。
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"

SHARED_ROOT="${SHARED_ROOT:-/opt}"
DOTFILES_SRC="${DOTFILES_SRC:-$(dirname "$here")}"
ROOT="$SHARED_ROOT/npm-global"
KEYFILE="$SHARED_ROOT/dotfiles-shared/keys/23"
AQUA_STORE="$SHARED_ROOT/aquaproj-aqua"

# 1 行 1 パッケージで <pkg>@<version> を書く（Renovate の regex manager がこの形を読む）。
NPM_GLOBALS=""
# ブラウザで差分を読む diff ビューア（herdr の <prefix> d から herdr-difit 経由で起動）。
NPM_GLOBALS="$NPM_GLOBALS difit@5.0.12"
# Cline CLI。VS Code 拡張と同じエージェントを端末で動かす。公式の配布は npm だけ。
NPM_GLOBALS="$NPM_GLOBALS cline@3.0.74"

# キーは node のピン（aqua.yaml の nodejs/node@... の行）と NPM_GLOBALS から決める。
src_key() {
	local node_pin
	node_pin="$(grep -E '^[[:space:]]*-[[:space:]]*name:[[:space:]]*nodejs/node@' "$DOTFILES_SRC/dot_config/aquaproj-aqua/aqua.yaml" | head -1 || true)"
	pins_key <(printf '%s\n%s\n' "$node_pin" "$NPM_GLOBALS")
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
# node は共有 aqua から引く。揃えるのは 20 の役目なので、揃っていなければここでは進めない。
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

NODE="$("$AQUA_BIN" which node 2>/dev/null || true)"
NPM="$("$AQUA_BIN" which npm 2>/dev/null || true)"
if [ -z "$NODE" ] || [ ! -x "$NODE" ] || [ -z "$NPM" ] || [ ! -x "$NPM" ]; then
	echo "共有 aqua ストアに node / npm がありません。先に bootstrap/20-shared-aqua.sh を実行し、aqua.yaml に nodejs/node があるか確かめてください" >&2
	exit 1
fi
NODE_DIR="$(dirname "$NODE")"

KEY="$(src_key)"
DEST="$ROOT/$KEY"

log "共有ディレクトリ ${ROOT} を準備 (${owner_group})"
mkdir -p "$ROOT"
set_owner "$ROOT"
chmod 755 "$ROOT"

# <dir>/bin の下の名前を並べる。
bin_names() {
	local f
	for f in "$1"/bin/*; do
		[ -e "$f" ] || [ -L "$f" ] || continue
		basename "$f"
	done
}

# npm の bin（相対 symlink）の指す実体の絶対パス。
link_target() {
	local link="$1" t d
	t="$(readlink "$link")"
	case "$t" in
	/*) ;;
	*) t="$(dirname "$link")/$t" ;;
	esac
	d="$(cd "$(dirname "$t")" && pwd -P)"
	printf '%s/%s\n' "$d" "$(basename "$t")"
}

# write_wrapper <出力先> <JS の実体>: 共有の node を絶対パスで呼ぶラッパーを書く。
write_wrapper() {
	cat >"$1" <<WRAP || return 1
#!/bin/sh
PATH="$NODE_DIR:\$PATH" exec "$NODE" "$2" "\$@"
WRAP
	chmod 755 "$1"
}

# $DEST に入れる。途中で失敗したら $DEST を消して非 0 を返す（current とキーには触れない）。
install_set() {
	local cache link name target rel real spec rc=0
	cache="$(mktemp -d)" || return 1
	rm -rf "$DEST"
	mkdir -p "$DEST" || return 1
	# --ignore-scripts: 一覧のどれも install script を走らせなくてよい（cline のは失敗しても無視される後処理）。
	# npm のキャッシュは一時ディレクトリに置き、終わったら消す（root が誰かのキャッシュに書かない）。
	# 呼び出したユーザや root の .npmrc は読まない。user / global の設定は別々の空ファイルにする
	# （npm は同じファイルを両方に指定すると double-loading config で止まる）。
	: >"$cache/npmrc.user" && : >"$cache/npmrc.global" || return 1
	# shellcheck disable=SC2086
	npm_config_cache="$cache" npm_config_userconfig="$cache/npmrc.user" npm_config_globalconfig="$cache/npmrc.global" PATH="$NODE_DIR:$PATH" "$NPM" install -g --prefix "$DEST/prefix" \
		--ignore-scripts --no-fund --no-audit --no-update-notifier $NPM_GLOBALS || rc=$?
	rm -rf "$cache"
	if [ "$rc" -ne 0 ]; then
		rm -rf "$DEST"
		return "$rc"
	fi

	# errexit は if の条件内で効かないため、大事なコマンドごとに失敗を返す。
	mkdir -p "$DEST/bin" || {
		rm -rf "$DEST"
		return 1
	}
	# link_target は pwd -P で実体のパスにする（macOS の /var -> /private/var など）ので、$DEST も実体で揃えて剥がす。
	real="$(cd "$DEST" && pwd -P)" || {
		rm -rf "$DEST"
		return 1
	}
	for link in "$DEST/prefix/bin/"*; do
		[ -L "$link" ] || continue
		name="$(basename "$link")"
		target="$(link_target "$link")" || {
			rm -rf "$DEST"
			return 1
		}
		rel="${target#"$real"/}"
		if ! write_wrapper "$DEST/bin/$name" "$DEST/$rel"; then
			rm -rf "$DEST"
			return 1
		fi
	done
	# NPM_GLOBALS の各パッケージの bin（パッケージ名の末尾と同名）が実行できることを確かめてから完了にする。
	for spec in $NPM_GLOBALS; do
		name="${spec%@*}"
		name="${name##*/}"
		if [ ! -x "$DEST/bin/$name" ]; then
			echo "$name の実行ファイルが $DEST/bin にありません" >&2
			rm -rf "$DEST"
			return 1
		fi
	done
	touch "$DEST/.complete" || {
		rm -rf "$DEST"
		return 1
	}
}

if [ -f "$DEST/.complete" ]; then
	log "npm の CLI は配置済み ($KEY)"
else
	log "npm の CLI を入れる ($KEY)"
	if ! install_set; then
		echo "npm の CLI を入れられませんでした。current は変えません" >&2
		exit 1
	fi
fi
set_owner "$DEST"
chmod -R a+rX "$DEST"

prev="$(readlink "$ROOT/current" 2>/dev/null || true)"
log "current を $KEY に向ける"
swap_symlink "$KEY" "$ROOT/current"
mkdir -p "$(dirname "$KEYFILE")"
src_key >"$KEYFILE"

# 動いているプロセスの実行ファイルが <name> の組の下にある、またはそのリンクで起動された、
# あるいは引数にその組のパスを含む（node が組の下の JS を読んでいる）ときは 0。
# macOS の ps は PATH 上のリンクで起動したプロセスをそのリンクのパスで出し、実体の組は出さない。
set_busy() {
	local d="$1" name n args
	name="$(basename "$d")"
	running_from_any "$d" && return 0
	running_matching "/npm-global/$name/" && return 0
	for n in $(bin_names "$d"); do
		running_exact "$ROOT/current/bin/$n" && return 0
		running_exact "$d/bin/$n" && return 0
	done
	args="$(ps -axww -o args= 2>/dev/null || true)"
	case "$args" in
	*"/npm-global/$name/"* | *"$d/"*) return 0 ;;
	esac
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
	name="$(basename "$d")"
	[ "$name" = "$KEY" ] && continue
	[ -n "$prev" ] && [ "$name" = "$prev" ] && continue
	if set_busy "$d"; then
		note "使用中のため残します: $d"
		gc_defer
		continue
	fi
	note "削除: $d"
	rm -rf "$d"
done

log "完了: npm の CLI を ${ROOT}/current に置きました"
note "各ユーザは ~/.config/shell/env.sh が PATH に入れる ${ROOT}/current/bin から使います"
