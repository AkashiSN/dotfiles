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
# fnm の配置: node-versions/<版>/installation/bin/node と、aliases/<名前> -> node-versions/<版>/installation。
# v24 は default / lts-latest / lts-krypton（fnm install --lts が付ける）が指す版、v20 はプロジェクト用（proj）。
mkfnm() {
	local f="$home/.local/share/fnm" v
	for v in v24 v20; do
		mkdir -p "$f/node-versions/$v/installation/bin"
		: >"$f/node-versions/$v/installation/bin/node"
	done
	mkdir -p "$f/aliases" "$f/keep"
	ln -sfn "$f/node-versions/v24/installation" "$f/aliases/default"
	ln -sfn "$f/node-versions/v24/installation" "$f/aliases/lts-latest"
	ln -sfn "$f/node-versions/v24/installation" "$f/aliases/lts-krypton"
	ln -sfn "$f/node-versions/v20/installation" "$f/aliases/proj"
}
# fnm の既定の版（v24 と、それを指す alias）だけが消え、他の版と alias が残っているか。
assert_default_only_removed() {
	local f="$home/.local/share/fnm" a
	[ ! -e "$f/node-versions/v24" ] || fail "$1: 既定の版 v24 が残った"
	for a in default lts-latest lts-krypton; do
		[ ! -e "$f/aliases/$a" ] && [ ! -L "$f/aliases/$a" ] || fail "$1: alias $a が残った"
	done
	[ -f "$f/node-versions/v20/installation/bin/node" ] || fail "$1: プロジェクト用の v20 まで消した"
	[ -L "$f/aliases/proj" ] || fail "$1: プロジェクト用の alias proj まで消した"
	[ -d "$f/keep" ] || fail "$1: fnm の他のディレクトリまで消した"
	echo "PASS: $1: 既定の版とその alias だけを消す"
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
assert_default_only_removed "共有側あり"
[ ! -e "$home/.cache/dotfiles/node-user.key" ] || fail "共有側ありでマーカーが残った"
[ -e "$home/.cache/dotfiles/node-home.cleaned" ] || fail "掃除を終えたのに印を置かない"
echo "PASS: 共有側あり: マーカーを消し、掃除済みの印を置く"

# 掃除済みなら、ユーザが自分で付け直した default は消さない
ln -sfn "$home/.local/share/fnm/node-versions/v20/installation" "$home/.local/share/fnm/aliases/default"
run30 >/dev/null || fail "掃除済みの再実行で失敗"
[ -L "$home/.local/share/fnm/aliases/default" ] && [ -d "$home/.local/share/fnm/node-versions/v20" ] || fail "掃除済みなのにユーザの default を消した"
echo "PASS: 掃除済みなら、ユーザが付け直した default とその版を消さない"
rm -f "$home/.local/share/fnm/aliases/default"

# 共有側が片方だけ（キーが無い）なら揃っていない扱い。ユーザ単位の導入をしたら掃除済みの印を外す
mkfnm
rm "$tmp/shared/keys/23"
run30 >/dev/null
[ -d "$home/.local/share/fnm/node-versions/v24" ] || fail "キーが無いのに fnm の Node を消した"
[ ! -e "$home/.cache/dotfiles/node-home.cleaned" ] || fail "ユーザ単位の導入をしたのに掃除済みの印が残った"
echo "PASS: キーが無ければ揃っていない扱い（消さない）、掃除済みの印を外す"
echo k >"$tmp/shared/keys/23"

# ---- 動いている node があれば消さない（単体: 判定関数を差し替え）----
(
	# shellcheck source-path=SCRIPTDIR source=../../bootstrap/lib.sh
	. "$REPO/bootstrap/lib.sh"
	# shellcheck source-path=SCRIPTDIR source=../../.chezmoitemplates/node-cleanup.sh
	. "$REPO/.chezmoitemplates/node-cleanup.sh"
	note() { :; }
	d="$tmp/u1/fnm"
	mk() {
		mkdir -p "$d/node-versions/v1/installation" "$d/aliases"
		ln -sfn "$d/node-versions/v1/installation" "$d/aliases/default"
	}
	# running_from_any
	mk
	running_from_any() { return 0; }
	running_matching() { return 1; }
	node_cleanup_home "$d" && fail "動いているのに 0 を返した"
	[ -d "$d/node-versions/v1" ] || fail "running_from_any を見ていない"
	# running_matching: fnm_multishells
	running_from_any() { return 1; }
	running_matching() {
		case "$1" in */fnm_multishells/) return 0 ;; esac
		return 1
	}
	node_cleanup_home "$d" && fail "動いているのに 0 を返した"
	[ -d "$d/node-versions/v1" ] || fail "fnm_multishells を見ていない"
	# running_matching: aliases 経由（PATH に aliases/default/bin を通した起動）
	running_matching() {
		case "$1" in "$d/aliases/") return 0 ;; esac
		return 1
	}
	node_cleanup_home "$d" && fail "動いているのに 0 を返した"
	[ -d "$d/node-versions/v1" ] || fail "fnm の aliases を見ていない"
	# 別の版だけが動いていても、消す版は消す
	running_matching() {
		case "$1" in */node-versions/v9/) return 0 ;; esac
		return 1
	}
	node_cleanup_home "$d" || fail "動いていないのに 1 を返した"
	[ ! -e "$d/node-versions/v1" ] && [ ! -L "$d/aliases/default" ] || fail "動いていないのに消えない"
	[ -d "$d/node-versions" ] && [ -d "$d/aliases" ] || fail "node-versions / aliases 自体を消した"
	# default が無ければ（fnm env が作る空のディレクトリだけなら）、消さず何も言わない
	note() { echo "$1"; }
	out="$(node_cleanup_home "$d")" || fail "default が無いのに 1 を返した"
	[ -z "$out" ] && [ -d "$d/node-versions" ] || fail "default が無いのに何かしようとした" "$out"
	# default が壊れている（版が無い）なら何もしない
	ln -sfn "$d/node-versions/v7/installation" "$d/aliases/default"
	out="$(node_cleanup_home "$d")" || fail "壊れた default で 1 を返した"
	[ -z "$out" ] && [ -L "$d/aliases/default" ] || fail "壊れた default に触れた" "$out"
) || exit 1
echo "PASS: 動いている node があれば fnm の Node を残す"
echo "PASS: default が無い・壊れているなら何もしない"

# ---- macOS の ps は fnm_multishells のリンクのパスだけを出す ----
if [ ! -d /proc/self ]; then
	mkfnm
	rm -f "$home/.cache/dotfiles/node-home.cleaned"
	printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s/.local/state/fnm_multishells/123_456/bin/node" /usr/bin/other\n' "$home" >"$stubs/ps"
	run30 >/dev/null || fail "ps 偽物で失敗"
	[ -d "$home/.local/share/fnm/node-versions/v24" ] || fail "リンク経由で動く node の実体を消した"
	printf '#!/usr/bin/env bash\nexit 0\n' >"$stubs/ps"
	[ ! -e "$home/.cache/dotfiles/node-home.cleaned" ] || fail "残したのに掃除済みの印を置いた"
	run30 >/dev/null
	assert_default_only_removed "止まった次回"
	echo "PASS: macOS 形式の ps（リンクのパスだけ）でも動作中を見て、実体を消さない"
fi

echo "ALL PASS"
