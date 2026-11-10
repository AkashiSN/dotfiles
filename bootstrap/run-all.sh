#!/usr/bin/env bash
# 共有ストアの bootstrap/NN-*.sh を番号順に扱う入口。
#
#   run-all.sh --check   各ステップの --check を流す（root 不要、何も書かない）。
#                        全ステップが一致なら 0、1 本でも食い違えば 1。
#   run-all.sh           （root）食い違うステップだけを番号順に流す。失敗した時点で止まる。
#
# ステップの約束:
#   - ファイル名は bootstrap/NN-*.sh（NN は 2 桁）。run-all.sh / lib.sh / guard.sh は対象外。
#   - 引数 --check: root なしで、共有側が DOTFILES_SRC のピンと一致すれば 0、食い違えば 1。何も書かない。
#   - 引数なし: root で共有側を揃える（冪等）。揃えたら $SHARED_ROOT/dotfiles-shared/keys/NN に
#     pins_key の結果を書く。--check はこのキーとソースから計算したキーを比べる。
#   - 環境変数: DOTFILES_SRC / AQUA_BIN / GITHUB_TOKEN / SHARED_ROOT / DOTFILES_SHARED_FORCE。
#
# git はここでは実行しない。root が利用者のリポジトリへ git を向けると「dubious ownership」で
# 拒否されるため、ダウングレード判定（shared_guard）は呼び出したユーザ側で済ませ、結果を
# DOTFILES_STATE_COMMIT（ok のときの HEAD）で受け取る。空なら state を書かない（force など）。
#
# テスト用の上書き: SHARED_ROOT（既定 /opt）/ BOOTSTRAP_DIR（ステップの置き場）/
# BOOTSTRAP_ALLOW_NONROOT=1（root 確認を省く）。
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"
# shellcheck source-path=SCRIPTDIR source=guard.sh
. "$here/guard.sh"

SHARED_ROOT="${SHARED_ROOT:-/opt}"
BOOTSTRAP_DIR="${BOOTSTRAP_DIR:-$here}"
DOTFILES_SRC="${DOTFILES_SRC:-$(dirname "$here")}"
export SHARED_ROOT DOTFILES_SRC

mode=run
case "${1:-}" in
"") ;;
--check) mode=check ;;
-h | --help)
	echo "使い方: run-all.sh [--check]"
	exit 0
	;;
*)
	echo "不明な引数: $1" >&2
	exit 2
	;;
esac

steps=()
for f in "$BOOTSTRAP_DIR"/[0-9][0-9]-*.sh; do
	[ -f "$f" ] && steps+=("$f")
done

# ステップが無ければ揃えるものも無い。
if [ "${#steps[@]}" -eq 0 ]; then
	exit 0
fi

# 食い違うステップを mismatched に集める。
mismatched=()
for f in "${steps[@]}"; do
	bash "$f" --check >/dev/null || mismatched+=("$f")
done

if [ "$mode" = check ]; then
	[ "${#mismatched[@]}" -eq 0 ]
	exit
fi

if [ "${BOOTSTRAP_ALLOW_NONROOT:-}" != 1 ] && [ "$(id -u)" -ne 0 ]; then
	echo "root で実行してください" >&2
	exit 1
fi

for f in ${mismatched[@]+"${mismatched[@]}"}; do
	name="$(basename "$f")"
	log "$name"
	if ! bash "$f"; then
		warn "$name が失敗しました。以降は実行していません"
		exit 1
	fi
	# 揃えたあとの --check が通らなければ、キーを書き忘れている。
	if ! bash "$f" --check >/dev/null; then
		warn "$name は実行後も食い違っています（キーを書いていません）"
		exit 1
	fi
done

if [ -n "${DOTFILES_STATE_COMMIT:-}" ]; then
	state_write "$SHARED_ROOT/dotfiles-shared/state" "$DOTFILES_STATE_COMMIT"
fi
