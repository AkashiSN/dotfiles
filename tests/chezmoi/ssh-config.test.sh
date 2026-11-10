#!/usr/bin/env bash
# personal=false で個人のホスト・鍵を出さず、既定（true）では出すこと。
set -u
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"

tmpl="$REPO/private_dot_ssh/private_config.tmpl"

out="$(chezmoi_render "$tmpl" personal=false)" || fail "render personal=false"
assert_not_contains "$out" "AkashiSN" "no AkashiSN when personal=false"
assert_not_contains "$out" "Host gw-suita" "no gw-suita when personal=false"
assert_not_contains "$out" "Host truenas" "no truenas when personal=false"
assert_not_contains "$out" "1password_AkashiSN" "no personal key when personal=false"
assert_contains "$out" "Host *" "Host * remains"
assert_contains "$out" "Host gitlab.com" "gitlab.com remains"
assert_contains "$out" "Host github.com" "github.com remains"

out_default="$(chezmoi_render "$tmpl")" || fail "render default"
assert_contains "$out_default" "Host gw-suita" "default keeps gw-suita"
assert_contains "$out_default" "Host truenas" "default keeps truenas"
assert_contains "$out_default" "Host github.com github.com-AkashiSN" "default keeps github.com"
assert_contains "$out_default" "IdentityFile    ~/.ssh/1password_AkashiSN.pub" "default keeps key"

# 管理対象の一覧
managed_false="$(chezmoi_managed personal=false)" || fail "managed personal=false"
managed_true="$(chezmoi_managed)" || fail "managed default"
for f in .ssh/1password_AkashiSN.pub .ssh/1password_su-nishi.pub .ssh/allowed_signers .ssh/authorized_keys .ssh/gpg.pub; do
	assert_not_contains "$managed_false" "$f" "$f not managed when personal=false"
	assert_contains "$managed_true" "$f" "$f managed by default"
done
assert_contains "$managed_false" ".ssh/config" ".ssh/config managed when personal=false"

# chezmoi.toml に personal が無い（init 前）場合も既定（true）と同じに出す
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
: >"$tmp/chezmoi.toml"
out_nodata="$(chezmoi --source "$REPO" --config "$tmp/chezmoi.toml" execute-template <"$tmpl")" || fail "render no data"
assert_contains "$out_nodata" "Host gw-suita" "fallback without data"
