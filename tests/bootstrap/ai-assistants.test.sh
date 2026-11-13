#!/usr/bin/env bash
# .chezmoitemplates/ai-cleanup.sh（ホームの公式インストーラの実体の掃除）のテスト。
# 偽のホームと偽の判定関数だけを使い、実機のファイルや aqua には触れない。
# shellcheck disable=SC2030,SC2031  # 子シェルでの PATH の変更は意図どおり
set -eu
# shellcheck source-path=SCRIPTDIR source=../lib.sh
. "$(dirname "$0")/../lib.sh"
# shellcheck source-path=SCRIPTDIR source=../../bootstrap/lib.sh
. "$REPO/bootstrap/lib.sh"
# shellcheck source-path=SCRIPTDIR source=../../.chezmoitemplates/ai-cleanup.sh
. "$REPO/.chezmoitemplates/ai-cleanup.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# 判定関数を差し替える。PROVIDED は aqua が提供するコマンド（空白区切り）、BUSY は動作中とみなす
# ディレクトリ部分文字列（空白区切り）。
ai_provided() {
	case " ${PROVIDED:-} " in *" $1 "*) return 0 ;; esac
	return 1
}
running_from_any() {
	case " ${BUSY:-} " in *" ${1%/} "*) return 0 ;; esac
	return 1
}
running_matching() { return 1; }
running_exact() { return 1; }

# 公式インストーラが置いた状態の偽ホームを作る。
mkhome() {
	local h="$1"
	mkdir -p "$h/.local/bin" "$h/.local/share/claude/versions/9.9.9" "$h/.local/state/claude" "$h/.cache/claude" \
		"$h/.codex/packages/standalone/releases/1" "$h/.codex/sessions" \
		"$h/.codegraph/versions/v1/bin" "$h/.claude"
	: >"$h/.local/share/claude/versions/9.9.9/claude"
	ln -s "$h/.local/share/claude/versions/9.9.9" "$h/.local/bin/claude"
	ln -s "$h/.codex/packages/standalone/releases/1" "$h/.codex/packages/standalone/current"
	ln -s "$h/.codex/packages/standalone/current/bin/codex" "$h/.local/bin/codex"
	: >"$h/.codex/config.toml"
	: >"$h/.codex/sessions/keep"
	: >"$h/.codegraph/telemetry.json"
	ln -s "$h/.codegraph/versions/v1/bin/codegraph" "$h/.local/bin/codegraph"
	ln -s "$h/.codegraph/versions/v1" "$h/.codegraph/current"
	: >"$h/.local/bin/kiro-cli"
	: >"$h/.local/bin/kiro-cli-chat"
	: >"$h/.local/bin/kiro-cli-term"
	: >"$h/.claude/settings.json"
}

# ---- aqua が何も提供しない: 何も消さない ----
h="$tmp/h1"
mkhome "$h"
before="$(cd "$h" && find . | sort)"
PROVIDED="" ai_cleanup_home "$h" >/dev/null
assert_eq "$before" "$(cd "$h" && find . | sort)" "提供なし: 何も消さない"

# ---- 全て提供: 実体と ~/.local/bin のリンクを消し、設定・認証は残す ----
h="$tmp/h2"
mkhome "$h"
PROVIDED="claude codex codegraph kiro-cli" ai_cleanup_home "$h" >/dev/null
for p in .local/bin/claude .local/share/claude .local/state/claude .cache/claude \
	.local/bin/codex .codex/packages .local/bin/codegraph .codegraph/versions .codegraph/current \
	.local/bin/kiro-cli .local/bin/kiro-cli-chat .local/bin/kiro-cli-term; do
	{ [ ! -e "$h/$p" ] && [ ! -L "$h/$p" ]; } || fail "提供あり: $p が残った"
done
echo "PASS: 提供あり: 公式インストーラの実体を消す"
for p in .claude/settings.json .codex/config.toml .codex/sessions/keep .codegraph/telemetry.json; do
	[ -e "$h/$p" ] || fail "提供あり: 設定・認証の $p まで消した"
done
echo "PASS: 設定・認証・履歴は残す"

# ---- 一部だけ提供: 提供されたものだけ消す ----
h="$tmp/h3"
mkhome "$h"
PROVIDED="claude" ai_cleanup_home "$h" >/dev/null
[ ! -L "$h/.local/bin/claude" ] || fail "claude のリンクが残った"
[ -L "$h/.local/bin/codex" ] && [ -d "$h/.codex/packages" ] || fail "提供されない codex を消した"
[ -L "$h/.local/bin/codegraph" ] && [ -e "$h/.local/bin/kiro-cli" ] || fail "提供されない codegraph / kiro を消した"
echo "PASS: 提供されたものだけ消す"

# ---- 動作中: リンクだけ外して実体は残す。止まったら次回に消える ----
h="$tmp/h4"
mkhome "$h"
out="$(PROVIDED="claude codex codegraph" BUSY="$h/.local/share/claude/versions $h/.codex/packages $h/.codegraph/versions" ai_cleanup_home "$h" 2>&1)"
for p in .local/bin/claude .local/bin/codex .local/bin/codegraph; do
	{ [ ! -e "$h/$p" ] && [ ! -L "$h/$p" ]; } || fail "動作中: $p のリンクを外していない"
done
[ -d "$h/.local/share/claude/versions/9.9.9" ] && [ -d "$h/.codex/packages/standalone/releases/1" ] &&
	[ -d "$h/.codegraph/versions/v1" ] || fail "動作中なのに実体を消した"
assert_contains "$out" "次の chezmoi apply" "動作中: 案内を出す"
PROVIDED="claude codex codegraph" ai_cleanup_home "$h" >/dev/null
[ ! -e "$h/.local/share/claude" ] && [ ! -e "$h/.codex/packages" ] && [ ! -e "$h/.codegraph/versions" ] ||
	fail "止まった次回に実体が消えない"
echo "PASS: 動作中は実体を残し、次回に消す"

# ---- symlink 経由のプロセス（running_matching）でも動作中とみなす ----
# shellcheck disable=SC2329  # ai_cleanup_home が呼ぶ
running_matching() {
	case "$1" in "$h/.local/share/claude/versions/") return 0 ;; esac
	return 1
}
h="$tmp/h5"
mkhome "$h"
PROVIDED="claude" ai_cleanup_home "$h" >/dev/null
[ -d "$h/.local/share/claude/versions/9.9.9" ] || fail "running_matching を見ていない"
echo "PASS: running_matching でも動作中とみなす"
running_matching() { return 1; }

# ---- aqua の実体を指す symlink は触らない ----
h="$tmp/h6"
mkhome "$h"
rm "$h/.local/bin/claude"
mkdir -p "$tmp/x/aquaproj-aqua/pkgs"
: >"$tmp/x/aquaproj-aqua/pkgs/claude"
ln -s "$tmp/x/aquaproj-aqua/pkgs/claude" "$h/.local/bin/claude"
PROVIDED="claude" ai_cleanup_home "$h" >/dev/null
[ -L "$h/.local/bin/claude" ] || fail "aqua を指すリンクを消した"
echo "PASS: aqua を指すリンクは消さない"

# ---- macOS の ps はリンクのパスだけを出す: 実体のディレクトリは消さず、リンクは外す ----
# lib.sh の本物の running_* を使い、ps だけを PATH 上の偽物にする（/proc の無い macOS でのみ意味がある）。
if [ ! -d /proc/self ]; then
	h="$tmp/h7"
	mkhome "$h"
	mkdir -p "$tmp/psbin"
	cat >"$tmp/psbin/ps" <<FAKE
#!/usr/bin/env bash
printf '%s\n' "$h/.local/bin/claude" "$h/.local/bin/claude-bedrock" /usr/bin/other
FAKE
	chmod +x "$tmp/psbin/ps"
	(
		PATH="$tmp/psbin:$PATH"
		# shellcheck source-path=SCRIPTDIR source=../../bootstrap/lib.sh
		. "$REPO/bootstrap/lib.sh"
		PROVIDED="claude codex" ai_cleanup_home "$h" >/dev/null
	)
	[ ! -L "$h/.local/bin/claude" ] || fail "リンク経由で動作中でも PATH 上のリンクは外す"
	[ -d "$h/.local/share/claude/versions/9.9.9" ] || fail "リンク経由で動いている claude の実体を消した"
	[ ! -e "$h/.codex/packages" ] || fail "動いていない codex の実体が残った"
	# 完全一致: claude-bedrock だけが動いていても claude の実体は止めない
	h="$tmp/h8"
	mkhome "$h"
	cat >"$tmp/psbin/ps" <<FAKE
#!/usr/bin/env bash
printf '%s\n' "$h/.local/bin/claude-bedrock"
FAKE
	(
		PATH="$tmp/psbin:$PATH"
		# shellcheck source-path=SCRIPTDIR source=../../bootstrap/lib.sh
		. "$REPO/bootstrap/lib.sh"
		PROVIDED="claude" ai_cleanup_home "$h" >/dev/null
	)
	[ ! -e "$h/.local/share/claude" ] || fail "claude-bedrock をリンク claude と取り違えた"
	echo "PASS: macOS 形式の ps（リンクのパスだけ）でも動作中を見て、実体を消さない"
fi

# ---- 既定の ai_provided: aqua pkgs の実体があるときだけ真 ----
unset -f ai_provided
# shellcheck source-path=SCRIPTDIR source=../../.chezmoitemplates/ai-cleanup.sh
. "$REPO/.chezmoitemplates/ai-cleanup.sh"
mkdir -p "$tmp/bin" "$tmp/pkgs/aquaproj-aqua/pkgs"
: >"$tmp/pkgs/aquaproj-aqua/pkgs/real"
chmod +x "$tmp/pkgs/aquaproj-aqua/pkgs/real"
cat >"$tmp/bin/aqua" <<FAKE
#!/usr/bin/env bash
[ "\$1" = which ] || exit 2
case "\$2" in
real) echo "$tmp/pkgs/aquaproj-aqua/pkgs/real" ;;
missing) echo "$tmp/pkgs/aquaproj-aqua/pkgs/missing" ;;
path) echo "$tmp/bin/aqua" ;;
*) exit 1 ;;
esac
FAKE
chmod +x "$tmp/bin/aqua"
(
	PATH="$tmp/bin:$PATH"
	ai_provided real || fail "実体があるのに偽"
	! ai_provided missing || fail "実体が無いのに真"
	! ai_provided path || fail "aqua 管理外の PATH 上のものを真とした"
	! ai_provided unknown || fail "aqua が知らないものを真とした"
) || exit 1
echo "PASS: 既定の ai_provided は aqua pkgs の実体の有無で決める"

# ---- run_after_40 の通し実行（偽コマンドだけを PATH に置く。実機のコマンドには触れない）----
cfg="$tmp/chezmoi.toml"
chezmoi_config "$cfg"
script="$tmp/run40.sh"
# 実機の共有側 (/opt) があっても影響されないよう、agmsg の共有側のパスは存在しない場所へ差し替える。
chezmoi --source "$REPO" --config "$cfg" execute-template <"$REPO/.chezmoiscripts/run_after_40-ai-assistants.sh.tmpl" |
	sed -e "s#^SHARED_AGMSG=.*#SHARED_AGMSG=$tmp/none/agmsg#" -e "s#^SHARED_AGMSG_KEY=.*#SHARED_AGMSG_KEY=$tmp/none/keys/22#" >"$script"
bash -n "$script" || fail "描画したスクリプトの構文エラー"
stubs="$tmp/stubs"
mkdir -p "$stubs"
# FAKE_FAIL に "<コマンド名>:<最初の引数>" を空白区切りで渡すと、その呼び出しだけ失敗する。
for c in codegraph uv graphify kiro-cli curl npm fnm claude codex; do
	cat >"$stubs/$c" <<'FAKE'
#!/usr/bin/env bash
echo "$(basename "$0") $*" >>"$CALLS"
case " ${FAKE_FAIL:-} " in *" $(basename "$0"):${1:-} "*) exit 1 ;; esac
FAKE
	chmod +x "$stubs/$c"
done
cat >"$stubs/aqua" <<'FAKE'
#!/usr/bin/env bash
echo "aqua $*" >>"$CALLS"
exit 1
FAKE
chmod +x "$stubs/aqua"
run40() {
	: >"$CALLS"
	HOME="$tmp/runhome" XDG_DATA_HOME="" XDG_CONFIG_HOME="" XDG_CACHE_HOME="" CALLS="$CALLS" \
		PATH="$stubs:/usr/bin:/bin" bash "$script" 2>&1
}
CALLS="$tmp/calls"
mkdir -p "$tmp/runhome"
mkhome "$tmp/runhome"
before="$(cd "$tmp/runhome" && find . | sort)"
out="$(run40)" || fail "run_after_40 が失敗" "$out"
c="$(cat "$CALLS")"
assert_eq "$before" "$(cd "$tmp/runhome" && find . | sort | grep -v '^./.cache/dotfiles')" "aqua が提供しなければホームの実体を消さない"
assert_contains "$c" "codegraph install --yes" "登録: codegraph install --yes"
assert_contains "$c" "codegraph telemetry off" "登録: codegraph telemetry off"
assert_contains "$c" "graphify install" "登録: graphify install"
assert_not_contains "$c" "uv tool install" "graphify を uv tool で入れない（共有か run_after_35 の役目）"
assert_contains "$c" "kiro-cli integrations uninstall -s dotfiles" "登録: kiro のシェル統合を外す"
assert_contains "$c" "setup.sh" "agmsg を導入する"
assert_not_contains "$c" "claude.ai/install.sh" "公式インストーラ(claude)を使わない"
assert_not_contains "$c" "chatgpt.com/codex/install.sh" "公式インストーラ(codex)を使わない"
assert_not_contains "$c" "colbymchenry/codegraph/main/install.sh" "公式インストーラ(codegraph)を使わない"
# 2 回目は時間のかかる取得・登録を省く（マーカー）
out="$(run40)" || fail "2 回目の run_after_40 が失敗" "$out"
c="$(cat "$CALLS")"
assert_not_contains "$c" "setup.sh" "2 回目: agmsg を取り直さない"
assert_not_contains "$c" "codegraph install" "2 回目: codegraph 登録を省く"
assert_contains "$c" "kiro-cli integrations uninstall" "2 回目も kiro の統合解除は流す（冪等で軽い）"
echo "PASS: 通し実行とマーカーによる省略"

# ---- 途中のコマンドが失敗して最後が成功しても、マーカーを進めない ----
rm -rf "$tmp/runhome/.cache/dotfiles"
FAKE_FAIL="curl:-fsSL codegraph:install graphify:install" run40 >/dev/null || fail "失敗するステップがあっても apply は止めない"
for k in agmsg codegraph graphify; do
	[ ! -e "$tmp/runhome/.cache/dotfiles/ai-$k.key" ] || fail "$k: 途中が失敗したのにマーカーを進めた"
done
echo "PASS: 途中の失敗（最後のコマンドは成功）ではマーカーを進めない"
run40 >/dev/null
for k in agmsg codegraph graphify; do
	[ -e "$tmp/runhome/.cache/dotfiles/ai-$k.key" ] || fail "$k: 成功したのにマーカーを書かなかった"
done
echo "PASS: 成功すればマーカーを書く"
# codegraph のピンが変わると再登録する
mkdir -p "$tmp/runhome/.config/aquaproj-aqua"
echo '  - name: colbymchenry/codegraph@v1.0.0' >"$tmp/runhome/.config/aquaproj-aqua/aqua.yaml"
run40 >/dev/null
assert_contains "$(cat "$CALLS")" "codegraph install --yes" "codegraph のピンが変わったら再登録する"

# ---- Claude Code の managed settings: 自動更新を止める ----
rendered="$(chezmoi --source "$REPO" --config "$cfg" execute-template <"$REPO/.chezmoiscripts/run_after_42-claude-managed-settings.sh.tmpl")"
# POLICY='...' の代入だけを取り出して評価する。
policy="$(
	eval "$(printf '%s\n' "$rendered" | sed -n "/^POLICY='/,/^}'\$/p")"
	printf '%s' "${POLICY:-}"
)"
[ -n "$policy" ] || fail "policy: POLICY の代入を取り出せない"
assert_eq "1" "$(printf '%s' "$policy" | python3 -c 'import json,sys; print(json.load(sys.stdin)["env"]["DISABLE_AUTOUPDATER"])')" "policy: env.DISABLE_AUTOUPDATER = 1"
assert_eq "False" "$(printf '%s' "$policy" | python3 -c 'import json,sys; print(json.load(sys.stdin)["attribution"]["sessionUrl"])')" "policy: attribution.sessionUrl = false"

# ---- env.sh: 更新確認の抑止 ----
envsh="$(chezmoi --source "$REPO" --config "$cfg" execute-template <"$REPO/dot_config/shell/env.sh.tmpl")"
assert_contains "$envsh" "export CODEGRAPH_NO_UPDATE_CHECK=1" "env.sh: CODEGRAPH_NO_UPDATE_CHECK"
assert_contains "$envsh" "export KIRO_NO_AUTO_UPDATE=1" "env.sh: KIRO_NO_AUTO_UPDATE"

# ---- ラッパー 4 本: AQUA_GLOBAL_CONFIG の判定ブロックが同一で、未設定ならホームの設定になる ----
extract_block() {
	awk '/^if \[ -z "\$\{AQUA_GLOBAL_CONFIG:-\}" \]; then$/ {p=1} p {print} p && /^fi$/ {exit}' "$1"
}
ref=""
for w in dot_local/bin/executable_claude-bedrock dot_local/bin/executable_codex-bedrock \
	dot_local/bin/executable_codex-wrapper dot_local/libexec/codex-dispatch/executable_codex; do
	b="$(extract_block "$REPO/$w")"
	[ -n "$b" ] || fail "$w に AQUA_GLOBAL_CONFIG のブロックが無い"
	[ -n "$ref" ] || ref="$b"
	assert_eq "$ref" "$b" "ラッパー: $w のブロックが他と同一"
done
# shellcheck disable=SC2016  # 子の bash で展開させる
probe='echo "$AQUA_GLOBAL_CONFIG $AQUA_ROOT_DIR"'
if [ ! -f /opt/aquaproj-aqua/config/aqua.yaml ]; then
	got="$(HOME="$tmp/wh" XDG_CONFIG_HOME="" XDG_DATA_HOME="" env -u AQUA_GLOBAL_CONFIG -u AQUA_POLICY_CONFIG -u AQUA_ROOT_DIR \
		bash -c "$ref
$probe")"
	assert_eq "$tmp/wh/.config/aquaproj-aqua/aqua.yaml $tmp/wh/.local/share/aquaproj-aqua" "$got" "ラッパー: 共有側が無ければホームの設定"
fi
got="$(AQUA_GLOBAL_CONFIG=/preset bash -c "$ref
$probe")"
assert_eq "/preset" "${got%% *}" "ラッパー: 設定済みならそのまま"

echo "ALL PASS"
