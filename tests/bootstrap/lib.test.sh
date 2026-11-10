#!/usr/bin/env bash
# bootstrap/lib.sh の携帯な共通関数のテスト。一時ディレクトリだけを触る。
set -eu
# shellcheck source-path=SCRIPTDIR source=../lib.sh
. "$(dirname "$0")/../lib.sh"
# shellcheck source-path=SCRIPTDIR source=../../bootstrap/lib.sh
. "$REPO/bootstrap/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- swap_symlink ---
mkdir "$tmp/a" "$tmp/b"
swap_symlink "$tmp/a" "$tmp/link"
assert_eq "$tmp/a" "$(readlink "$tmp/link")" "swap_symlink: 新規作成"
swap_symlink "$tmp/b" "$tmp/link"
assert_eq "$tmp/b" "$(readlink "$tmp/link")" "swap_symlink: 差し替え"
[ ! -e "$tmp/b/b" ] || fail "swap_symlink: 差し替え先の中に symlink を作った"
assert_eq "" "$(ls -A "$tmp/b")" "swap_symlink: ディレクトリの中へ作らない"

mkdir "$tmp/realdir"
if swap_symlink "$tmp/a" "$tmp/realdir" 2>"$tmp/err"; then
	fail "swap_symlink: 実ディレクトリを置き換えた"
fi
assert_contains "$(cat "$tmp/err")" "$tmp/realdir" "swap_symlink: 実ディレクトリは stderr に理由を出して失敗"
[ -d "$tmp/realdir" ] && [ ! -L "$tmp/realdir" ] || fail "swap_symlink: 実ディレクトリが壊れた"

# --- running_from_any ---
mkdir "$tmp/run"
cp /bin/sleep "$tmp/run/sleep"
# macOS はコピーした署名付きバイナリを kill するため ad-hoc 署名し直す
if [ "$(uname -s)" = Darwin ]; then
	codesign -s - --force "$tmp/run/sleep" 2>/dev/null
fi
"$tmp/run/sleep" 30 &
pid=$!
sleep 1
rc=0
running_from_any "$tmp/run" || rc=$?
assert_eq "0" "$rc" "running_from_any: 実行中なら 0"
rc=0
running_from_any "$tmp/run/" || rc=$?
assert_eq "0" "$rc" "running_from_any: 末尾スラッシュでも 0"
rc=0
running_from_any "$tmp/other" || rc=$?
assert_eq "1" "$rc" "running_from_any: 別ディレクトリなら 1"
rc=0
running_matching "/run/sleep" || rc=$?
assert_eq "0" "$rc" "running_matching: 実行パスに部分文字列があれば 0"
rc=0
running_matching "/no-such-dir-$$/" || rc=$?
assert_eq "1" "$rc" "running_matching: 無ければ 1"
realrun="$(cd "$tmp/run" && pwd -P)"
rc=0
running_exact "$tmp/run/sleep" || running_exact "$realrun/sleep" || rc=$?
assert_eq "0" "$rc" "running_exact: 実行パスが完全一致なら 0"
rc=0
running_exact "$tmp/run/slee" || rc=$?
assert_eq "1" "$rc" "running_exact: 前方一致だけなら 1"
rc=0
running_exact "$tmp/run/sleep-bedrock" || rc=$?
assert_eq "1" "$rc" "running_exact: 後ろに続く名前には一致しない"
kill "$pid"
wait "$pid" 2>/dev/null || true
rc=0
running_from_any "$tmp/run" || rc=$?
assert_eq "1" "$rc" "running_from_any: kill 後は 1"
rc=0
running_matching "/run/sleep" || rc=$?
assert_eq "1" "$rc" "running_matching: kill 後は 1"
rc=0
running_exact "$tmp/run/sleep" || running_exact "$realrun/sleep" || rc=$?
assert_eq "1" "$rc" "running_exact: kill 後は 1"

# --- shared_owner_group ---
case "$(uname -s)" in
Darwin) want="root:wheel" ;;
*) want="root:root" ;;
esac
assert_eq "$want" "$(shared_owner_group)" "shared_owner_group"

# --- pins_key ---
printf 'one\n' >"$tmp/f1"
printf 'two\n' >"$tmp/f2"
k1="$(pins_key "$tmp/f1" "$tmp/f2")"
assert_eq "$k1" "$(pins_key "$tmp/f1" "$tmp/f2")" "pins_key: 同じ入力は同じ値"
assert_eq "12" "${#k1}" "pins_key: 12 桁"
printf 'twO\n' >"$tmp/f3"
k2="$(pins_key "$tmp/f1" "$tmp/f3")"
[ "$k1" != "$k2" ] || fail "pins_key: 内容を変えても同じ値"
echo "PASS: pins_key: 内容が違えば違う値"
k3="$(pins_key "$tmp/f2" "$tmp/f1")"
[ "$k1" != "$k3" ] || fail "pins_key: 引数順が無視された"
echo "PASS: pins_key: 引数順を区別"

# --- macOS 形式の ps: comm / args が symlink（venv のリンク）でも実体で照合する ---
# /proc の無い環境でだけ意味がある（/proc があれば readlink が実体を返す）。
if [ ! -d /proc/self ]; then
	(
		tmp="$(cd "$tmp" && pwd -P)"
		pyd="$tmp/uvpy/python/cpython-3.13.0/bin"
		mkdir -p "$pyd" "$tmp/proj/.venv/bin" "$tmp/other"
		: >"$pyd/python3.13"
		chmod +x "$pyd/python3.13"
		# venv: python -> python3 (相対) -> uv の Python（絶対）の 2 段
		ln -s "$pyd/python3.13" "$tmp/proj/.venv/bin/python3"
		ln -s python3 "$tmp/proj/.venv/bin/python"
		: >"$tmp/other/plain"
		mkdir -p "$tmp/psbin"
		cat >"$tmp/psbin/ps" <<FAKE
#!/usr/bin/env bash
case "\$*" in
*comm=*) printf '%s\n' "\$FAKE_PS_COMM" ;;
*args=*) printf '%s\n' "\$FAKE_PS_ARGS" ;;
esac
FAKE
		chmod +x "$tmp/psbin/ps"
		PATH="$tmp/psbin:$PATH"
		export FAKE_PS_COMM="$tmp/proj/.venv/bin/python" FAKE_PS_ARGS="$tmp/proj/.venv/bin/python -m app"
		running_from_any "$tmp/uvpy/python" || fail "running_from_any: venv のリンク経由の Python を見ない"
		running_matching "/uvpy/python/cpython-3.13.0/" || fail "running_matching: venv のリンクの実体を見ない"
		running_exact "$pyd/python3.13" || fail "running_exact: リンクの実体のパスを見ない"
		running_args_matching "/uvpy/python/" || fail "running_args_matching: 引数の第 1 語のリンクを見ない"
		export FAKE_PS_COMM="$tmp/other/plain" FAKE_PS_ARGS="$tmp/other/plain x"
		! running_from_any "$tmp/uvpy/python" || fail "running_from_any: 無関係なプロセスで真"
		! running_matching "/uvpy/python/" || fail "running_matching: 無関係なプロセスで真"
		! running_exact "$pyd/python3.13" || fail "running_exact: 無関係なプロセスで真"
		! running_args_matching "/uvpy/python/" || fail "running_args_matching: 無関係なプロセスで真"
	) || exit 1
	echo "PASS: macOS 形式の ps: symlink のパスでも実体で照合する"
fi
