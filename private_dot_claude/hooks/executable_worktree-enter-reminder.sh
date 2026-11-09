#!/usr/bin/env bash
# PostToolUse(Bash) hook: git worktree add の後、作った worktree へ EnterWorktree(path) で
# セッションごと移るよう Claude に促す。
#
# 目的: herdr の popup (<prefix> d の difit など) は herdr-here 経由で claude プロセスの cwd を
# 起点に開く。シェルで worktree を作っただけでは claude の cwd は元のリポジトリのままなので、
# EnterWorktree で移らせて cwd を worktree へ切り替える。
#
# 何もしない条件:
#   - 実行されたコマンドが git worktree add を含まない
#   - jq が使えない
#
# 出力: hookSpecificOutput.additionalContext（Claude のコンテキストへ注入される）
#   作った worktree のパスがコマンドから解ければそれを示し、解けなければ
#   git worktree list で確かめるよう促す。
#
# 登録はユーザ層(private_dot_claude/modify_settings.json.tmpl)で行う。
# policy 層(managed-settings.json)には書かないこと(hooks は全ソースがマージされるため
# 両方に書くと二重に走る)。
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

payload=$(cat)
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
cwd=$(printf '%s' "$payload" | jq -r '.cwd // ""' 2>/dev/null) || cwd=''
[ -n "$cwd" ] || cwd=$PWD

# 先頭・パイプ/セミコロン/&& の直後の git [-C <dir>] worktree add のみを対象にする
re='(^|[;&|(])[[:space:]]*git([[:space:]]+-C[[:space:]]+[^[:space:];&|]+)?[[:space:]]+worktree[[:space:]]+add([[:space:]]|$)'
printf '%s' "$cmd" | grep -qE "$re" || exit 0

# worktree のパスを解く: git worktree add の後ろで、オプションでない最初の引数
wt=''
seg=$(printf '%s' "$cmd" | grep -oE 'git([[:space:]]+-C[[:space:]]+[^[:space:];&|]+)?[[:space:]]+worktree[[:space:]]+add[^;&|]*' | head -1)
read -r -a words <<<"$seg"
base=$cwd
i=0
n=${#words[@]}
while [ "$i" -lt "$n" ]; do
	case ${words[i]} in
	-C)
		i=$((i + 1))
		dir=${words[i]:-}
		dir=${dir%\"}
		dir=${dir#\"}
		dir=${dir%\'}
		dir=${dir#\'}
		case $dir in /*) base=$dir ;; *) base=$cwd/$dir ;; esac
		;;
	add) break ;;
	esac
	i=$((i + 1))
done
i=$((i + 1))
while [ "$i" -lt "$n" ]; do
	w=${words[i]}
	case $w in
	-b | -B | --reason) i=$((i + 2)) ;;
	--) i=$((i + 1)) ;;
	-*) i=$((i + 1)) ;;
	*)
		w=${w%\"}
		w=${w#\"}
		w=${w%\'}
		w=${w#\'}
		w=${w/#\~/$HOME}
		case $w in /*) wt=$w ;; *) wt=$base/$w ;; esac
		break
		;;
	esac
done

if [ -n "$wt" ] && [ -d "$wt" ]; then
	wt=$(cd "$wt" && pwd -P)
	target="作成した worktree: ${wt}
次のツール呼び出しで EnterWorktree を path=\"${wt}\" で呼び、セッションをこの worktree へ移してください。"
else
	target="git worktree list で作成した worktree のパスを確かめ、EnterWorktree を path=<そのパス> で呼んでセッションを移してください。"
fi

jq -n --arg t "$target" '
{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: (
      "git worktree add で worktree を作りました。シェルで作っただけではセッション（claude プロセス）の cwd は元のリポジトリのままで、herdr の <prefix> d（difit）などがこの worktree を見られません。\n" +
      $t + "\n" +
      "以後は cd や git -C で外から操作せず、移った worktree の中で作業してください。" +
      "EnterWorktree が使えない・拒否された場合は、その旨をユーザに伝えてください。"
    )
  }
}'
