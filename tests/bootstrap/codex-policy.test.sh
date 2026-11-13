#!/usr/bin/env bash
# bootstrap/31-codex-policy.sh のテスト（ステップの契約: --check / 引数なし）。
# CODEX_MANAGED_DIR と SHARED_ROOT を一時ディレクトリへ向ける。
set -eu
# shellcheck source-path=SCRIPTDIR source=../lib.sh
. "$(dirname "$0")/../lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
step="$REPO/bootstrap/31-codex-policy.sh"
export SHARED_ROOT="$tmp/opt" CODEX_MANAGED_DIR="$tmp/etc/codex" DOTFILES_SRC="$REPO" BOOTSTRAP_ALLOW_NONROOT=1

rc=0
bash "$step" --check || rc=$?
assert_eq "1" "$rc" "未配置: --check は 1"
[ ! -e "$tmp/etc" ] && [ ! -e "$tmp/opt" ] || fail "--check が何かを書いた"

bash "$step" >/dev/null
dest="$CODEX_MANAGED_DIR/managed_config.toml"
cmp "$REPO/bootstrap/codex/managed_config.toml" "$dest" || fail "配置した内容がソースと違う"
assert_contains "$(cat "$dest")" "check_for_update_on_startup = false" "更新確認を止める設定"
mode="$(stat -c %a "$dest" 2>/dev/null || stat -f %Lp "$dest")"
assert_eq "644" "$mode" "ファイルは 644"
assert_eq "1" "$(wc -l <"$SHARED_ROOT/dotfiles-shared/keys/31" | tr -d ' ')" "キーは 1 行"
bash "$step" --check || fail "配置後の --check が通らない"
echo "PASS: 配置後は --check が 0"

# 冪等
bash "$step" >/dev/null
bash "$step" --check || fail "再実行後の --check が通らない"

# ピンが変われば食い違う（DOTFILES_SRC のコピーを書き換える）
mkdir -p "$tmp/src/bootstrap/codex"
cp "$REPO/bootstrap/codex/managed_config.toml" "$tmp/src/bootstrap/codex/"
echo '# changed' >>"$tmp/src/bootstrap/codex/managed_config.toml"
rc=0
DOTFILES_SRC="$tmp/src" bash "$step" --check || rc=$?
assert_eq "1" "$rc" "ソースが変われば --check は 1"

# 配置先ファイルが消されたら、キーが一致していても食い違いとする
rm "$dest"
rc=0
bash "$step" --check || rc=$?
assert_eq "1" "$rc" "配置先が無ければ --check は 1"
bash "$step" >/dev/null
bash "$step" --check || fail "復旧後の --check が通らない"
echo "ALL PASS"
