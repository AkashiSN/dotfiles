# コード知識グラフ チートシート

リポジトリを索引化してエージェントに渡す 2 つのツール。**置き換えではなく併用する**。
解いている問題が違う。

| | CodeGraph | graphify |
| --- | --- | --- |
| 対象 | ソースコードのみ | コード + ドキュメント / PDF / 画像 / 動画 / SQL スキーマ |
| ストア | SQLite（`.codegraph/`） | `graphify-out/`（`graph.json` / `graph.html` / `GRAPH_REPORT.md`） |
| 連携 | 常駐 MCP サーバー + `codegraph prompt-hook` | `~/.claude/skills/graphify/SKILL.md`（`/graphify`） |
| 粒度 | 関数・クラス単位（決定的） | 概念単位（`EXTRACTED` / `INFERRED` / `AMBIGUOUS` の信頼度タグ付き） |
| 得意 | 呼び出し関係・影響範囲・逐語ソース取得 | プロジェクト全体の概念マップ、Leiden 法によるクラスタリング |

CodeGraph は**配線図**（`foo()` を変えると誰が壊れるか）、graphify は**地図**
（この機能の設計意図がどのドキュメントとどのテーブルに跨っているか）。

どちらも `.chezmoiscripts/run_onchange_after_40-ai-assistants.sh.tmpl` で、claude / codex を
入れた**後**に CodeGraph → graphify の順で導入する。Claude Code のフックを持つのは
`codegraph prompt-hook` だけで、graphify は git フックしか持たない（[性能とコスト](#性能とコスト)）。

---

## CodeGraph

[CodeGraph](https://github.com/colbymchenry/codegraph) は、コードベースをローカルの SQLite
知識グラフ（シンボル・エッジ・ファイル）に索引化し、**MCP 経由でエージェントに渡す**ツール。
`codegraph_explore` 1 回で「関連シンボルの逐語ソース + それらの間の呼び出しパス + 影響範囲」が
返るので、grep と Read のループを 1 往復に置き換えてツール呼び出し回数とトークンを減らす。
LLM を呼ばずローカル解析だけで動く（31 言語）。

### 導入（chezmoi）

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

#### 書き込み先と chezmoi の分担

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
[graphify](#graphify) の登録セクションはマーカーを持たないため、あちらは
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

### プロジェクトごとの索引（手動）

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

### MCP ツール

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

### CLI コマンド

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

### インデックスの更新

- **daemon** が複数セッションで 1 つの索引プロセスを共有する（OS のネイティブファイル
  ロックで排他）。`CODEGRAPH_NO_DAEMON=1` でプロセス内実行にフォールバックできる。
- ファイル監視は OS のネイティブイベント（macOS は FSEvents、Linux は inotify）で、
  既定 2 秒の quiet window でデバウンスしてから自動 sync する。
- 変更ファイルのみ更新する。sync 中はエージェントに staleness バナーが出る。
- サーバが落ちていた間の編集は接続時の突き合わせで回収される。

### 設定ファイル

プロジェクトルートの `codegraph.json`（任意）で調整する。

| キー | 効果 |
| --- | --- |
| `exclude` | gitignore 形式でスキップするパターン |
| `include` | 特定パスについて `.gitignore` を上書きして索引対象にする |
| `extensions` | 独自拡張子を言語 ID にマップ（例 `".dota_lua": "lua"`） |

`.gitignore` は自動で尊重される。加えて `node_modules` / `dist` / `build` / `target` /
`.venv` / `Pods` / `.next` は組み込みで除外される。

### 環境変数

| 変数 | 効果 |
| --- | --- |
| `CODEGRAPH_MCP_TOOLS` | 公開する MCP ツールをカンマ区切りで指定（既定は `codegraph_explore` のみ） |
| `CODEGRAPH_WATCH_DEBOUNCE_MS` | 自動 sync のデバウンス幅（100ms〜60s、既定 2000） |
| `CODEGRAPH_NO_DAEMON` | 共有 daemon を使わずプロセス内で動かす |
| `CODEGRAPH_DIR` | 索引ディレクトリ名の変更（既定 `.codegraph`） |
| `CODEGRAPH_TELEMETRY=0` / `DO_NOT_TRACK` | テレメトリ無効化（`codegraph telemetry off` と同じ効果） |
| `CODEGRAPH_NO_WATCHDOG=1` | メインスレッド無応答時に自動 kill するウォッチドッグを止める |


### 運用上の注意

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

---

## graphify

[graphify](https://github.com/Graphify-Labs/graphify) は、リポジトリを**クエリ可能な知識
グラフ**に変換するツール。コードは tree-sitter でローカルに AST 解析し（LLM 呼び出しなし）、
それに加えてドキュメント / PDF / 画像 / 動画・音声 / SQL スキーマ / Excel まで取り込んで
一つのグラフにまとめる。出力は `graphify-out/` の JSON・HTML・Markdown。

### 導入（chezmoi）

- `.chezmoiscripts/run_onchange_after_40-ai-assistants.sh.tmpl` の末尾で、CodeGraph に続けて
  `uv tool install graphifyy` → `graphify install` を実行する（PyPI 上のパッケージ名は
  **graphifyy**、コマンド名は `graphify`）。`graphify install` が claude の設定を書き換える
  ため、claude 本体を入れた**後**（同スクリプトの最後）に置く。
- uv 本体は aqua 管理（`astral-sh/uv`）なので、同スクリプトで aqua の bin を PATH に足している。
  uv が無い環境ではブロックごとスキップする。
- **バージョン追従／固定**はスクリプト中の `GRAPHIFY_VERSION` で切り替える。`latest` なら
  毎回 `uv tool install --upgrade` で最新へ、版を書けば（例 `0.9.13`）そこにピンする。
  値を書き換えると run_onchange で既存マシンでも再実行される。
- **`.sql` / `.tf` のパーサーは extra で入れる。** SQL 抽出器（`graphify/extractors/sql.py`）が
  import する `tree_sitter_sql` と、HCL 用の `tree_sitter_hcl` は graphifyy 本体の依存では
  なく extra（`sql` / `terraform`）。入れないと `.sql` / `.tf` は
  `tree_sitter_sql not installed` 相当のエラーでスキップされる（他言語の tree-sitter 文法は
  同梱されている）。そのため `uv tool install "graphifyy[sql,terraform]"` で導入する
  （スクリプト中の `GRAPHIFY_EXTRAS`）。
- `graphify install`（グローバル）が書き換える chezmoi 管理外のもの:
  - `~/.claude/skills/graphify/SKILL.md`（スキル本体。`/graphify` の実体）
  - `~/.claude/CLAUDE.md` の `# graphify` 登録セクション
- `~/.claude/CLAUDE.md` は `private_dot_claude/modify_CLAUDE.md` が生成するため、graphify の
  追記は放置すると `chezmoi apply` ごとに消える。graphify は本文に `graphify` の文字列が
  あれば追記をスキップするので、**登録セクションを modify_CLAUDE.md の `USER_BLOCK` に
  宣言して chezmoi 側が所有**している（追記 → apply で消えるフラッピングを避ける）。
- **PreToolUse フックは入れていない。** グローバル `graphify install` は
  `~/.claude/settings.json` を触らない。`Bash|Grep` と `Read|Glob` に割り込んで「まずグラフを
  引け」と促すフックを書き込むのは `graphify install --project` / `graphify claude install`
  の方で、これは既に入っている `codegraph prompt-hook` と二重注入になるため採用していない。
  必要になったらリポジトリ単位で `graphify install --project`（強制したいなら `--strict`）を
  実行する。

### リポジトリごとのセットアップ（手動）

グラフ本体と git フックは**リポジトリごと**。自動化はせず、使いたいリポジトリで手動実行する。

| 手順 | コマンド | 何が起きるか |
| --- | --- | --- |
| 1. グラフ作成 | Claude Code で `/graphify .` | `graphify-out/` を生成。コードは AST のみ、ドキュメント／画像は LLM を使う |
| 2. git フック導入 | `graphify hook install` | post-commit / post-checkout フック + マージドライバを登録 |
| 3. 確認 | `graphify hook status` | フックとマージドライバの登録状態を表示 |

#### `graphify hook install` が実際に触るもの

**カレントディレクトリから見て最も近い git リポジトリ**に対して、3 つのことをする。

- `.git/hooks/post-commit` — コミット後にグラフを再構築（バックグラウンド実行）
- `.git/hooks/post-checkout` — チェックアウト後にグラフを再構築
- マージドライバ登録 — `git config merge.graphify.{name,driver}` をリポジトリローカルに設定し、
  **追跡ファイルである `.gitattributes` に `graphify-out/graph.json merge=graphify` を追記**する

`core.hooksPath` は git 自身に解決させるので Husky 等と共存する（`.husky/_` を検出したら
親の `.husky/` に置く）。フックとマージドライバは `graphify install` 時の Python
インタプリタを絶対パスでピンするため、`graphify` が PATH に無い状況でも動く。
外すときは `graphify hook uninstall`（`.gitattributes` の他の行は保持される）。

#### post-commit フックの挙動（commit はブロックされない）

- 再構築は**デタッチして実行**する（POSIX は `start_new_session`）ので、`git commit` は
  即座に返る。commit 時に増えるのはシェルスクリプトの数ミリ秒と Python 起動だけ。
- 再構築プロセスは `os.nice(10)` で優先度を落とす。既定タイムアウトは 600 秒。
- ログは `~/.cache/graphify-rebuild.log`。
- 走らない条件（自動スキップ）:
  - rebase / merge / cherry-pick の途中（`--continue` を妨げないため）
  - 変更が `graphify-out/` 配下だけのとき（再構築ループ防止）
  - `GRAPHIFY_SKIP_HOOK=1` のとき

#### `graphify-out/` は gitignore しない

`graphify-out/` はグローバル gitignore（`dot_gitignore_global`）に**入れていない**。
`graph.json` をコミットして共有する運用で、そのために `hook install` がマージドライバ
（`graphify merge-driver`、2 つの `graph.json` を union マージする）を登録している。
`.codegraph/` は逆に gitignore 済み（SQLite の生成物で共有しない）。

副作用として、**コミットのたびにバックグラウンド再構築が `graph.json` を書き換えるので、
コミット直後に作業ツリーが汚れる**。再構築ループは防止されている（グラフだけの変更では
再発火しない）が、生成物を追跡している以上コミットし直す手間は残る。`git commit --amend`
で畳むか、区切りのいいタイミングだけコミットする運用になる。

### よく使うコマンド

グラフは既定で `graphify-out/graph.json` を読む（どのコマンドも `--graph <path>` で変更可）。

| コマンド | 動作 |
| --- | --- |
| `graphify query "<質問>"` | グラフを BFS 走査して回答（`--dfs` で深さ優先、`--budget N` で出力トークン上限、既定 2000） |
| `graphify path "A" "B"` | 2 ノード間の最短経路 |
| `graphify explain "X"` | ノードとその近傍を平易な言葉で説明 |
| `graphify affected "X"` | X の影響を受けるノードを逆方向に探索（`--depth N`、既定 2） |
| `graphify god-nodes` | 最も接続の多いノード＝アーキテクチャ上のハブ（`--top N`、既定 10） |
| `graphify update <path>` | 変更ファイルのみ再抽出してグラフ更新（**LLM 不要**） |
| `graphify watch <path>` | ディレクトリを監視してコード変更時に再構築 |
| `graphify extract <path>` | CI / スクリプト向けのヘッドレス完全抽出（AST + LLM 意味抽出） |
| `graphify extract <path> --code-only` | コードのみ索引化（ローカル AST のみ、API キー不要） |
| `graphify add <url>` | URL を取得して `./raw` に保存しグラフへ追加（arXiv 論文・YouTube 等） |
| `graphify tree` | 折りたたみツリー HTML（`graphify-out/GRAPH_TREE.html`）を生成 |
| `graphify export callflow-html` | Mermaid ベースのアーキテクチャ／コールフロー HTML |
| `graphify global list` / `global add <graph.json>` | 横断グラフ（`~/.graphify/global-graph.json`）の管理 |
| `graphify diagnose multigraph` | 同一端点エッジの潰れリスクを報告 |
| `graphify check-update <path>` | 意味的な再抽出が保留かを確認（cron 向け） |
| `graphify uninstall` | 検出した全プラットフォームから graphify を除去（`--purge` で `graphify-out/` も削除） |

### LLM を使う境界

| 対象 | LLM |
| --- | --- |
| コード（36 言語の tree-sitter 文法）・SQL スキーマ | **使わない**。ローカル AST 解析で決定的 |
| `graphify update`（増分更新） | **使わない**。変更ファイルの AST 再抽出のみ |
| ドキュメント / PDF / 画像 | 使う（意味抽出） |
| 動画・音声 | ローカルの faster-whisper で文字起こし（API 呼び出しなし） |
| コミュニティ命名（クラスタのラベル付け） | 使う。`--no-label` で抑止、`--backend` / `--model` で選択 |

つまり**コードだけのリポジトリならトークンコストはほぼゼロ**で、PDF や画像を多く含む
リポジトリでは初回抽出が重くなる。


### 環境変数

| 変数 | 効果 |
| --- | --- |
| `GRAPHIFY_OUT` | 出力ディレクトリ名の変更（既定 `graphify-out`） |
| `GRAPHIFY_SKIP_HOOK=1` | git フックによる再構築を一時的に止める |
| `GRAPHIFY_HOOK_STRICT` | PreToolUse の strict モードを再インストールなしで on/off |
| `GRAPHIFY_FORCE=1` | `update` / `extract` の増分ゲートとキャッシュを無視して完全再走査 |
| `GRAPHIFY_REBUILD_TIMEOUT` | フック再構築のタイムアウト秒（既定 600、`0` で無効） |
| `GRAPHIFY_REBUILD_MEMORY_LIMIT_MB` | 再構築プロセスのメモリ上限（macOS は `RLIMIT_DATA`、Linux は `RLIMIT_AS`） |
| `GRAPHIFY_MAX_WORKERS` | AST 抽出のサブプロセス数（既定は CPU 数） |

### 運用上の注意

- `graph.json` は**スナップショット**なので、`hook install` を入れていないリポジトリでは
  腐る。手で更新するなら `graphify update .`（LLM 不要・高速）を回す。
- グローバル `graphify install` は `~/.claude/CLAUDE.md` に登録行を追記しようとするが、
  chezmoi 側が同じ内容を宣言済みなので `already registered (no change)` になる。
  もし `USER_BLOCK` から `graphify` の文字列を消すと、追記と `chezmoi apply` の
  削除が交互に起きるので消さないこと。
- `graphify install --project` を実行したリポジトリでは `.claude/settings.json` が
  書き換わり、元ファイルが `.claude/settings.json.graphify-bak` に退避される。

---

## 性能とコスト

二つのフックは**別の軸**にあって重ならないので、併用しても体感の劣化はない。

| 何 | 発火タイミング | コスト |
| --- | --- | --- |
| `codegraph prompt-hook`（`UserPromptSubmit`） | プロンプト 1 回につき 1 回 | 約 50ms（実測、2026-07-30 / macOS） |
| codegraph MCP サーバー（常駐） | セッションごとに 1 プロセス | CPU 0.0% / RSS 約 80MB（アイドル時実測） |
| graphify post-commit / post-checkout | commit / checkout 時 | commit はブロックしない。再構築は AST のみで**トークン 0** |

要点:

- `codegraph prompt-hook` は `UserPromptSubmit` にしか登録していない。**ツール呼び出しごとでは
  ない**ので、grep や Read の回数では増えない。
- graphify 側は Claude Code のフックを一つも持たない（git フックだけ）。したがって
  「両方が毎ツール呼び出しに割り込む」状況は構造的に起きない。
- 継続的にトークンを食うのは `codegraph prompt-hook` の毎プロンプト注入だけで、これは
  graphify 導入で増えるものではない。
- 索引はどちらも LLM を使わないので**トークンコストは 0**。トークンを消費するのは
  `codegraph prompt-hook` の注入と `codegraph_explore` の出力で、これは grep + Read のループを
  置き換える対価として全体では削減になる想定。

**PreToolUse フックを入れなかった理由（性能面）**: 入れると `Bash|Grep` と `Read|Glob` の
すべてに Python プロセスが 1 個生える。ガード自体は軽い（`graph.json` をパースせず
`is_file()` と文字列マッチのみ、`hook-guard` はスキルのバージョンチェックもスキップする）が、
Python インタプリタの起動が毎回乗る。graphify の `__main__` は `cli.py`・`install.py`
（いずれも 2000〜3000 行規模）をトップレベルで import するため、素の `python3` 起動
（この機体で warm 20〜30ms）より確実に大きい。加えて nudge テキストが `additionalContext`
として毎回入るのでトークンも増える。
