#!/usr/bin/env bash
# bootstrap/23-shared-npm.sh のテスト。
# /opt は触らず、SHARED_ROOT を一時ディレクトリへ向ける。aqua / node / npm は偽のスクリプトに差し替える。
set -eu
# shellcheck source-path=SCRIPTDIR source=../lib.sh
. "$(dirname "$0")/../lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export SHARED_ROOT="$tmp/opt" BOOTSTRAP_ALLOW_NONROOT=1
export DOTFILES_SRC="$tmp/src"
unset GITHUB_TOKEN DOTFILES_SHARED_FORCE DOTFILES_STATE_COMMIT FAKE_NPM_FAIL
# 本体はリポの bootstrap/ から相対で lib.sh を読むので、コピーを作って NPM_GLOBALS の行を書き換えられるようにする。
mkdir -p "$tmp/src/bootstrap" "$tmp/src/dot_config/aquaproj-aqua"
cp "$REPO/bootstrap/lib.sh" "$REPO/bootstrap/23-shared-npm.sh" "$tmp/src/bootstrap/"
fake_shared_aqua_step "$tmp/src/bootstrap"
STEP="$tmp/src/bootstrap/23-shared-npm.sh"
AQUA_YAML="$tmp/src/dot_config/aquaproj-aqua/aqua.yaml"
set_node() { printf 'packages:\n  - name: golang/go@go1.0.0\n  - name: nodejs/node@%s # node\n' "$1" >"$AQUA_YAML"; }
set_node v1.0.0
keyfile="$SHARED_ROOT/dotfiles-shared/keys/23"
root="$SHARED_ROOT/npm-global"

# ---- 偽の aqua / node / npm ----
fakebin="$tmp/fakenode"
mkdir -p "$fakebin"
printf '#!/bin/sh\necho v1.0.0\n' >"$fakebin/node"
cat >"$fakebin/npm" <<'FAKE'
#!/usr/bin/env bash
# install -g --prefix P ... <pkg>... を真似て P/bin/<名前> -> ../lib/node_modules/<pkg>/bin/<名前>.js を作る。
echo "npm $* | cwd=$PWD cache=${npm_config_cache:-} PATH0=${PATH%%:*} userconfig=${npm_config_userconfig:-} globalconfig=${npm_config_globalconfig:-}" >>"$FAKE_LOG"
[ -n "${npm_config_cache:-}" ] && : >"$npm_config_cache/cachefile"
prefix=""
pkgs=()
while [ $# -gt 0 ]; do
	case "$1" in
	--prefix) prefix="$2"; shift ;;
	install | -g | --*) ;;
	*) pkgs+=("$1") ;;
	esac
	shift
done
[ -n "$prefix" ] || exit 2
[ "${FAKE_NPM_NOBIN:-}" = 1 ] && exit 0
for p in "${pkgs[@]}"; do
	n="${p%@*}"
	b="${n##*/}"
	mkdir -p "$prefix/lib/node_modules/$n/bin" "$prefix/bin"
	echo "// $p" >"$prefix/lib/node_modules/$n/bin/$b.js"
	ln -s "../lib/node_modules/$n/bin/$b.js" "$prefix/bin/$b"
done
[ "${FAKE_NPM_FAIL:-}" = 1 ] && exit 1
exit 0
FAKE
chmod +x "$fakebin/node" "$fakebin/npm"
fakeaqua="$tmp/fake-aqua"
cat >"$fakeaqua" <<FAKE
#!/usr/bin/env bash
echo "aqua \$* ROOT=\${AQUA_ROOT_DIR:-} GLOBAL=\${AQUA_GLOBAL_CONFIG:-} POLICY=\${AQUA_POLICY_CONFIG:-}" >>"\$FAKE_LOG"
[ "\$1" = which ] || exit 2
case "\$2" in
node) echo "$fakebin/node" ;;
npm) echo "$fakebin/npm" ;;
*) exit 1 ;;
esac
FAKE
chmod +x "$fakeaqua"
export FAKE_LOG="$tmp/log"
: >"$FAKE_LOG"

# ---- 共有 aqua が揃っていない: 明確なメッセージで失敗し、何も作らない ----
rc=0
out="$(AQUA_BIN="$fakeaqua" bash "$STEP" 2>&1)" || rc=$?
[ "$rc" -ne 0 ] || fail "共有 aqua が無いのに成功した"
assert_contains "$out" "共有 aqua" "共有 aqua が無ければメッセージを出して失敗する"
[ ! -e "$root" ] && [ ! -e "$keyfile" ] || fail "共有 aqua が無いのに何かを作った"

mkdir -p "$SHARED_ROOT/aquaproj-aqua/config" "$SHARED_ROOT/dotfiles-shared/keys"
: >"$SHARED_ROOT/aquaproj-aqua/config/aqua.yaml"
: >"$SHARED_ROOT/aquaproj-aqua/config/aqua-policy.yaml"
echo k20 >"$SHARED_ROOT/dotfiles-shared/keys/20"
assert_stale_shared_aqua_skips "$STEP" "$SHARED_ROOT/dotfiles-shared/keys/20" "$root" "$keyfile"

# ---- AQUA_BIN が空 ----
rc=0
out="$(env -u AQUA_BIN bash "$STEP" 2>&1)" || rc=$?
[ "$rc" -ne 0 ] || fail "AQUA_BIN 空で成功した"
assert_contains "$out" "AQUA_BIN" "AQUA_BIN が空ならメッセージを出して失敗する"

# ---- --check ----
rc=0
bash "$STEP" --check || rc=$?
assert_eq "1" "$rc" "--check: キーが無ければ 1"
[ ! -e "$root" ] || fail "--check: 何かを書いた"

run() { AQUA_BIN="$fakeaqua" bash "$STEP" 2>&1; }
cur() { readlink "$root/current"; }

out="$(run)" || fail "通常の実行が失敗" "$out"
k1="$(cat "$keyfile")"
assert_eq "$k1" "$(cur)" "current が新しい key を指し、key は keys/23 と同じ"
rc=0
bash "$STEP" --check || rc=$?
assert_eq "0" "$rc" "--check: 実行後は 0"

# NPM_GLOBALS の行を変えると 1
cp "$STEP" "$tmp/step.orig"
sed -i.bak 's|difit@[0-9.]*|difit@0.0.1|' "$STEP" && rm "$STEP.bak"
rc=0
bash "$STEP" --check || rc=$?
assert_eq "1" "$rc" "--check: NPM_GLOBALS の行を変えれば 1"
cp "$tmp/step.orig" "$STEP"
# node の版（aqua.yaml）を変えると 1
set_node v2.0.0
rc=0
bash "$STEP" --check || rc=$?
assert_eq "1" "$rc" "--check: node の版を変えれば 1"
set_node v1.0.0
rc=0
bash "$STEP" --check || rc=$?
assert_eq "0" "$rc" "--check: 戻せば 0"

# ---- 配置の中身 ----
l="$(cat "$FAKE_LOG")"
assert_contains "$l" "ROOT=$SHARED_ROOT/aquaproj-aqua GLOBAL=$SHARED_ROOT/aquaproj-aqua/config/aqua.yaml POLICY=$SHARED_ROOT/aquaproj-aqua/config/aqua-policy.yaml" "共有 aqua の設定で node を解決する"
assert_contains "$l" "install -g --prefix $root/$k1/prefix" "key のディレクトリの中へ npm install する"
assert_contains "$l" "difit@" "NPM_GLOBALS の difit を入れる"
assert_contains "$l" "cline@" "NPM_GLOBALS の cline を入れる"
assert_contains "$l" "cwd=/" "ルートへ移ってから npm を流す"
cachedir="$(sed -n 's/.*cache=\([^ ]*\) PATH0.*/\1/p' "$FAKE_LOG" | head -1)"
case "$cachedir" in "$root"/* | "$HOME"/* | "") fail "npm のキャッシュが共有側かホームを指す: $cachedir" ;; esac
[ ! -e "$cachedir" ] || fail "npm の一時キャッシュを消していない"
echo "PASS: npm のキャッシュは一時ディレクトリで、終わったら消す"
[ -x "$root/$k1/bin/difit" ] && [ -x "$root/$k1/bin/cline" ] || fail "ラッパーが無い"
w="$(cat "$root/current/bin/difit")"
assert_contains "$w" "$fakebin/node" "ラッパーは共有 aqua の node を絶対パスで呼ぶ"
assert_contains "$w" "\"$root/$k1/prefix/lib/node_modules/difit/bin/difit.js\"" "ラッパーは key 配下の実体を指す（パスを二重にしない）"

# 2 回目は取得しない
n1="$(grep -c 'install -g' "$FAKE_LOG")"
run >/dev/null || fail "2 回目が失敗"
assert_eq "$n1" "$(grep -c 'install -g' "$FAKE_LOG")" "配置済みなら npm install を流し直さない"

# ---- 組の入れ替え: current は新しい key、1 つ前の組は残り、2 つ前は消える ----
set_node v2.0.0
run >/dev/null || fail "2 つ目の組が失敗"
k2="$(cat "$keyfile")"
set_node v3.0.0
run >/dev/null || fail "3 つ目の組が失敗"
k3="$(cat "$keyfile")"
[ "$k1" != "$k2" ] && [ "$k2" != "$k3" ] || fail "key が変わらない"
assert_eq "$k3" "$(cur)" "current が最新の組を指す"
[ -d "$root/$k2" ] || fail "1 つ前の組を消した"
[ ! -e "$root/$k1" ] || fail "2 つ前の組が残った"
echo "PASS: 1 つ前の組は残り、2 つ前は消える"

# ---- 失敗: 途中の組を消し、current と key は変えず、非 0 ----
set_node v4.0.0
rc=0
out="$(FAKE_NPM_FAIL=1 run)" || rc=$?
[ "$rc" -ne 0 ] || fail "npm の失敗で成功した"
assert_eq "$k3" "$(cur)" "失敗しても current は変えない"
assert_eq "$k3" "$(cat "$keyfile")" "失敗してもキーを進めない"
assert_eq "3" "$(find "$root" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" "失敗した組のディレクトリを残さない（current と既存の 2 組だけ）"
failcache="$(sed -n 's/.*cache=\([^ ]*\) PATH0.*/\1/p' "$FAKE_LOG" | tail -1)"
[ ! -e "$failcache" ] || fail "失敗時に npm の一時キャッシュを残した"
echo "PASS: 失敗時も一時キャッシュを消す"
# npm が成功しても bin が無ければ失敗扱い
rc=0
out="$(FAKE_NPM_NOBIN=1 run)" || rc=$?
[ "$rc" -ne 0 ] || fail "bin が無いのに成功した"
assert_eq "$k3" "$(cur)" "bin が無ければ current は変えない"
assert_eq "$k3" "$(cat "$keyfile")" "bin が無ければキーを進めない"
assert_eq "3" "$(find "$root" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" "bin が無い組は残さない"
# root が npm を流すときはユーザの npmrc を読ませない
uc="$(sed -n 's/.* userconfig=\([^ ]*\) .*/\1/p' "$FAKE_LOG" | head -n 1)"
gc="$(sed -n 's/.* globalconfig=\([^ ]*\)$/\1/p' "$FAKE_LOG" | head -n 1)"
case "$uc" in */npmrc.user) ;; *) fail "npm_config_userconfig が一時の空ファイルでない" "$uc" ;; esac
case "$gc" in */npmrc.global) ;; *) fail "npm_config_globalconfig が一時の空ファイルでない" "$gc" ;; esac
[ "$uc" != "$gc" ] || fail "userconfig と globalconfig が同じ（npm が double-loading で止まる）"
echo "PASS: npm_config_userconfig / globalconfig を別々の空ファイルにする"
# 失敗の後に成功すれば入る
out="$(run)" || fail "失敗の後の再実行が失敗" "$out"
k4="$(cat "$keyfile")"
assert_eq "$k4" "$(cur)" "失敗の後の再実行で current が進む"
[ -d "$root/$k3" ] && [ ! -e "$root/$k2" ] || fail "再実行後の組の入れ替えが違う"

# ---- 同じ key での入れ直し（keys/23 を消した再実行）: 1 つ前の組を消さない ----
mkdir -p "$root/ancient/bin"
: >"$root/ancient/.complete"
touch -t 200001010000 "$root/ancient"
rm -f "$keyfile"
run >/dev/null || fail "同じ key の再実行が失敗"
assert_eq "$k4" "$(cur)" "同じ key: current は変わらない"
[ -d "$root/$k3" ] || fail "同じ key の再実行で 1 つ前の組を消した"
[ ! -e "$root/ancient" ] || fail "同じ key の再実行で古い組が残った"
echo "PASS: 同じ key の再実行でも 1 つ前の組を残し、それ以前は消す"

# ---- macOS 形式の ps（リンクのパスだけ）でも動作中の古い組を消さない ----
# lib.sh の本物の running_* を使い、ps だけを PATH 上の偽物にする（/proc の無い macOS でのみ意味がある）。
if [ ! -d /proc/self ]; then
	mkdir -p "$tmp/psbin"
	# どの引数で呼ばれても、渡した 1 行だけを出す偽の ps。
	psout() {
		printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s"\n' "$1" >"$tmp/psbin/ps"
		chmod +x "$tmp/psbin/ps"
	}
	runps() { PATH="$tmp/psbin:$PATH" AQUA_BIN="$fakeaqua" bash "$STEP" 2>&1; }
	# k3 は今は 1 つ前、k4 が current。次の組 k5 を入れたとき k3 が消える対象になる。
	# (a) リンクのパス（current/bin/difit）だけが ps に出る
	psout "$root/current/bin/difit"
	set_node v5.0.0
	out="$(runps)" || fail "(a) 実行が失敗" "$out"
	[ -d "$root/$k3" ] || fail "(a) リンク経由で動いているのに古い組を消した"
	# (b) 動いていなければ消える
	psout "/usr/bin/other"
	set_node v6.0.0
	runps >/dev/null || fail "(b) 実行が失敗"
	[ ! -e "$root/$k3" ] || fail "(b) 動いていないのに古い組が残った"
	# (c) 古い組へ symlink 越しでなく直接のパスで動いていても消さない
	set_node v7.0.0
	runps >/dev/null || fail "(c) 準備が失敗"
	# 1 つ前でも current でもない組を作って、その下から動いている形にする
	mkdir -p "$root/stale/bin"
	: >"$root/stale/.complete"
	psout "$root/stale/prefix/node"
	set_node v8.0.0
	runps >/dev/null || fail "(c) 実行が失敗"
	[ -d "$root/stale" ] || fail "(c) 組の下から動いているのに消した"
	psout "/usr/bin/other"
	set_node v9.0.0
	runps >/dev/null || fail "(c2) 実行が失敗"
	[ ! -e "$root/stale" ] || fail "(c2) 止まったのに消えない"
	echo "PASS: macOS 形式の ps（リンクのパスだけ）でも動作中の古い組を消さない"
fi

# ---- env.sh: 揃っているときだけ ~/.local/bin の後ろに足す ----
cfg="$tmp/chezmoi.toml"
chezmoi_config "$cfg"
envsh="$(chezmoi --source "$REPO" --config "$cfg" execute-template <"$REPO/dot_config/shell/env.sh.tmpl")"
assert_contains "$envsh" "[ -d /opt/npm-global/current/bin ] && [ -f /opt/dotfiles-shared/keys/23 ]" "env.sh: 揃っているときだけ足す"
npm_line="$(printf '%s\n' "$envsh" | grep -n '_path_prepend /opt/npm-global/current/bin' | cut -d: -f1)"
# shellcheck disable=SC2016  # grep の固定文字列
local_line="$(printf '%s\n' "$envsh" | grep -n '_path_prepend "$LOCAL_PREFIX/bin"' | cut -d: -f1)"
[ -n "$npm_line" ] && [ "$npm_line" -lt "$local_line" ] || fail "env.sh: npm の CLI を ~/.local/bin より先に prepend していない（PATH では後ろにならない）"
echo "PASS: env.sh: PATH では ~/.local/bin の後ろ"

echo "ALL PASS"
