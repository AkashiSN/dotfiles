#!/usr/bin/env bash
# 共有 aqua ストア $SHARED_ROOT/aquaproj-aqua（pkgs / bin / config）を揃える。root で実行する。
#   20-shared-aqua.sh --check   共有側がソースのピンと一致するか（0 一致 / 1 食い違い）。何も書かない。
#   20-shared-aqua.sh           config を置き、aqua で install し、古い版を掃除して、キーを書く。
# 環境変数: DOTFILES_SRC / SHARED_ROOT（既定 /opt）/ AQUA_BIN（呼び出しユーザの aqua の絶対パス）/
#           GITHUB_TOKEN（呼び出しユーザの gh の token。無くてもよい）。
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"

SHARED_ROOT="${SHARED_ROOT:-/opt}"
DOTFILES_SRC="${DOTFILES_SRC:-$(dirname "$here")}"
STORE="$SHARED_ROOT/aquaproj-aqua"
CONFIG="$STORE/config"
KEYFILE="$SHARED_ROOT/dotfiles-shared/keys/20"
SRC_CFG="$DOTFILES_SRC/dot_config/aquaproj-aqua"
# 共有側へ置く 4 ファイル。キーはこの順で計算する。
PIN_FILES="aqua.yaml registry.yaml aqua-policy.yaml aqua-checksums.json"

src_key() {
	local f files=()
	for f in $PIN_FILES; do
		files+=("$SRC_CFG/$f")
	done
	pins_key "${files[@]}"
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

umask 022
owner_group="$(shared_owner_group)"
# root のときだけ所有者を揃える（テストは一般ユーザで流す）。
set_owner() {
	[ "$(id -u)" -ne 0 ] || chown "$owner_group" "$@"
}

log "共有 aqua ストア ${STORE} を準備 (${owner_group})"
mkdir -p "$CONFIG"
set_owner "$STORE" "$CONFIG"
chmod 755 "$STORE" "$CONFIG"

# 新しい config は config.new/ に置き、そこを向けて install する。成功したときだけ config/ へ移す。
# 失敗したら config/ には触れず、中途半端な状態を共有側として採用しない。
STAGE="$STORE/config.new"
trap 'rm -rf "$STAGE"' EXIT
rm -rf "$STAGE"
mkdir -p "$STAGE"
for f in $PIN_FILES; do
	cp "$SRC_CFG/$f" "$STAGE/$f"
	chmod 644 "$STAGE/$f"
done
set_owner "$STAGE" "$STAGE"/*

# 作業ディレクトリに aqua.yaml があると拾われるため、ルートへ移る。
cd /
export AQUA_ROOT_DIR="$STORE"
export AQUA_GLOBAL_CONFIG="$STAGE/aqua.yaml"
export AQUA_POLICY_CONFIG="$STAGE/aqua-policy.yaml"
# attestation の検証が呼ぶ gh は共有 bin にある。
export PATH="$STORE/bin:$PATH"

# local registry のパッケージを許可する。許可が無いと aqua が "this package isn't allowed" で拒否する。
"$AQUA_BIN" policy allow "$AQUA_POLICY_CONFIG"

# attestation の検証は gh を呼び、その gh も aqua 管理のため、token が無いと検証つきの install は
# 通らない。token が空なら bootstrap タグの gh だけ検証なしで先に入れ、残りは検証つきで入れる。
if [ -z "${GITHUB_TOKEN:-}" ]; then
	warn "GITHUB_TOKEN が空です。bootstrap タグの gh だけ検証なしで導入します"
	AQUA_DISABLE_GITHUB_ARTIFACT_ATTESTATION=true "$AQUA_BIN" install -a -t bootstrap
fi
log "aqua 管理ツールを共有ストアへ install"
"$AQUA_BIN" install -a

# install が通ったので config/ へ移す。aqua.yaml を最後にして、途中で止まっても旧い組のまま読まれない順にする。
for f in registry.yaml aqua-policy.yaml aqua-checksums.json aqua.yaml; do
	mv -f "$STAGE/$f" "$CONFIG/$f"
done
rmdir "$STAGE"
export AQUA_GLOBAL_CONFIG="$CONFIG/aqua.yaml"
export AQUA_POLICY_CONFIG="$CONFIG/aqua-policy.yaml"
"$AQUA_BIN" policy allow "$AQUA_POLICY_CONFIG"

# 共有 aqua の github_release は pkgs/github_release/<host>/<owner>/<repo>/<version>/ に置かれる。
# 共有 config に次の行として載るパッケージの、参照されなくなった版だけを消す。
#   - name: <owner>/<repo>@<version>   （引用符なし、version に / や空白なし、行末コメントのみ可）
# <owner>/<repo> がそれ以外の形（引用符つき、version: 別行、/ を含む版、コメントのみの言及など）でも
# 出てくる場合、または版が載っていなければ、そのパッケージの版は全て残す。
# 設定の版で終わる名前や、設定の版と同名のディレクトリが無いパッケージ（version_prefix つきのタグ）も残す。
# cli/cli（gh）は消さない。aqua は attestation の検証に自分で固定した版の gh を入れて使うため、
# 設定の版と違っても参照されている。
# どのユーザのプロセスでも、その版の下から動いていれば消さず次回に回す。macOS の ps は
# ホームの symlink 経由で起動したパス（.../aquaproj-aqua/pkgs/...）を出すため、それでも照合する。
gc_old_versions() {
	local base="$STORE/pkgs/github_release" d rel host o r v key lines line l nm ver vers ok x found
	[ -d "$base" ] || return 0
	for d in "$base"/*/*/*/*; do
		[ -d "$d" ] || continue
		rel="${d#"$base"/}"
		host="${rel%%/*}"
		v="${d##*/}"
		r="${d%/*}"
		r="${r##*/}"
		o="${d%/*/*}"
		o="${o##*/}"
		key="$(printf '%s/%s' "$o" "$r" | tr '[:upper:]' '[:lower:]')"
		[ "$key" != cli/cli ] || continue
		lines="$(grep -iF -- "$key" "$CONFIG/aqua.yaml" || true)"
		ok=1
		vers=""
		while IFS= read -r line; do
			[ -n "$line" ] || continue
			l="$(printf '%s\n' "$line" | sed -nE "s|^[[:space:]]*-[[:space:]]*name:[[:space:]]*([^[:space:]\"'#@]+)@([^[:space:]\"'#/]+)[[:space:]]*(#.*)?\$|\\1 \\2|p")"
			if [ -z "$l" ]; then
				ok=0
				break
			fi
			nm="$(printf '%s' "${l% *}" | tr '[:upper:]' '[:lower:]')"
			ver="$(printf '%s' "${l#* }" | tr '[:upper:]' '[:lower:]')"
			if [ "$nm" != "$key" ]; then
				ok=0
				break
			fi
			vers="$vers $ver"
		done <<<"$lines"
		[ "$ok" -eq 1 ] && [ -n "$vers" ] || continue
		v="$(printf '%s' "$v" | tr '[:upper:]' '[:lower:]')"
		# 設定の版と同名の版ディレクトリが 1 つも無ければ、設定と dir の命名が対応しているか分からないので残す。
		found=0
		for x in "${d%/*}"/*; do
			x="$(printf '%s' "${x##*/}" | tr '[:upper:]' '[:lower:]')"
			case " $vers " in
			*" $x "*) found=1 ;;
			esac
		done
		[ "$found" -eq 1 ] || continue
		for x in $vers; do
			case "$v" in
			*"$x") continue 2 ;;
			esac
		done
		if running_from_any "$d" || running_matching "/aquaproj-aqua/pkgs/github_release/$host/$o/$r/${d##*/}/"; then
			note "使用中のため残します: $d"
			gc_defer
			continue
		fi
		note "古い版を削除: $key@${d##*/}"
		rm -rf "$d"
	done
}
gc_old_versions

log "全ユーザが読めて root だけが書ける権限にする (a+rX,go-w)"
chmod -R a+rX,go-w "$STORE"

mkdir -p "$(dirname "$KEYFILE")"
src_key >"$KEYFILE"
log "完了: 共有 aqua ストアを揃えました"
