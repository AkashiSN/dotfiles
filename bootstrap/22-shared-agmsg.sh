#!/usr/bin/env bash
# agmsg の配布物を $SHARED_ROOT/agmsg/<版> に置き、current をその版へ向ける。root で実行する。
#   22-shared-agmsg.sh --check   共有側が下のピンと一致するか（0 一致 / 1 食い違い）。何も書かない。
#   22-shared-agmsg.sh           tag を取得し、commit を確かめて置き、current を付け替えて、キーを書く。
# 環境変数: DOTFILES_SRC / SHARED_ROOT（既定 /opt）。
#
# 各ユーザは chezmoi apply（run_after_40-ai-assistants）で $SHARED_ROOT/agmsg/current/install.sh を流し、
# 自分の ~/.agents/skills/agmsg へ入れる。install.sh は自分のディレクトリを読むだけで、書くのは
# ユーザ側なので、ここは読み取り専用でよい。
#
# 版は下の 2 行で固定する。Renovate が tag と commit を一緒に上げる（.github/renovate.json）。
# 取得した tag の commit が AGMSG_COMMIT と違えば、置かずに非 0 で終わる。
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"

AGMSG_VERSION="1.5.0"
AGMSG_COMMIT="c487be269c1973aeb01ca831806eb3f65ff3366d"

SHARED_ROOT="${SHARED_ROOT:-/opt}"
ROOT="$SHARED_ROOT/agmsg"
DEST="$ROOT/$AGMSG_VERSION"
KEYFILE="$SHARED_ROOT/dotfiles-shared/keys/22"
COMMIT_FILE=.agmsg-commit
REPO_URL=https://github.com/fujibee/agmsg.git

src_key() {
	pins_key <(printf 'agmsg-1\n%s\n%s\n' "$AGMSG_VERSION" "$AGMSG_COMMIT")
}

if [ "${1:-}" = "--check" ]; then
	[ -f "$KEYFILE" ] && [ "$(cat "$KEYFILE")" = "$(src_key)" ]
	exit
fi

if [ "${BOOTSTRAP_ALLOW_NONROOT:-}" != 1 ] && [ "$(id -u)" -ne 0 ]; then
	echo "root で実行してください" >&2
	exit 1
fi

umask 022
owner_group="$(shared_owner_group)"
# root のときだけ所有者を揃える（テストは一般ユーザで流す）。
set_owner() {
	[ "$(id -u)" -ne 0 ] || chown "$@"
}

# 作業ディレクトリの設定を拾わないよう、ルートへ移る。
cd /

log "共有ディレクトリ ${ROOT} を準備 (${owner_group})"
mkdir -p "$ROOT"
set_owner "$owner_group" "$ROOT"
chmod 755 "$ROOT"

# いま current が指している版（付け替え後に 1 つ前として残す）。
prev=""
[ ! -L "$ROOT/current" ] || prev="$(readlink "$ROOT/current")"

# <版> の下で動いているプロセスがあるか。agmsg は bash のスクリプトで動くので、ps の引数にパスが出る。
version_busy() {
	running_from_any "$ROOT/$1" && return 0
	running_args_matching "/agmsg/$1/" && return 0
	return 1
}

if [ -f "$DEST/$COMMIT_FILE" ] && [ "$(cat "$DEST/$COMMIT_FILE")" = "$AGMSG_COMMIT" ]; then
	log "agmsg $AGMSG_VERSION は配置済み"
else
	log "agmsg $AGMSG_VERSION を取得 (v$AGMSG_VERSION = $AGMSG_COMMIT)"
	tmp="$(mktemp -d "$ROOT/.tmp.XXXXXX")"
	trap 'rm -rf "$tmp"' EXIT
	git -c advice.detachedHead=false clone -q --depth 1 --branch "v$AGMSG_VERSION" "$REPO_URL" "$tmp/src"
	got="$(git -C "$tmp/src" rev-parse HEAD)"
	if [ "$got" != "$AGMSG_COMMIT" ]; then
		echo "v$AGMSG_VERSION の commit が宣言と違います（宣言: ${AGMSG_COMMIT} / 取得: ${got}）。置きません" >&2
		exit 1
	fi
	if [ ! -x "$tmp/src/install.sh" ] || [ ! -f "$tmp/src/VERSION" ]; then
		echo "取得した配布物に install.sh か VERSION がありません。置きません" >&2
		exit 1
	fi
	# 各ユーザの git から見ると他人 (root) の checkout になり safe.directory で弾かれるので、
	# .git は持たない。install.sh は VERSION ファイルから版を読む。
	rm -rf "$tmp/src/.git"
	printf '%s\n' "$AGMSG_COMMIT" >"$tmp/src/$COMMIT_FILE"
	set_owner -R "$owner_group" "$tmp/src"
	chmod -R a+rX,go-w "$tmp/src"
	if [ -e "$DEST" ]; then
		# 同じ版で commit が違う（再タグなど）。動いているなら置き換えない。
		if version_busy "$AGMSG_VERSION"; then
			echo "$DEST が使用中のため置き換えられません。止まってから再実行してください" >&2
			exit 1
		fi
		rm -rf "$DEST"
	fi
	mv "$tmp/src" "$DEST"
	rm -rf "$tmp"
	trap - EXIT
fi

log "current を $AGMSG_VERSION に向ける"
swap_symlink "$AGMSG_VERSION" "$ROOT/current"
mkdir -p "$(dirname "$KEYFILE")"
src_key >"$KEYFILE"

log "使わなくなった版を削除"
# 現行と 1 つ前は残す。各ユーザの導入物は ~/.agents/skills/agmsg への複製なので、古い版を消しても動き続ける。
# 動いているプロセス（install.sh や watch.sh など）があれば消さず、次回に回す。
for d in "$ROOT"/*/; do
	d="${d%/}"
	[ -L "$d" ] && continue
	v="$(basename "$d")"
	[ "$v" = "$AGMSG_VERSION" ] && continue
	[ -n "$prev" ] && [ "$v" = "$prev" ] && continue
	if version_busy "$v"; then
		note "使用中のため残します: $d"
		continue
	fi
	note "削除: $d"
	rm -rf "$d"
done

log "完了: agmsg $AGMSG_VERSION を ${ROOT}/current に置きました"
note "各ユーザは chezmoi apply で ~/.agents/skills/agmsg へ入ります"
