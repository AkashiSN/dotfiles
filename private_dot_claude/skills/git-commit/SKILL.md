---
name: git-commit
description: |
  変更内容から適切なコミットメッセージを考えて git コミットを作成し、確認のうえリモートへ push する。
  デフォルトブランチ上ならフィーチャーブランチを切ってからコミットする。
  コミットメッセージの書き方は対象リポジトリの CLAUDE.md などの規約と git log に合わせる。
  MANDATORY TRIGGERS: /git-commit, コミットして, コミットを作って, commit して push。
  DO NOT TRIGGER: PR の作成（gh-pr-create）, コミットメッセージの添削だけ。
allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git commit:*), Bash(git diff:*), Bash(git branch:*), Bash(git checkout:*), Bash(git switch:*), Bash(git push:*), Bash(git log:*), Bash(gh repo view:*), Read, AskUserQuestion
---

# git コミット作成

## コンテキスト

- 現在のgitステータス: !`git status`
- 変更差分（ステージ済み・未ステージ）: !`git diff HEAD`
- 現在のブランチ: !`git branch --show-current`
- 最近のコミット履歴: !`git log --oneline -20`

## タスク

上記の変更内容に基づいて、適切なコミットメッセージを考えて単一のgitコミットを作成してください。
ただし、対象が全く異なるなど分割した方が良い場合は分割を提案してください。

$ARGUMENTS にブランチ名・コミットメッセージの方針・対象ファイルなどの指定があれば、それに従ってください。

## リポジトリの規約を先に読む

コミットメッセージとブランチ名は、**対象リポジトリの規約を最優先**する。次の順に確認し、見つかった規約に従う。このスキルの「既定の書き方」は、リポジトリに規約が無い部分を埋めるためのものである。

1. リポジトリの `CLAUDE.md` / `AGENTS.md`（ルートと、変更したファイルのあるディレクトリ）。コミット・ブランチ・用語・表記についての記述を拾う。そこから参照されている文書（記述ルールなど）が commit / PR の書き方に関わるなら、それも読む
2. `CONTRIBUTING.md` / `.github/CONTRIBUTING.md` / `docs/CONTRIBUTING.md`
3. `git log` の既存コミット: type の種類、scope の付け方（何を scope にしているか）、件名の言語、本文の書き方を真似る

規約が見つからず、既存コミットからも書き方が読み取れない場合は、下の「既定の書き方」を使う。

## 既定の書き方

### 基本フォーマット
```
<type>(<scope>): <subject>

<body>
```

### Type（変更の種類）
- `feat`: 新機能の追加
- `fix`: バグ修正
- `chore`: ビルドプロセスやツールの変更、メンテナンス作業
- `refactor`: リファクタリング（機能変更を伴わないコード改善）
- `docs`: ドキュメントのみの変更
- `style`: コードフォーマットなど（機能に影響しない変更）
- `test`: テストの追加・修正
- `perf`: パフォーマンス改善

### Scope（変更の対象）
- 変更したコンポーネント・ディレクトリ・ツール名など、変更対象が一目で分かる短い名前
- 既存コミットで使われている scope があれば、同じ対象には同じ scope を使う
- 対象が広く 1 つに絞れない場合は省略してよい

### Subject（件名）
- 既存コミットと同じ言語で簡潔に記述（日本語なら 50 文字以内推奨）
- 何をしたかを明確に

### Body（本文）- オプション
- 必要に応じて変更の理由や詳細を記述
- 複数の変更がある場合は箇条書きで列挙

### 例
```
feat(api): ユーザー一覧に検索条件を追加

- 名前の部分一致で絞り込めるようにする
- 該当 0 件のときは空配列を返す
```

```
fix(ci): キャッシュキーにロックファイルのハッシュを含める
```

## 書いてはいけないもの

リポジトリの規約に関係なく守る。

- **skip ci 系のマーカー（角括弧で囲んだ `skip ci` / `ci skip` / `no ci` / `skip actions` / `actions skip`）を、件名にも本文にも書かない。** GitHub は本文まで走査し、そのコミットが HEAD の間は `push` / `pull_request` の run が一切作られない。マーカーに触れる説明を書くときは「skip ci 系のマーカー」のように崩して書く
- **`#番号` はこのリポジトリの PR・issue を指すときだけ使う。** GitHub は `#番号` をこのリポジトリの PR・issue への自動リンクにするため、ほかのものに使うと無関係な PR・issue に飛ぶ
  - 同じ GitHub (Enterprise) の別リポジトリは `owner/repo#番号`
  - 別ホストのリポジトリ（github.com の upstream など）と workflow の run は URL
  - 節・ステップ・項目の番号に `#` を使わない（`ステップ 7`、`1.5` のように書く）
- **Claude Code のセッション URL（`https://claude.ai/...` の会話へのリンク）を書かない。**

## 実行手順

1. **現在のブランチを確認する**
   - デフォルトブランチは `gh repo view --json defaultBranchRef -q .defaultBranchRef.name` で確認する（`gh` が使えなければ `git symbolic-ref refs/remotes/origin/HEAD`）。リポジトリの規約に統合ブランチ（`develop` など）が書かれていれば、それも直接コミットしないブランチとして扱う
   - **デフォルトブランチ・統合ブランチでは直接コミットしない。** 該当する場合:
     - 変更内容とリポジトリの命名規則に基づいてブランチ名を決める（規則が無ければ下の「ブランチ命名の既定」）
     - `git switch -c <新しいブランチ名>` で新しいフィーチャーブランチを作成
   - ただし、リポジトリの規約がデフォルトブランチへの直接コミットを認めている場合（個人の dotfiles など）や、ユーザーがそう指示した場合はそのまま続行する
   - フィーチャーブランチにいる場合: そのまま続行

2. 変更されたファイルを確認し、変更の内容と目的を理解する

3. 上記の規約に従ってコミットメッセージを作成する

4. 関連するファイルを `git add` でステージングする
   - パスを指定して add し、このコミットに関係しないファイルを混ぜない（`git add -A` / `git add .` は使わない）
   - `.gitignore` 済みのファイル（`.superpowers/` や `docs/superpowers/` などの作業用ファイル）を `git add -f` で入れない
   - `git diff --cached --name-only` でステージ内容を確かめてからコミットする

5. 作成したコミットメッセージで `git commit` を実行する（pre-commit フックが失敗したら、原因を直して新しくコミットし直す。`--no-verify` で回避しない）

6. コミット後、`git status` で結果を確認する

7. **リモートへのpush**
   - コミット完了後、ユーザーにpushするかどうかをAskUserQuestionツールで確認する
   - pushする場合:
     - upstream が無いブランチ: `git push -u origin <ブランチ名>`
     - 既存のブランチ: `git push`
   - push完了後、ブランチのリモートURLを表示

## ブランチ命名の既定

リポジトリに命名規則が無い場合に使う。小文字とハイフンで、簡潔で内容が分かる名前にする。

- `feat/<機能名>` - 新機能追加（例: `feat/add-user-search`）
- `fix/<修正内容>` - バグ修正（例: `fix/cache-key`）
- `docs/<ドキュメント名>` - ドキュメント更新（例: `docs/update-readme`）
- `chore/<作業内容>` - メンテナンス作業（例: `chore/bump-node`）
- `refactor/<対象>` - リファクタリング（例: `refactor/auth-module`）
