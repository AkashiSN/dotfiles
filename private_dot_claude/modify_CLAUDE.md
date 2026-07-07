#!/bin/sh
# chezmoi modify_ script for ~/.claude/CLAUDE.md
#
# このファイルには 2 つの書き手がいる:
#   1. ユーザの手書きグローバルルール（このスクリプト内で管理）
#   2. `codegraph install` が <!-- CODEGRAPH_START --> 〜 END に注入するブロック
# 単純な静的ファイルにすると codegraph の再注入と chezmoi が衝突するため、
# modify_ スクリプトでユーザ部分のみを強制し、codegraph ブロックは現物
# （stdin = 適用先の現在の内容）からそのまま引き継ぐ。
set -eu

# --- ユーザの手書きグローバルルール（ここを編集する） -------------------------
USER_BLOCK=$(cat <<'EOF'
## issue / PR の本文を書くときの改行

GitHub の issue・PR の説明文やコメントなど、**1 改行がそのまま改行として
レンダリングされる Markdown** を出力するときは、見やすさのために文の途中で改行を
入れない。1 段落は改行せず 1 行で書き、段落の区切りにだけ空行を入れる。
（GitHub は表示時に自動で折り返すため、手動の wrap は不要かつ意図しない改行になる）

ただしコミットメッセージ・コード内コメント・プレーンテキストなど、改行幅が意味を
持つ場所では従来どおり適切に折り返してよい。

## 公開場所に Claude セッション URL を書かない

GitHub の issue・PR・コメントなど**公開される場所**の本文には、Claude Code の
セッション URL（`https://claude.ai/...` などの会話へのリンク）を絶対に含めない。
セッションには非公開のやり取りや作業ログが含まれ、URL を知る者が閲覧できてしまう
ため、外部へ露出させてはならない。生成した本文にこれらの URL が紛れ込んでいないか
投稿前に必ず確認する。
EOF
)
# -----------------------------------------------------------------------------

# 適用先の現在の内容（codegraph ブロックを含む可能性）を読み取る。
INPUT=$(cat)
# codegraph ブロックをマーカーごと抽出（無ければ空）。
CODEGRAPH_BLOCK=$(printf '%s\n' "$INPUT" | awk '/<!-- CODEGRAPH_START -->/,/<!-- CODEGRAPH_END -->/')

printf '%s\n' "$USER_BLOCK"
if [ -n "$CODEGRAPH_BLOCK" ]; then
	printf '\n%s\n' "$CODEGRAPH_BLOCK"
fi
