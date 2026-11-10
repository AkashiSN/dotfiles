#!/usr/bin/env bash
# bootstrap/20-shared-aqua.sh のテスト。
# /opt は触らず、SHARED_ROOT を一時ディレクトリへ向ける。aqua は偽のスクリプトに差し替える。
set -eu
# shellcheck source-path=SCRIPTDIR source=../lib.sh
. "$(dirname "$0")/../lib.sh"
# shellcheck source-path=SCRIPTDIR source=../../bootstrap/lib.sh
. "$REPO/bootstrap/lib.sh"

STEP="$REPO/bootstrap/20-shared-aqua.sh"
tmp="$(mktemp -d)"
bgpid=""
cleanup() {
	[ -z "$bgpid" ] || kill "$bgpid" 2>/dev/null || true
	rm -rf "$tmp"
}
trap cleanup EXIT

export SHARED_ROOT="$tmp/opt" BOOTSTRAP_ALLOW_NONROOT=1
export DOTFILES_SRC="$tmp/src"
unset GITHUB_TOKEN AQUA_BIN DOTFILES_SHARED_FORCE DOTFILES_STATE_COMMIT
cfg="$DOTFILES_SRC/dot_config/aquaproj-aqua"
mkdir -p "$cfg" "$SHARED_ROOT"
printf 'packages:\n  - name: cli/cli@v2.0.0\n  - name: Foo/Bar@v0.2.0 # x\n' >"$cfg/aqua.yaml"
echo 'packages: []' >"$cfg/registry.yaml"
echo 'registries: []' >"$cfg/aqua-policy.yaml"
echo '{}' >"$cfg/aqua-checksums.json"
want="$(pins_key "$cfg/aqua.yaml" "$cfg/registry.yaml" "$cfg/aqua-policy.yaml" "$cfg/aqua-checksums.json")"
keyfile="$SHARED_ROOT/dotfiles-shared/keys/20"
store="$SHARED_ROOT/aquaproj-aqua"

# ---- --check ----
rc=0
bash "$STEP" --check || rc=$?
assert_eq "1" "$rc" "--check: キーが無ければ 1"
[ ! -e "$SHARED_ROOT/dotfiles-shared" ] || fail "--check: 何かを書いた"
mkdir -p "$(dirname "$keyfile")"
echo "$want" >"$keyfile"
rc=0
bash "$STEP" --check || rc=$?
assert_eq "0" "$rc" "--check: ソースと同じキーなら 0"
echo '# changed' >>"$cfg/aqua.yaml"
rc=0
bash "$STEP" --check || rc=$?
assert_eq "1" "$rc" "--check: aqua.yaml を変えれば 1"
sed -i.bak '$d' "$cfg/aqua.yaml" && rm "$cfg/aqua.yaml.bak"
rm "$keyfile"

# ---- 偽の aqua ----
log="$tmp/aqua.log"
fake="$tmp/fake-aqua"
cat >"$fake" <<'FAKE'
#!/usr/bin/env bash
echo "ARGS=$* ROOT=${AQUA_ROOT_DIR:-} GLOBAL=${AQUA_GLOBAL_CONFIG:-} POLICY=${AQUA_POLICY_CONFIG:-} NOATTEST=${AQUA_DISABLE_GITHUB_ARTIFACT_ATTESTATION:-} TOKEN=${GITHUB_TOKEN:+set} PATH0=${PATH%%:*}" >>"$FAKE_LOG"
if [ "${FAKE_FAIL_VERIFIED:-}" = 1 ] && [ "$1 $2" = "install -a" ] && [ "${3:-}" != -t ] && [ -z "${AQUA_DISABLE_GITHUB_ARTIFACT_ATTESTATION:-}" ]; then
	exit 1
fi
exit 0
FAKE
chmod +x "$fake"
export FAKE_LOG="$log"

# ---- AQUA_BIN が空 / 実行できない ----
rc=0
out="$(bash "$STEP" 2>&1)" || rc=$?
[ "$rc" -ne 0 ] || fail "AQUA_BIN 空で成功した"
assert_contains "$out" "AQUA_BIN" "AQUA_BIN が空ならメッセージを出して失敗する"
rc=0
out="$(AQUA_BIN="$tmp/nonexistent" bash "$STEP" 2>&1)" || rc=$?
[ "$rc" -ne 0 ] || fail "AQUA_BIN 不在で成功した"
[ ! -e "$keyfile" ] || fail "失敗したのにキーを書いた"

# ---- 通常（token あり）----
rm -f "$log"
rc=0
out="$(AQUA_BIN="$fake" GITHUB_TOKEN=SECRET_TOKEN bash "$STEP" 2>&1)" || rc=$?
assert_eq "0" "$rc" "token あり: 成功する"
assert_eq "$want" "$(cat "$keyfile")" "token あり: キーを書く"
for f in aqua.yaml registry.yaml aqua-policy.yaml aqua-checksums.json; do
	cmp -s "$cfg/$f" "$store/config/$f" || fail "config/$f がソースと違う"
done
echo "PASS: config へ 4 ファイルをコピーする"
l="$(cat "$log")"
assert_contains "$l" "ARGS=policy allow $store/config/aqua-policy.yaml" "policy allow を共有側の policy へ"
assert_contains "$l" "ARGS=install -a ROOT=$store GLOBAL=$store/config/aqua.yaml POLICY=$store/config/aqua-policy.yaml" "install -a を共有側の root / config で"
assert_not_contains "$l" "-t bootstrap" "token あり: bootstrap 先行は不要"
assert_not_contains "$l" "NOATTEST=true" "token あり: 検証を切らない"
assert_not_contains "$out" "SECRET_TOKEN" "token を表示しない"
assert_not_contains "$l" "SECRET_TOKEN" "token を argv や環境ログに出さない"
assert_contains "$l" "PATH0=$store/bin" "PATH の先頭に共有 bin（attestation の gh 用）"

# ---- token なし: bootstrap の gh を検証なしで先に入れる ----
rm -f "$log" "$keyfile"
rc=0
FAKE_FAIL_VERIFIED=0 AQUA_BIN="$fake" bash "$STEP" >/dev/null 2>&1 || rc=$?
assert_eq "0" "$rc" "token なし: 成功する"
l="$(cat "$log")"
assert_contains "$l" "ARGS=install -a -t bootstrap" "token なし: bootstrap タグを先に入れる"
assert_contains "$l" "NOATTEST=true" "token なし: bootstrap だけ検証なし"
assert_eq "1" "$(grep -c 'NOATTEST=true' "$log")" "token なし: 検証なしは bootstrap の 1 回だけ"

# ---- token なしで検証つき install が失敗 → 非 0、キーなし ----
rm -f "$log" "$keyfile"
rc=0
out="$(FAKE_FAIL_VERIFIED=1 AQUA_BIN="$fake" bash "$STEP" 2>&1)" || rc=$?
[ "$rc" -ne 0 ] || fail "検証つき install の失敗で成功した"
[ ! -e "$keyfile" ] || fail "install 失敗なのにキーを書いた"
echo "PASS: install 失敗は非 0 でキーを書かない"

# ---- 古い版の掃除 ----
gh="$store/pkgs/github_release/github.com"
rm -rf "$store/pkgs"
mkdir -p "$gh/cli/cli/v1.0.0/x" "$gh/cli/cli/v2.0.0/x" "$gh/cli/cli/v2.0.1/x" \
	"$gh/Foo/Bar/v0.1.0/x" "$gh/Foo/Bar/v0.2.0/x" \
	"$gh/other/tool/v9.9.9/x" "$gh/aquaproj/aqua-proxy/v1.2.3/x"
# 古い Foo/Bar の下から動いているプロセスを立てる
cp /bin/sleep "$gh/Foo/Bar/v0.1.0/x/sleeper"
# macOS はコピーした署名つきバイナリを起動時に殺すため、ad-hoc 署名し直す。
if [ "$(uname -s)" = Darwin ]; then codesign -f -s - "$gh/Foo/Bar/v0.1.0/x/sleeper" 2>/dev/null; fi
"$gh/Foo/Bar/v0.1.0/x/sleeper" 60 &
bgpid=$!
sleep 1
rm -f "$keyfile"
AQUA_BIN="$fake" GITHUB_TOKEN=t bash "$STEP" >/dev/null 2>&1
[ ! -d "$gh/cli/cli/v1.0.0" ] || fail "参照されない古い版が残った (cli v1.0.0)"
[ ! -d "$gh/cli/cli/v2.0.1" ] || fail "参照されない版が残った (cli v2.0.1)"
echo "PASS: 参照されない版を消す"
[ -d "$gh/cli/cli/v2.0.0" ] || fail "参照される版を消した (cli v2.0.0)"
[ -d "$gh/Foo/Bar/v0.2.0" ] || fail "参照される版を消した (Foo/Bar v0.2.0。大文字小文字違い)"
echo "PASS: 参照される版は残す"
[ -d "$gh/Foo/Bar/v0.1.0" ] || fail "動いている版を消した"
echo "PASS: 動いている版は次回へ回す"
[ -d "$gh/other/tool/v9.9.9" ] || fail "設定に出てこないパッケージを消した"
[ -d "$gh/aquaproj/aqua-proxy/v1.2.3" ] || fail "aqua-proxy を消した"
echo "PASS: 設定に出てこないパッケージには触らない"
kill "$bgpid" 2>/dev/null || true
bgpid=""

# 次回（動いていない）で消える
rm -f "$keyfile"
AQUA_BIN="$fake" GITHUB_TOKEN=t bash "$STEP" >/dev/null 2>&1
[ ! -d "$gh/Foo/Bar/v0.1.0" ] || fail "動いていなくなった版が残った"
echo "PASS: 動いていなくなった版は次回で消える"

echo "ALL PASS"
