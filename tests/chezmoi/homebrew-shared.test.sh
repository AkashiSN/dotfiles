#!/usr/bin/env bash
# Apple Silicon の Homebrew を共有する仕組み（before_05 の展開と homebrew-shared.sh の関数）。
set -u
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"

# (a) before_05 が darwin/arm64 では /bin/sh のスクリプトを出す
if [ "$(uname -sm)" = "Darwin arm64" ]; then
	out="$(chezmoi_render "$REPO/.chezmoiscripts/run_before_05-homebrew-shared.sh.tmpl")" || fail "render before_05"
	[ -n "$out" ] || fail "before_05 is empty on darwin/arm64"
	assert_eq "#!/bin/sh" "$(printf '%s\n' "$out" | head -n 1)" "before_05 shebang"
	assert_contains "$out" "homebrew_shared_ok" "before_05 includes the shared functions"
fi

# (b) brew_shared は umask 002 で brew を呼ぶ
# shellcheck source=../../.chezmoitemplates/homebrew-shared.sh
. "$REPO/.chezmoitemplates/homebrew-shared.sh"
# shellcheck disable=SC2329 # brew_shared から呼ばれる
brew() { umask; }
(umask 022 && assert_eq "0002" "$(brew_shared check)" "brew_shared runs brew with umask 002")
unset -f brew

# (c) homebrew_shared_ok: グループ・g+w・setgid・プロセスのグループ所属
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
grp="$(id -gn)"
export BREW_GROUP="$grp"

mkdir "$tmp/none"
chgrp "$grp" "$tmp/none"
chmod 755 "$tmp/none"
homebrew_shared_ok "$tmp/none" && fail "g+w も setgid も無いのに真"
echo "PASS: no g+w / no setgid is false"

mkdir "$tmp/gw"
chgrp "$grp" "$tmp/gw"
chmod 775 "$tmp/gw"
homebrew_shared_ok "$tmp/gw" && fail "setgid が無いのに真"
echo "PASS: g+w without setgid is false"

mkdir "$tmp/ok"
chgrp "$grp" "$tmp/ok"
chmod 775 "$tmp/ok"
chmod g+s "$tmp/ok"
if [ -g "$tmp/ok" ]; then
	homebrew_shared_ok "$tmp/ok" || fail "g+w と setgid があるのに偽"
	echo "PASS: g+w and setgid is true"
	BREW_GROUP="no-such-group-xyz" homebrew_shared_ok "$tmp/ok" && fail "グループが違うのに真"
	echo "PASS: other group is false"
else
	echo "SKIP: この FS では chmod g+s が効かない"
fi

homebrew_shared_ok "$tmp/missing" && fail "存在しない prefix で真"
echo "PASS: missing prefix is false"
