#!/usr/bin/env bash
# agmsg (https://github.com/fujibee/agmsg) を再現的に導入する。
# claude(Claude Code) と codex が同一プロジェクト内でメッセージをやり取りし、
# 相互レビューできるようにするためのツール。nvim の IDE モード(ide.lua)で
# codex/claude ペインを並べて使う運用を想定している。
#
# agmsg は chezmoi 管理外のディレクトリ(~/.agents/skills, ~/.claude/commands,
# 既存なら ~/.codex/config.toml)を書き換えるため、dotfiles では「ソースを
# 展開する」のではなく、この run スクリプトで公式 install.sh を実行して導入する。
#
# run_onchange_: このスクリプトの内容が変わったときだけ再実行される。
# agmsg 本体を更新したいときは下の AGMSG_REF を書き換える(= 内容が変わるので再実行)。
#
# AGMSG_REF: main
set -euo pipefail

REPO_URL="https://github.com/fujibee/agmsg.git"
SRC_DIR="${HOME}/.local/share/agmsg-src"
SKILL_DIR="${HOME}/.agents/skills/agmsg"

# sqlite3 が無いと agmsg のメッセージ DB を作れない。macOS は標準搭載だが念のため確認。
if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "agmsg: sqlite3 が見つかりません。インストールしてから再実行してください。" >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "agmsg: git が見つかりません。" >&2
  exit 1
fi

# ソースを取得 / 更新
if [ -d "${SRC_DIR}/.git" ]; then
  echo "agmsg: 既存ソースを更新 (${SRC_DIR})"
  git -C "${SRC_DIR}" pull --ff-only
else
  echo "agmsg: ソースを取得 (${SRC_DIR})"
  git clone "${REPO_URL}" "${SRC_DIR}"
fi

# install.sh は非対話 --cmd agmsg で実行。既存インストールがあれば
# --update でスクリプトのみ更新し、DB / teams 設定は保持する。
cd "${SRC_DIR}"
if [ -d "${SKILL_DIR}" ]; then
  echo "agmsg: 既存インストールを更新 (--update)"
  ./install.sh --cmd agmsg --update
else
  echo "agmsg: 新規インストール (--cmd agmsg)"
  ./install.sh --cmd agmsg
fi

echo "agmsg: 完了。各プロジェクトで Claude Code は /agmsg、Codex は \$agmsg を一度実行してチームに参加してください。"
