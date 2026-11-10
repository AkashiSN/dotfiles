#!/usr/bin/env bash
# .chezmoiscripts/run_after_20-aqua-verify.sh.tmpl のテスト。
# 描画したスクリプトの SHARED だけ一時ディレクトリへ差し替え、HOME も一時ディレクトリにする。
set -eu
# shellcheck source-path=SCRIPTDIR source=../lib.sh
. "$(dirname "$0")/../lib.sh"

tmp="$(mktemp -d)"
bgpid=""
cleanup() {
	[ -z "$bgpid" ] || kill "$bgpid" 2>/dev/null || true
	rm -rf "$tmp"
}
trap cleanup EXIT

cfgtoml="$tmp/chezmoi.toml"
chezmoi_config "$cfgtoml"
script="$tmp/verify.sh"
chezmoi --source "$REPO" --config "$cfgtoml" execute-template <"$REPO/.chezmoiscripts/run_after_20-aqua-verify.sh.tmpl" |
	sed "s#^SHARED=/opt/aquaproj-aqua#SHARED=$tmp/shared#" >"$script"
grep -q "^SHARED=$tmp/shared" "$script" || fail "SHARED の差し替えに失敗"

export HOME="$tmp/home" XDG_DATA_HOME="" XDG_CONFIG_HOME=""
unset XDG_DATA_HOME XDG_CONFIG_HOME
root="$HOME/.local/share/aquaproj-aqua"
mkdir -p "$root/pkgs/x" "$root/bin"
echo data >"$root/pkgs/x/file"

# ---- 共有側が無い: ホームに何もしない ----
rc=0
out="$(bash "$script" 2>&1)" || rc=$?
assert_eq "0" "$rc" "共有側なし: 終了コード 0"
assert_contains "$out" "共有 aqua ストア" "共有側なし: 警告する"
[ -d "$root/pkgs" ] && [ ! -L "$root/pkgs" ] && [ -f "$root/pkgs/x/file" ] || fail "共有側なしなのにホームの pkgs を変えた"
[ -d "$root/bin" ] && [ ! -L "$root/bin" ] || fail "共有側なしなのにホームの bin を変えた"
set -- "$root"/*.old.*
[ ! -e "$1" ] || fail "共有側なしなのに退避した"
echo "PASS: 共有側が無ければホームは何も消さない・動かさない"

# ---- 共有側あり: 退避して symlink、動いていなければ古いものを消す ----
mkdir -p "$tmp/shared/config" "$tmp/shared/pkgs" "$tmp/shared/bin"
echo 'packages: []' >"$tmp/shared/config/aqua.yaml"
# 動いているプロセスを pkgs の実体の下で立てる
cp /bin/sleep "$root/pkgs/x/sleeper"
if [ "$(uname -s)" = Darwin ]; then codesign -f -s - "$root/pkgs/x/sleeper" 2>/dev/null; fi
"$root/pkgs/x/sleeper" 60 &
bgpid=$!
sleep 1
rc=0
out="$(bash "$script" 2>&1)" || rc=$?
assert_eq "0" "$rc" "共有側あり: 終了コード 0"
assert_eq "$tmp/shared/pkgs" "$(readlink "$root/pkgs")" "pkgs が共有側への symlink"
assert_eq "$tmp/shared/bin" "$(readlink "$root/bin")" "bin が共有側への symlink"
set -- "$root"/pkgs.old.*
[ -d "$1" ] || fail "動いているのに退避した pkgs を消した"
echo "PASS: 動いている間は退避したものを残す"
assert_contains "$out" "次回に回します" "使用中の案内を出す"
ls -d "$root"/bin.old.* >/dev/null 2>&1 && fail "動いていない bin の退避が残った"
echo "PASS: 動いていない退避は消す"

# プロセスが終わった次の apply で消える
kill "$bgpid" 2>/dev/null || true
wait "$bgpid" 2>/dev/null || true
bgpid=""
bash "$script" >/dev/null 2>&1
ls -d "$root"/pkgs.old.* >/dev/null 2>&1 && fail "動いていない退避した pkgs が残った"
echo "PASS: 次回の apply で退避を消す"
assert_eq "$tmp/shared/pkgs" "$(readlink "$root/pkgs")" "2 回目も symlink のまま（冪等）"

echo "ALL PASS"
