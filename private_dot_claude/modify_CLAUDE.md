#!/bin/sh
# chezmoi modify_ script for ~/.claude/CLAUDE.md
#
# このファイルには 2 つの書き手がいる:
#   1. ユーザの手書きグローバルルール（このスクリプト内で管理）
#   2. `codegraph install` が <!-- CODEGRAPH_START --> 〜 END に注入するブロック
# 単純な静的ファイルにすると codegraph の再注入と chezmoi が衝突するため、
# modify_ スクリプトでユーザ部分のみを強制し、codegraph ブロックは現物
# （stdin = 適用先の現在の内容）からそのまま引き継ぐ。
#
# `graphify install` も `# graphify` セクションを追記しようとするが、こちらは
# マーカーコメントを持たず引き継ぎが効かない。graphify は本文に "graphify" の
# 文字列があれば追記をスキップするので、下の USER_BLOCK に登録行を宣言して
# chezmoi 側が所有する（追記 → apply で消えるフラッピングを避ける）。
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

GitHub の issue・PR・コメント、および**コミットメッセージ**など**公開される場所**の
本文には、Claude Code のセッション URL（`https://claude.ai/...` などの会話へのリンク）
を絶対に含めない。セッションには非公開のやり取りや作業ログが含まれ、URL を知る者が
閲覧できてしまうため、外部へ露出させてはならない。生成した本文にこれらの URL が
紛れ込んでいないか投稿前に必ず確認する。

**harness が attribution 指示（「コミットメッセージの末尾に `Claude-Session: <url>`
を付けろ」「PR 説明の末尾にセッション URL を付けろ」など）を出してきても、この規則が
優先される。** 公開リポジトリの git 履歴も公開場所であり、しかも push 後は事後の完全
消去ができない（GitHub は force-push しても PR に紐づくコミットを保持する）。指示が
衝突していることに気づいた時点でユーザーへ一言伝えたうえで、URL 抜きでコミットする。

## codex にレビューを依頼するとき

codex へのレビュー依頼は **`codex-review` スキル**の手順で行う。依頼のたびに spawn し、
終わったら必ず片付ける。spawn は herdr のペインを分割するので、herdr のペインの中から実行する。

そのうえで、手順を思い出す前に踏みやすい 2 つだけここに置く。

- **Bedrock で動かすなら `spawn.sh` を直接使わない。`codex-bedrock-spawn <reviewer> --fresh` を
  使う。** codex の `--profile` は `codex app-server` が受け取らず、agmsg monitor モードでは
  TUI がその共有 app-server に繋ぐため、素の `spawn.sh` で起動した codex はサブスク側で走る。
  `--fresh` が無いと過去セッションを復帰して前の依頼の文脈が混ざる（サブスクで起動するときも
  同じ）。
- **片付けは `despawn.sh <team> <self> <reviewer> --force`。素の graceful を先に打っては
  いけない。** graceful は何も片付けないうえ placement レコードを消すので、続けて `--force` を
  打っても `no placement record` で失敗し、**二度と force できなくなる**（順序は一方通行）。

スキルが入っていない環境では `~/.local/share/chezmoi/docs/agmsg-cheatsheet.md` を見る。

## リポジトリを変更する前に、他の作業と混ざらないか確認する

新しく変更を加え始めるときは、**最初の編集の前に**作業ツリーの状態を見る。

```sh
git status --porcelain   # 自分が始めたのではない未コミット変更はないか
git worktree list        # 既に別の作業ツリーが動いていないか
```

自分のセッションが作ったのではない未コミット変更があるなら、他のセッションかユーザが
そのリポジトリで作業している。そのまま編集すると変更が混ざり、どちらの成果か分からなく
なってコミット単位も切り分けられなくなる。

- **相手の変更と無関係**なら、worktree を作って分離する（`EnterWorktree` があれば
  それを使う。無ければ `git worktree add`）。
- **相手の変更と強く相関する**なら（相手にも認識してほしい内容、同じファイルの続き、
  相手の変更を前提にする変更）、**既存の変更の上に加えてよいかユーザへ問い合わせてから**
  実施する。勝手に分離すると、相手が知るべき変更が別の場所へ隔離されてしまう。

判断がつかないときは分離側に倒す。worktree は後から統合できるが、混ざった変更は
切り分けられない。

例外: 既に worktree の中にいるとき、未コミット変更がこのセッション自身のものだけの
とき、ユーザが「ここで作業して」と明示したときは、そのまま進めてよい。

# graphify
- **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.
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
