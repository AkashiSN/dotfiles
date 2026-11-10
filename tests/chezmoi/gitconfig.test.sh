#!/usr/bin/env bash
# dot_gitconfig.tmpl が chezmoi データ (.git.*) から identity を組み立てること。
set -u
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"

tmpl="$REPO/dot_gitconfig.tmpl"

out="$(chezmoi_render "$tmpl" git.name=Risa git.email=risa@example.com git.signingkey=)" || fail "render custom"
assert_contains "$out" "name = Risa" "name from data"
assert_contains "$out" "email = risa@example.com" "email from data"
assert_not_contains "$out" "gpgsign = true" "no signing without key"
assert_not_contains "$out" "signingkey" "no signingkey line without key"
assert_not_contains "$out" "AkashiSN" "no personal identity"

out_default="$(chezmoi_render "$tmpl")" || fail "render default"
assert_contains "$out_default" "name = AkashiSN" "default keeps current"
assert_contains "$out_default" "signingkey = ssh-ed25519" "default keeps signingkey"
if [ "$(uname -s)" = Darwin ]; then
	assert_contains "$out_default" "gpgsign = true" "default keeps signing"
fi

# chezmoi.toml に [data.git] が無い（init 前）場合も既定値で展開する
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
: >"$tmp/chezmoi.toml"
out_nodata="$(chezmoi --source "$REPO" --config "$tmp/chezmoi.toml" execute-template <"$tmpl")" || fail "render no data"
assert_contains "$out_nodata" "name = AkashiSN" "fallback without data"

# 共有の Homebrew 用の [safe] は darwin/arm64 だけ
if [ "$(uname -sm)" = "Darwin arm64" ]; then
	assert_contains "$out_default" "directory = /opt/homebrew" "safe directory on darwin/arm64"
	assert_contains "$out_default" "directory = /opt/homebrew/Library/Taps/*/*" "safe taps on darwin/arm64"
fi
