#!/usr/bin/env bash
# run_after_40-ai-assistants.sh.tmpl（AI エージェントの CLI の登録）のテスト。
# 偽のホームと偽のコマンドだけを使い、実機のファイルや aqua には触れない。
# shellcheck disable=SC2030,SC2031  # 子シェルでの PATH の変更は意図どおり
set -eu
# shellcheck source-path=SCRIPTDIR source=../lib.sh
. "$(dirname "$0")/../lib.sh"
# shellcheck source-path=SCRIPTDIR source=../../bootstrap/lib.sh
. "$REPO/bootstrap/lib.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ---- run_after_40 の通し実行（偽コマンドだけを PATH に置く。実機のコマンドには触れない）----
cfg="$tmp/chezmoi.toml"
chezmoi_config "$cfg"
script="$tmp/run40.sh"
# 実機の共有側 (/opt) があっても影響されないよう、agmsg と uv の共有側のパスは存在しない場所へ差し替える。
chezmoi --source "$REPO" --config "$cfg" execute-template <"$REPO/.chezmoiscripts/run_after_40-ai-assistants.sh.tmpl" |
	sed -e "s#^SHARED_AGMSG=.*#SHARED_AGMSG=$tmp/none/agmsg#" -e "s#^SHARED_AGMSG_KEY=.*#SHARED_AGMSG_KEY=$tmp/none/keys/22#" \
		-e "s#^SHARED_UV=.*#SHARED_UV=$tmp/none/uv#" -e "s#^SHARED_UV_KEY=.*#SHARED_UV_KEY=$tmp/none/keys/24#" >"$script"
grep -q "^SHARED_UV=$tmp/none/uv" "$script" || fail "run_after_40 の SHARED_UV を差し替えられない"
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
# kiro-cli: uninstall の --help は KIRO_NO_DOTFILES=1 のとき dotfiles を出さない（Linux の 3.x と同じ）。
cat >"$stubs/kiro-cli" <<'FAKE'
#!/usr/bin/env bash
if [ "$*" = "integrations uninstall --help" ]; then
	echo "Commands:"
	[ "${KIRO_NO_DOTFILES:-}" = 1 ] || echo "  dotfiles               "
	echo "  kiro-command-router  "
	exit 0
fi
echo "kiro-cli $*" >>"$CALLS"
FAKE
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
out="$(run40)" || fail "run_after_40 が失敗" "$out"
c="$(cat "$CALLS")"
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
# uninstall に dotfiles が無い kiro-cli（Linux の 3.x）では、統合解除を呼ばずエラーも出さない
out="$(KIRO_NO_DOTFILES=1 run40)" || fail "dotfiles の無い kiro で run_after_40 が失敗" "$out"
assert_not_contains "$(cat "$CALLS")" "kiro-cli integrations uninstall" "dotfiles の無い kiro では統合解除を呼ばない"
echo "PASS: dotfiles の無い kiro-cli では統合解除を飛ばす"

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
