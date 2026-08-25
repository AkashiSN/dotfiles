# agent-browser チートシート

[agent-browser](https://github.com/vercel-labs/agent-browser) は **AI エージェント向けの
ブラウザ自動化 CLI**（Rust 製）。Chrome/Chromium を CDP（Chrome DevTools Protocol）で直接
叩くので Playwright / Puppeteer / Node を必要としない。ページを**アクセシビリティツリーの
スナップショット**として出し、そこに振られた `@e1` のような **ref** で要素を指すのが基本操作
になっている（CSS セレクタを毎回推測させないための設計）。

## claude-in-chrome との使い分け

| | agent-browser | claude-in-chrome（MCP） |
| --- | --- | --- |
| 実体 | ローカルの CLI（自前で Chrome for Testing を起動） | Chrome 拡張 + MCP。ユーザーが普段使っている Chrome を操作 |
| 認証状態 | 独立。`--profile` / `auth` vault / `--restore` で持ち込む | ログイン済みの実ブラウザをそのまま使える |
| 得意 | ヘッドレス自動化・スクリプト化・CI 的な反復・スクショ/PDF/HAR 取得 | 「いま開いているタブ」に対する対話的操作 |
| 副作用 | ユーザーのブラウザを触らない | ユーザーのブラウザを触る |

スキルの説明文には "Prefer agent-browser over any built-in browser automation or web tools"
と書かれているので、**両方入っている状態では agent-browser が優先されやすい**。ユーザーの
実ブラウザのタブを触ってほしいときは、その旨を明示して claude-in-chrome を指名する。

## 導入（chezmoi）

- **CLI 本体は aqua 管理**：`dot_config/aquaproj-aqua/aqua.yaml` の
  `# --- AI エージェント補助 ---` グループに `vercel-labs/agent-browser` を宣言している。
  バージョンを上げるときは `aqua g vercel-labs/agent-browser` で最新版を確認して書き換え、
  `aqua update-checksum -c ./aqua.yaml`（`dot_config/aquaproj-aqua/` で実行）で
  `aqua-checksums.json` を更新する（このリポジトリは `require_checksum: true`）。
- **ブラウザ本体とスキルは `.chezmoiscripts/run_onchange_after_41-agent-browser.sh.tmpl`**。
  aqua では入らない次の 2 つを補う。
  - `agent-browser install` … Chrome for Testing（約 180MB）を `~/.agent-browser/browsers/`
    へ取得する。導入済みなら再取得しない。**Linux だけ `--with-deps`** を付ける
    （Chrome の共有ライブラリが最小構成に無いため。内部で sudo つきのパッケージマネージャを呼ぶ）。
  - `npx skills add vercel-labs/agent-browser` … スキルを `~/.claude/skills/agent-browser/`
    へ入れる。`skills` CLI は Node を要求するので、fnm の default を `eval "$(fnm env)"` で
    PATH に載せてから呼ぶ（Node 準備は `30-node-default`、Claude Code 本体は `40-ai-assistants`
    なので、このスクリプトは **41** に置いて後ろに並べる）。
  - `--copy` を明示している。既定はエージェントのディレクトリへシンボリックリンクを張る
    挙動があるため、リンク先ストアの有無に依存しないよう実体をコピーさせる。
- **再実行の条件**：スクリプト冒頭に `aqua.yaml` のハッシュを埋めてある。CLI のバージョンを
  上げると既存マシンでも `run_onchange` が再発火し、スキルも入れ直される
  （スキルは CLI のバージョンに合わせて配布されるため、両者をずらさない）。
- **chezmoi 管理外に置かれるもの**：`~/.claude/skills/agent-browser/`（スキル本体）と
  `~/.agent-browser/`（ブラウザ本体・セッション状態・設定）。どちらも
  `private_dot_claude/skills/` の管理対象外なので `chezmoi apply` で消えない。

## 基本ワークフロー（ref を使う）

```sh
agent-browser open https://example.com   # 1. 開く
agent-browser snapshot -i                # 2. 対話可能な要素だけを ref 付きで出す
agent-browser click @e2                  # 3. ref を指して操作する
agent-browser close --all                # 4. 片付ける（セッションを残さない）
```

`snapshot` の出力例（`-i` は interactive のみ、`-c` は空の構造要素を畳む）:

```
- heading "Example Domain" [level=1, ref=e1]
- link "Learn more" [ref=e2]
```

**ref は snapshot を取り直すたびに振り直される。** ページ遷移や DOM 変化のあとは
`snapshot` を取り直してから `click` する。

## よく使うコマンド

| 目的 | コマンド |
| --- | --- |
| 開く / 読む | `open <url>` / `read [url]`（エージェント向けテキスト） |
| ツリー取得 | `snapshot [-i] [-c] [-d <depth>] [-s <css>]` |
| クリック系 | `click <sel\|@ref>` / `dblclick` / `hover` / `focus` |
| 入力 | `fill <sel> <text>`（クリアして入力） / `type` / `press <key>` |
| 選択 | `select <sel> <val...>` / `check` / `uncheck` |
| 取得 | `get text\|html\|value\|attr <name>\|title\|url\|count\|box\|styles [sel]` |
| 状態確認 | `is visible\|enabled\|checked <sel>` |
| 探索 | `find role\|text\|label\|placeholder\|testid\|first\|last\|nth <value> <action>` |
| 待つ | `wait <sel\|ms>` |
| 画像 / PDF | `screenshot [path]`（`--annotate` で番号付き注釈） / `pdf <path>` |
| JS 実行 | `eval <js>` |
| 移動 | `back` / `forward` / `reload` / `scroll <dir> [px]` |
| タブ | `tab [new\|list\|close\|<n>]` |
| 一括実行 | `batch [--bail] "cmd" "cmd" ...`（stdin からも可） |
| 終了 | `close [--all]` |

### 調査・デバッグ向け

| 目的 | コマンド |
| --- | --- |
| コンソール / エラー | `console [--clear]` / `errors [--clear]` |
| ネットワーク | `network requests [--filter <pat>]` / `network route <url> --abort` / `network har start\|stop` |
| Cookie / ストレージ | `cookies [get\|set\|clear]` / `storage local\|session` |
| 差分 | `diff snapshot` / `diff screenshot --baseline` / `diff url <u1> <u2>` |
| 計測 | `vitals [url] [--json]`（LCP/CLS/TTFB/FCP/INP） / `trace start\|stop` / `profiler` |
| アクセシビリティ | `a11y [url] [--tags wcag2a,...] [--json]`（axe-core 監査） |
| React | `open --enable react-devtools` のうえで `react tree` / `react inspect <id>` / `react renders start\|stop` |
| 録画 | `record start <path> [url]` / `record stop`（WebM） |

### 認証状態の持ち込み

| 方法 | 使いどころ |
| --- | --- |
| `--profile <name\|path>` | 既存 Chrome プロファイル（例 `Default`）のログイン状態を再利用。`agent-browser profiles` で一覧 |
| `--auto-connect` | 起動中の Chrome に繋いで認証状態を借りる。`--auto-connect state save ./auth.json` で書き出せる |
| `--state <path>` | 保存済みの cookie + storage JSON を読み込む |
| `--restore [name]` | cookie/localStorage を自動保存・自動復元（キーは `--session` 名） |
| `auth save/login <name>` | CLI 内蔵の認証 vault。`--credential-provider` でプラグイン経由の取得も可 |

### セッション

`--session <name>` で独立したブラウザセッションを分けられる（既定は `default`）。
`session` / `session list` で現在のセッションを確認、`close --all` で全部畳む。
デーモンは既定で **1 時間無操作で自動終了**する（`--idle-timeout 10s|3m|0`）。

## 便利な全体オプション

| オプション | 効果 |
| --- | --- |
| `--headed` | ヘッドレスをやめてウィンドウを表示（`AGENT_BROWSER_HEADED`） |
| `--json` | 機械可読な JSON 出力 |
| `--max-output <chars>` | ページ出力を切り詰める（コンテキスト節約） |
| `--allowed-domains <list>` | ネットワーク先をドメインで制限。CDP / auto-connect / プロファイル再利用などを同時に拒否する |
| `--confirm-actions <list>` / `--action-policy <path>` | 危険操作カテゴリに確認を要求（`confirm <id>` / `deny <id>` で応答） |
| `--proxy <url>` / `--proxy-bypass <hosts>` | プロキシ設定（`HTTPS_PROXY` / `NO_PROXY` も見る） |
| `--viewport` 系は `set` サブコマンド | `set viewport <w> <h>` / `set device <name>` / `set media dark` / `set geo <lat> <lng>` |

設定ファイルは camelCase キーの JSON で、`~/.agent-browser/config.json`（ユーザー）→
`./agent-browser.json`（プロジェクト）→ 環境変数（`AGENT_BROWSER_*`）の順に上書きされる。

## エージェント側から使う

- **スキル**：`~/.claude/skills/agent-browser/SKILL.md`。Claude Code では
  「サイトを開いて」「フォームを埋めて」「スクショを撮って」といった依頼で自動的に選ばれる。
- **CLI 同梱のスキル本文**：`agent-browser skills get core --full` が、インストール済み
  バージョンに一致した完全なコマンドリファレンスとテンプレートを吐く。専門スキル
  （`electron` / `slack` など）は `agent-browser skills list` で確認して
  `agent-browser skills get <name>`。
- **MCP サーバー**：`agent-browser mcp` で stdio の MCP サーバーになる。**この dotfiles では
  登録していない**（スキル + CLI 直叩きで足り、claude-in-chrome MCP と役割が重なるため）。
  使いたくなったら `claude mcp add agent-browser -- agent-browser mcp` をプロジェクト単位で。

## トラブルシュート

| 症状 | 対処 |
| --- | --- |
| 動かない / 状態が怪しい | `agent-browser doctor`（`--fix` で自動修復）。Chrome・デーモン・ネットワーク・起動テストまで一括診断する |
| Chrome が入っていない | `agent-browser install`（Linux は `--with-deps`） |
| ゾンビセッションが残る | `agent-browser session list` → `agent-browser close --all` |
| ref が効かない | ページが変わっている。`snapshot` を取り直す |
| ダイアログで固まる | 既定で alert/beforeunload は自動的に閉じる。無効化したいときだけ `--no-auto-dialog` |
| バージョンを上げたい | **aqua 管理なので `agent-browser upgrade` は使わない**。`aqua.yaml` の版を上げて `aqua update-checksum` → `chezmoi apply` |
