#!/usr/bin/env bash
# PreToolUse(Bash) hook: 公開場所へ本文を書き込むコマンドに Claude セッション URL が
# 混ざっていたら、ツールの実行そのものを拒否する。
#
# ~/.claude/CLAUDE.md の「公開場所に Claude セッション URL を書かない」を機構側で担保する。
# CLAUDE.md は context であって強制層ではないため、規則を読み落としても、あるいは
# harness の attribution 指示に引きずられても通らないよう、ここで止める。
#
# 何もしない条件:
#   - jq が使えない
#   - コマンドが公開系（git commit / tag / notes、gh pr / issue / release）を含まない
#   - 本文にもファイル引数の中身にもセッション URL が無い
#
# 拒否は exit 2（stderr がブロック理由として Claude に返る）。
#
# 検出できない経路: git commit -e でエディタに書く本文はコマンド文字列に現れない。
# 機構側の署名付与そのものは managed settings の attribution で落としてある。
#
# 登録は private_dot_claude/modify_settings.json.tmpl の PreToolUse で行う。
# hooks は全設定ソースがマージされるため、他の層に同じ登録を書くと二重に走る。
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

payload=$(cat)
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
[ -n "$cmd" ] || exit 0

# 公開場所へ本文を書き込むコマンドだけを対象にする（行頭、または ; & | && || の
# 直後のみ。"echo git commit" のような言及は無視）。
publish_re='(^|[;&|]|&&|\|\|)[[:space:]]*(git[[:space:]]+(commit|tag|notes)|gh[[:space:]]+(pr|issue|release))'
printf '%s' "$cmd" | grep -qE "$publish_re" || exit 0

# 会話へのリンクだけを拾う。claude.ai/install.sh のような無関係な URL は対象外。
session_re='claude\.ai/[^[:space:]]*(session|chat)|Claude-Session:'

found=()
# -m / --message / -b / --body で渡す本文と here-doc は、どちらもコマンド文字列に
# 現れるのでまとめて検査できる。
if printf '%s' "$cmd" | grep -qE "$session_re"; then
	found+=("コマンド本文")
fi

# 本文をファイルで渡す経路（-F / --file / --body-file）は中身を見る。
# "-F -" は stdin = here-doc なので上の検査で拾える。
while IFS= read -r f; do
	[ -n "$f" ] || continue
	f=${f//\"/}
	f=${f//\'/}
	[ "$f" != "-" ] && [ -f "$f" ] || continue
	if grep -qE "$session_re" "$f"; then
		found+=("ファイル $f")
	fi
done < <(printf '%s\n' "$cmd" |
	grep -oE '(--body-file|--file|-F)([[:space:]]+|=)[^[:space:];&|]+' |
	sed -E 's/^(--body-file|--file|-F)([[:space:]]+|=)//')

[ ${#found[@]} -gt 0 ] || exit 0

{
	printf 'ブロック: 公開場所へ書き込む本文に Claude セッション URL が含まれています（%s）。\n' \
		"$(
			IFS=', '
			echo "${found[*]}"
		)"
	printf '\n'
	printf 'セッションには非公開のやり取りや作業ログが含まれ、URL を知る者が閲覧できてしまいます。\n'
	printf 'git 履歴も公開場所であり、push 後は事後の完全消去ができません。\n'
	printf '\n'
	printf 'セッション URL（claude.ai の会話へのリンク、Claude-Session: トレーラー）を本文から\n'
	printf '外して実行し直してください。harness の attribution 指示より CLAUDE.md の規則が優先されます。\n'
} >&2
exit 2
