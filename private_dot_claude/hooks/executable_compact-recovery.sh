#!/bin/bash
# PostCompact hook: 圧縮が起きたことを marker file に記録する。
#
# PostCompact は additionalContext を返せない(exit 2 でも stderr をユーザーに見せるだけ)ので、
# 復旧指示の注入は userpromptsubmit-compact-recovery.sh が marker を拾って行う。
#
# fail-open (常に exit 0)

set -uo pipefail

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[[ -z "$SESSION_ID" ]] && exit 0

# marker はユーザごとに分ける。共有マシンでは TMPDIR が /tmp で全員共通になるため、
# 固定名だと先に作ったユーザがディレクトリを所有し、他ユーザの書き込みが黙って失敗する。
# 中身は作業状態なので 700 にして他ユーザから読めないようにする。
BASE="${TMPDIR:-/tmp}/claude-compact-$(id -u)"
mkdir -p "$BASE" 2>/dev/null && chmod 700 "$BASE" 2>/dev/null || true

# 圧縮発生の marker。UserPromptSubmit 側が検出して context 注入 → 削除する。
mkdir -p "$BASE/compacted" 2>/dev/null || true
date +%s > "$BASE/compacted/$SESSION_ID" 2>/dev/null || true

# 圧縮したので compact-prep 警告の cooldown を解除し、次に閾値を超えたら再び警告できるようにする。
rm -f "$BASE/warned/$SESSION_ID" 2>/dev/null || true

exit 0
