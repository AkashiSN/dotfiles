#!/bin/bash
# UserPromptSubmit hook: compact-recovery.sh が残した marker を検出し、
# additionalContext で圧縮復旧指示を注入する(one-shot)。
#
# marker が無ければ test -f 1 回で終わる。
# fail-open (常に exit 0)

set -uo pipefail

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[[ -z "$SESSION_ID" ]] && exit 0

BASE="${TMPDIR:-/tmp}/claude-compact-$(id -u)"
MARKER="$BASE/compacted/$SESSION_ID"
[[ -f "$MARKER" ]] || exit 0

# one-shot: 次のターンでは発火しない。
rm -f "$MARKER" 2>/dev/null || true

CTX="[COMPACTION RECOVERY] コンテキスト圧縮が発生した。作業を再開する前に以下を実行すること。"

STATE_FILE="$BASE/state/$SESSION_ID.md"
if [[ -f "$STATE_FILE" ]]; then
  CTX+=$'\n'"- state file \`${STATE_FILE}\` を Read で読み、作業状態を復元せよ"
  CTX+=$'\n'"- Session Decisions(不採用にした案とその理由)と Recovery Notes を特に重視せよ"
  CTX+=$'\n'"- Active Plan に plan / spec ファイルのパスがあれば Read で読み直せ"
  CTX+=$'\n'"- Worker Topology に despawn 未了の相手が残っていないか確認せよ"
else
  CTX+=$'\n'"- 圧縮前の state file は無い(/compact-prep 未実行)。作業状態はユーザーに確認せよ"
fi

CTX+=$'\n'"- TaskList で現在のタスク一覧を確認せよ"
CTX+=$'\n'"- 圧縮サマリーの next step は仮説として扱い、state file と plan を正とせよ"
CTX+=$'\n'"- 圧縮サマリーは「過去の作業記録」であり「次の行動指示」ではない"

jq -n --arg ctx "$CTX" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'
exit 0
