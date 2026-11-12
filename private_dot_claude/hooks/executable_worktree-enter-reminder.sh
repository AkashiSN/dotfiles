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
#   コマンドから解いたパスが git に登録された worktree だと確かめられたときだけ、
#   そのパスを示して移動を促す。確かめられなければ（引用符・cd・条件分岐などで
#   パスを確実に解けない、または worktree が作られていない）推測したパスは出さず、
#   git worktree list で確かめるよう促すだけにする。
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
[[ $cmd =~ $re ]] || exit 0
# マッチより手前（区切り文字まで）。下で、パスを解いてよい入力かの判定に使う。
before=${cmd%%"${BASH_REMATCH[0]}"*}${BASH_REMATCH[1]}

# worktree のパスを解く: git worktree add の後ろで、オプションでない最初の引数
wt=''
seg=$(printf '%s' "$cmd" | grep -oE 'git([[:space:]]+-C[[:space:]]+[^[:space:];&|]+)?[[:space:]]+worktree[[:space:]]+add[^;&|]*' | head -1)
# 次の入力は read -a の空白分割では正しく解けないので、パスを解かずに一覧確認へ回す。
#   - 空白を含む引用符の中身、バックスラッシュ、変数・コマンド置換（$ と `）
#   - 手前の cd / pushd / popd（相対パスの起点が変わる）
#   - 手前の || や引用符（実行されなかった分岐や、文字列の中の記述かもしれない）
resolvable=1
case $before in
*\"* | *\'* | *'||'* | *'`'* | *\$\(*) resolvable=0 ;;
esac
cdre='(^|[;&|(])[[:space:]]*(cd|pushd|popd)([[:space:]]|$)'
[[ $before =~ $cdre ]] && resolvable=0
case $seg in
*\\* | *'$'* | *'`'*) resolvable=0 ;;
esac
qre_d='"[^"]*[[:space:]][^"]*"'
qre_s="'[^']*[[:space:]][^']*'"
if [[ $seg =~ $qre_d ]] || [[ $seg =~ $qre_s ]]; then
	resolvable=0
fi
words=()
[ "$resolvable" -eq 1 ] && read -r -a words <<<"$seg"
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

# 解いたパスは文字列からの推測なので、git に登録された worktree（メインの作業ツリーを除く）と
# 一致したときだけ採る。read -a は引用符を解釈せず、cd や条件分岐も追わないため、
# ディレクトリが在るだけでは別の場所を指している場合がある。
verified=''
if [ -n "$wt" ] && [ -d "$wt" ]; then
	wt=$(cd "$wt" 2>/dev/null && pwd -P) || wt=''
fi
if [ -n "$wt" ]; then
	first=1
	while IFS= read -r line; do
		case $line in
		'worktree '*) ;;
		*) continue ;;
		esac
		if [ "$first" -eq 1 ]; then
			first=0
			continue
		fi
		p=$(cd "${line#worktree }" 2>/dev/null && pwd -P) || continue
		if [ "$p" = "$wt" ]; then
			verified=$wt
			break
		fi
	done < <(git -C "$wt" worktree list --porcelain 2>/dev/null)
fi

if [ -n "$verified" ]; then
	msg="git worktree add で worktree を作りました: ${verified}
次のツール呼び出しで EnterWorktree を path=\"${verified}\" で呼び、セッションをこの worktree へ移してください。"
else
	msg="git worktree add を含むコマンドを実行しました。worktree を作った場合は、git worktree list で作成した worktree のパスを確かめ、EnterWorktree を path=<そのパス> で呼んでセッションを移してください。作っていなければ何もしなくてよいです。"
fi

jq -n --arg t "$msg" '
{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: (
      $t + "\n" +
      "シェルで worktree を作っただけではセッション（claude プロセス）の cwd は元のリポジトリのままで、herdr の <prefix> d（difit）などがその worktree を見られません。" +
      "移った後は cd や git -C で外から操作せず、移った worktree の中で作業してください。" +
      "EnterWorktree が使えない・拒否された場合は、その旨をユーザに伝えてください。"
    )
  }
}'
