---
name: gh-pr-create
description: |
  現在のブランチから GitHub のプルリクエストを draft で作成する。同じブランチの OPEN な PR があればタイトルと説明を更新する。
  ベースブランチは引数で指定でき、省略時はリポジトリの規約またはデフォルトブランチを使う。本文は PR テンプレートに沿って書く。
  MANDATORY TRIGGERS: /gh-pr-create, PR を作って, プルリクを作成, PR の説明を更新して。
  DO NOT TRIGGER: コミットの作成（git-commit）, PR のレビュー, PR のレビューコメント対応。
allowed-tools: Bash(git branch:*), Bash(git status:*), Bash(git fetch:*), Bash(git log:*), Bash(git diff:*), Bash(gh pr:*), Bash(gh repo view:*), Read, AskUserQuestion
---

# プルリクエスト作成・更新

## コンテキスト

- 現在のブランチ: !`git branch --show-current`
- 最近のコミット履歴: !`git log --oneline -10`
- リポジトリ: !`gh repo view --json nameWithOwner,url,defaultBranchRef -q '"\(.nameWithOwner) \(.url) default=\(.defaultBranchRef.name)"'`

## タスク

現在のブランチからベースブランチへのプルリクエスト（PR）を作成または更新してください。
既にPRが存在し、かつOPEN状態の場合は、新しいPRを作成するのではなく、既存のPRのタイトルと説明を更新します。
PRが存在しない場合、またはMERGED/CLOSED状態の場合は、新規PRを作成します。

## 入力

$ARGUMENTS から次を受け取る。

- **ベースブランチ**（例: `/gh-pr-create develop`、`--base main`）。省略時は次の順で決める:
  1. リポジトリの `CLAUDE.md` / `AGENTS.md` / `CONTRIBUTING.md` に PR のマージ先（統合ブランチ）が書かれていればそれ
  2. リポジトリのデフォルトブランチ（上のコンテキストの `default=`）
- **draft にしない指定**（`--ready` など）。省略時は draft で作成する
- そのほか、関連リンク（Jira・Confluence など）やレビュアーの指定があれば反映する

以降、決まったベースブランチを `<base>` と書く。

## リポジトリの規約を先に読む

タイトル・本文の書き方は、**対象リポジトリの規約を最優先**する。

1. PR テンプレート: `.github/PULL_REQUEST_TEMPLATE.md` / `.github/pull_request_template.md` / `.github/PULL_REQUEST_TEMPLATE/*.md` / `docs/pull_request_template.md` / ルートの `pull_request_template.md`。複数ある場合はどれを使うか AskUserQuestion で確認する
2. リポジトリの `CLAUDE.md` / `AGENTS.md` / `CONTRIBUTING.md` にある PR・用語・表記の規約。そこから参照されている記述ルールなどが PR の書き方に関わるなら、それも読む
3. 既存の PR（`gh pr list --state merged --limit 5 --json title,body`）のタイトルと本文の書き方

## 実行手順

### 1. 事前確認

- 現在のブランチが `<base>` やデフォルトブランチの場合はエラーを表示して終了
- `git status` でコミットされていない変更がないか確認
  - 未コミットの変更がある場合は警告を表示し、`/git-commit` でのコミットを促す

### 2. リモートの最新状態を確認

- `git fetch origin` でリモートの最新情報を取得
- `git log origin/<base>..HEAD --oneline` と `git diff origin/<base>...HEAD --stat` で差分を確認
- コミットがない場合は警告を表示して終了
- 現在のブランチが未 push、またはリモートより進んでいる場合は、push するか AskUserQuestion で確認する（`gh pr create` は push 済みのブランチを前提にする）

### 3. 既存PRの確認

- `gh pr view --json number,title,url,state,baseRefName` で現在のブランチのPRが既に存在するか確認
  - 状態が `OPEN` の場合: 既存のPR情報を取得し、更新フローに進む。`baseRefName` が `<base>` と違う場合は、ベースを変えるか AskUserQuestion で確認する
  - PRが存在しない場合、または `CLOSED` / `MERGED` の場合: 新規作成フローに進む

### 4. PRタイトルの生成

- リポジトリの規約・既存 PR のタイトルの書き方に合わせる
- 規約が無ければ、ブランチ名とコミット履歴から全体の変更を要約し、既存 PR と同じ言語で簡潔に書く（日本語なら 50 文字程度）

**例:**
- `feat/add-user-search` → "ユーザー一覧に検索機能を追加"
- `fix/cache-key` → "CI のキャッシュキーが更新されない問題を修正"

### 5. PR本文の生成

#### PR テンプレートがある場合

- テンプレートの見出し・項目・チェックリストを残し、各セクションを埋める
- テンプレート内のコメント（`<!-- -->`）に書き方の指示があれば従い、提出する本文からはコメントを消す
- 埋める材料が無い項目は、ユーザーに確認する（関連リンクなど）か、テンプレートの既定のまま残す。推測で埋めない
- デプロイ手順・動作確認などのセクションは、差分（変更したディレクトリやファイル）から必要な手順を具体的に書く

#### PR テンプレートが無い場合

次の最小構成で書く:

```markdown
## 概要
<何のために何を変えたか。主要な変更点を箇条書きで>

## 関連リンク
<関連する issue・チケット・ドキュメント。無ければ「なし」>

## 備考
<レビュアーに伝えたい補足。無ければ「なし」>
```

関連リンクは、ユーザーに関連する issue・Jira チケット・Confluence ページの有無を確認して記載する。

#### 本文全体の書き方

リポジトリの規約に関係なく守る。

- **段落の途中で改行しない。** GitHub は 1 つの改行をそのまま改行として表示するので、1 段落は 1 行で書き、段落の区切りにだけ空行を入れる（表示時に自動で折り返される）
- **Claude Code のセッション URL（`https://claude.ai/...` の会話へのリンク）を書かない。** PR は公開される場所で、URL を知る者がセッションの非公開のやり取りを閲覧できてしまう。投稿前に本文に紛れていないか確かめる
- **`#番号` はこのリポジトリの PR・issue を指すときだけ使う。** GitHub は `#番号` をこのリポジトリの PR・issue への自動リンクにするため、ほかのものに使うと無関係な PR・issue に飛ぶ
  - 同じ GitHub (Enterprise) の別リポジトリは `owner/repo#番号`
  - 別ホストのリポジトリ（github.com の upstream など）と workflow の run は URL
  - 節・ステップ・項目の番号に `#` を使わない（`ステップ 7`、`1.5` のように書く）
- **skip ci 系のマーカー（角括弧で囲んだ `skip ci` など）を書かない。** マーカーに触れるときは「skip ci 系のマーカー」のように崩して書く

### 6. PRの作成または更新

#### 新規作成

```bash
gh pr create \
  --base <base> \
  --draft \
  --title "PRタイトル" \
  --body "$(cat <<'EOF'
（生成した本文）
EOF
)"
```

- draft にしない指定があれば `--draft` を外す
- レビュアーの指定があれば `--reviewer` を付ける

#### 既存のOPENなPRを更新

```bash
gh pr edit <PR番号> \
  --title "PRタイトル" \
  --body "$(cat <<'EOF'
（生成した本文）
EOF
)"
```

- タイトルと説明（body）を最新のコミット履歴に基づいて更新する
- タイトルが既に変更内容を適切に表している場合は、`--title` を省略して元のタイトルを維持してよい
- 既存の本文にユーザーが手で書き足した内容（関連リンク、レビュー向けの補足など）があれば、消さずに引き継ぐ

### 7. PR作成/更新後の処理

- 作成・更新したPRのURLを表示
- リポジトリに CODEOWNERS（`.github/CODEOWNERS` / `CODEOWNERS` / `docs/CODEOWNERS`）があれば、変更したパスに該当するオーナーを案内する

## エラーハンドリング

以下の場合はエラーメッセージを表示して終了：

1. ベースブランチ・デフォルトブランチ上にいる場合
   - 「ベースブランチからはPRを作成できません。フィーチャーブランチを作成してください。」
2. コミットされていない変更がある場合（ユーザーが続行を選ばなかったとき）
   - 「未コミットの変更があります。先に `/git-commit` でコミットしてください。」
3. ベースブランチとの差分がない場合
   - 「<base> ブランチとの差分がありません。変更をコミットしてからPRを作成してください。」
4. gh コマンドが利用できない、または認証されていない場合
   - 「GitHub CLI が利用できません。`gh auth status` を確認してください。」
