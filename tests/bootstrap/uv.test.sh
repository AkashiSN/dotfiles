#!/usr/bin/env bash
# bootstrap/24-shared-uv.sh と run_after_35-uv-tools.sh.tmpl（.chezmoitemplates/uv-cleanup.sh）のテスト。
# /opt は触らず SHARED_ROOT / HOME を一時ディレクトリへ向ける。aqua / uv / ps は偽物に差し替える。
set -eu
# shellcheck source-path=SCRIPTDIR source=../lib.sh
. "$(dirname "$0")/../lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export SHARED_ROOT="$tmp/opt" BOOTSTRAP_ALLOW_NONROOT=1
export DOTFILES_SRC="$tmp/src"
unset GITHUB_TOKEN DOTFILES_SHARED_FORCE DOTFILES_STATE_COMMIT FAKE_UV_FAIL FAKE_UV_NOCMD
mkdir -p "$tmp/src/bootstrap" "$tmp/src/dot_config/uv"
cp "$REPO/bootstrap/lib.sh" "$tmp/src/bootstrap/"
fake_shared_aqua_step "$tmp/src/bootstrap"
STEP="$tmp/src/bootstrap/24-shared-uv.sh"
PYVER="$tmp/src/dot_config/uv/dot_python-version"
echo 3.13 >"$PYVER"
keyfile="$SHARED_ROOT/dotfiles-shared/keys/24"
root="$SHARED_ROOT/uv"

# ---- 偽の uv / aqua ----
fakebin="$tmp/fakeuv"
mkdir -p "$fakebin"
cat >"$fakebin/uv" <<'FAKE'
#!/usr/bin/env bash
echo "uv $* | cwd=$PWD cache=${UV_CACHE_DIR:-} noconfig=${UV_NO_CONFIG:-} pydir=${UV_PYTHON_INSTALL_DIR:-} tooldir=${UV_TOOL_DIR:-}" >>"$FAKE_LOG"
case "$1 ${2:-}" in
"python install")
	py="$UV_PYTHON_INSTALL_DIR/cpython-$3.0-fake/bin"
	mkdir -p "$py" "$UV_PYTHON_BIN_DIR"
	printf '#!/bin/sh\n' >"$py/python3"
	# 展開したアーカイブには誰でも書ける権限のファイルが入っていることがある
	chmod 777 "$py/python3"
	for n in python python3 "python$3"; do
		ln -sf "$py/python3" "$UV_PYTHON_BIN_DIR/$n"
	done
	[ -z "${UV_CACHE_DIR:-}" ] || : >"$UV_CACHE_DIR/cachefile"
	;;
"tool install")
	[ "${FAKE_UV_FAIL:-}" = 1 ] && exit 1
	spec="${*: -1}"
	name="${spec%%[[=]*}"
	cmd="$name"
	[ "$name" = graphifyy ] && cmd=graphify
	mkdir -p "$UV_TOOL_DIR/$name/bin" "$UV_TOOL_BIN_DIR"
	printf 'home = %s/cpython-%s.0-fake/bin\n' "$UV_PYTHON_INSTALL_DIR" "$4" >"$UV_TOOL_DIR/$name/pyvenv.cfg"
	[ "${FAKE_UV_NOCMD:-}" = 1 ] && exit 0
	printf '#!/bin/sh\n' >"$UV_TOOL_DIR/$name/bin/$cmd"
	chmod +x "$UV_TOOL_DIR/$name/bin/$cmd"
	ln -sf "$UV_TOOL_DIR/$name/bin/$cmd" "$UV_TOOL_BIN_DIR/$cmd"
	;;
"tool list")
	for d in "$UV_TOOL_DIR"/*/; do
		[ -d "$d" ] || continue
		n="$(basename "$d")"
		echo "$n v1.0"
		for c in "$d"bin/*; do [ -e "$c" ] && echo "- $(basename "$c")"; done
	done
	;;
esac
exit 0
FAKE
chmod +x "$fakebin/uv"
fakeaqua="$tmp/fake-aqua"
cat >"$fakeaqua" <<FAKE
#!/usr/bin/env bash
echo "aqua \$* ROOT=\${AQUA_ROOT_DIR:-} GLOBAL=\${AQUA_GLOBAL_CONFIG:-}" >>"\$FAKE_LOG"
[ "\$1" = which ] || exit 2
case "\$2" in
uv) echo "$fakebin/uv" ;;
*) exit 1 ;;
esac
FAKE
chmod +x "$fakeaqua"
export FAKE_LOG="$tmp/log"
: >"$FAKE_LOG"

# ---- 共有 aqua が揃っていない ----
cp "$REPO/bootstrap/24-shared-uv.sh" "$STEP" 2>/dev/null || fail "bootstrap/24-shared-uv.sh が無い"
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
rc=0
out="$(env -u AQUA_BIN bash "$STEP" 2>&1)" || rc=$?
[ "$rc" -ne 0 ] || fail "AQUA_BIN 空で成功した"
assert_contains "$out" "AQUA_BIN" "AQUA_BIN が空ならメッセージを出して失敗する"

# ---- --check ----
rc=0
bash "$STEP" --check || rc=$?
assert_eq "1" "$rc" "--check: キーが無ければ 1"

run() { AQUA_BIN="$fakeaqua" bash "$STEP" 2>&1; }
cur() { readlink "$root/current"; }

out="$(run)" || fail "通常の実行が失敗" "$out"
k1="$(cat "$keyfile")"
assert_eq "$k1" "$(cur)" "current が新しい key を指し、key は keys/24 と同じ"
for d in tools bin; do
	assert_eq "current/$d" "$(readlink "$root/$d")" "$root/$d は current/$d への symlink"
done
[ -d "$root/python" ] && [ ! -L "$root/python" ] || fail "$root/python が実ディレクトリでない"
assert_no_group_other_write "uv の Python" "$root/python"/cpython-*/bin/python3
[ -x "$root/bin/python3" ] && [ -x "$root/bin/ansible" ] && [ -x "$root/bin/graphify" ] || fail "共有 bin に python3 / ansible / graphify が揃っていない"
rc=0
bash "$STEP" --check || rc=$?
assert_eq "0" "$rc" "--check: 実行後は 0"

# キーは UV_TOOLS と dot_python-version から決まる
echo 3.14 >"$PYVER"
rc=0
bash "$STEP" --check || rc=$?
assert_eq "1" "$rc" "--check: Python の版を変えれば 1"
echo 3.13 >"$PYVER"
cp "$STEP" "$tmp/step.orig"
sed -i.bak 's|ansible==[0-9.]*|ansible==0.0.1|' "$STEP" && rm "$STEP.bak"
rc=0
bash "$STEP" --check || rc=$?
assert_eq "1" "$rc" "--check: UV_TOOLS の行を変えれば 1"
cp "$tmp/step.orig" "$STEP"
rc=0
bash "$STEP" --check || rc=$?
assert_eq "0" "$rc" "--check: 戻せば 0"

# ---- 配置の中身 ----
l="$(cat "$FAKE_LOG")"
assert_contains "$l" "aqua which uv ROOT=$SHARED_ROOT/aquaproj-aqua GLOBAL=$SHARED_ROOT/aquaproj-aqua/config/aqua.yaml" "共有 aqua の設定で uv を解決する"
assert_contains "$l" "uv python install 3.13 --default" "dot_python-version の版を --default で入れる"
assert_contains "$l" "uv tool install --python 3.13 ansible==" "ansible を版指定で入れる"
assert_contains "$l" "graphifyy[sql,terraform]==" "graphifyy を extra と版指定で入れる"
assert_contains "$l" "cwd=/" "ルートへ移ってから uv を流す"
assert_contains "$l" "noconfig=1" "UV_NO_CONFIG=1"
assert_contains "$l" "pydir=$root/python " "Python は key の外の固定の場所へ入れる"
assert_contains "$l" "tooldir=$root/$k1/tools" "ツールは key のディレクトリの中へ入れる"
cachedir="$(sed -n 's/.*cache=\([^ ]*\) noconfig.*/\1/p' "$FAKE_LOG" | head -1)"
case "$cachedir" in "$root"/* | "$HOME"/* | "") fail "uv のキャッシュが共有側かホームを指す: $cachedir" ;; esac
[ ! -e "$cachedir" ] || fail "uv の一時キャッシュを消していない"
echo "PASS: uv のキャッシュは一時ディレクトリで、終わったら消す"

# 2 回目は取得しない
n1="$(grep -c 'uv tool install' "$FAKE_LOG")"
run >/dev/null || fail "2 回目が失敗"
assert_eq "$n1" "$(grep -c 'uv tool install' "$FAKE_LOG")" "配置済みなら uv tool install を流し直さない"

# ---- 組の入れ替え: 1 つ前は残り、2 つ前は消える ----
echo 3.14 >"$PYVER"
run >/dev/null || fail "2 つ目の組が失敗"
k2="$(cat "$keyfile")"
echo 3.15 >"$PYVER"
run >/dev/null || fail "3 つ目の組が失敗"
k3="$(cat "$keyfile")"
[ "$k1" != "$k2" ] && [ "$k2" != "$k3" ] || fail "key が変わらない"
assert_eq "$k3" "$(cur)" "current が最新の組を指す"
[ -d "$root/$k2" ] || fail "1 つ前の組を消した"
[ ! -e "$root/$k1" ] || fail "2 つ前の組が残った"
[ -x "$root/bin/graphify" ] || fail "swap 後に共有 bin が壊れた"
echo "PASS: 1 つ前の組は残り、2 つ前は消える"
# Python: 3.13 は組 k1 だけが使っていた(消えた)ので消え、3.14(1 つ前の組)と 3.15(現在)は残る
[ ! -e "$root/python/cpython-3.13.0-fake" ] || fail "どの組も使わない古い Python が残った"
[ -d "$root/python/cpython-3.14.0-fake" ] && [ -d "$root/python/cpython-3.15.0-fake" ] || fail "残した組が使う Python を消した"
[ -x "$root/$k2/bin/python3" ] || fail "1 つ前の組の python3 が壊れた"
echo "PASS: 古い Python は残る組が使っていなければ消し、使っていれば残す"

# ---- 失敗: 組を消し、current と key は変えず、非 0 ----
echo 3.16 >"$PYVER"
rc=0
out="$(FAKE_UV_FAIL=1 run)" || rc=$?
[ "$rc" -ne 0 ] || fail "uv の失敗で成功した"
assert_eq "$k3" "$(cur)" "失敗しても current は変えない"
assert_eq "$k3" "$(cat "$keyfile")" "失敗してもキーを進めない"
n="$(find "$root" -mindepth 1 -maxdepth 1 ! -type l | wc -l | tr -d ' ')"
assert_eq "3" "$n" "失敗した組のディレクトリを残さない（python と既存の 2 組だけ）"
failcache="$(sed -n 's/.*cache=\([^ ]*\) noconfig.*/\1/p' "$FAKE_LOG" | tail -1)"
[ ! -e "$failcache" ] || fail "失敗時に uv の一時キャッシュを残した"
# uv が成功してもコマンドが無ければ失敗扱い
rc=0
out="$(FAKE_UV_NOCMD=1 run)" || rc=$?
[ "$rc" -ne 0 ] || fail "コマンドが無いのに成功した"
assert_eq "$k3" "$(cur)" "コマンドが無ければ current は変えない"
assert_eq "$k3" "$(cat "$keyfile")" "コマンドが無ければキーを進めない"
n="$(find "$root" -mindepth 1 -maxdepth 1 ! -type l | wc -l | tr -d ' ')"
assert_eq "3" "$n" "コマンドが無い組は残さない"
echo 3.15 >"$PYVER"

# ---- 同じ key での入れ直し（keys/24 を消した再実行）----
mkdir -p "$root/ancient/bin"
: >"$root/ancient/.complete"
touch -t 200001010000 "$root/ancient"
rm -f "$keyfile"
run >/dev/null || fail "同じ key の再実行が失敗"
assert_eq "$k3" "$(cur)" "同じ key: current は変わらない"
[ -d "$root/$k2" ] || fail "同じ key の再実行で 1 つ前の組を消した"
[ ! -e "$root/ancient" ] || fail "同じ key の再実行で古い組が残った"
echo "PASS: 同じ key の再実行でも 1 つ前の組を残し、それ以前は消える"

# ---- macOS 形式の ps（リンクのパスだけ、または引数にスクリプト）でも動作中の古い組を消さない ----
if [ ! -d /proc/self ]; then
	mkdir -p "$tmp/psbin"
	psout() {
		printf '#!/usr/bin/env bash\nif [ "$*" = "-axww -o args=" ]; then printf "%%s\\n" "%s"; else printf "%%s\\n" "%s"; fi\n' "${2:-/usr/bin/other}" "$1" >"$tmp/psbin/ps"
		chmod +x "$tmp/psbin/ps"
	}
	runps() { PATH="$tmp/psbin:$PATH" AQUA_BIN="$fakeaqua" bash "$STEP" 2>&1; }
	# k3 が current。k4 を入れ、k5 を入れる直前に k3 が 1 つ前でなくなる状況を作る
	echo 4.0 >"$PYVER"
	run >/dev/null || fail "準備(k4)が失敗"
	# (a) 共有 bin のリンクのパスだけが ps の comm に出る
	psout "$root/bin/python3"
	echo 4.1 >"$PYVER"
	out="$(runps)" || fail "(a) 実行が失敗" "$out"
	[ -d "$root/$k3" ] || fail "(a) リンク経由で動く Python の組を消した"
	# (b) 動いていなければ消える
	psout "/usr/bin/other"
	echo 4.2 >"$PYVER"
	runps >/dev/null || fail "(b) 実行が失敗"
	[ ! -e "$root/$k3" ] || fail "(b) 動いていないのに古い組が残った"
	# (c) comm は /usr/bin/python 風のインタプリタ、引数にツールの venv のスクリプトのパス
	mkdir -p "$root/stale/bin"
	: >"$root/stale/.complete"
	psout "/some/interp" "/some/interp $root/stale/tools/ansible/bin/ansible-playbook"
	echo 4.3 >"$PYVER"
	runps >/dev/null || fail "(c) 実行が失敗"
	[ -d "$root/stale" ] || fail "(c) 引数にパスを持つプロセスが動いているのに消した"
	psout "/usr/bin/other"
	echo 4.4 >"$PYVER"
	runps >/dev/null || fail "(c2) 実行が失敗"
	[ ! -e "$root/stale" ] || fail "(c2) 止まったのに消えない"
	# (d) プロジェクトの venv のリンク（comm）が、古い Python を指す
	mkdir -p "$root/python/cpython-9.9.0-fake/bin" "$tmp/proj/.venv/bin"
	: >"$root/python/cpython-9.9.0-fake/bin/python3"
	ln -sf "$root/python/cpython-9.9.0-fake/bin/python3" "$tmp/proj/.venv/bin/python"
	psout "$tmp/proj/.venv/bin/python" "$tmp/proj/.venv/bin/python -m app"
	echo 4.5 >"$PYVER"
	runps >/dev/null || fail "(d) 実行が失敗"
	[ -d "$root/python/cpython-9.9.0-fake" ] || fail "(d) venv のリンク経由で動く古い Python を消した"
	psout "/usr/bin/other"
	echo 4.6 >"$PYVER"
	runps >/dev/null || fail "(d2) 実行が失敗"
	[ ! -e "$root/python/cpython-9.9.0-fake" ] || fail "(d2) 止まったのに古い Python が残った"
	echo "PASS: macOS 形式の ps でも動作中の古い組を消さない"
fi

# ---- ツールの版を上げても Python の場所は動かない ----
pyl="$(readlink "$root/bin/python3")"
sed -i.bak 's|ansible==[0-9.]*|ansible==8.7.1|' "$STEP" && rm "$STEP.bak"
run >/dev/null || fail "ツールの版を上げた実行が失敗"
kb="$(cat "$keyfile")"
assert_eq "$pyl" "$(readlink "$root/bin/python3")" "ツールの版を上げても python3 の向け先（Python の場所）は同じ"
case "$pyl" in "$root/python/"*) ;; *) fail "python3 が $root/python の外を指す: $pyl" ;; esac
[ -d "$root/python/cpython-$(cat "$PYVER").0-fake" ] || fail "ツールの版を上げて Python が消えた"
grep -q "$root/python/" "$root/$kb/tools/ansible/pyvenv.cfg" || fail "ツールの venv が固定の Python を指さない"
cp "$tmp/step.orig" "$STEP"
echo "PASS: ツールの版を上げても Python の場所は変わらない"

# ---- env.sh: 揃っているときだけ ~/.local/bin の後ろに足す ----
cfg="$tmp/chezmoi.toml"
chezmoi_config "$cfg"
envsh="$(chezmoi --source "$REPO" --config "$cfg" execute-template <"$REPO/dot_config/shell/env.sh.tmpl")"
assert_contains "$envsh" "[ -d /opt/uv/bin ] && [ -f /opt/dotfiles-shared/keys/24 ]" "env.sh: 揃っているときだけ足す"
uv_line="$(printf '%s\n' "$envsh" | grep -n '_path_prepend /opt/uv/bin' | cut -d: -f1)"
# shellcheck disable=SC2016  # grep の固定文字列
local_line="$(printf '%s\n' "$envsh" | grep -n '_path_prepend "$LOCAL_PREFIX/bin"' | cut -d: -f1)"
[ -n "$uv_line" ] && [ "$uv_line" -lt "$local_line" ] || fail "env.sh: /opt/uv/bin を ~/.local/bin より先に prepend していない"
echo "PASS: env.sh: PATH では ~/.local/bin の後ろ"

# ================= run_after_35 =================
script="$tmp/run35.sh"
chezmoi --source "$REPO" --config "$cfg" execute-template <"$REPO/.chezmoiscripts/run_after_35-uv-tools.sh.tmpl" |
	sed -e "s#^SHARED_UV=/opt/uv#SHARED_UV=$tmp/shared/uv#" \
		-e "s#^SHARED_UV_KEY=.*#SHARED_UV_KEY=$tmp/shared/keys/24#" >"$script"
grep -q "^SHARED_UV=$tmp/shared" "$script" || fail "共有側のパスの差し替えに失敗"
bash -n "$script" || fail "描画したスクリプトの構文エラー"
home="$tmp/home"
stubs="$tmp/stubs"
mkdir -p "$home" "$stubs"
CALLS="$tmp/calls"
export CALLS
cat >"$stubs/uv" <<'FAKE'
#!/usr/bin/env bash
echo "uv $*" >>"$CALLS"
case " ${FAKE_FAIL:-} " in *" uv:${1:-}${2:+ $2} "*) exit 1 ;; esac
exit 0
FAKE
chmod +x "$stubs/uv"
printf '#!/usr/bin/env bash\nexit 0\n' >"$stubs/ps"
chmod +x "$stubs/ps"
run35() {
	: >"$CALLS"
	HOME="$home" XDG_DATA_HOME="" XDG_CONFIG_HOME="" XDG_CACHE_HOME="" \
		PATH="$stubs:/usr/bin:/bin" bash "$script" 2>&1
}
mkuv() {
	local d="$home/.local/share/uv" b="$home/.local/bin"
	mkdir -p "$d/python/cpython-3.13.5-x/bin" "$d/python/cpython-3.14.0-x/bin" "$d/tools/ansible/bin" "$d/tools/graphifyy/bin" "$d/tools/mytool/bin" "$b"
	: >"$d/python/cpython-3.13.5-x/bin/python3"
	: >"$d/python/cpython-3.14.0-x/bin/python3.14"
	ln -sfn cpython-3.13.5-x "$d/python/cpython-3.13-x"
	: >"$d/tools/ansible/bin/ansible"
	: >"$d/tools/graphifyy/bin/graphify"
	: >"$d/tools/mytool/bin/mytool"
	ln -sf "$d/python/cpython-3.13.5-x/bin/python3" "$b/python3"
	ln -sf "$d/python/cpython-3.14.0-x/bin/python3.14" "$b/python3.14"
	ln -sf "$d/tools/ansible/bin/ansible" "$b/ansible"
	ln -sf "$d/tools/graphifyy/bin/graphify" "$b/graphify"
	ln -sf "$d/tools/mytool/bin/mytool" "$b/mytool"
	ln -sf /usr/bin/true "$b/other"
}
mkuv

# ---- 共有側が無い: ユーザ単位に入れ、ホームのものは消さない ----
out="$(run35)" || fail "共有側なしで失敗" "$out"
c="$(cat "$CALLS")"
assert_contains "$c" "uv python install 3.13 --default" "共有側なし: Python を入れる"
assert_contains "$c" "uv tool install ansible==" "共有側なし: ansible を入れる"
assert_contains "$c" "uv tool install graphifyy[sql,terraform]==" "共有側なし: graphify も入れる"
[ -L "$home/.local/bin/ansible" ] && [ -d "$home/.local/share/uv/python" ] || fail "共有側なしなのにホームのものを消した"
[ -f "$home/.cache/dotfiles/uv-user.key" ] || fail "成功したのにマーカーを書かなかった"
out="$(run35)" || fail "2 回目が失敗"
assert_eq "" "$(cat "$CALLS")" "2 回目: 何も流さない（マーカー）"
rm -f "$home/.cache/dotfiles/uv-user.key"
out="$(FAKE_FAIL='uv:tool install' run35)" || fail "失敗しても apply は止めない" "$out"
[ ! -e "$home/.cache/dotfiles/uv-user.key" ] || fail "uv tool が失敗したのにマーカーを進めた"
rm -f "$home/.cache/dotfiles/uv-user.key"
FAKE_FAIL='uv:python install' run35 >/dev/null || fail "python 失敗でも apply は止めない"
[ ! -e "$home/.cache/dotfiles/uv-user.key" ] || fail "uv python が失敗したのにマーカーを進めた"
echo "PASS: 共有側なし: ユーザ単位に入れ、成功したときだけマーカーを進める"

# ---- 共有側が揃っている: 移したツールの symlink と実体だけ消す ----
mkdir -p "$tmp/shared/uv/bin" "$tmp/shared/keys"
echo k >"$tmp/shared/keys/24"
echo stale >"$home/.cache/dotfiles/uv-user.key"
# (a) リンクのパスだけが ps に出る（macOS 形式）→ 何も消さない
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s/.local/bin/ansible"\n' "$home" >"$stubs/ps"
run35 >/dev/null || fail "(a) 失敗"
[ -d "$home/.local/share/uv/tools/ansible" ] && [ -L "$home/.local/bin/ansible" ] || fail "(a) リンク経由で動いているのに消した"
# (b) インタプリタが comm、引数にホームのツールのスクリプト
# shellcheck disable=SC2016  # 偽 ps のソースなので展開させない
printf '#!/usr/bin/env bash\nif [ "$1" = "-axww" ]; then printf "%%s\\n" "python3 %s/.local/share/uv/tools/ansible/bin/ansible-playbook"; else echo python3; fi\n' "$home" >"$stubs/ps"
run35 >/dev/null || fail "(b) 失敗"
[ -d "$home/.local/share/uv/tools/ansible" ] || fail "(b) 引数にパスを持つプロセスが動いているのに消した"
# (b2) プロジェクトの venv のリンク（comm）が、ホームの uv の Python を指す（macOS 形式）
if [ ! -d /proc/self ]; then
	mkdir -p "$home/proj/.venv/bin"
	ln -sf "$home/.local/share/uv/python/cpython-3.13.5-x/bin/python3" "$home/proj/.venv/bin/python"
	# shellcheck disable=SC2016  # 偽 ps のソースなので展開させない
	printf '#!/usr/bin/env bash\nif [ "$1" = "-axww" ]; then echo "%s/proj/.venv/bin/python -m app"; else echo "%s/proj/.venv/bin/python"; fi\n' "$home" "$home" >"$stubs/ps"
	run35 >/dev/null || fail "(b2) 失敗"
	[ -d "$home/.local/share/uv/tools/ansible" ] && [ -d "$home/.local/share/uv/python/cpython-3.13.5-x" ] || fail "(b2) venv のリンク経由で動く Python があるのに消した"
	echo "PASS: venv のリンクで動く uv の Python は消さない"
	rm -rf "$home/proj"
fi
# (c) 動いていない
printf '#!/usr/bin/env bash\nexit 0\n' >"$stubs/ps"
out="$(run35)" || fail "(c) 失敗" "$out"
assert_eq "" "$(cat "$CALLS")" "共有側あり: uv を流さない"
d="$home/.local/share/uv"
[ ! -e "$d/tools/ansible" ] && [ ! -e "$d/tools/graphifyy" ] || fail "移したツールの実体が残った"
[ ! -e "$home/.local/bin/ansible" ] && [ ! -L "$home/.local/bin/ansible" ] && [ ! -L "$home/.local/bin/graphify" ] || fail "移したツールの symlink が残った"
[ -L "$home/.local/bin/mytool" ] && [ -d "$d/tools/mytool" ] || fail "自分で入れたツールまで消した"
[ -L "$home/.local/bin/other" ] || fail "無関係な symlink を消した"
[ -d "$d/python/cpython-3.13.5-x" ] && [ -L "$home/.local/bin/python3" ] || fail "残ったツールがあるのに Python を消した"
[ ! -e "$home/.cache/dotfiles/uv-user.key" ] || fail "共有側ありでマーカーが残った"
echo "PASS: 移したツールだけ消し、ユーザのツールと使われている Python は残す"
# 残りのツールが無くなれば Python と python3 のリンクを消す
rm -rf "$d/tools/mytool" "$home/.local/bin/mytool"
run35 >/dev/null || fail "(d) 失敗"
[ ! -e "$d/python/cpython-3.13.5-x" ] && [ ! -L "$d/python/cpython-3.13-x" ] && [ ! -L "$home/.local/bin/python3" ] || fail "ツールが無いのに既定の Python が残った"
[ -d "$d/python/cpython-3.14.0-x" ] && [ -L "$home/.local/bin/python3.14" ] || fail "既定の版でない Python（と symlink）まで消した"
[ -L "$home/.local/bin/other" ] || fail "(d) 無関係な symlink を消した"
echo "PASS: 残るツールが無ければ既定の版の Python と python3 のリンクを消す（ユーザが出した別の版は残す）"
# (d2) dot_python-version を上げる前の既定の版（python / python3 / python3.12 が指す）と、
# どのリンクからも指されない版は消す。ユーザが出した版（python3.14）は残す。
mkdir -p "$d/python/cpython-3.12.9-x/bin" "$d/python/cpython-3.11.2-x/bin"
: >"$d/python/cpython-3.12.9-x/bin/python3"
: >"$d/python/cpython-3.11.2-x/bin/python3"
ln -sfn cpython-3.12.9-x "$d/python/cpython-3.12-x"
ln -sfn cpython-3.11.2-x "$d/python/cpython-3.11-x"
for n in python python3 python3.12; do
	ln -sf "$d/python/cpython-3.12.9-x/bin/python3" "$home/.local/bin/$n"
done
run35 >/dev/null || fail "(d2) 失敗"
[ ! -e "$d/python/cpython-3.12.9-x" ] && [ ! -L "$d/python/cpython-3.12-x" ] || fail "(d2) python3 が指す前の既定の版が残った"
for n in python python3 python3.12; do
	[ ! -L "$home/.local/bin/$n" ] || fail "(d2) 前の既定の版を指す $n のリンクが残った"
done
[ ! -e "$d/python/cpython-3.11.2-x" ] && [ ! -L "$d/python/cpython-3.11-x" ] || fail "(d2) どのリンクからも指されない版が残った"
[ -d "$d/python/cpython-3.14.0-x" ] && [ -L "$home/.local/bin/python3.14" ] || fail "(d2) ユーザが出した版まで消した"
[ -L "$home/.local/bin/other" ] || fail "(d2) 無関係な symlink を消した"
echo "PASS: 前の既定の版とリンクの無い版は消し、ユーザが出した版は残す"
# (d3) ホームにツールが残っている間は、別の版の Python にも触らない
mkdir -p "$d/tools/mytool/bin" "$d/python/cpython-3.11.2-x/bin"
run35 >/dev/null || fail "(d3) 失敗"
[ -d "$d/python/cpython-3.11.2-x" ] || fail "(d3) ツールが残っているのに別の版を消した"
rm -rf "$d/tools/mytool"
# 共有側のキーだけ無ければ揃っていない扱い
rm "$tmp/shared/keys/24"
rm -rf "$d"
mkuv
run35 >/dev/null || fail "(e) 失敗"
[ -d "$d/tools/ansible" ] || fail "キーが無いのにホームを消した"
echo "PASS: キーが無ければ揃っていない扱い（消さない）"

echo "ALL PASS"
