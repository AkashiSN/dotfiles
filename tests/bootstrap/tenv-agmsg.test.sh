#!/usr/bin/env bash
# bootstrap/21-shared-tenv.sh / 22-shared-agmsg.sh と、ユーザ側（run_after_21 / run_after_40）のテスト。
# /opt は触らず SHARED_ROOT / HOME を一時ディレクトリへ向ける。aqua / tenv / git / ps は偽物に差し替える。
set -eu
# shellcheck source-path=SCRIPTDIR source=../lib.sh
. "$(dirname "$0")/../lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export SHARED_ROOT="$tmp/opt" BOOTSTRAP_ALLOW_NONROOT=1
export DOTFILES_SRC="$tmp/src"
unset GITHUB_TOKEN DOTFILES_SHARED_FORCE DOTFILES_STATE_COMMIT FAKE_TENV_FAIL FAKE_TENV_NOBIN FAKE_GIT_COMMIT
mkdir -p "$tmp/src/bootstrap"
cp "$REPO/bootstrap/lib.sh" "$tmp/src/bootstrap/"
export FAKE_LOG="$tmp/log"
: >"$FAKE_LOG"
keys="$SHARED_ROOT/dotfiles-shared/keys"

# ================= 21-shared-tenv =================
TSTEP="$tmp/src/bootstrap/21-shared-tenv.sh"
VFILE="$tmp/src/bootstrap/tenv-versions.txt"
cp "$REPO/bootstrap/21-shared-tenv.sh" "$TSTEP" 2>/dev/null || fail "bootstrap/21-shared-tenv.sh が無い"
[ -f "$REPO/bootstrap/tenv-versions.txt" ] || fail "bootstrap/tenv-versions.txt が無い"
printf '# comment\n1.0.0\n2.0.0 # trailing\n\n' >"$VFILE"
TROOT="$SHARED_ROOT/tenv"

fakebin="$tmp/faketenv"
mkdir -p "$fakebin"
cat >"$fakebin/tenv" <<'FAKE'
#!/usr/bin/env bash
echo "tenv $* | cwd=$PWD TENV_ROOT=${TENV_ROOT:-} VALIDATION=${TENV_VALIDATION:-}" >>"$FAKE_LOG"
[ "$1 $2" = "terraform install" ] || exit 2
[ "${FAKE_TENV_FAIL:-}" = "$3" ] && exit 1
mkdir -p "$TENV_ROOT/Terraform/$3"
[ "${FAKE_TENV_NOBIN:-}" = "$3" ] && exit 0
printf '#!/bin/sh\necho Terraform v%s\n' "$3" >"$TENV_ROOT/Terraform/$3/terraform"
chmod +x "$TENV_ROOT/Terraform/$3/terraform"
FAKE
chmod +x "$fakebin/tenv"
fakeaqua="$tmp/fake-aqua"
cat >"$fakeaqua" <<FAKE
#!/usr/bin/env bash
echo "aqua \$* ROOT=\${AQUA_ROOT_DIR:-} GLOBAL=\${AQUA_GLOBAL_CONFIG:-}" >>"\$FAKE_LOG"
[ "\$1" = which ] || exit 2
case "\$2" in tenv) echo "$fakebin/tenv" ;; *) exit 1 ;; esac
FAKE
chmod +x "$fakeaqua"

# 共有 aqua が揃っていない
rc=0
out="$(AQUA_BIN="$fakeaqua" bash "$TSTEP" 2>&1)" || rc=$?
[ "$rc" -ne 0 ] || fail "共有 aqua が無いのに成功した"
assert_contains "$out" "共有 aqua" "tenv: 共有 aqua が無ければメッセージを出して失敗する"
[ ! -e "$TROOT" ] && [ ! -e "$keys/21" ] || fail "tenv: 共有 aqua が無いのに何かを作った"
mkdir -p "$SHARED_ROOT/aquaproj-aqua/config" "$keys"
: >"$SHARED_ROOT/aquaproj-aqua/config/aqua.yaml"
: >"$SHARED_ROOT/aquaproj-aqua/config/aqua-policy.yaml"
echo k20 >"$keys/20"
rc=0
out="$(env -u AQUA_BIN bash "$TSTEP" 2>&1)" || rc=$?
[ "$rc" -ne 0 ] || fail "tenv: AQUA_BIN 空で成功した"
assert_contains "$out" "AQUA_BIN" "tenv: AQUA_BIN が空ならメッセージを出して失敗する"

rc=0
bash "$TSTEP" --check || rc=$?
assert_eq "1" "$rc" "tenv --check: キーが無ければ 1"

trun() { AQUA_BIN="$fakeaqua" bash "$TSTEP" 2>&1; }
out="$(trun)" || fail "tenv の通常の実行が失敗" "$out"
[ -x "$TROOT/Terraform/1.0.0/terraform" ] && [ -x "$TROOT/Terraform/2.0.0/terraform" ] || fail "tenv: 版が入っていない"
l="$(cat "$FAKE_LOG")"
assert_contains "$l" "tenv terraform install 1.0.0 | cwd=/ TENV_ROOT=$TROOT VALIDATION=sha" "tenv: ルートへ移り、共有の TENV_ROOT・sha 検証で入れる"
assert_contains "$l" "aqua which tenv ROOT=$SHARED_ROOT/aquaproj-aqua GLOBAL=$SHARED_ROOT/aquaproj-aqua/config/aqua.yaml" "tenv: 共有 aqua の設定で tenv を解決する"
assert_not_contains "$l" "install #" "tenv: コメントを版として扱わない"
k21="$(cat "$keys/21")"
rc=0
bash "$TSTEP" --check || rc=$?
assert_eq "0" "$rc" "tenv --check: 実行後は 0"
printf '1.0.0\n' >"$VFILE"
rc=0
bash "$TSTEP" --check || rc=$?
assert_eq "1" "$rc" "tenv --check: 版の一覧を変えれば 1"
printf '1.0.0\n2.0.0\n' >"$VFILE"
bash "$TSTEP" --check || fail "tenv: 同じ一覧に戻したのに 1"

# 失敗: 前の版とキーは壊れない。新しい版の中途半端な dir は残らない
printf '1.0.0\n3.0.0\n' >"$VFILE"
rc=0
out="$(FAKE_TENV_FAIL=3.0.0 trun)" || rc=$?
[ "$rc" -ne 0 ] || fail "tenv の導入が失敗したのに成功した"
assert_eq "$k21" "$(cat "$keys/21")" "tenv 失敗: キーは変わらない"
[ -x "$TROOT/Terraform/2.0.0/terraform" ] && [ -x "$TROOT/Terraform/1.0.0/terraform" ] || fail "tenv 失敗: 前の版を消した"
rc=0
out="$(FAKE_TENV_NOBIN=3.0.0 trun)" || rc=$?
[ "$rc" -ne 0 ] || fail "実行ファイルが無いのに成功した"
assert_contains "$out" "3.0.0" "tenv: 実行ファイルが無い版を名指しする"
assert_eq "$k21" "$(cat "$keys/21")" "tenv 実行ファイル欠落: キーは変わらない"
[ ! -e "$TROOT/Terraform/3.0.0" ] || fail "tenv 失敗: 中途半端な版が残った"
[ -x "$TROOT/Terraform/2.0.0/terraform" ] || fail "tenv 失敗: 一覧から外れた版を、成功前に消した"
echo "PASS: tenv: 失敗しても前の版とキーは変わらず、非 0"

# 成功: 一覧に無い 2.0.0 を消す
out="$(trun)" || fail "tenv: 3.0.0 の実行が失敗" "$out"
[ -x "$TROOT/Terraform/3.0.0/terraform" ] && [ ! -e "$TROOT/Terraform/2.0.0" ] || fail "tenv: 一覧に無い版を消していない"
echo "PASS: tenv: 一覧に無い版を消す"

# 動いている版は消さない（macOS 形式の ps のときだけ）
if [ ! -d /proc/self ]; then
	mkdir -p "$tmp/psbin"
	cat >"$tmp/psbin/ps" <<FAKE
#!/usr/bin/env bash
printf '%s\n' "$TROOT/Terraform/1.0.0/terraform"
FAKE
	chmod +x "$tmp/psbin/ps"
	printf '3.0.0\n' >"$VFILE"
	PATH="$tmp/psbin:$PATH" AQUA_BIN="$fakeaqua" bash "$TSTEP" >/dev/null 2>&1 || fail "busy: 実行が失敗"
	[ -d "$TROOT/Terraform/1.0.0" ] || fail "動いている版を消した"
	printf '#!/usr/bin/env bash\nexit 0\n' >"$tmp/psbin/ps"
	PATH="$tmp/psbin:$PATH" AQUA_BIN="$fakeaqua" bash "$TSTEP" >/dev/null 2>&1 || fail "idle: 実行が失敗"
	[ ! -e "$TROOT/Terraform/1.0.0" ] || fail "止まった版が残った"
	echo "PASS: tenv: 動いている版は消さず、止まれば消す"
fi

# ================= 22-shared-agmsg =================
ASTEP="$tmp/src/bootstrap/22-shared-agmsg.sh"
cp "$REPO/bootstrap/22-shared-agmsg.sh" "$ASTEP" 2>/dev/null || fail "bootstrap/22-shared-agmsg.sh が無い"
ROOT="$SHARED_ROOT/agmsg"
ver="$(sed -n 's/^AGMSG_VERSION="\(.*\)"$/\1/p' "$ASTEP")"
commit="$(sed -n 's/^AGMSG_COMMIT="\(.*\)"$/\1/p' "$ASTEP")"
printf '%s' "$commit" | grep -Eq '^[0-9a-f]{40}$' || fail "AGMSG_COMMIT が 40 桁の 16 進でない: $commit"
[ "$(grep -n '^AGMSG_VERSION=' "$ASTEP" | cut -d: -f1)" -eq "$(($(grep -n '^AGMSG_COMMIT=' "$ASTEP" | cut -d: -f1) - 1))" ] || fail "AGMSG_COMMIT が AGMSG_VERSION の直後の行でない"

# 偽の git: clone は src を作り、rev-parse は FAKE_GIT_COMMIT（既定は宣言どおり）を返す。
gitbin="$tmp/fakegit"
mkdir -p "$gitbin"
cat >"$gitbin/git" <<'FAKE'
#!/usr/bin/env bash
echo "git $* | cwd=$PWD GIT_CONFIG_GLOBAL=${GIT_CONFIG_GLOBAL:-} NOSYSTEM=${GIT_CONFIG_NOSYSTEM:-} PROMPT=${GIT_TERMINAL_PROMPT:-}" >>"$FAKE_LOG"
args=("$@")
for a in "${args[@]}"; do
	case "$a" in
	clone)
		dest="${args[$((${#args[@]} - 1))]}"
		mkdir -p "$dest/.git"
		printf '#!/bin/sh\necho install\n' >"$dest/install.sh"
		chmod 777 "$dest/install.sh"
		printf '%s\n' "$FAKE_GIT_VERSION" >"$dest/VERSION"
		exit 0
		;;
	rev-parse)
		echo "${FAKE_GIT_COMMIT:-$FAKE_GIT_WANT}"
		exit 0
		;;
	esac
done
exit 2
FAKE
chmod +x "$gitbin/git"
export FAKE_GIT_WANT="$commit" FAKE_GIT_VERSION="$ver"
arun() { PATH="$gitbin:$PATH" bash "$ASTEP" 2>&1; }

rc=0
bash "$ASTEP" --check || rc=$?
assert_eq "1" "$rc" "agmsg --check: キーが無ければ 1"

# commit が違えば置かない
rc=0
out="$(FAKE_GIT_COMMIT=0000000000000000000000000000000000000000 arun)" || rc=$?
[ "$rc" -ne 0 ] || fail "agmsg: commit が違うのに成功した"
assert_contains "$out" "commit" "agmsg: commit の食い違いを伝える"
[ ! -e "$ROOT/current" ] && [ ! -e "$ROOT/$ver" ] && [ ! -e "$keys/22" ] || fail "agmsg: commit が違うのに current / 版 / キーを置いた"
[ -z "$(ls -A "$ROOT" 2>/dev/null)" ] || fail "agmsg: 作業ディレクトリが残った: $(ls -A "$ROOT")"
echo "PASS: agmsg: 取得した commit が宣言と違えば置かず、非 0"

out="$(arun)" || fail "agmsg の通常の実行が失敗" "$out"
[ -x "$ROOT/$ver/install.sh" ] && [ -f "$ROOT/$ver/VERSION" ] || fail "agmsg: 版が置かれていない"
[ ! -e "$ROOT/$ver/.git" ] || fail "agmsg: .git を残した"
assert_eq "$ver" "$(readlink "$ROOT/current")" "agmsg: current が版を指す"
assert_eq "$commit" "$(cat "$ROOT/$ver/.agmsg-commit")" "agmsg: 取得した commit を記録する"
# 偽の git は install.sh を 777 で作る。置いた後はグループ・他人の書込が外れている。
perm="$(ls -ld "$ROOT/$ver/install.sh")"
[ "${perm:5:1}" = "-" ] && [ "${perm:8:1}" = "-" ] || fail "agmsg: グループ・他人に書込権限が残った" "$perm"
echo "PASS: agmsg: グループ・他人の書込権限を外す"
assert_contains "$(cat "$FAKE_LOG")" "clone -q --depth 1 --branch v$ver" "agmsg: tag を浅く clone する"
assert_contains "$(cat "$FAKE_LOG")" "| cwd=/ " "agmsg: ルートへ移ってから流す"
assert_contains "$(cat "$FAKE_LOG")" "GIT_CONFIG_GLOBAL=/dev/null NOSYSTEM=1 PROMPT=0" "agmsg: git はユーザの gitconfig を読まない"
bash "$ASTEP" --check || fail "agmsg --check: 実行後は 0"
: >"$FAKE_LOG"
arun >/dev/null || fail "agmsg: 再実行が失敗"
assert_not_contains "$(cat "$FAKE_LOG")" "clone" "agmsg: 配置済みなら取り直さない"

# 止められた実行の作業ディレクトリは、次の実行で片付ける
mkdir -p "$ROOT/.tmp.ORPHAN"
arun >/dev/null || fail "agmsg: 孤児の作業ディレクトリがある状態の再実行が失敗"
[ ! -e "$ROOT/.tmp.ORPHAN" ] || fail "agmsg: 孤児の作業ディレクトリを片付けていない"
echo "PASS: agmsg: 残った作業ディレクトリを片付ける"

# 版を上げる: 1 つ前を残し、それ以前を消す。動いている版は消さない
cp "$ASTEP" "$tmp/astep.orig"
bump() { # 版 commit
	sed -i.bak -e "s|^AGMSG_VERSION=.*|AGMSG_VERSION=\"$1\"|" -e "s|^AGMSG_COMMIT=.*|AGMSG_COMMIT=\"$2\"|" "$ASTEP" && rm "$ASTEP.bak"
}
c2=2222222222222222222222222222222222222222
c3=3333333333333333333333333333333333333333
c4=4444444444444444444444444444444444444444
bump 9.0.0 "$c2"
FAKE_GIT_WANT="$c2" FAKE_GIT_VERSION=9.0.0 arun >/dev/null || fail "agmsg: 9.0.0 の実行が失敗"
assert_eq "9.0.0" "$(readlink "$ROOT/current")" "agmsg: 版を上げると current が付け替わる"
[ -d "$ROOT/$ver" ] || fail "agmsg: 1 つ前の版を消した"
bump 9.1.0 "$c3"
FAKE_GIT_WANT="$c3" FAKE_GIT_VERSION=9.1.0 arun >/dev/null || fail "agmsg: 9.1.0 の実行が失敗"
[ ! -e "$ROOT/$ver" ] && [ -d "$ROOT/9.0.0" ] && [ -d "$ROOT/9.1.0" ] || fail "agmsg: 1 つ前を残し、それ以前を消すのに違う"
echo "PASS: agmsg: 1 つ前の版を残し、それ以前を消す"
# 取得に失敗したら current は動かない
bump 9.2.0 "$c4"
rc=0
out="$(FAKE_GIT_WANT="$c4" FAKE_GIT_COMMIT="$c2" FAKE_GIT_VERSION=9.2.0 arun)" || rc=$?
[ "$rc" -ne 0 ] || fail "agmsg: 版を上げる途中の commit 不一致で成功した"
assert_eq "9.1.0" "$(readlink "$ROOT/current")" "agmsg: commit 不一致では current が動かない"
[ ! -e "$ROOT/9.2.0" ] || fail "agmsg: 不一致の版を置いた"
if [ ! -d /proc/self ]; then
	mkdir -p "$tmp/psbin2"
	printf '#!/usr/bin/env bash\nprintf "%%s\\n" "bash %s/9.0.0/scripts/watch.sh"\n' "$ROOT" >"$tmp/psbin2/ps"
	chmod +x "$tmp/psbin2/ps"
	bump 9.3.0 "$c4"
	PATH="$tmp/psbin2:$gitbin:$PATH" FAKE_GIT_WANT="$c4" FAKE_GIT_VERSION=9.3.0 bash "$ASTEP" >/dev/null 2>&1 || fail "agmsg busy: 実行が失敗"
	[ -d "$ROOT/9.0.0" ] || fail "agmsg: 動いている版を消した"
	[ -d "$ROOT/9.1.0" ] || fail "agmsg: 1 つ前の版を消した（動いている版があるとき）"
	echo "PASS: agmsg: 動いている版は消さない"
fi
cp "$tmp/astep.orig" "$ASTEP"

# ================= ユーザ側: tenv =================
cfg="$tmp/chezmoi.toml"
chezmoi_config "$cfg"
# shellcheck source-path=SCRIPTDIR source=../../.chezmoitemplates/tenv-link.sh
. "$REPO/.chezmoitemplates/tenv-link.sh"
# shellcheck source-path=SCRIPTDIR source=../../bootstrap/lib.sh
. "$REPO/bootstrap/lib.sh"
note() { :; }
SH="$tmp/shared-tenv/Terraform"
UH="$tmp/home-tenv/Terraform"
mkshared() {
	rm -rf "$tmp/shared-tenv" "$tmp/home-tenv"
	for v in 1.0.0 2.0.0; do
		mkdir -p "$SH/$v"
		printf '#!/bin/sh\n' >"$SH/$v/terraform"
		chmod +x "$SH/$v/terraform"
	done
	mkdir -p "$SH/3.0.0" # 実行ファイル無し: 共有側が壊れている
}
mkshared
# 実ファイルが 1.0.0 にあり（共有が覆う）、0.9.0 は共有に無い
mkdir -p "$UH/1.0.0" "$UH/0.9.0"
printf 'own' >"$UH/1.0.0/terraform"
printf 'own' >"$UH/0.9.0/terraform"
printf 'x' >"$UH/1.0.0/last-use.txt"
tenv_link_shared "$SH" "$UH"
[ -L "$UH/1.0.0/terraform" ] && [ "$(readlink "$UH/1.0.0/terraform")" = "$SH/1.0.0/terraform" ] || fail "tenv user: 共有が覆う実ファイルを symlink に替えていない"
[ -L "$UH/2.0.0/terraform" ] || fail "tenv user: 無い版を symlink していない"
[ -f "$UH/0.9.0/terraform" ] && [ ! -L "$UH/0.9.0/terraform" ] || fail "tenv user: 共有が覆わない版を触った"
[ ! -e "$UH/3.0.0" ] || fail "tenv user: 実行ファイルの無い共有の版を link した"
[ -f "$UH/1.0.0/last-use.txt" ] || fail "tenv user: ユーザの last-use.txt を消した"
echo "PASS: tenv user: 共有が覆う版だけ symlink にし、他は触らない"
# 動いているなら実ファイルを残す
mkshared
mkdir -p "$UH/1.0.0"
printf 'own' >"$UH/1.0.0/terraform"
running_exact() { return 1; }
running_matching() {
	case "$1" in */Terraform/1.0.0/*) return 0 ;; esac
	return 1
}
running_args_matching() { return 1; }
tenv_link_shared "$SH" "$UH"
[ -f "$UH/1.0.0/terraform" ] && [ ! -L "$UH/1.0.0/terraform" ] || fail "tenv user: 動いている実ファイルを消した"
[ -L "$UH/2.0.0/terraform" ] || fail "tenv user: 動いている版があっても他の版は link する"
running_matching() { return 1; }
tenv_link_shared "$SH" "$UH"
[ -L "$UH/1.0.0/terraform" ] || fail "tenv user: 止まった次回に symlink へ替わらない"
echo "PASS: tenv user: 動いている実ファイルは残し、次回に替える"
# 共有から消えた版の dangling symlink を外す
rm -rf "$SH/2.0.0"
tenv_link_shared "$SH" "$UH"
[ ! -e "$UH/2.0.0/terraform" ] && [ ! -L "$UH/2.0.0/terraform" ] || fail "tenv user: dangling symlink が残った"
[ -L "$UH/1.0.0/terraform" ] || fail "tenv user: 生きている symlink を外した"
echo "PASS: tenv user: 共有から消えた版の dangling symlink を外す"

# テンプレート: 共有が揃っていないときは何もしない
script="$tmp/run21.sh"
chezmoi --source "$REPO" --config "$cfg" execute-template <"$REPO/.chezmoiscripts/run_after_21-tenv-verify.sh.tmpl" |
	sed -e "s#^SHARED_TENV=.*#SHARED_TENV=$tmp/s21/tenv#" -e "s#^SHARED_TENV_KEY=.*#SHARED_TENV_KEY=$tmp/s21/keys/21#" >"$script"
grep -q "^SHARED_TENV=$tmp/s21" "$script" || fail "run_after_21: 共有側のパスの差し替えに失敗"
bash -n "$script" || fail "run_after_21: 構文エラー"
h21="$tmp/h21"
mkdir -p "$h21/.tenv/Terraform/1.0.0" "$tmp/s21/tenv/Terraform/1.0.0" "$tmp/s21/keys"
printf 'own' >"$h21/.tenv/Terraform/1.0.0/terraform"
printf '#!/bin/sh\n' >"$tmp/s21/tenv/Terraform/1.0.0/terraform"
chmod +x "$tmp/s21/tenv/Terraform/1.0.0/terraform"
runu() { HOME="$h21" TENV_ROOT="" XDG_CACHE_HOME="" PATH="$tmp/psbin3:/usr/bin:/bin" bash "$script" 2>&1; }
mkdir -p "$tmp/psbin3"
printf '#!/usr/bin/env bash\nexit 0\n' >"$tmp/psbin3/ps"
chmod +x "$tmp/psbin3/ps"
runu >/dev/null || fail "run_after_21 (キー無し) が失敗"
[ ! -L "$h21/.tenv/Terraform/1.0.0/terraform" ] || fail "run_after_21: キーが無いのに共有へ向けた"
echo k >"$tmp/s21/keys/21"
runu >/dev/null || fail "run_after_21 が失敗"
[ -L "$h21/.tenv/Terraform/1.0.0/terraform" ] || fail "run_after_21: 揃っているのに共有へ向けない"
echo "PASS: run_after_21: 共有が揃っているときだけ共有へ向ける"

# ================= ユーザ側: run_after_40 の agmsg =================
script40="$tmp/run40.sh"
chezmoi --source "$REPO" --config "$cfg" execute-template <"$REPO/.chezmoiscripts/run_after_40-ai-assistants.sh.tmpl" |
	sed -e "s#^SHARED_AGMSG=.*#SHARED_AGMSG=$tmp/s40/agmsg#" -e "s#^SHARED_AGMSG_KEY=.*#SHARED_AGMSG_KEY=$tmp/s40/keys/22#" >"$script40"
grep -q "^SHARED_AGMSG=$tmp/s40" "$script40" || fail "run_after_40: 共有側のパスの差し替えに失敗"
bash -n "$script40" || fail "run_after_40: 構文エラー"
stubs="$tmp/stubs40"
mkdir -p "$stubs" "$tmp/h40"
export CALLS="$tmp/calls40"
for c in codegraph uv graphify kiro-cli curl npm fnm claude codex aqua; do
	cat >"$stubs/$c" <<'FAKE'
#!/usr/bin/env bash
echo "$(basename "$0") $*" >>"$CALLS"
case " ${FAKE_FAIL:-} " in *" $(basename "$0"):${1:-} "*) exit 1 ;; esac
[ "$(basename "$0")" = aqua ] && exit 1
exit 0
FAKE
	chmod +x "$stubs/$c"
done
run40() {
	: >"$CALLS"
	HOME="$tmp/h40" XDG_DATA_HOME="" XDG_CONFIG_HOME="" XDG_CACHE_HOME="" PATH="$stubs:/usr/bin:/bin" bash "$script40" 2>&1
}
# 共有側なし: 従来どおり setup.sh をユーザ単位で取る
run40 >/dev/null || fail "run_after_40 (共有なし) が失敗"
assert_contains "$(cat "$CALLS")" "setup.sh" "agmsg: 共有側が無ければ従来どおり setup.sh"
# 共有側あり: current/install.sh を流し、setup.sh は取らない
mkdir -p "$tmp/s40/agmsg/9.9.9" "$tmp/s40/keys"
cat >"$tmp/s40/agmsg/9.9.9/install.sh" <<'FAKE'
#!/usr/bin/env bash
echo "shared-install $*" >>"$CALLS"
[ -z "${FAKE_INSTALL_FAIL:-}" ]
FAKE
chmod +x "$tmp/s40/agmsg/9.9.9/install.sh"
echo 9.9.9 >"$tmp/s40/agmsg/9.9.9/VERSION"
echo cafe >"$tmp/s40/agmsg/9.9.9/.agmsg-commit"
ln -s 9.9.9 "$tmp/s40/agmsg/current"
run40 >/dev/null || fail "run_after_40 (キー無し) が失敗"
assert_not_contains "$(cat "$CALLS")" "shared-install" "agmsg: キーが無ければ共有側を使わない"
echo k >"$tmp/s40/keys/22"
rm -rf "$tmp/h40/.cache"
run40 >/dev/null || fail "run_after_40 (共有あり) が失敗"
c="$(cat "$CALLS")"
assert_contains "$c" "shared-install --cmd agmsg" "agmsg: 共有側の install.sh を流す"
assert_not_contains "$c" "setup.sh" "agmsg: 共有側があれば setup.sh を取らない"
run40 >/dev/null
assert_not_contains "$(cat "$CALLS")" "shared-install" "agmsg: 2 回目は流さない（マーカー）"
# 版が変わったら流し直す。既に導入済みなら --update
mkdir -p "$tmp/h40/.agents/skills/agmsg"
echo 9.9.10 >"$tmp/s40/agmsg/9.9.9/VERSION"
run40 >/dev/null
assert_contains "$(cat "$CALLS")" "shared-install --cmd agmsg --update" "agmsg: 版が変わると --update で流し直す"
# 失敗したらマーカーを進めない
echo 9.9.11 >"$tmp/s40/agmsg/9.9.9/VERSION"
FAKE_INSTALL_FAIL=1 run40 >/dev/null || fail "run_after_40: install.sh が失敗しても apply は止めない"
FAKE_INSTALL_FAIL=1 run40 >/dev/null
assert_contains "$(cat "$CALLS")" "shared-install" "agmsg: 失敗したら次の apply でやり直す"
run40 >/dev/null
run40 >/dev/null
assert_not_contains "$(cat "$CALLS")" "shared-install" "agmsg: 成功したらマーカーが進む"
echo "PASS: agmsg ユーザ側"

echo "ALL PASS"
