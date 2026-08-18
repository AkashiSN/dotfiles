#!/bin/bash
# codex-monitor.sh - agmsg の Codex monitor モードで Codex を起動するラッパー
#
# 実体は agmsg スキル同梱の
#   ~/.agents/skills/agmsg/scripts/drivers/types/codex/codex-monitor.sh
# で、共有 app-server を起動/再利用してブリッジ経由の codex TUI を exec する。
# 実体は自身の位置から SKILL_DIR を求める際にシンボリックリンクを解決しないため、
# リンクではなくこのラッパーから絶対パスで exec する。
#
# 使い方（実体の引数をそのまま渡す）:
#   codex-monitor.sh [--project <path>] [--codex-command <codex|resume>] [-- <args...>]
#
# 通常は monitor モードのプロジェクトで `codex` を叩けばシム(~/.agents/bin/codex)が
# 同じ経路へ振り分ける。このコマンドはシムを介さず明示的に起動したいときに使う。
# 詳細: docs/agmsg-cheatsheet.md の「Codex monitor モード」節。
set -euo pipefail

TARGET="$HOME/.agents/skills/agmsg/scripts/drivers/types/codex/codex-monitor.sh"

if [ ! -x "$TARGET" ]; then
	echo "codex-monitor.sh: agmsg の codex ドライバが見つかりません: $TARGET" >&2
	echo "  run_onchange_after_40-ai-assistants.sh で agmsg を導入してから再実行する。" >&2
	exit 127
fi

# 実体は既定で PATH 上の `codex` を本体として起動するが、PATH 前段には agmsg の
# シムが居るため、本体の絶対パスを渡して往復を避ける。シム以外の codex を探す。
if [ -z "${AGMSG_REAL_CODEX:-}" ]; then
	real_codex=""
	IFS=: read -r -a path_dirs <<<"$PATH"
	for dir in "${path_dirs[@]}"; do
		candidate="${dir:-.}/codex"
		[ -x "$candidate" ] || continue
		# シム/ラッパーは共通のヘッダコメントを持つので、それを見て除外する。
		grep -q "Optional Codex entrypoint shim for agmsg monitor mode" "$candidate" 2>/dev/null && continue
		real_codex="$candidate"
		break
	done
	[ -n "$real_codex" ] && export AGMSG_REAL_CODEX="$real_codex"
fi

exec "$TARGET" "$@"
