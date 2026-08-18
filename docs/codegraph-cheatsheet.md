# CodeGraph チートシート

[CodeGraph](https://github.com/colbymchenry/codegraph) は、コードベースをローカルの SQLite
知識グラフ（シンボル・エッジ・ファイル）に索引化し、**MCP 経由でエージェントに渡す**ツール。
`codegraph_explore` 1 回で「関連シンボルの逐語ソース + それらの間の呼び出しパス + 影響範囲」が
返るので、grep と Read のループを 1 往復に置き換えてツール呼び出し回数とトークンを減らす。
LLM を呼ばずローカル解析だけで動く（31 言語）。

グラフの用途の違い（コード専用の CodeGraph と、ドキュメント込みの概念マップを作る graphify）は
[graphify-cheatsheet.md](graphify-cheatsheet.md) の住み分け表を参照。**両者は併用する。**

## 導入（chezmoi）

- `.chezmoiscripts/run_onchange_after_40-ai-assistants.sh.tmpl` で、claude / codex を入れた
  **後**に公式 `install.sh` を curl ワンライナーで実行する。自前ランタイム同梱のバイナリを
  `~/.local/bin` に置くので Node は不要。以後は本体が `codegraph upgrade` で自己更新する
  （**aqua 管理外**）。
- 続けて実行するもの:
  - `codegraph install --yes` — claude / codex を自動検出して非対話・グローバルで設定
    （`--yes` は `--location=global --target=auto`、auto-allow 権限も書く）
  - `codegraph telemetry off` — 匿名テレメトリを無効化
- **再インストール／更新を強制したいとき**は、スクリプト中の
  `# codegraph-reinstall-marker: <日付>` 行を書き換える（内容が変わり run_onchange が再実行される）。

### 書き込み先と chezmoi の分担

| 対象 | 書き手 | chezmoi 管理 |
| --- | --- | --- |
| `~/.local/bin/codegraph` + `~/.codegraph/versions/` | `install.sh` / `codegraph upgrade` | 管理外（自己更新に任せる） |
| `~/.claude.json` の `mcpServers.codegraph` | `codegraph install` | 管理外 |
| `~/.claude/settings.json` の `permissions.allow`（`mcp__codegraph__*`） | `codegraph install`（`--no-permissions` で抑止可） | **管理下** — `private_dot_claude/modify_settings.json.tmpl` に宣言済み |
| `~/.claude/settings.json` の `UserPromptSubmit` フック | — | **管理下** — `modify_settings.json.tmpl` で `codegraph prompt-hook` を宣言 |
| `~/.claude/CLAUDE.md` の `<!-- CODEGRAPH_START -->` ブロック | `codegraph install` | **半管理** — `private_dot_claude/modify_CLAUDE.md` が現物から引き継ぐ |
| `<repo>/.codegraph/` | `codegraph init` / daemon | `dot_gitignore_global` で除外 |

`~/.claude/CLAUDE.md` は静的ファイルにすると codegraph の再注入と衝突するため、
`modify_CLAUDE.md`（chezmoi の `modify_` スクリプト）でユーザ部分だけを強制し、
CODEGRAPH ブロックは**適用先の現物からマーカーごとそのまま引き継ぐ**。
[graphify](graphify-cheatsheet.md) の登録セクションはマーカーを持たないため、あちらは
逆に `USER_BLOCK` に宣言して chezmoi 側が所有している。

`~/.claude/settings.json` も `modify_settings.json.tmpl`（同じく `modify_` スクリプト）で
管理する。Claude Code は設定を変えるたびにこのファイルを自分のキー順で書き戻すので、
静的テンプレートだとキー順と末尾改行の違いだけで `chezmoi diff` が毎回汚れる。スクリプトは
JSON の**内容**（`jq -Sc` で正規化した値）を比較し、一致していれば現物のバイト列をそのまま
返すため整形差分では書き換えない。所有権は次のとおり:

- スクリプト内の `MANAGED` に宣言したキー … chezmoi が権威（食い違えば `apply` で戻す）
- 宣言していないキー … 現物から引き継ぐ（Claude Code が後から足す設定は消えない）
- 配列（`permissions.allow` や `hooks` の各エントリ） … `MANAGED` 側で丸ごと置き換わる
- 現物が未作成 / JSON として壊れている場合 … `MANAGED` の内容で作り直す

## プロジェクトごとの索引（手動）

索引を作るかは**リポジトリごとのユーザの判断**。自動化しない。

| コマンド | 動作 |
| --- | --- |
| `codegraph init [path]` | `.codegraph/` を作り初回インデックスを構築（`-f` でホーム直下等でも強制） |
| `codegraph status [path]` | インデックスの状態と統計（`-j` で JSON） |
| `codegraph sync [path]` | 前回インデックス以降の変更を反映（`-q` は git フック向け） |
| `codegraph index [path]` | フルインデックスを作り直す |
| `codegraph uninit [path]` | `.codegraph/` を削除してプロジェクトから外す |

`.codegraph/` が無いリポジトリでは MCP ツールも `prompt-hook` も**何もしない**
（未索引のリポジトリで structural な質問を投げても注入は空）。

## MCP ツール

既定で一覧に出るのは `codegraph_explore` の 1 つだけ。他のツールも動作はするが既定では
非公開で、`CODEGRAPH_MCP_TOOLS` で公開対象を指定して有効化する。

| ツール | 相当する CLI | 用途 |
| --- | --- | --- |
| `codegraph_explore` | `codegraph explore` | 関連シンボルの逐語ソース + 呼び出しパス + 影響範囲を 1 往復で取得 |
| `codegraph_node` | `codegraph node` | 1 シンボルのソースと caller/callee の連なり、またはファイルを行番号付きで読む |
| `codegraph_search` | `codegraph query` | シンボル検索 |
| `codegraph_callers` / `codegraph_callees` | 同名 | 呼び出し元 / 呼び出し先 |
| `codegraph_impact` | `codegraph impact` | シンボル変更の影響範囲 |
| `codegraph_files` | `codegraph files` | インデックスから見たファイル構成 |
| `codegraph_status` | `codegraph status` | インデックス状態 |

`modify_settings.json.tmpl` の `permissions.allow` で `mcp__codegraph__*` を許可済みなので、
これらの呼び出しで確認プロンプトは出ない。

## CLI コマンド

MCP が使えない場面（別のエージェント、シェルから直接）でも同じ出力が得られる。

| コマンド | 動作 |
| --- | --- |
| `codegraph explore "<質問 or シンボル名>"` | MCP の `codegraph_explore` と同じ出力（`--max-files N` でソース収録上限） |
| `codegraph node <name>` | シンボルのソース + caller/callee。`-f` でファイルモード（`--offset` / `--limit` / `--symbols-only`） |
| `codegraph query <search>` | シンボル検索（`-l` 件数、`-k` 種別フィルタ、`-j` JSON） |
| `codegraph callers <symbol>` / `callees <symbol>` | 呼び出し元 / 呼び出し先（`-l` 既定 20） |
| `codegraph impact <symbol>` | 変更の影響範囲（`-d` 深さ、既定 2） |
| `codegraph affected [files...]` | 変更ソースに影響されるテストファイルを列挙（`--stdin`、`-d` 既定 5、`-f` glob、`-q`） |
| `codegraph files` | ファイル構成（`--format tree\|flat\|grouped`、`--filter` / `--pattern` / `--max-depth`） |
| `codegraph daemon` | 稼働中のバックグラウンド daemon を選んで停止する |
| `codegraph unlock [path]` | インデックスを止めている古いロックファイルを削除 |
| `codegraph upgrade [version]` | 最新（または指定版）へ更新（`--check` で確認のみ、`-f` で再インストール） |
| `codegraph telemetry [status\|on\|off]` | テレメトリの確認・切替 |

`codegraph prompt-hook` は `--help` の一覧に出ない隠しコマンドで、Claude Code の
`UserPromptSubmit` フック専用（stdin から `{prompt, cwd}` の JSON を読む）。

## インデックスの更新

- **daemon** が複数セッションで 1 つの索引プロセスを共有する（OS のネイティブファイル
  ロックで排他）。`CODEGRAPH_NO_DAEMON=1` でプロセス内実行にフォールバックできる。
- ファイル監視は OS のネイティブイベント（macOS は FSEvents、Linux は inotify）で、
  既定 2 秒の quiet window でデバウンスしてから自動 sync する。
- 変更ファイルのみ更新する。sync 中はエージェントに staleness バナーが出る。
- サーバが落ちていた間の編集は接続時の突き合わせで回収される。

## 設定ファイル

プロジェクトルートの `codegraph.json`（任意）で調整する。

| キー | 効果 |
| --- | --- |
| `exclude` | gitignore 形式でスキップするパターン |
| `include` | 特定パスについて `.gitignore` を上書きして索引対象にする |
| `extensions` | 独自拡張子を言語 ID にマップ（例 `".dota_lua": "lua"`） |

`.gitignore` は自動で尊重される。加えて `node_modules` / `dist` / `build` / `target` /
`.venv` / `Pods` / `.next` は組み込みで除外される。

## 環境変数

| 変数 | 効果 |
| --- | --- |
| `CODEGRAPH_MCP_TOOLS` | 公開する MCP ツールをカンマ区切りで指定（既定は `codegraph_explore` のみ） |
| `CODEGRAPH_WATCH_DEBOUNCE_MS` | 自動 sync のデバウンス幅（100ms〜60s、既定 2000） |
| `CODEGRAPH_NO_DAEMON` | 共有 daemon を使わずプロセス内で動かす |
| `CODEGRAPH_DIR` | 索引ディレクトリ名の変更（既定 `.codegraph`） |
| `CODEGRAPH_TELEMETRY=0` / `DO_NOT_TRACK` | テレメトリ無効化（`codegraph telemetry off` と同じ効果） |
| `CODEGRAPH_NO_WATCHDOG=1` | メインスレッド無応答時に自動 kill するウォッチドッグを止める |

## 性能とコスト

| 何 | 発火タイミング | コスト |
| --- | --- | --- |
| `codegraph prompt-hook`（`UserPromptSubmit`） | プロンプト 1 回につき 1 回 | 約 50ms（実測、2026-07-30 / macOS） |
| MCP サーバー（常駐） | セッションごとに 1 プロセス | CPU 0.0% / RSS 約 80MB（アイドル時実測） |

- フックは `UserPromptSubmit` にしか登録していない。**ツール呼び出しごとではない**ので、
  grep や Read の回数で増えることはない。
- 索引は LLM を使わないので**トークンコストは 0**。トークンを消費するのは
  `prompt-hook` が毎プロンプトで注入するコンテキストと、`codegraph_explore` の出力。
  これは grep + Read のループを置き換える対価で、全体では削減になる想定。
- graphify との併用時の内訳は [graphify-cheatsheet.md](graphify-cheatsheet.md) の
  「性能とコスト」節にまとめてある。

## 運用上の注意

- **バージョンは自己更新**なので chezmoi では固定していない。MCP サーバーは起動時の版で
  動き続けるため、`codegraph upgrade` した直後は「新しい版があります」と表示されたまま
  古い版が常駐していることがある。反映にはセッション（MCP サーバー）の再起動が必要。
- `codegraph upgrade` は設定済みエージェントに対して `codegraph install --refresh` を
  自動実行する（新しいエージェントを勝手に追加はしない）。
- `~/.codegraph/` は versions と同梱ランタイムを含むため**数百 MB 規模**になる
  （実測 223MB）。古い版は `versions/` 配下に残る。
- インデックスが進まないときは `codegraph unlock <path>` で古いロックを消す。
  常駐 daemon を止めたいときは `codegraph daemon`。
- `codegraph install` は `~/.claude/settings.json` の権限リストも書くが、そこは chezmoi が
  宣言的に所有している。`modify_settings.json.tmpl` から `mcp__codegraph__*` を消すと、
  install の書き込みと `chezmoi apply` の削除が交互に起きるので消さないこと。
