#!/usr/bin/env bash
# Codex の管理者設定 bootstrap/codex/managed_config.toml を $CODEX_MANAGED_DIR（既定 /etc/codex）へ置く。
# Linux と macOS のどちらも /etc/codex/managed_config.toml が置き場所（OpenAI の Codex ドキュメントの
# Managed configuration の Locations）。root で実行する。
#   31-codex-policy.sh --check   置いてあるファイルがソースと同じで、キーも一致するか（0 一致 / 1 食い違い）。
#   31-codex-policy.sh           ファイルを root:所有グループ 644 で置き、キーを書く。
# 環境変数: DOTFILES_SRC / SHARED_ROOT（既定 /opt）/ CODEX_MANAGED_DIR（既定 /etc/codex。テスト用の上書き）。
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"

SHARED_ROOT="${SHARED_ROOT:-/opt}"
DOTFILES_SRC="${DOTFILES_SRC:-$(dirname "$here")}"
CODEX_MANAGED_DIR="${CODEX_MANAGED_DIR:-/etc/codex}"
KEYFILE="$SHARED_ROOT/dotfiles-shared/keys/31"
SRC="$DOTFILES_SRC/bootstrap/codex/managed_config.toml"
DEST="$CODEX_MANAGED_DIR/managed_config.toml"

if [ "${1:-}" = "--check" ]; then
	[ -f "$KEYFILE" ] && [ "$(cat "$KEYFILE")" = "$(pins_key "$SRC")" ] && [ -f "$DEST" ] && cmp -s "$SRC" "$DEST"
	exit
fi

if [ "${BOOTSTRAP_ALLOW_NONROOT:-}" != 1 ] && [ "$(id -u)" -ne 0 ]; then
	echo "root で実行してください" >&2
	exit 1
fi
[ -f "$SRC" ] || {
	echo "$SRC が見つかりません" >&2
	exit 1
}

log "Codex の管理者設定を $DEST へ配置"
umask 022
mkdir -p "$CODEX_MANAGED_DIR"
chmod 755 "$CODEX_MANAGED_DIR"
cp "$SRC" "$DEST.tmp.$$"
chmod 644 "$DEST.tmp.$$"
# root のときだけ所有者を揃える（テストは一般ユーザで流す）。
[ "$(id -u)" -ne 0 ] || chown "$(shared_owner_group)" "$CODEX_MANAGED_DIR" "$DEST.tmp.$$"
mv -f "$DEST.tmp.$$" "$DEST"

mkdir -p "$(dirname "$KEYFILE")"
pins_key "$SRC" >"$KEYFILE"
log "完了: Codex の管理者設定を置きました（各ユーザは次回起動時から反映）"
