#!/usr/bin/env bash
# .chezmoiscripts/run_after_30-node-default.sh.tmpl（と .chezmoitemplates/node-cleanup.sh）のテスト。
# 描画したスクリプトの共有側のパスだけ一時ディレクトリへ差し替え、HOME も一時ディレクトリにする。
# fnm / npm / ps は PATH 上の偽物で、実機のコマンドや fnm の Node には触れない。
set -eu
# shellcheck source-path=SCRIPTDIR source=../lib.sh
. "$(dirname "$0")/../lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cfg="$tmp/chezmoi.toml"
chezmoi_config "$cfg"
script="$tmp/run30.sh"
chezmoi --source "$REPO" --config "$cfg" execute-template <"$REPO/.chezmoiscripts/run_after_30-node-default.sh.tmpl" |
	sed -e "s#^SHARED_NPM=/opt/npm-global#SHARED_NPM=$tmp/shared/npm-global#" \
		-e "s#^SHARED_NPM_KEY=.*#SHARED_NPM_KEY=$tmp/shared/keys/23#" >"$script"
grep -q "^SHARED_NPM=$tmp/shared" "$script" || fail "共有側のパスの差し替えに失敗"
bash -n "$script" || fail "描画したスクリプトの構文エラー"

home="$tmp/home"
stubs="$tmp/stubs"
mkdir -p "$home" "$stubs"
CALLS="$tmp/calls"
export CALLS
# FAKE_FAIL に "<コマンド名>:<最初の引数>" を空白区切りで渡すと、その呼び出しだけ失敗する。
for c in fnm npm; do
	cat >"$stubs/$c" <<'FAKE'
#!/usr/bin/env bash
echo "$(basename "$0") $*" >>"$CALLS"
case " ${FAKE_FAIL:-} " in *" $(basename "$0"):${1:-} "*) exit 1 ;; esac
exit 0
FAKE
	chmod +x "$stubs/$c"
done
# 何も動いていない ps。
printf '#!/usr/bin/env bash\nexit 0\n' >"$stubs/ps"
chmod +x "$stubs/ps"
run30() {
	: >"$CALLS"
	HOME="$home" XDG_DATA_HOME="" XDG_CONFIG_HOME="" XDG_CACHE_HOME="" FNM_DIR="" \
		PATH="$stubs:/usr/bin:/bin" bash "$script" 2>&1
}
mkfnm() {
	mkdir -p "$home/.local/share/fnm/node-versions/v24/bin" "$home/.local/share/fnm/aliases" "$home/.local/share/fnm/keep"
	: >"$home/.local/share/fnm/node-versions/v24/bin/node"
}
mkfnm

# ---- 共有側が無い: fnm で LTS を用意して NPM_GLOBALS を入れ、fnm の Node は消さない ----
out="$(run30)" || fail "共有側なしで失敗" "$out"
assert_contains "$out" "ユーザ単位" "共有側なし: 案内を出す"
c="$(cat "$CALLS")"
assert_contains "$c" "fnm install --lts" "共有側なし: fnm install --lts"
assert_contains "$c" "npm install -g difit@" "共有側なし: difit を入れる"
assert_contains "$c" "cline@" "共有側なし: cline も入れる"
[ -d "$home/.local/share/fnm/node-versions/v24" ] || fail "共有側なしなのに fnm の Node を消した"
[ -f "$home/.cache/dotfiles/node-user.key" ] || fail "成功したのにマーカーを書かなかった"
echo "PASS: 共有側なし: ユーザ単位に入れ、fnm の Node は消さない"

# 2 回目は省く
out="$(run30)" || fail "2 回目が失敗" "$out"
assert_eq "" "$(cat "$CALLS")" "2 回目: 何も流さない（マーカー）"

# 一覧が変わるとマーカーが変わる。npm が失敗すると進めない
rm -f "$home/.cache/dotfiles/node-user.key"
out="$(FAKE_FAIL="npm:install" run30)" || fail "失敗しても apply は止めない" "$out"
[ ! -e "$home/.cache/dotfiles/node-user.key" ] || fail "npm が失敗したのにマーカーを進めた"
echo "PASS: npm の失敗ではマーカーを進めない"
rm -f "$home/.cache/dotfiles/node-user.key"
FAKE_FAIL="fnm:install" run30 >/dev/null || fail "fnm 失敗でも apply は止めない"
[ ! -e "$home/.cache/dotfiles/node-user.key" ] || fail "fnm install が失敗したのにマーカーを進めた"
echo "PASS: fnm の失敗ではマーカーを進めない"
run30 >/dev/null
[ -f "$home/.cache/dotfiles/node-user.key" ] || fail "成功した再実行でマーカーを書かない"

# fnm が無ければ何もしない
rm -f "$home/.cache/dotfiles/node-user.key"
mv "$stubs/fnm" "$stubs/fnm.off"
out="$(run30)" || fail "fnm 無しで失敗" "$out"
[ ! -e "$home/.cache/dotfiles/node-user.key" ] || fail "fnm が無いのにマーカーを書いた"
mv "$stubs/fnm.off" "$stubs/fnm"

# ---- 共有側が揃っている: fnm の Node を消し、取得しない ----
mkdir -p "$tmp/shared/npm-global/current/bin" "$tmp/shared/keys"
echo k >"$tmp/shared/keys/23"
mkdir -p "$home/.cache/dotfiles"
echo stale >"$home/.cache/dotfiles/node-user.key"
out="$(run30)" || fail "共有側ありで失敗" "$out"
assert_eq "" "$(cat "$CALLS")" "共有側あり: fnm / npm を流さない"
[ ! -e "$home/.local/share/fnm/node-versions" ] && [ ! -e "$home/.local/share/fnm/aliases" ] || fail "共有側ありなのに fnm の Node が残った"
[ -d "$home/.local/share/fnm/keep" ] || fail "fnm の他のディレクトリまで消した"
[ ! -e "$home/.cache/dotfiles/node-user.key" ] || fail "共有側ありでマーカーが残った"
echo "PASS: 共有側あり: fnm の Node だけ消し、マーカーも消す"

# 共有側が片方だけ（キーが無い）なら揃っていない扱い
mkfnm
rm "$tmp/shared/keys/23"
run30 >/dev/null
[ -d "$home/.local/share/fnm/node-versions/v24" ] || fail "キーが無いのに fnm の Node を消した"
echo "PASS: キーが無ければ揃っていない扱い（消さない）"
echo k >"$tmp/shared/keys/23"

# ---- 動いている node があれば消さない（単体: 判定関数を差し替え）----
(
	# shellcheck source-path=SCRIPTDIR source=../../bootstrap/lib.sh
	. "$REPO/bootstrap/lib.sh"
	# shellcheck source-path=SCRIPTDIR source=../../.chezmoitemplates/node-cleanup.sh
	. "$REPO/.chezmoitemplates/node-cleanup.sh"
	note() { :; }
	d="$tmp/u1/fnm"
	mk() { mkdir -p "$d/node-versions/v1" "$d/aliases"; }
	# running_from_any
	mk
	running_from_any() { return 0; }
	running_matching() { return 1; }
	node_cleanup_home "$d"
	[ -d "$d/node-versions" ] || fail "running_from_any を見ていない"
	# running_matching: fnm_multishells
	running_from_any() { return 1; }
	running_matching() {
		case "$1" in */fnm_multishells/) return 0 ;; esac
		return 1
	}
	node_cleanup_home "$d"
	[ -d "$d/node-versions" ] || fail "fnm_multishells を見ていない"
	# 動いていない
	running_matching() { return 1; }
	node_cleanup_home "$d"
	[ ! -e "$d/node-versions" ] && [ ! -e "$d/aliases" ] || fail "動いていないのに消えない"
) || exit 1
echo "PASS: 動いている node があれば fnm の Node を残す"

# ---- macOS の ps は fnm_multishells のリンクのパスだけを出す ----
if [ ! -d /proc/self ]; then
	mkfnm
	printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s/.local/state/fnm_multishells/123_456/bin/node" /usr/bin/other\n' "$home" >"$stubs/ps"
	run30 >/dev/null || fail "ps 偽物で失敗"
	[ -d "$home/.local/share/fnm/node-versions/v24" ] || fail "リンク経由で動く node の実体を消した"
	printf '#!/usr/bin/env bash\nexit 0\n' >"$stubs/ps"
	run30 >/dev/null
	[ ! -e "$home/.local/share/fnm/node-versions" ] || fail "止まった次回に消えない"
	echo "PASS: macOS 形式の ps（リンクのパスだけ）でも動作中を見て、実体を消さない"
fi

echo "ALL PASS"
