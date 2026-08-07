#!/usr/bin/env bash
# PostToolUse(Bash) hook: git push の後、対象ブランチに OPEN な PR があれば
# 「今回の push で PR のタイトル・説明が実態とずれていないか」を Claude に確認させる。
#
# 何もしない条件:
#   - 実行されたコマンドが git push を含まない
#   - jq / gh が使えない / リポジトリ外 / PR が存在しない / PR が OPEN でない
#
# 出力: hookSpecificOutput.additionalContext（Claude のコンテキストへ注入される）
#
# 登録は private_dot_claude/settings.json.tmpl の PostToolUse で行う。
# hooks は全設定ソースがマージされるため、他の層に同じ登録を書くと二重に走る。
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

payload=$(cat)
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0

# 先頭・パイプ/セミコロン/&& の直後の git push のみを対象にする（"echo git push" 等を除外）
printf '%s' "$cmd" | grep -qE '(^|[;&|]|&&|\|\|)[[:space:]]*git[[:space:]]+push' || exit 0

command -v gh >/dev/null 2>&1 || exit 0

pr=$(gh pr view --json number,state,title,url,baseRefName 2>/dev/null) || exit 0
[ -n "$pr" ] || exit 0
[ "$(printf '%s' "$pr" | jq -r '.state // ""')" = "OPEN" ] || exit 0

num=$(printf '%s' "$pr" | jq -r '.number')
title=$(printf '%s' "$pr" | jq -r '.title')
url=$(printf '%s' "$pr" | jq -r '.url')
base=$(printf '%s' "$pr" | jq -r '.baseRefName')

commits=$(git log "origin/${base}..HEAD" --oneline 2>/dev/null | head -30)
[ -n "$commits" ] || commits="(取得できず)"

jq -n --arg n "$num" --arg t "$title" --arg u "$url" --arg b "$base" --arg c "$commits" '
{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: (
      "push したブランチには OPEN な PR があります。\n" +
      "  PR #\($n): \($t)\n  \($u)\n\n" +
      "現在 \($b) との差分にあるコミット:\n\($c)\n\n" +
      "今回の push でPRのタイトル・説明が実態とずれていないか確認してください。" +
      "ずれている場合は gh pr edit \($n) でタイトル・本文を更新すること" +
      "（本文はリポジトリの PR テンプレートの構成を維持する）。" +
      "ずれていなければ何もせず、その旨だけ一言添えてください。"
    )
  }
}'
