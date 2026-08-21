#!/bin/bash
# UserPromptSubmit hook: statusline.sh が書いた warn marker を検出し、
# additionalContext で compact-prep の実行を促す(one-shot)。
#
# 自動 compact は context 使用率 90〜95% で勝手に発火する。そこへ先制されると
# 圧縮前の state 保存ができないため、閾値に達した時点で 1 度だけ知らせる。
#
# フロー:
#   statusline.sh が閾値超で warn marker を書く
#   → 本 hook が検出 → additionalContext 注入 → warn marker 削除 + warned marker 作成
#   → compact-recovery.sh (PostCompact) が warned marker を削除して cooldown をリセット
#
# fail-open (常に exit 0)

set -uo pipefail

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[[ -z "$SESSION_ID" ]] && exit 0

BASE="${TMPDIR:-/tmp}/claude-compact-$(id -u)"
WARN_MARKER="$BASE/warn/$SESSION_ID"
[[ -f "$WARN_MARKER" ]] || exit 0

CTX_PCT=$(cat "$WARN_MARKER" 2>/dev/null)
CTX_PCT=${CTX_PCT:-"?"}

# one-shot: 読んだら消す。
rm -f "$WARN_MARKER" 2>/dev/null || true

# cooldown marker。次に compact が起きるまで statusline は warn marker を書かない。
mkdir -p "$BASE/warned" 2>/dev/null || true
date +%s > "$BASE/warned/$SESSION_ID" 2>/dev/null || true

CTX="[COMPACT PREP REMINDER] context 使用率が ${CTX_PCT}% に達した。"
CTX+=$'\n'"- 作業の区切りでユーザーに \`/compact-prep\` の実行を提案せよ。"
CTX+=$'\n'"- \`/compact-prep\` の完了後、ユーザーに \`/compact\` の実行を案内せよ。"
CTX+=$'\n'"- scope を勝手に縮めたり別セッションへ逃がしたりせず、圧縮前の state 保存で対処せよ。"

jq -n --arg ctx "$CTX" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'
exit 0
