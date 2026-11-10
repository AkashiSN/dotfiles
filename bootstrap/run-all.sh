#!/usr/bin/env bash
# 共有ストアの bootstrap/NN-*.sh を番号順に扱う入口。
#
#   run-all.sh --check   各ステップの --check を流す（root 不要、何も書かない）。
#                        全ステップが一致なら 0、1 本でも不一致なら 1。
#   run-all.sh           （root）不一致のステップだけを番号順に流す。1 本が失敗しても後続は流し、
#                        失敗があれば state を書かずに 1 で終わる。
#
# ステップの約束:
#   - ファイル名は bootstrap/NN-*.sh（NN は 2 桁）。run-all.sh / lib.sh / guard.sh は対象外。
#   - 引数 --check: root なしで、共有側が DOTFILES_SRC のピンと一致すれば 0、食い違えば 1。何も書かない。
#     1 以外の非 0 はステップ自身の異常として警告し（終了コードを表示）、不一致として数える。
#   - 引数なし: root で共有側を揃える（冪等）。揃えたら $SHARED_ROOT/dotfiles-shared/keys/NN に
#     pins_key の結果を書く。--check はこのキーとソースから計算したキーを比べる。
#   - 環境変数: DOTFILES_SRC / AQUA_BIN / GITHUB_TOKEN / SHARED_ROOT / DOTFILES_SHARED_FORCE。
#   - 使用中で消せなかったものがあれば gc_defer（lib.sh）で $SHARED_ROOT/dotfiles-shared/pending/NN を置く。
#     --check が 0 でも pending/NN があれば不一致として数え、次の apply でステップを流し直す。
#     ステップを流す前に pending/NN を外す（また使用中なら、ステップが置き直す）。
#
# git はここでは実行しない。root が利用者のリポジトリへ git を向けると「dubious ownership」で
# 拒否されるため、ダウングレード判定（shared_guard）は呼び出したユーザ側で済ませ、結果を
# DOTFILES_STATE_COMMIT（ok のときの HEAD）で受け取る。空なら state を書かない（force など）。
#
# テスト用の上書き: SHARED_ROOT（既定 /opt）/ BOOTSTRAP_DIR（ステップの置き場）/
# BOOTSTRAP_ALLOW_NONROOT=1（root 確認を省く）/ BOOTSTRAP_ROOT_HOME（ステップに渡す HOME）。
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

PENDING="$SHARED_ROOT/dotfiles-shared/pending"
# step_pending <step のパス>: そのステップに消し残し（pending/NN）があれば 0。
step_pending() {
	local nn
	nn="$(basename "$1")"
	[ -e "$PENDING/${nn%%-*}" ]
}

# 不一致のステップを mismatched に集める。--check の 1 は食い違い、それ以外の非 0 は異常。
# --check が 0 でも消し残しがあれば、掃除をやり直すため不一致として数える。
mismatched=()
for f in "${steps[@]}"; do
	rc=0
	bash "$f" --check >/dev/null || rc=$?
	case "$rc" in
	0) step_pending "$f" && mismatched+=("$f") ;;
	1) mismatched+=("$f") ;;
	*)
		warn "$(basename "$f") の --check が異常終了しました (終了コード $rc)。不一致として扱います"
		mismatched+=("$f")
		;;
	esac
done

if [ "$mode" = check ]; then
	[ "${#mismatched[@]}" -eq 0 ]
	exit
fi

if [ "${BOOTSTRAP_ALLOW_NONROOT:-}" != 1 ] && [ "$(id -u)" -ne 0 ]; then
	echo "root で実行してください" >&2
	exit 1
fi

# sudo --preserve-env は呼び出したユーザの HOME と SSH_AUTH_SOCK を持ち込む。root のステップが
# そのユーザの ~/.gitconfig（https の ssh 書き換えや 1Password の署名）や ssh-agent を拾わないよう、
# HOME を root のものに替え、SSH_AUTH_SOCK を外す。root でないとき（テスト）は、
# BOOTSTRAP_ROOT_HOME があるときだけ HOME を替える。
root_home="${BOOTSTRAP_ROOT_HOME:-}"
if [ -z "$root_home" ] && [ "$(id -u)" -eq 0 ]; then
	root_home="$(eval echo "~$(id -un)" 2>/dev/null || true)"
	case "$root_home" in
	/*) ;;
	*)
		case "$(uname -s)" in
		Darwin) root_home=/var/root ;;
		*) root_home=/root ;;
		esac
		;;
	esac
fi
[ -z "$root_home" ] || export HOME="$root_home"
unset SSH_AUTH_SOCK

failed=0
for f in ${mismatched[@]+"${mismatched[@]}"}; do
	name="$(basename "$f")"
	log "$name"
	rm -f "$PENDING/${name%%-*}"
	if ! bash "$f"; then
		warn "$name が失敗しました。後続のステップは続けます"
		failed=1
		continue
	fi
	# 揃えたあとの --check が通らなければ、キーを書き忘れている。
	if ! bash "$f" --check >/dev/null; then
		warn "$name は実行後も食い違っています（キーを書いていません）"
		failed=1
	fi
done

# 1 本でも失敗したら state は進めず、次の apply でやり直す。
[ "$failed" -eq 0 ] || exit 1

if [ -n "${DOTFILES_STATE_COMMIT:-}" ]; then
	state_write "$SHARED_ROOT/dotfiles-shared/state" "$DOTFILES_STATE_COMMIT"
fi
