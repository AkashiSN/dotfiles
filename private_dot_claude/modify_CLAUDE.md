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

GitHub の issue・PR・コメントなど**公開される場所**の本文には、Claude Code の
セッション URL（`https://claude.ai/...` などの会話へのリンク）を絶対に含めない。
セッションには非公開のやり取りや作業ログが含まれ、URL を知る者が閲覧できてしまう
ため、外部へ露出させてはならない。生成した本文にこれらの URL が紛れ込んでいないか
投稿前に必ず確認する。

## codex にレビューを依頼するときの手順（agmsg / herdr）

codex へのレビュー依頼は agmsg 経由で行う。**依頼のたびに spawn し、終わったら
必ず片付ける。** チーム名とエージェント名はプロジェクトごとに違うので、
`whoami.sh <project>` かそのプロジェクトのドキュメントで確認する（下の `<team>` は
チーム、`<self>` は自分、`<reviewer>` は codex のレビュー役）。

端末は herdr。spawn は herdr のペインを分割してそこに codex を立てるので、
**herdr のペインの中から実行する**（`HERDR_PANE_ID` が要る）。

### サブスク（OpenAI ログイン）で起動する場合

```bash
S=~/.agents/skills/agmsg/scripts

$S/spawn.sh codex <reviewer> --project "$(pwd)"   # 起動。ペインが開く
$S/delivery.sh status codex "$(pwd)"              # → Codex bridge: ... alive を確認してから送る
$S/send.sh <team> <self> <reviewer> "<依頼>"
$S/despawn.sh <team> <self> <reviewer> --force    # 片付け → status=forced
$S/delivery.sh status codex "$(pwd)"              # → no identities registered for this project
```

### Amazon Bedrock で起動する場合

`spawn.sh` を直接は使わない。`codex-bedrock-spawn`（内部で spawn.sh を呼ぶ）を使う。
確認・送信・片付けはサブスクの場合と同じコマンド。

```bash
S=~/.agents/skills/agmsg/scripts

codex-bedrock-spawn <reviewer>                    # 起動。Bedrock 用のペインが開く
$S/delivery.sh status codex "$(pwd)"              # → Codex bridge: ... alive を確認してから送る
$S/send.sh <team> <self> <reviewer> "<依頼>"
$S/despawn.sh <team> <self> <reviewer> --force    # 片付けは共通 → status=forced
```

**素の `spawn.sh` では Bedrock にならない。** monitor モードでは codex TUI が共有
app-server へ `--remote` で繋がり、モデル解決と認証は app-server 側の設定で決まる。
`--profile` は app-server が受け取らず、`--profile` 相当の環境変数も無いので、
`CODEX_HOME` を Bedrock 用の一時 home へ向けるしかない。`codex-bedrock-spawn` は
その home を用意し、`herdr pane split --env` で流し込んでから spawn する
（`spawn.sh` の herdr パスは `--env` を渡さないので、この差し込みは自前で要る）。

### 共通の注意

**`--force` を最初から付ける。素の graceful を先に打ってはいけない。** graceful な
despawn は actas ロックだけを土台にしているが、codex は `actas-claim` を一度も
走らせないのでロックが常に `free`。graceful は `status=ok note=no-live-lock` を
返して**何も片付けない**うえ、離脱の直前に placement レコードを消す。そのため
続けて `--force` を打っても `no placement record` で失敗し、**二度と force できなく
なる**（順序は一方通行）。

spawn は codex の readiness を待たないので、送る前に bridge の生存を確認する。
起動しっぱなしにすると、codex CLI が終わっても bridge だけが生き残り、
`<reviewer>` 宛に送ったメッセージを黙って飲み込む。

app-server はプロジェクトパスだけでキーされ、設定を見ずに再利用される。同じ
プロジェクトでサブスク版と Bedrock 版を混ぜると、先に起動した側の app-server を
後から起動した側が黙って再利用する。`codex-bedrock-spawn` と zsh の `codex` 関数は
起動前に `codex-appserver-evict` で食い違う app-server を畳むので、**種類を切り替える
ときは開いていた側の codex セッションが切れる**。

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
