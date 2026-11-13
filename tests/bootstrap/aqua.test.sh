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
# 展開したアーカイブが誰でも書ける権限で置いたファイル
mkdir -p "$store/pkgs/github_release/github.com/x/y/v1"
: >"$store/pkgs/github_release/github.com/x/y/v1/f"
chmod 777 "$store/pkgs/github_release/github.com/x/y/v1" "$store/pkgs/github_release/github.com/x/y/v1/f"
rc=0
out="$(AQUA_BIN="$fake" GITHUB_TOKEN=SECRET_TOKEN bash "$STEP" 2>&1)" || rc=$?
assert_eq "0" "$rc" "token あり: 成功する"
assert_no_group_other_write "共有 aqua" "$store/pkgs/github_release/github.com/x/y/v1" "$store/pkgs/github_release/github.com/x/y/v1/f"
rm -rf "$store/pkgs/github_release/github.com/x"
assert_eq "$want" "$(cat "$keyfile")" "token あり: キーを書く"
for f in aqua.yaml registry.yaml aqua-policy.yaml aqua-checksums.json; do
	cmp -s "$cfg/$f" "$store/config/$f" || fail "config/$f がソースと違う"
done
echo "PASS: config へ 4 ファイルをコピーする"
l="$(cat "$log")"
assert_contains "$l" "ARGS=policy allow $store/config.new/aqua-policy.yaml" "install 前に staging の policy を許可する"
assert_contains "$l" "ARGS=policy allow $store/config/aqua-policy.yaml" "反映後に共有側の policy を許可する"
assert_contains "$l" "ARGS=install -a ROOT=$store GLOBAL=$store/config.new/aqua.yaml POLICY=$store/config.new/aqua-policy.yaml" "install -a を staging の config で"
[ ! -e "$store/config.new" ] || fail "config.new が残った"
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
[ ! -e "$store/config.new" ] || fail "失敗後に config.new が残った"
echo "PASS: install 失敗は非 0 でキーを書かない"

# 失敗した実行は config/ を変えない
echo 'packages: [old]' >"$store/config/aqua.yaml"
rm -f "$keyfile"
rc=0
FAKE_FAIL_VERIFIED=1 AQUA_BIN="$fake" bash "$STEP" >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "失敗が成功した"
assert_eq "packages: [old]" "$(cat "$store/config/aqua.yaml")" "失敗した実行は config/ を変えない"
[ ! -e "$store/config.new" ] || fail "失敗後に config.new が残った"

# ---- 古い版の掃除 ----
setup_cfg() {
	printf 'packages:\n%s\n' "$1" >"$cfg/aqua.yaml"
}
gh="$store/pkgs/github_release/github.com"
mkgc() {
	rm -rf "$store/pkgs"
	local d
	for d in "$@"; do mkdir -p "$gh/$d/x"; done
}
rungc() {
	rm -f "$keyfile"
	AQUA_BIN="$fake" GITHUB_TOKEN=t bash "$STEP" >/dev/null 2>&1
}
keep() { [ -d "$gh/$1" ] || fail "消してはいけない版を消した: $1 ($2)"; }
gone() { [ ! -d "$gh/$1" ] || fail "古い版が残った: $1"; }

setup_cfg '  - name: acme/tool@v2.0.0
  - name: Foo/Bar@v0.2.0 # x'
mkgc acme/tool/v1.0.0 acme/tool/v2.0.0 acme/tool/v2.0.1 Foo/Bar/v0.1.0 Foo/Bar/v0.2.0 other/tool/v9.9.9 aquaproj/aqua-proxy/v1.2.3
# 古い Foo/Bar の下から動いているプロセスを立てる
cp /bin/sleep "$gh/Foo/Bar/v0.1.0/x/sleeper"
# macOS はコピーした署名つきバイナリを起動時に殺すため、ad-hoc 署名し直す。
if [ "$(uname -s)" = Darwin ]; then codesign -f -s - "$gh/Foo/Bar/v0.1.0/x/sleeper" 2>/dev/null; fi
"$gh/Foo/Bar/v0.1.0/x/sleeper" 60 &
bgpid=$!
sleep 1
rungc
gone acme/tool/v1.0.0
gone acme/tool/v2.0.1
echo "PASS: 参照されない版を消す"
keep acme/tool/v2.0.0 参照中
keep Foo/Bar/v0.2.0 "参照中。大文字小文字違い"
echo "PASS: 参照される版は残す"
keep Foo/Bar/v0.1.0 動作中
echo "PASS: 動いている版は次回へ回す"
keep other/tool/v9.9.9 未掲載
keep aquaproj/aqua-proxy/v1.2.3 未掲載
echo "PASS: 設定に出てこないパッケージには触らない"
kill "$bgpid" 2>/dev/null || true
wait "$bgpid" 2>/dev/null || true
bgpid=""
rungc
gone Foo/Bar/v0.1.0
echo "PASS: 動いていなくなった版は次回で消える"

# symlink 経由（macOS の ps が出すパス）で動いている版は消さない
mkgc acme/tool/v1.0.0 acme/tool/v2.0.0
mkdir -p "$tmp/home/aquaproj-aqua"
ln -s "$store/pkgs" "$tmp/home/aquaproj-aqua/pkgs"
cp /bin/sleep "$gh/acme/tool/v1.0.0/x/sleeper"
if [ "$(uname -s)" = Darwin ]; then codesign -f -s - "$gh/acme/tool/v1.0.0/x/sleeper" 2>/dev/null; fi
"$tmp/home/aquaproj-aqua/pkgs/github_release/github.com/acme/tool/v1.0.0/x/sleeper" 60 &
bgpid=$!
sleep 1
if [ "$(uname -s)" = Darwin ]; then
	rungc
	keep acme/tool/v1.0.0 symlink経由で実行中
	echo "PASS: symlink 経由で動く版は消さない"
fi
kill "$bgpid" 2>/dev/null || true
wait "$bgpid" 2>/dev/null || true
bgpid=""

# 厳密に読めない書き方は、そのパッケージの版を全て残す
check_skip() { # <説明> <設定> <dir...>
	local what="$1" conf="$2" d
	shift 2
	setup_cfg "$conf"
	mkgc "$@"
	rungc
	for d in "$@"; do keep "$d" "$what"; done
	echo "PASS: $what は消さない"
}
check_skip "引用符つきの name" '  - name: "acme/tool@v2.0.0"' acme/tool/v1.0.0 acme/tool/v2.0.0
check_skip "/ を含む版" '  - name: acme/tool@go/v2.0.0' acme/tool/v1.0.0 acme/tool/go
check_skip "version_prefix つきのタグ" '  - name: acme/tool@2.0.0' acme/tool/prefix-1.0.0 acme/tool/prefix-2.0.0
check_skip "version: が別行" '  - name: acme/tool
    version: v2.0.0' acme/tool/v1.0.0 acme/tool/v2.0.0
check_skip "コメントだけの言及" '  # acme/tool@v2.0.0 を使う予定' acme/tool/v1.0.0 acme/tool/v2.0.0
check_skip "別の形でも出てくる" '  - name: acme/tool@v2.0.0
  - name: "acme/tool@v3"' acme/tool/v1.0.0 acme/tool/v2.0.0

# aqua が内部で使う gh（cli/cli）は、設定の版と違っても消さない
setup_cfg '  - name: cli/cli@v2.0.0'
mkgc cli/cli/v1.0.0 cli/cli/v2.0.0 cli/cli/v2.0.1
rungc
keep cli/cli/v1.0.0 "aqua 内部の gh"
keep cli/cli/v2.0.1 "aqua 内部の gh"
echo "PASS: cli/cli（gh）の版は消さない"

# npm の CLI（23）のラッパーが絶対パスで指す版は、動いていなくても消さない
setup_cfg '  - name: acme/node@v2.0.0'
mkgc acme/node/v1.0.0 acme/node/v2.0.0 acme/node/v0.9.0
mkdir -p "$SHARED_ROOT/npm-global/old/bin"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$gh/acme/node/v1.0.0/x/node" >"$SHARED_ROOT/npm-global/old/bin/difit"
rungc
keep acme/node/v1.0.0 "npm のラッパーが参照"
gone acme/node/v0.9.0
rm -rf "$SHARED_ROOT/npm-global"
rungc
gone acme/node/v1.0.0
echo "PASS: npm のラッパーが参照する版は残し、参照が消えたら消す"

echo "ALL PASS"
