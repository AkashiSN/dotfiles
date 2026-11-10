#!/usr/bin/env bash
# Terraform の版を共有 tenv ストア $SHARED_ROOT/tenv に置く。root で実行する。
#   21-shared-tenv.sh --check   共有側が tenv-versions.txt と一致するか（0 一致 / 1 食い違い）。何も書かない。
#   21-shared-tenv.sh           版を入れ、一覧に無い版を掃除して、キーを書く。
# 環境変数: DOTFILES_SRC / SHARED_ROOT（既定 /opt）/ AQUA_BIN（呼び出しユーザの aqua の絶対パス）。
#
# terraform の実体は aqua ではなく tenv が管理する（aqua が配るのは tenv 本体だけ）。共有しないと
# 各ユーザが初回に releases.hashicorp.com から個別に取得するため待たされる。terraform は bash の
# 動的補完（complete -C terraform terraform）でも起動されるので、Tab のたびに起きる。
#
# 配置: $SHARED_ROOT/tenv/Terraform/<版>/terraform。各ユーザは run_after_21-tenv-verify が、自分の
# TENV_ROOT（~/.tenv）の版のディレクトリに共有の terraform への symlink を張る。tenv が実行のたびに
# 書く last-use.txt はユーザ側に残る（共有側は読み取り専用）。provider のキャッシュはユーザごとのまま。
#
# 版は同じディレクトリの tenv-versions.txt（1 行 1 版）で固定する。tenv 本体は共有 aqua ストア
# （aqua.yaml のピン）から引く。
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"

SHARED_ROOT="${SHARED_ROOT:-/opt}"
DOTFILES_SRC="${DOTFILES_SRC:-$(dirname "$here")}"
VERSIONS_FILE="$DOTFILES_SRC/bootstrap/tenv-versions.txt"
TENV_STORE="$SHARED_ROOT/tenv"
KEYFILE="$SHARED_ROOT/dotfiles-shared/keys/21"
AQUA_STORE="$SHARED_ROOT/aquaproj-aqua"

# tenv-versions.txt の版（コメントと空行を除く）を 1 行ずつ出す。
versions() {
	local line v
	while IFS= read -r line || [ -n "$line" ]; do
		v="${line%%#*}"
		v="$(printf '%s' "$v" | tr -d '[:space:]')"
		[ -z "$v" ] || printf '%s\n' "$v"
	done <"$VERSIONS_FILE"
}

src_key() {
	pins_key <(printf 'tenv-1\n%s\n' "$(versions | tr '\n' ' ')")
}

if [ "${1:-}" = "--check" ]; then
	[ -f "$VERSIONS_FILE" ] || exit 1
	[ -f "$KEYFILE" ] && [ "$(cat "$KEYFILE")" = "$(src_key)" ]
	exit
fi

if [ "${BOOTSTRAP_ALLOW_NONROOT:-}" != 1 ] && [ "$(id -u)" -ne 0 ]; then
	echo "root で実行してください" >&2
	exit 1
fi
if [ ! -f "$VERSIONS_FILE" ]; then
	echo "$VERSIONS_FILE がありません" >&2
	exit 1
fi
if [ -z "${AQUA_BIN:-}" ] || [ ! -x "$AQUA_BIN" ]; then
	echo "AQUA_BIN が空か実行できません（呼び出したユーザの aqua の絶対パスを渡す）: '${AQUA_BIN:-}'" >&2
	exit 1
fi
# tenv は共有 aqua から引く。揃えるのは 20 の役目なので、揃っていなければここでは進めない。
if [ ! -f "$AQUA_STORE/config/aqua.yaml" ] || [ ! -f "$SHARED_ROOT/dotfiles-shared/keys/20" ]; then
	echo "共有 aqua ストア ($AQUA_STORE) が揃っていません。先に bootstrap/20-shared-aqua.sh を実行してください" >&2
	exit 1
fi

umask 022
owner_group="$(shared_owner_group)"
# root のときだけ所有者を揃える（テストは一般ユーザで流す）。
set_owner() {
	[ "$(id -u)" -ne 0 ] || chown "$@"
}

# 作業ディレクトリの設定ファイル（.terraform-version など）を拾わないよう、ルートへ移る。
cd /
export AQUA_ROOT_DIR="$AQUA_STORE"
export AQUA_GLOBAL_CONFIG="$AQUA_STORE/config/aqua.yaml"
export AQUA_POLICY_CONFIG="$AQUA_STORE/config/aqua-policy.yaml"
export AQUA_DISABLE_LAZY_INSTALL=true

TENV="$("$AQUA_BIN" which tenv 2>/dev/null || true)"
if [ -z "$TENV" ] || [ ! -x "$TENV" ]; then
	echo "共有 aqua ストアに tenv がありません。先に bootstrap/20-shared-aqua.sh を実行し、aqua.yaml に tofuutils/tenv があるか確かめてください" >&2
	exit 1
fi

export TENV_ROOT="$TENV_STORE"
export TENV_VALIDATION=sha
# 呼び出し元の環境に引きずられない。
unset TENV_AUTO_INSTALL TENV_TERRAFORM_VERSION TENV_REMOTE

log "共有ディレクトリ ${TENV_STORE} を準備 (${owner_group})"
mkdir -p "$TENV_STORE"
set_owner "$owner_group" "$TENV_STORE"
chmod 755 "$TENV_STORE"

# 版が入り、terraform が実行できるか確かめる。
verify_version() {
	local bin="$TENV_STORE/Terraform/$1/terraform"
	if [ ! -x "$bin" ]; then
		echo "Terraform $1 の実行ファイルがありません: $bin" >&2
		return 1
	fi
}

log "宣言された版を入れる"
want=" "
while IFS= read -r v; do
	want="$want$v "
	note "Terraform $v"
	had=0
	[ ! -d "$TENV_STORE/Terraform/$v" ] || had=1
	# tenv install は導入済みなら何もしない。失敗したら、元から無かった版の dir は消す。
	if ! "$TENV" terraform install "$v" || ! verify_version "$v"; then
		[ "$had" = 1 ] || rm -rf "${TENV_STORE:?}/Terraform/$v"
		echo "Terraform $v を入れられませんでした。ほかの版とキーは変えません" >&2
		exit 1
	fi
done < <(versions)

set_owner -R "$owner_group" "$TENV_STORE"
chmod -R a+rX,go-w "$TENV_STORE"
mkdir -p "$(dirname "$KEYFILE")"
src_key >"$KEYFILE"

# 版 <v> の terraform が動いているか。macOS の ps は symlink 経由で起動したパス（ホームの ~/.tenv）を
# そのまま出すので、パスの部分文字列でも照合する。
version_busy() {
	local v="$1"
	running_from_any "$TENV_STORE/Terraform/$v" && return 0
	running_matching "/Terraform/$v/" && return 0
	running_args_matching "/Terraform/$v/" && return 0
	return 1
}

log "一覧に無い版を削除"
for d in "$TENV_STORE"/Terraform/*/; do
	d="${d%/}"
	[ -d "$d" ] || continue
	v="$(basename "$d")"
	case "$want" in *" $v "*) continue ;; esac
	if version_busy "$v"; then
		note "使用中のため残します: $d"
		gc_defer
		continue
	fi
	note "削除: $d"
	rm -rf "$d"
done

log "完了: Terraform の版を ${TENV_STORE} に置きました"
note "各ユーザは chezmoi apply のときに ~/.tenv へ symlink を張ります"
