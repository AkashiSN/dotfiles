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
	sed -e "s#^SHARED=/opt/aquaproj-aqua#SHARED=$tmp/shared#" -e "s#^SHARED_KEY=.*#SHARED_KEY=$tmp/keys/20#" >"$script"
grep -q "^SHARED=$tmp/shared" "$script" || fail "SHARED の差し替えに失敗"

export HOME="$tmp/home" XDG_DATA_HOME="" XDG_CONFIG_HOME=""
unset XDG_DATA_HOME XDG_CONFIG_HOME
root="$HOME/.local/share/aquaproj-aqua"
mkdir -p "$root/pkgs/x" "$root/bin"
echo data >"$root/pkgs/x/file"

# ---- 共有側が無い: ホームの pkgs / bin は動かさず、ユーザ単位で install する ----
mkdir -p "$HOME/.config/aquaproj-aqua" "$tmp/bin"
echo 'packages: []' >"$HOME/.config/aquaproj-aqua/aqua.yaml"
echo 'packages: []' >"$HOME/.config/aquaproj-aqua/registry.yaml"
echo 'registries: []' >"$HOME/.config/aquaproj-aqua/aqua-policy.yaml"
echo '{}' >"$HOME/.config/aquaproj-aqua/aqua-checksums.json"
calls="$tmp/calls"
cat >"$tmp/bin/aqua" <<'FAKE'
#!/usr/bin/env bash
echo "aqua $* ROOT=${AQUA_ROOT_DIR:-} GLOBAL=${AQUA_GLOBAL_CONFIG:-}" >>"$CALLS"
[ "${FAKE_AQUA_FAIL:-}" = 1 ] && [ "$1 $2" = "install -a" ] && exit 1
exit 0
FAKE
cat >"$tmp/bin/gh" <<'FAKE'
#!/usr/bin/env bash
exit "${FAKE_GH_RC:-1}"
FAKE
chmod +x "$tmp/bin/aqua" "$tmp/bin/gh"
export CALLS="$calls" PATH="$tmp/bin:$PATH"
rc=0
out="$(bash "$script" 2>&1)" || rc=$?
assert_eq "0" "$rc" "共有側なし: 終了コード 0"
assert_contains "$out" "共有 aqua ストア" "共有側なし: 警告する"
[ -d "$root/pkgs" ] && [ ! -L "$root/pkgs" ] && [ -f "$root/pkgs/x/file" ] || fail "共有側なしなのにホームの pkgs を変えた"
[ -d "$root/bin" ] && [ ! -L "$root/bin" ] || fail "共有側なしなのにホームの bin を変えた"
set -- "$root"/*.old.*
[ ! -e "$1" ] || fail "共有側なしなのに退避した"
echo "PASS: 共有側が無ければホームの既存ファイルは消さない・動かさない"
c="$(cat "$calls")"
assert_contains "$c" "aqua policy allow" "共有側なし: policy allow"
assert_contains "$c" "aqua install -a -t bootstrap" "共有側なし: 未認証なら bootstrap の gh を先に入れる"
assert_contains "$c" "aqua install -a ROOT=$root GLOBAL=$HOME/.config/aquaproj-aqua/aqua.yaml" "共有側なし: ホームの設定で install -a"
[ -f "$HOME/.cache/dotfiles/aqua-user.key" ] || fail "成功したのにマーカーを書かなかった"
# 設定が同じなら 2 回目は install しない
: >"$calls"
bash "$script" >/dev/null 2>&1
[ ! -s "$calls" ] || fail "設定が同じなのに再 install した"
echo "PASS: 設定が変わらなければ install を省く"
# 設定が変われば再 install、失敗したらマーカーを更新しない
echo '# changed' >>"$HOME/.config/aquaproj-aqua/aqua.yaml"
oldkey="$(cat "$HOME/.cache/dotfiles/aqua-user.key")"
rc=0
FAKE_AQUA_FAIL=1 bash "$script" >/dev/null 2>&1 || rc=$?
assert_eq "0" "$rc" "install 失敗でも apply は止めない"
assert_eq "$oldkey" "$(cat "$HOME/.cache/dotfiles/aqua-user.key")" "失敗したらマーカーを進めない"
# gh が認証済みなら bootstrap を先に入れない
: >"$calls"
FAKE_GH_RC=0 bash "$script" >/dev/null 2>&1
assert_not_contains "$(cat "$calls")" "-t bootstrap" "認証済みなら bootstrap を別に入れない"

# 共有側の config だけでキーが無いときも、共有側は使わない
mkdir -p "$tmp/shared/config" "$tmp/shared/pkgs" "$tmp/shared/bin"
echo 'packages: []' >"$tmp/shared/config/aqua.yaml"
bash "$script" >/dev/null 2>&1
[ -d "$root/pkgs" ] && [ ! -L "$root/pkgs" ] || fail "キーが無いのに共有側へ向けた"
echo "PASS: config だけでキーが無ければ共有側は未完成として扱う"
mkdir -p "$tmp/keys"
echo k >"$tmp/keys/20"

# ---- 共有側あり: 退避して symlink、動いていなければ古いものを消す ----
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
assert_contains "$out" "使用中のため残します" "使用中の案内を出す"
assert_contains "$out" "rm -rf '$1'" "残したものを手で消すコマンドを案内する"
assert_contains "$out" "$(du -sh "$1" | cut -f1)" "残したものの大きさを出す"
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
