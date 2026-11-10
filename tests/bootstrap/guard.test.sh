#!/usr/bin/env bash
# bootstrap/guard.sh のダウングレード防止判定と state 読み書きのテスト。
# 一時ディレクトリのローカル bare リポジトリだけを触る。ネットワークと署名は使わない。
set -eu
# shellcheck source-path=SCRIPTDIR source=../lib.sh
. "$(dirname "$0")/../lib.sh"
# shellcheck source-path=SCRIPTDIR source=../../bootstrap/guard.sh
. "$REPO/bootstrap/guard.sh"

# ユーザの gitconfig（署名設定など）を読ませない。
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
unset DOTFILES_SHARED_FORCE

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

g() { git -c commit.gpgsign=false "$@"; }

g init -q --bare -b main "$tmp/origin.git"
g clone -q "$tmp/origin.git" "$tmp/repo" 2>/dev/null
for n in 1 2 3; do
	echo "$n" >"$tmp/repo/f"
	g -C "$tmp/repo" add f
	g -C "$tmp/repo" commit -q -m "c$n"
done
g -C "$tmp/repo" push -q origin HEAD:main 2>/dev/null
g -C "$tmp/repo" fetch -q origin 2>/dev/null
head="$(g -C "$tmp/repo" rev-parse HEAD)"
parent="$(g -C "$tmp/repo" rev-parse HEAD~1)"
state="$tmp/state/state"

# (a) HEAD == origin/main、state 無し
rc=0
out="$(shared_guard "$tmp/repo" "$state")" || rc=$?
assert_eq "ok" "$out" "guard: state 無しは ok"
assert_eq "0" "$rc" "guard: ok の終了コードは 0"

# state_write / state_commit
assert_eq "" "$(state_commit "$state")" "state_commit: ファイル無しは空"
state_write "$state" "$parent"
assert_eq "$parent" "$(state_commit "$state")" "state_commit: 書いたコミットを読む"
assert_contains "$(cat "$state")" "updated_by=" "state_write: updated_by を書く"
assert_contains "$(cat "$state")" "updated_at=" "state_write: updated_at を書く"
[ "$(wc -l <"$state" | tr -d ' ')" = 3 ] || fail "state_write: 3 行ではない"
assert_eq "state" "$(find "$tmp/state" -type f -exec basename {} \;)" "state_write: 一時ファイルが残らない"

# (b) state が HEAD の親
assert_eq "ok" "$(shared_guard "$tmp/repo" "$state")" "guard: state が HEAD の親なら ok"

# (c) state が HEAD の子（HEAD を戻す）
state_write "$state" "$head"
g -C "$tmp/repo" reset -q --hard HEAD~1
rc=0
out="$(shared_guard "$tmp/repo" "$state")" || rc=$?
assert_eq "stale:behind-state" "$out" "guard: state より古い HEAD は behind-state"
assert_eq "1" "$rc" "guard: stale の終了コードは 1"

# (g) FORCE
rc=0
out="$(DOTFILES_SHARED_FORCE=1 shared_guard "$tmp/repo" "$state")" || rc=$?
assert_eq "force" "$out" "guard: DOTFILES_SHARED_FORCE=1 は force"
assert_eq "0" "$rc" "guard: force の終了コードは 0"
assert_eq "$head" "$(state_commit "$state")" "guard: force は state を書き換えない"

# (e) 存在しない sha
state_write "$state" "0123456789abcdef0123456789abcdef01234567"
assert_eq "stale:state-commit-unknown" "$(shared_guard "$tmp/repo" "$state")" "guard: 未知の state は state-commit-unknown"

# (d) origin/main に無いローカルコミット
rm -f "$state"
echo local >"$tmp/repo/f"
g -C "$tmp/repo" commit -q -am local
assert_eq "stale:not-on-origin-main" "$(shared_guard "$tmp/repo" "$state")" "guard: ローカルコミットは not-on-origin-main"

# (f) origin が無い
g clone -q "$tmp/origin.git" "$tmp/noorigin" 2>/dev/null
g -C "$tmp/noorigin" remote remove origin
assert_eq "stale:no-origin-main" "$(shared_guard "$tmp/noorigin" "$state")" "guard: origin/main 無しは no-origin-main"

# hint
for r in no-origin-main not-on-origin-main behind-state state-commit-unknown; do
	assert_contains "$(shared_guard_hint "$r")" "DOTFILES_SHARED_FORCE=1" "hint: $r に FORCE の案内がある"
done
