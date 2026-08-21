#!/bin/bash
# Claude Code statusLine: model / ディレクトリ / git ブランチ / context 使用率を 1 行で出す。
#
# 表示のついでに、context 使用率が閾値を超えたら compact-prep の警告 marker を書く。
# statusLine は context_window を受け取れる唯一の拡張点で、hook 側からは使用率が見えない。
# marker を読んで実際に知らせるのは userpromptsubmit-compact-prep-reminder.sh。
#
# fail-open (常に exit 0)

set -uo pipefail

input=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  echo "claude"
  exit 0
fi

get() { printf '%s' "$input" | jq -r "$1" 2>/dev/null; }

model=$(get '.model.display_name // "claude"')
cwd=$(get '.workspace.current_dir // .cwd // ""')
session_id=$(get '.session_id // empty')
model=${model:-claude}
# used_percentage は最初の API 応答前と /compact 直後に null になる。
pct=$(get '.context_window.used_percentage // 0' | cut -d. -f1)
win=$(get '.context_window.context_window_size // 0' | cut -d. -f1)
[[ "$pct" =~ ^[0-9]+$ ]] || pct=0
[[ "$win" =~ ^[0-9]+$ ]] || win=0

# 自動 compact は 90〜95% で発火する。そこまでに /compact-prep と /compact を挟める余力を残す。
# 1M 窓なら 60%(≒400K 残)、200K 窓は同じ割合だと残りが薄いので 80%(≒40K 残)。
if [[ -n "${CLAUDE_COMPACT_WARN_THRESHOLD:-}" ]]; then
  threshold="$CLAUDE_COMPACT_WARN_THRESHOLD"
elif (( win >= 500000 )); then
  threshold=60
else
  threshold=80
fi

# --- 表示 ---------------------------------------------------------------
branch=""
if [[ -n "$cwd" ]] && command -v git >/dev/null 2>&1; then
  branch=$(git --no-optional-locks -C "$cwd" branch --show-current 2>/dev/null)
fi

filled=$(( pct / 10 ))
(( filled > 10 )) && filled=10
bar=""
for ((i = 0; i < 10; i++)); do
  if (( i < filled )); then bar+="▓"; else bar+="░"; fi
done

if (( pct >= threshold + 20 )); then
  color=$'\033[31m'   # 赤: 自動 compact が目前
elif (( pct >= threshold )); then
  color=$'\033[33m'   # 黄: compact-prep を促す圏内
else
  color=$'\033[32m'
fi
reset=$'\033[0m'
dim=$'\033[2m'

line="${dim}[${model}]${reset} ${cwd##*/}"
[[ -n "$branch" ]] && line+=" ${dim}(${branch})${reset}"
line+=" ${color}${bar} ${pct}%${reset}"
printf '%s\n' "$line"

# --- 閾値超で警告 marker を書く -----------------------------------------
# warned marker(cooldown)がある間は書かない。cooldown は PostCompact で解除される。
if [[ -n "$session_id" ]] && (( pct >= threshold )); then
  # marker はユーザごとに分ける。共有マシンでは TMPDIR が /tmp で全員共通になるため、
  # 固定名だと先に作ったユーザがディレクトリを所有し、他ユーザの書き込みが黙って失敗する。
  base="${TMPDIR:-/tmp}/claude-compact-$(id -u)"
  if [[ ! -f "$base/warned/$session_id" ]]; then
    mkdir -p "$base" 2>/dev/null && chmod 700 "$base" 2>/dev/null || true
    mkdir -p "$base/warn" 2>/dev/null || true
    printf '%s\n' "$pct" > "$base/warn/$session_id" 2>/dev/null || true
  fi
fi

exit 0
