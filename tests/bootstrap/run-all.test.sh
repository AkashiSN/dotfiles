#!/usr/bin/env bash
# bootstrap/run-all.sh と shared_store_trigger のテスト。
# sudo は偽の関数に差し替え、/opt は触らない（SHARED_ROOT を一時ディレクトリへ向ける）。
set -eu
# shellcheck source-path=SCRIPTDIR source=../lib.sh
. "$(dirname "$0")/../lib.sh"
# shellcheck source-path=SCRIPTDIR source=../../bootstrap/lib.sh
. "$REPO/bootstrap/lib.sh"
# shellcheck source-path=SCRIPTDIR source=../../bootstrap/guard.sh
. "$REPO/bootstrap/guard.sh"
# shellcheck source-path=SCRIPTDIR source=../../.chezmoitemplates/shared-store-trigger.sh
. "$REPO/.chezmoitemplates/shared-store-trigger.sh"

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
unset DOTFILES_SHARED_FORCE DOTFILES_STATE_COMMIT

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
g() { git -c commit.gpgsign=false "$@"; }

# ---- run-all.sh（偽のステップ）----
export SHARED_ROOT="$tmp/opt"
export BOOTSTRAP_ALLOW_NONROOT=1
bd="$tmp/steps"
mkdir -p "$bd" "$SHARED_ROOT/dotfiles-shared/keys"
# 偽ステップ: <SHARED_ROOT>/dotfiles-shared/keys/NN が "ok" なら一致。引数なしは "ok" を書き、実行を記録する。
mkstep() {
	cat >"$bd/$1" <<'STEP'
#!/usr/bin/env bash
nn="$(basename "$0" | cut -c1-2)"
key="$SHARED_ROOT/dotfiles-shared/keys/$nn"
if [ "${1:-}" = "--check" ]; then
	[ "$(cat "$key" 2>/dev/null)" = ok ]
	exit
fi
echo "$nn $DOTFILES_SRC ${GITHUB_TOKEN:-}" >>"$SHARED_ROOT/ran"
mkdir -p "$(dirname "$key")"
echo ok >"$key"
STEP
}
mkstep 10-a.sh
mkstep 20-b.sh
# 対象外のファイル
echo 'exit 9' >"$bd/lib.sh"
echo 'exit 9' >"$bd/run-all.sh"
echo 'exit 9' >"$bd/5-x.sh"
export BOOTSTRAP_DIR="$bd" DOTFILES_SRC="$tmp/src"
RUN="$REPO/bootstrap/run-all.sh"

echo ok >"$SHARED_ROOT/dotfiles-shared/keys/10"
rc=0
bash "$RUN" --check || rc=$?
assert_eq "1" "$rc" "run-all --check: 1 本でも食い違えば 1"
echo ok >"$SHARED_ROOT/dotfiles-shared/keys/20"
rc=0
bash "$RUN" --check || rc=$?
assert_eq "0" "$rc" "run-all --check: 全部一致なら 0"
[ ! -e "$SHARED_ROOT/ran" ] || fail "run-all --check: ステップを実行してしまった"

# (f) 食い違うステップだけを流し、DOTFILES_STATE_COMMIT があれば state を書く
rm "$SHARED_ROOT/dotfiles-shared/keys/20"
GITHUB_TOKEN=tok DOTFILES_STATE_COMMIT=abc123 bash "$RUN" >/dev/null
assert_eq "20 $tmp/src tok" "$(cat "$SHARED_ROOT/ran")" "run-all: 食い違う 20 だけを流す"
assert_eq "abc123" "$(state_commit "$SHARED_ROOT/dotfiles-shared/state")" "run-all: state に commit を書く"

# commit が空（force）なら state を書かない
rm "$SHARED_ROOT/dotfiles-shared/state" "$SHARED_ROOT/dotfiles-shared/keys/20"
DOTFILES_STATE_COMMIT='' bash "$RUN" >/dev/null
[ ! -e "$SHARED_ROOT/dotfiles-shared/state" ] || fail "run-all: commit が空なのに state を書いた"
echo "PASS: run-all: DOTFILES_STATE_COMMIT が空なら state を書かない"

# (A1) 先頭のステップが失敗しても後続を流し、state は書かず、終了コードは 1
rm -f "$SHARED_ROOT/dotfiles-shared/keys/10" "$SHARED_ROOT/dotfiles-shared/keys/20" "$SHARED_ROOT/ran" "$SHARED_ROOT/dotfiles-shared/state"
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\n[ "${1:-}" = --check ] && exit 1\nexit 3\n' >"$bd/10-a.sh"
rc=0
DOTFILES_STATE_COMMIT=zzz bash "$RUN" >/dev/null 2>&1 || rc=$?
assert_eq "1" "$rc" "run-all: ステップ失敗で 1"
assert_eq "20 $tmp/src " "$(cat "$SHARED_ROOT/ran")" "run-all: 10 が失敗しても 20 を流す"
[ ! -e "$SHARED_ROOT/dotfiles-shared/state" ] || fail "run-all: 失敗したのに state を書いた"
echo "PASS: run-all: 失敗があれば state を書かない"

# 実行後の --check が通らない（キーの書き忘れ）ステップも失敗扱いで、state を書かない
rm -f "$SHARED_ROOT/dotfiles-shared/keys/20" "$SHARED_ROOT/ran"
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\n[ "${1:-}" = --check ] && exit 1\nexit 0\n' >"$bd/10-a.sh"
rc=0
DOTFILES_STATE_COMMIT=zzz bash "$RUN" >/dev/null 2>&1 || rc=$?
assert_eq "1" "$rc" "run-all: 実行後も食い違えば 1"
[ ! -e "$SHARED_ROOT/dotfiles-shared/state" ] || fail "run-all: 食い違ったまま state を書いた"

# (A2) --check の 1 は食い違い、それ以外の非 0 はステップの異常。どちらも不一致として数え、異常は終了コードを出す
mkstep 10-a.sh
echo ok >"$SHARED_ROOT/dotfiles-shared/keys/10"
echo ok >"$SHARED_ROOT/dotfiles-shared/keys/20"
printf '#!/usr/bin/env bash\nexit 7\n' >"$bd/20-b.sh"
rc=0
out="$(bash "$RUN" --check 2>&1)" || rc=$?
assert_eq "1" "$rc" "run-all --check: ステップの異常は不一致として 1"
assert_contains "$out" "20-b.sh" "run-all --check: 異常のステップ名を警告する"
assert_contains "$out" "7" "run-all --check: 異常の終了コードを警告する"
mkstep 20-b.sh

# ---- 消し残し（pending/NN）: キーが一致していても流し直し、まだ使用中なら印を置き直す ----
echo ok >"$SHARED_ROOT/dotfiles-shared/keys/10"
echo ok >"$SHARED_ROOT/dotfiles-shared/keys/20"
rm -f "$SHARED_ROOT/ran" "$SHARED_ROOT/dotfiles-shared/state"
mkdir -p "$SHARED_ROOT/dotfiles-shared/pending"
: >"$SHARED_ROOT/dotfiles-shared/pending/20"
rc=0
bash "$RUN" --check || rc=$?
assert_eq "1" "$rc" "run-all --check: キーが一致していても消し残しがあれば 1"
# 20 は本物の gc_defer で「まだ使用中」を記録する
cat >"$bd/20-b.sh" <<STEP
#!/usr/bin/env bash
. "$REPO/bootstrap/lib.sh"
[ "\${1:-}" = "--check" ] && exit 0
echo 20 >>"\$SHARED_ROOT/ran"
[ -e "\$SHARED_ROOT/still-busy" ] && gc_defer
exit 0
STEP
: >"$SHARED_ROOT/still-busy"
DOTFILES_STATE_COMMIT=p1 bash "$RUN" >/dev/null 2>&1 || fail "run-all: 消し残しの流し直しが失敗扱いになった"
assert_eq "20" "$(cat "$SHARED_ROOT/ran")" "run-all: 消し残しのあるステップだけを流し直す"
[ -e "$SHARED_ROOT/dotfiles-shared/pending/20" ] || fail "run-all: まだ使用中なのに消し残しの印が消えた"
assert_eq "p1" "$(state_commit "$SHARED_ROOT/dotfiles-shared/state")" "run-all: 使用中で残しても失敗ではなく state を書く"
rm -f "$SHARED_ROOT/still-busy" "$SHARED_ROOT/ran"
bash "$RUN" >/dev/null 2>&1 || fail "run-all: 2 回目の流し直しが失敗"
[ ! -e "$SHARED_ROOT/dotfiles-shared/pending/20" ] || fail "run-all: 使い終わったのに消し残しの印が残った"
rc=0
bash "$RUN" --check || rc=$?
assert_eq "0" "$rc" "run-all --check: 消し終われば 0"
mkstep 20-b.sh

# 非 root で BOOTSTRAP_ALLOW_NONROOT 無しは拒否（--check は root 不要）
if [ "$(id -u)" -ne 0 ]; then
	rc=0
	BOOTSTRAP_ALLOW_NONROOT='' bash "$RUN" >/dev/null 2>&1 || rc=$?
	assert_eq "1" "$rc" "run-all: 非 root は実行を拒否する"
fi
unset BOOTSTRAP_DIR BOOTSTRAP_ALLOW_NONROOT

# ---- run-all.sh: ステップは root の HOME で動き、SSH_AUTH_SOCK を持たない ----
hd="$tmp/hstep"
mkdir -p "$hd"
cat >"$hd/10-env.sh" <<'STEP'
#!/usr/bin/env bash
if [ "${1:-}" = "--check" ]; then
	[ -f "$SHARED_ROOT/envseen" ]
	exit
fi
echo "HOME=$HOME SOCK=${SSH_AUTH_SOCK:-unset}" >"$SHARED_ROOT/envseen"
STEP
chmod +x "$hd/10-env.sh"
rm -f "$SHARED_ROOT/envseen"
BOOTSTRAP_ALLOW_NONROOT=1 HOME="$tmp/callerhome" SSH_AUTH_SOCK=/tmp/agent.sock BOOTSTRAP_ROOT_HOME="$tmp/roothome" BOOTSTRAP_DIR="$hd" bash "$REPO/bootstrap/run-all.sh" >"$tmp/envout" 2>&1 || fail "run-all (env) が失敗" "$(cat "$tmp/envout")"
assert_eq "HOME=$tmp/roothome SOCK=unset" "$(cat "$SHARED_ROOT/envseen")" "run-all: ステップは root の HOME で動き、SSH_AUTH_SOCK を持たない"
rm -f "$SHARED_ROOT/envseen"
BOOTSTRAP_ALLOW_NONROOT=1 HOME="$tmp/callerhome" SSH_AUTH_SOCK=/tmp/agent.sock BOOTSTRAP_DIR="$hd" bash "$REPO/bootstrap/run-all.sh" >/dev/null 2>&1 || fail "run-all (env, hook なし) が失敗"
assert_eq "HOME=$tmp/callerhome SOCK=unset" "$(cat "$SHARED_ROOT/envseen")" "run-all: root でなく hook も無ければ HOME は変えないが、SSH_AUTH_SOCK は外す"
rm -f "$SHARED_ROOT/envseen"

# ---- shared_store_trigger ----
# DOTFILES_SRC は git リポジトリ。bootstrap/run-all.sh は偽（--check の結果を FAKE_CHECK_RC で決める）。
src="$tmp/repo"
g init -q --bare -b main "$tmp/origin.git"
g clone -q "$tmp/origin.git" "$src" 2>/dev/null
mkdir -p "$src/bootstrap"
cat >"$src/bootstrap/run-all.sh" <<'FAKE'
#!/usr/bin/env bash
[ "${1:-}" = "--check" ] && exit "${FAKE_CHECK_RC:-0}"
exit 0
FAKE
echo 1 >"$src/f"
g -C "$src" add -A
g -C "$src" commit -q -m c1
g -C "$src" push -q origin HEAD:main 2>/dev/null
g -C "$src" fetch -q origin 2>/dev/null
head="$(g -C "$src" rev-parse HEAD)"
export DOTFILES_SRC="$src" SHARED_ROOT="$tmp/opt2"

calls="$tmp/sudo.calls"
SUDO_N_RC=0
SUDO_RC=0
# 偽 sudo: 呼び出しの引数と、環境変数で渡った値を記録する。
sudo() {
	if [ "$1" = "-n" ]; then
		return "$SUDO_N_RC"
	fi
	{
		echo "ARGS: $*"
		echo "ENV: token=${GITHUB_TOKEN:-} force=${DOTFILES_SHARED_FORCE:-} commit=${DOTFILES_STATE_COMMIT:-} aqua=${AQUA_BIN:-} root=${SHARED_ROOT:-} src=${DOTFILES_SRC:-}"
	} >>"$calls"
	return "$SUDO_RC"
}
gh() { [ "$1 $2" = "auth token" ] && echo SECRET_TOKEN; }
# shellcheck disable=SC2329  # trigger の command -v aqua が見つける偽物
aqua() { :; }
trig() {
	rm -f "$calls"
	local rc=0
	shared_store_trigger </dev/null 2>&1 || rc=$?
	echo "rc=$rc"
}

# (a) 一致 → sudo を呼ばない
out="$(FAKE_CHECK_RC=0 trig)"
assert_contains "$out" "rc=0" "trigger (a): 終了コード 0"
[ ! -e "$calls" ] || fail "trigger (a): sudo を呼んだ"
echo "PASS: trigger (a): 一致なら sudo を呼ばない"

# (b) 食い違い + stale → 呼ばない・警告
g -C "$src" reset -q --hard HEAD
echo 2 >"$src/f"
g -C "$src" commit -q -am c2 # origin/main に無い
out="$(FAKE_CHECK_RC=1 trig)"
[ ! -e "$calls" ] || fail "trigger (b): sudo を呼んだ"
assert_contains "$out" "DOTFILES_SHARED_FORCE=1" "trigger (b): stale は警告して force の案内を出す"
assert_contains "$out" "rc=0" "trigger (b): 終了コード 0"
g -C "$src" reset -q --hard "$head"

# (c)(e) 食い違い + ok → 呼ぶ。state commit を渡す。token は argv に出ない。
out="$(FAKE_CHECK_RC=1 trig)"
assert_contains "$out" "rc=0" "trigger (c): 終了コード 0"
[ -e "$calls" ] || fail "trigger (c): sudo を呼んでいない"
c="$(cat "$calls")"
assert_contains "$c" "commit=$head" "trigger (e): ok は DOTFILES_STATE_COMMIT を渡す"
assert_contains "$c" "force= " "trigger (e): ok は DOTFILES_SHARED_FORCE を渡さない"
assert_contains "$c" "token=SECRET_TOKEN" "trigger (c): GITHUB_TOKEN を環境変数で渡す"
assert_contains "$c" "root=$tmp/opt2" "trigger (c): SHARED_ROOT を渡す"
assert_contains "$c" "--preserve-env=DOTFILES_SRC,AQUA_BIN,GITHUB_TOKEN,DOTFILES_SHARED_FORCE,DOTFILES_STATE_COMMIT,SHARED_ROOT" "trigger (c): --preserve-env を使う"
assert_contains "$c" "bash $src/bootstrap/run-all.sh" "trigger (c): run-all.sh を bash で呼ぶ"
assert_not_contains "$(grep '^ARGS' "$calls")" "SECRET_TOKEN" "trigger (c): token が argv に出ない"
assert_not_contains "$out" "SECRET_TOKEN" "trigger (c): token を表示しない"

# 設定済みの GITHUB_TOKEN は gh auth token より優先する
out="$(FAKE_CHECK_RC=1 GITHUB_TOKEN=PRESET_TOKEN trig)"
c="$(cat "$calls")"
assert_contains "$c" "token=PRESET_TOKEN" "trigger: 設定済みの GITHUB_TOKEN を保つ"
assert_not_contains "$c" "SECRET_TOKEN" "trigger: 設定済みなら gh auth token を使わない"

# 初回の apply: aqua が PATH に無くても ~/.local/bin のものを AQUA_BIN に渡す
unset -f aqua
mkdir -p "$tmp/fresh/.local/bin"
printf '#!/bin/sh\n' >"$tmp/fresh/.local/bin/aqua"
chmod +x "$tmp/fresh/.local/bin/aqua"
out="$(FAKE_CHECK_RC=1 HOME="$tmp/fresh" PATH="/usr/bin:/bin" trig)"
assert_contains "$(cat "$calls")" "aqua=$tmp/fresh/.local/bin/aqua " "trigger: PATH に無い ~/.local/bin/aqua を AQUA_BIN に渡す"
# shellcheck disable=SC2329
aqua() { :; }

# (e) force → DOTFILES_SHARED_FORCE=1、state commit 無し
g -C "$src" reset -q --hard HEAD
echo 3 >"$src/f"
g -C "$src" commit -q -am c3
out="$(FAKE_CHECK_RC=1 DOTFILES_SHARED_FORCE=1 trig)"
c="$(cat "$calls")"
assert_contains "$c" "force=1 commit= " "trigger (e): force は FORCE=1 を渡し state commit を渡さない"
g -C "$src" reset -q --hard "$head"

# (d) sudo -n 失敗 + TTY 無し → 呼ばない・警告・0
SUDO_N_RC=1
out="$(FAKE_CHECK_RC=1 trig)"
[ ! -e "$calls" ] || fail "trigger (d): sudo を呼んだ"
assert_contains "$out" "rc=0" "trigger (d): 終了コード 0"
assert_contains "$out" "sudo" "trigger (d): sudo を使えない旨を警告する"
SUDO_N_RC=0

# sudo が断られても 0
SUDO_RC=1
out="$(FAKE_CHECK_RC=1 trig)"
assert_contains "$out" "rc=0" "trigger: sudo を断られても終了コード 0"
SUDO_RC=0

# --check が 1 以外で失敗（スクリプト自体のエラー）でも 0、sudo 無し
out="$(FAKE_CHECK_RC=2 trig)"
assert_contains "$out" "rc=0" "trigger: --check の異常でも終了コード 0"
[ ! -e "$calls" ] || fail "trigger: --check 異常で sudo を呼んだ"

echo "ALL PASS"
