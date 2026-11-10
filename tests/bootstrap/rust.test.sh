#!/usr/bin/env bash
# bootstrap/25-shared-rust.sh と run_after_32-rust-default.sh.tmpl（.chezmoitemplates/rust-cleanup.sh）のテスト。
# /opt は触らず SHARED_ROOT / HOME を一時ディレクトリへ向ける。aqua / rustup-init / rustup / ps は偽物に差し替える。
set -eu
# shellcheck source-path=SCRIPTDIR source=../lib.sh
. "$(dirname "$0")/../lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export SHARED_ROOT="$tmp/opt" BOOTSTRAP_ALLOW_NONROOT=1
export DOTFILES_SRC="$tmp/src"
unset GITHUB_TOKEN DOTFILES_SHARED_FORCE DOTFILES_STATE_COMMIT FAKE_RUSTUP_FAIL FAKE_RUSTUP_NOCOMP
mkdir -p "$tmp/src/bootstrap" "$tmp/src/dot_config/aquaproj-aqua"
cp "$REPO/bootstrap/lib.sh" "$tmp/src/bootstrap/"
fake_shared_aqua_step "$tmp/src/bootstrap"
cp "$REPO/dot_config/aquaproj-aqua/aqua.yaml" "$tmp/src/dot_config/aquaproj-aqua/"
STEP="$tmp/src/bootstrap/25-shared-rust.sh"
keyfile="$SHARED_ROOT/dotfiles-shared/keys/25"
RH="$SHARED_ROOT/rustup"
CH="$SHARED_ROOT/cargo"

# ---- 偽の rustup-init / rustup / aqua ----
fakebin="$tmp/fakerust"
mkdir -p "$fakebin"
cat >"$fakebin/rustup" <<'FAKE'
#!/usr/bin/env bash
# 1 つのスクリプトを rustup と、そのハードリンクのプロキシ（cargo / rustc など）の両方に使う。
name="$(basename "$0")"
if [ "$name" != rustup ]; then
	echo "${name} ${RUSTUP_TOOLCHAIN:-none}"
	exit 0
fi
echo "rustup $* | cwd=$PWD RUSTUP_HOME=${RUSTUP_HOME:-} CARGO_HOME=${CARGO_HOME:-}" >>"$FAKE_LOG"
case "${1:-} ${2:-}" in
"set auto-self-update") ;;
"toolchain install")
	[ "${FAKE_RUSTUP_FAIL:-}" = 1 ] && exit 1
	tc="$3-fake-host"
	mkdir -p "$RUSTUP_HOME/toolchains/$tc/bin"
	for b in rustc cargo rustfmt cargo-clippy clippy-driver; do
		[ "$b" = clippy-driver ] && [ "${FAKE_RUSTUP_NOCOMP:-}" = 1 ] && continue
		printf '#!/bin/sh\necho "%s %s"\n' "$b" "$3" >"$RUSTUP_HOME/toolchains/$tc/bin/$b"
		chmod +x "$RUSTUP_HOME/toolchains/$tc/bin/$b"
	done
	;;
"toolchain uninstall") rm -rf "$RUSTUP_HOME/toolchains/$3" ;;
"toolchain list") ls "$RUSTUP_HOME/toolchains" 2>/dev/null || true ;;
"default "*) printf 'default_toolchain = "%s-fake-host"\n' "$2" >"$RUSTUP_HOME/settings.toml" ;;
esac
exit 0
FAKE
chmod +x "$fakebin/rustup"
cat >"$fakebin/rustup-init" <<'FAKE'
#!/usr/bin/env bash
echo "rustup-init $* | cwd=$PWD RUSTUP_HOME=${RUSTUP_HOME:-} CARGO_HOME=${CARGO_HOME:-} SKIP=${RUSTUP_INIT_SKIP_PATH_CHECK:-}" >>"$FAKE_LOG"
mkdir -p "$CARGO_HOME/bin" "$RUSTUP_HOME"
rm -f "$CARGO_HOME/bin/rustup"
cp "$(dirname "$0")/rustup" "$CARGO_HOME/bin/rustup"
for n in cargo rustc rustdoc rustfmt cargo-clippy clippy-driver; do
	rm -f "$CARGO_HOME/bin/$n"
	ln "$CARGO_HOME/bin/rustup" "$CARGO_HOME/bin/$n"
done
exit 0
FAKE
chmod +x "$fakebin/rustup-init"
fakeaqua="$tmp/fake-aqua"
cat >"$fakeaqua" <<FAKE
#!/usr/bin/env bash
echo "aqua \$* ROOT=\${AQUA_ROOT_DIR:-} GLOBAL=\${AQUA_GLOBAL_CONFIG:-}" >>"\$FAKE_LOG"
[ "\$1" = which ] || exit 2
case "\$2" in
rustup-init) echo "$fakebin/rustup-init" ;;
*) exit 1 ;;
esac
FAKE
chmod +x "$fakeaqua"
export FAKE_LOG="$tmp/log"
: >"$FAKE_LOG"

# ---- 共有 aqua が揃っていない ----
cp "$REPO/bootstrap/25-shared-rust.sh" "$STEP" 2>/dev/null || fail "bootstrap/25-shared-rust.sh が無い"
rc=0
out="$(AQUA_BIN="$fakeaqua" bash "$STEP" 2>&1)" || rc=$?
[ "$rc" -ne 0 ] || fail "共有 aqua が無いのに成功した"
assert_contains "$out" "共有 aqua" "共有 aqua が無ければメッセージを出して失敗する"
[ ! -e "$RH" ] && [ ! -e "$keyfile" ] || fail "共有 aqua が無いのに何かを作った"
mkdir -p "$SHARED_ROOT/aquaproj-aqua/config" "$SHARED_ROOT/dotfiles-shared/keys"
: >"$SHARED_ROOT/aquaproj-aqua/config/aqua.yaml"
: >"$SHARED_ROOT/aquaproj-aqua/config/aqua-policy.yaml"
echo k20 >"$SHARED_ROOT/dotfiles-shared/keys/20"
assert_stale_shared_aqua_skips "$STEP" "$SHARED_ROOT/dotfiles-shared/keys/20" "$RH" "$keyfile"
rc=0
out="$(env -u AQUA_BIN bash "$STEP" 2>&1)" || rc=$?
[ "$rc" -ne 0 ] || fail "AQUA_BIN 空で成功した"
assert_contains "$out" "AQUA_BIN" "AQUA_BIN が空ならメッセージを出して失敗する"

# ---- --check ----
rc=0
bash "$STEP" --check || rc=$?
assert_eq "1" "$rc" "--check: キーが無ければ 1"

run() { AQUA_BIN="$fakeaqua" bash "$STEP" 2>&1; }
default_tc() { sed -n 's/^default_toolchain = "\(.*\)"$/\1/p' "$RH/settings.toml"; }
ver="$(sed -n 's/^RUST_VERSION="\(.*\)"$/\1/p' "$STEP")"
[ -n "$ver" ] || fail "RUST_VERSION の行が読めない"

# 前回までに誰でも書ける権限で残ったファイル（展開したアーカイブなど）
mkdir -p "$RH/stray" "$CH/bin"
: >"$RH/stray/f"
: >"$CH/bin/stray"
chmod 777 "$RH/stray" "$RH/stray/f" "$CH/bin/stray"
out="$(run)" || fail "通常の実行が失敗" "$out"
assert_no_group_other_write "rust" "$RH/stray" "$RH/stray/f" "$CH/bin/stray"
rm -rf "$RH/stray" "$CH/bin/stray"
k1="$(cat "$keyfile")"
assert_eq "$ver-fake-host" "$(default_tc)" "RUST_VERSION の toolchain が既定になる"
[ -x "$CH/bin/cargo" ] && [ -x "$CH/bin/rustup" ] || fail "$CH/bin にプロキシが無い"
rc=0
bash "$STEP" --check || rc=$?
assert_eq "0" "$rc" "--check: 実行後は 0"

l="$(cat "$FAKE_LOG")"
assert_contains "$l" "aqua which rustup-init ROOT=$SHARED_ROOT/aquaproj-aqua GLOBAL=$SHARED_ROOT/aquaproj-aqua/config/aqua.yaml" "共有 aqua の設定で rustup-init を解決する"
assert_contains "$l" "rustup-init -y --no-modify-path --profile minimal --default-toolchain none" "rustup-init は toolchain を入れずに rustup だけ入れる"
assert_contains "$l" "RUSTUP_HOME=$RH CARGO_HOME=$CH SKIP=yes" "RUSTUP_HOME / CARGO_HOME は共有側"
assert_contains "$l" "rustup toolchain install $ver --profile minimal --no-self-update -c clippy -c rustfmt -c rust-docs" "minimal に現行のコンポーネントを足す"
assert_contains "$l" "cwd=/ " "ルートへ移ってから流す"
assert_contains "$l" "rustup set auto-self-update disable" "rustup 本体の自己更新を止める"
echo "PASS: 導入のコマンド"

# キーは RUST_VERSION とコンポーネントから決まる
cp "$STEP" "$tmp/step.orig"
sed -i.bak 's|^RUST_VERSION=".*"|RUST_VERSION="0.0.1"|' "$STEP" && rm "$STEP.bak"
rc=0
bash "$STEP" --check || rc=$?
assert_eq "1" "$rc" "--check: RUST_VERSION を変えれば 1"
cp "$tmp/step.orig" "$STEP"

# ---- 失敗しても既定の toolchain と組は壊れない ----
sed -i.bak 's|^RUST_VERSION=".*"|RUST_VERSION="2.0.0"|' "$STEP" && rm "$STEP.bak"
rc=0
out="$(FAKE_RUSTUP_FAIL=1 run)" || rc=$?
[ "$rc" -ne 0 ] || fail "toolchain の導入が失敗したのに成功した"
assert_eq "$ver-fake-host" "$(default_tc)" "導入失敗: 前の既定 toolchain のまま"
assert_eq "$k1" "$(cat "$keyfile")" "導入失敗: キーは変わらない"
[ ! -e "$RH/toolchains/2.0.0-fake-host" ] || fail "導入失敗: 中途半端な toolchain が残った"
rc=0
out="$(FAKE_RUSTUP_NOCOMP=1 run)" || rc=$?
[ "$rc" -ne 0 ] || fail "コンポーネントが欠けているのに成功した"
assert_contains "$out" "clippy-driver" "欠けたコンポーネントを名指しする"
assert_eq "$ver-fake-host" "$(default_tc)" "コンポーネント欠落: 前の既定 toolchain のまま"
assert_eq "$k1" "$(cat "$keyfile")" "コンポーネント欠落: キーは変わらない"
[ ! -e "$RH/toolchains/2.0.0-fake-host" ] || fail "コンポーネント欠落: 新しい toolchain を消していない"
echo "PASS: 失敗しても前の既定 toolchain とキーは変わらず、非 0"

# ---- 版を上げる: 1 つ前を残し、それ以前を消す ----
out="$(run)" || fail "版を上げた実行が失敗" "$out"
assert_eq "2.0.0-fake-host" "$(default_tc)" "版を上げると既定が変わる"
[ -d "$RH/toolchains/$ver-fake-host" ] || fail "1 つ前の toolchain を消した"
sed -i.bak 's|^RUST_VERSION=".*"|RUST_VERSION="3.0.0"|' "$STEP" && rm "$STEP.bak"
run >/dev/null || fail "3.0.0 の実行が失敗"
[ ! -e "$RH/toolchains/$ver-fake-host" ] || fail "2 つ前の toolchain が残った"
[ -d "$RH/toolchains/2.0.0-fake-host" ] && [ -d "$RH/toolchains/3.0.0-fake-host" ] || fail "1 つ前か現行が無い"
# 同じ版の再実行でも、1 つ前を残す
run >/dev/null || fail "同じ版の再実行が失敗"
[ -d "$RH/toolchains/2.0.0-fake-host" ] || fail "同じ版の再実行で 1 つ前を消した"
echo "PASS: 1 つ前の toolchain を残し、それ以前を消す"

# ---- 動いている toolchain は消さない ----
# Linux は /proc を見るため ps の偽物は効かない。macOS 形式のときだけ検証する。
if [ ! -d /proc/self ]; then
	mkdir -p "$tmp/psbin"
	psout() {
		printf '#!/usr/bin/env bash\nif [ "$*" = "-axww -o args=" ]; then printf "%%s\\n" "%s"; else printf "%%s\\n" "%s"; fi\n' "${2:-/usr/bin/other}" "$1" >"$tmp/psbin/ps"
		chmod +x "$tmp/psbin/ps"
	}
	runps() { PATH="$tmp/psbin:$PATH" AQUA_BIN="$fakeaqua" bash "$STEP" 2>&1; }
	sed -i.bak 's|^RUST_VERSION=".*"|RUST_VERSION="4.0.0"|' "$STEP" && rm "$STEP.bak"
	# (a) 2.0.0 の実体が動いている
	psout "$RH/toolchains/2.0.0-fake-host/bin/rustc"
	runps >/dev/null || fail "(a) 実行が失敗"
	[ -d "$RH/toolchains/2.0.0-fake-host" ] || fail "(a) 動いている toolchain を消した"
	# (b) 共有のプロキシのパスが ps に出る（macOS）→ GC を見送る
	psout "$CH/bin/rustc"
	sed -i.bak 's|^RUST_VERSION=".*"|RUST_VERSION="5.0.0"|' "$STEP" && rm "$STEP.bak"
	runps >/dev/null || fail "(b) 実行が失敗"
	[ -d "$RH/toolchains/3.0.0-fake-host" ] || fail "(b) プロキシが動いているのに古い toolchain を消した"
	# (c) 何も動いていなければ消える
	psout "/usr/bin/other"
	sed -i.bak 's|^RUST_VERSION=".*"|RUST_VERSION="6.0.0"|' "$STEP" && rm "$STEP.bak"
	runps >/dev/null || fail "(c) 実行が失敗"
	[ ! -e "$RH/toolchains/2.0.0-fake-host" ] && [ ! -e "$RH/toolchains/3.0.0-fake-host" ] || fail "(c) 止まったのに古い toolchain が残った"
	echo "PASS: macOS 形式の ps でも動いている toolchain は消さない"
	# (d) 消す候補が無ければ、プロキシが動いていても次回へ回す印を置かない
	rm -f "$SHARED_ROOT/dotfiles-shared/pending/25"
	psout "$CH/bin/rustc"
	runps >/dev/null || fail "(d) 実行が失敗"
	[ ! -e "$SHARED_ROOT/dotfiles-shared/pending/25" ] || fail "(d) 消す候補が無いのに pending/25 を置いた"
	# 候補があってプロキシが動いていれば置く
	mkdir -p "$RH/toolchains/0.1.0-fake-host"
	runps >/dev/null || fail "(d) 候補ありの実行が失敗"
	[ -e "$SHARED_ROOT/dotfiles-shared/pending/25" ] || fail "(d) 候補があってプロキシが動いているのに pending/25 を置かない"
	[ -d "$RH/toolchains/0.1.0-fake-host" ] || fail "(d) プロキシが動いているのに消した"
	rm -f "$SHARED_ROOT/dotfiles-shared/pending/25"
	echo "PASS: 消す候補があるときだけ次回へ回す印を置く"
fi
cp "$tmp/step.orig" "$STEP"

# ---- env.sh: 揃っているときだけ RUSTUP_HOME と /opt/cargo/bin ----
cfg="$tmp/chezmoi.toml"
chezmoi_config "$cfg"
envsh="$(chezmoi --source "$REPO" --config "$cfg" execute-template <"$REPO/dot_config/shell/env.sh.tmpl")"
assert_contains "$envsh" "/opt/dotfiles-shared/keys/25" "env.sh: 揃い判定に keys/25 を見る"
assert_contains "$envsh" 'RUSTUP_HOME=/opt/rustup' "env.sh: 揃っていれば RUSTUP_HOME=/opt/rustup"
assert_contains "$envsh" '_path_prepend /opt/cargo/bin' "env.sh: /opt/cargo/bin を足す"
# shellcheck disable=SC2016  # grep の固定文字列
shared_line="$(printf '%s\n' "$envsh" | grep -n '_path_prepend /opt/cargo/bin' | cut -d: -f1)"
# shellcheck disable=SC2016
user_line="$(printf '%s\n' "$envsh" | grep -n '_path_prepend "$CARGO_HOME/bin"' | cut -d: -f1)"
[ -n "$shared_line" ] && [ -n "$user_line" ] && [ "$shared_line" -lt "$user_line" ] || fail "env.sh: PATH では \$CARGO_HOME/bin が /opt/cargo/bin より先でない"
echo "PASS: env.sh: PATH では \$CARGO_HOME/bin の後ろに /opt/cargo/bin"
# 実際に env.sh を評価して、揃っていないときは RUSTUP_HOME がホームのままであること
envtest() {
	# 揃い判定のパスを一時ディレクトリへ差し替えて評価する。
	printf '%s\n' "$envsh" | sed -e "s#/opt/dotfiles-shared/keys/25#$tmp/shared/keys/25#g" -e "s#/opt/cargo/bin#$tmp/shared/cargo/bin#g" -e "s#/opt/rustup#$tmp/shared/rustup#g" >"$tmp/env.eval.sh"
	# shellcheck disable=SC2016  # bash -c の中で展開させる
	env -i HOME="$tmp/envhome" PATH=/usr/bin:/bin bash -c '. "$1"; printf "%s|%s|%s\n" "$RUSTUP_HOME" "$CARGO_HOME" "$PATH"' _ "$tmp/env.eval.sh"
}
mkdir -p "$tmp/envhome/.local/share/cargo/bin"
r="$(envtest)"
case "$r" in "$tmp/envhome/.local/share/rustup|"*) echo "PASS: 揃っていなければ RUSTUP_HOME はホーム" ;; *) fail "揃っていないのに RUSTUP_HOME が変わった" "$r" ;; esac
mkdir -p "$tmp/shared/keys" "$tmp/shared/cargo/bin" "$tmp/shared/rustup/toolchains/x"
: >"$tmp/shared/cargo/bin/cargo"
chmod +x "$tmp/shared/cargo/bin/cargo"
r="$(envtest)"
case "$r" in "$tmp/envhome/.local/share/rustup|"*) ;; *) fail "キーが無いのに RUSTUP_HOME が変わった" "$r" ;; esac
echo k >"$tmp/shared/keys/25"
r="$(envtest)"
case "$r" in "$tmp/shared/rustup|"*) ;; *) fail "揃っているのに RUSTUP_HOME が共有側でない" "$r" ;; esac
path="${r#*|*|}"
case "$path" in *"$tmp/envhome/.local/share/cargo/bin:"*"$tmp/shared/cargo/bin"*) echo "PASS: 揃っていれば共有の RUSTUP_HOME と PATH（CARGO_HOME が先）" ;; *) fail "PATH の順序が違う" "$path" ;; esac
rm -rf "$tmp/shared"

# ================= run_after_32 =================
script="$tmp/run32.sh"
chezmoi --source "$REPO" --config "$cfg" execute-template <"$REPO/.chezmoiscripts/run_after_32-rust-default.sh.tmpl" |
	sed -e "s#^SHARED_RUSTUP=/opt/rustup#SHARED_RUSTUP=$tmp/shared/rustup#" \
		-e "s#^SHARED_CARGO_BIN=/opt/cargo/bin#SHARED_CARGO_BIN=$tmp/shared/cargo/bin#" \
		-e "s#^SHARED_RUST_KEY=.*#SHARED_RUST_KEY=$tmp/shared/keys/25#" >"$script"
grep -q "^SHARED_RUSTUP=$tmp/shared" "$script" || fail "共有側のパスの差し替えに失敗"
grep -q "^SHARED_RUST_KEY=$tmp/shared" "$script" || fail "キーのパスの差し替えに失敗"
bash -n "$script" || fail "描画したスクリプトの構文エラー"
home="$tmp/home"
stubs="$tmp/stubs"
mkdir -p "$home" "$stubs"
CALLS="$tmp/calls"
export CALLS
cat >"$stubs/rustup-init" <<'FAKE'
#!/usr/bin/env bash
echo "rustup-init $*" >>"$CALLS"
case " ${FAKE_FAIL:-} " in *" rustup-init "*) exit 1 ;; esac
exit 0
FAKE
cat >"$stubs/rustup" <<'FAKE'
#!/usr/bin/env bash
echo "rustup $*" >>"$CALLS"
case " ${FAKE_FAIL:-} " in *" rustup:${1:-} "*) exit 1 ;; esac
exit 0
FAKE
chmod +x "$stubs/rustup-init" "$stubs/rustup"
printf '#!/usr/bin/env bash\nexit 0\n' >"$stubs/ps"
chmod +x "$stubs/ps"
run32() {
	: >"$CALLS"
	HOME="$home" XDG_DATA_HOME="" XDG_CONFIG_HOME="" XDG_CACHE_HOME="" \
		PATH="$stubs:/usr/bin:/bin" bash "$script" 2>&1
}
CB="$home/.local/share/cargo/bin"
OLDRH="$home/.local/share/rustup"
mkhome() {
	rm -rf "$home/.local"
	mkdir -p "$CB" "$OLDRH/toolchains/stable-x/bin"
	: >"$CB/rustup"
	for n in cargo rustc rustfmt cargo-clippy rust-analyzer; do ln "$CB/rustup" "$CB/$n"; done
	# cargo install したもの（別のファイル）
	printf 'x' >"$CB/cargo-foo"
	printf 'y' >"$CB/sheldon"
}
mkhome

# ---- 共有側が無い: ユーザ単位に入れ、ホームのものは消さない ----
rm -rf "$CB" # 初回は cargo も無い
mkdir -p "$CB"
out="$(run32)" || fail "共有側なしで失敗" "$out"
c="$(cat "$CALLS")"
assert_contains "$c" "rustup-init -y --no-modify-path --default-toolchain $ver" "共有側なし: 固定の版で rustup-init"
assert_contains "$c" "rustup default $ver" "共有側なし: 既定を固定の版にする"
[ -f "$home/.cache/dotfiles/rust-user.key" ] || fail "成功したのにマーカーを書かなかった"
out="$(run32)" || fail "2 回目が失敗"
assert_eq "" "$(cat "$CALLS")" "2 回目: 何も流さない（マーカー）"
rm -f "$home/.cache/dotfiles/rust-user.key"
out="$(FAKE_FAIL='rustup-init' run32)" || fail "失敗しても apply は止めない" "$out"
[ ! -e "$home/.cache/dotfiles/rust-user.key" ] || fail "rustup-init が失敗したのにマーカーを進めた"
# cargo があるときは toolchain install で更新
: >"$CB/cargo"
chmod +x "$CB/cargo"
out="$(FAKE_FAIL='rustup:default' run32)" || fail "default 失敗でも apply は止めない" "$out"
[ ! -e "$home/.cache/dotfiles/rust-user.key" ] || fail "rustup default が失敗したのにマーカーを進めた"
assert_contains "$(cat "$CALLS")" "rustup toolchain install $ver" "cargo 済みなら toolchain install"
echo "PASS: 共有側なし: ユーザ単位に入れ、成功したときだけマーカーを進める"

# ---- 共有側が揃っている: プロキシと ~/.local/share/rustup だけ消す ----
mkhome
mkdir -p "$tmp/shared/rustup/toolchains/1-x" "$tmp/shared/cargo/bin" "$tmp/shared/keys"
: >"$tmp/shared/cargo/bin/cargo"
chmod +x "$tmp/shared/cargo/bin/cargo"
# キーだけ無ければ揃っていない扱い（消さない）
run32 >/dev/null || fail "(キー無し) 失敗"
[ -e "$CB/rustup" ] && [ -d "$OLDRH" ] || fail "キーが無いのにホームを消した"
echo k >"$tmp/shared/keys/25"
mkdir -p "$home/.cache/dotfiles"
echo stale >"$home/.cache/dotfiles/rust-user.key"
# running_as <path>: <path> から動くプロセスがあるように見せる。macOS は偽の ps にそのパスを出させ、
# Linux（/proc を見る）は sleep の実体を <path> に書いて実際に起動する。止めるのは stop_running。
running_pid=""
running_as() {
	if [ -d /proc/self ]; then
		cat "$(command -v sleep)" >"$1"
		chmod +x "$1"
		"$1" 300 &
		running_pid=$!
	else
		printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s"\n' "$1" >"$stubs/ps"
	fi
}
stop_running() {
	if [ -n "$running_pid" ]; then
		kill "$running_pid" 2>/dev/null || true
		wait "$running_pid" 2>/dev/null || true
		running_pid=""
	fi
	printf '#!/usr/bin/env bash\nexit 0\n' >"$stubs/ps"
}
# (a) ホームのプロキシ経由で動いている（macOS の ps はプロキシのパスを出す）
running_as "$CB/rust-analyzer"
run32 >/dev/null || fail "(a) 失敗"
stop_running
[ -d "$OLDRH" ] && [ -e "$CB/rustup" ] || fail "(a) プロキシ経由で動いているのに消した"
# (b) ホームの toolchain の実体が動いている
running_as "$OLDRH/toolchains/stable-x/bin/rustc"
run32 >/dev/null || fail "(b) 失敗"
stop_running
[ -d "$OLDRH" ] && [ -e "$CB/rustup" ] || fail "(b) toolchain が動いているのに消した"
# (c) 引数にホームの toolchain のパス（rust-analyzer などが読んでいる）
# shellcheck disable=SC2016  # 偽 ps のソースなので展開させない
printf '#!/usr/bin/env bash\nif [ "$1" = "-axww" ]; then printf "%%s\\n" "tool --sysroot %s/toolchains/stable-x"; else echo tool; fi\n' "$OLDRH" >"$stubs/ps"
run32 >/dev/null || fail "(c) 失敗"
[ -d "$OLDRH" ] || fail "(c) 引数にパスを持つプロセスが動いているのに消した"
echo "PASS: 動いているホームの Rust（プロキシ・実体・引数）があれば消さない"
# (d) 動いていない
printf '#!/usr/bin/env bash\nexit 0\n' >"$stubs/ps"
out="$(run32)" || fail "(d) 失敗" "$out"
assert_eq "" "$(cat "$CALLS")" "共有側あり: rustup を流さない"
[ ! -e "$CB/rustup" ] && [ ! -e "$CB/cargo" ] && [ ! -e "$CB/rustc" ] && [ ! -e "$CB/rust-analyzer" ] || fail "rustup のハードリンクが残った"
[ -f "$CB/cargo-foo" ] && [ -f "$CB/sheldon" ] || fail "cargo install したものまで消した"
[ ! -e "$OLDRH" ] || fail "ホームの rustup が残った"
[ ! -e "$home/.cache/dotfiles/rust-user.key" ] || fail "共有側ありでマーカーが残った"
echo "PASS: rustup と同じ inode のものだけ消し、cargo install したものは残す"
# 名前が同じでも別のファイルなら消さない（cargo が rustup のリンクでない）
mkhome
rm "$CB/cargo"
printf 'real cargo' >"$CB/cargo"
run32 >/dev/null || fail "(e) 失敗"
[ -f "$CB/cargo" ] && [ ! -e "$CB/rustup" ] || fail "inode が違う cargo を消したか、rustup が残った"
echo "PASS: 名前ではなく inode で判定する"

# cargo install したものが動いていても、掃除は止まらない
mkhome
running_as "$CB/cargo-foo"
run32 >/dev/null || fail "(f) 失敗"
stop_running
[ ! -e "$CB/rustup" ] && [ -f "$CB/cargo-foo" ] || fail "cargo install したものが動いているだけで掃除が止まった"
echo "PASS: cargo install したものが動いていても掃除は止まらない"

echo "ALL PASS"
