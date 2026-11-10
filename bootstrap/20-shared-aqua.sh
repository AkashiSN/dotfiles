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
for f in $PIN_FILES; do
	cp "$SRC_CFG/$f" "$CONFIG/.$f.new"
	chmod 644 "$CONFIG/.$f.new"
	set_owner "$CONFIG/.$f.new"
	mv -f "$CONFIG/.$f.new" "$CONFIG/$f"
done

export AQUA_ROOT_DIR="$STORE"
export AQUA_GLOBAL_CONFIG="$CONFIG/aqua.yaml"
export AQUA_POLICY_CONFIG="$CONFIG/aqua-policy.yaml"
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

# 共有 aqua の github_release は pkgs/github_release/github.com/<owner>/<repo>/<version>/ に置かれる。
# 共有 config に <owner>/<repo>@<別の版> として載っているパッケージの、参照されなくなった版を消す。
# config に名前が出てこないパッケージ（依存や他の種別）には触らない。どのユーザのプロセスでも
# その版の下から動いていれば消さず、次回に回す。
gc_old_versions() {
	local base="$STORE/pkgs/github_release/github.com" refs d v r o key
	[ -d "$base" ] || return 0
	refs="$(grep -oE '[A-Za-z0-9._-]+/[A-Za-z0-9._-]+@[^ "]+' "$CONFIG/aqua.yaml" | tr '[:upper:]' '[:lower:]' || true)"
	for d in "$base"/*/*/*; do
		[ -d "$d" ] || continue
		v="${d##*/}"
		r="${d%/*}"
		r="${r##*/}"
		o="${d%/*/*}"
		o="${o##*/}"
		key="$(printf '%s/%s' "$o" "$r" | tr '[:upper:]' '[:lower:]')"
		# 名前が載っていなければ対象外。
		printf '%s\n' "$refs" | awk -v p="$key@" 'index($0, p) == 1 { f = 1 } END { exit !f }' || continue
		# この版が載っていれば残す。
		printf '%s\n' "$refs" | grep -qixF "$key@$(printf '%s' "$v" | tr '[:upper:]' '[:lower:]')" && continue
		if running_from_any "$d"; then
			note "使用中のため残します: $d"
			continue
		fi
		note "古い版を削除: $key@$v"
		rm -rf "$d"
	done
}
gc_old_versions

log "全ユーザが読めるよう world 読取/実行権限を付与"
chmod -R a+rX "$STORE"

mkdir -p "$(dirname "$KEYFILE")"
src_key >"$KEYFILE"
log "完了: 共有 aqua ストアを揃えました"
