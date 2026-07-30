# graphify チートシート

[graphify](https://github.com/Graphify-Labs/graphify) は、リポジトリを**クエリ可能な知識
グラフ**に変換するツール。コードは tree-sitter でローカルに AST 解析し（LLM 呼び出しなし）、
それに加えてドキュメント / PDF / 画像 / 動画・音声 / SQL スキーマ / Excel まで取り込んで
一つのグラフにまとめる。出力は `graphify-out/` の JSON・HTML・Markdown。

## CodeGraph との住み分け（併用する）

[CodeGraph](https://github.com/colbymchenry/codegraph) と graphify は**置き換えではなく併用**。
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

## 導入（chezmoi）

- `.chezmoiscripts/run_onchange_after_40-ai-assistants.sh.tmpl` の末尾で、CodeGraph に続けて
  `uv tool install graphifyy` → `graphify install` を実行する（PyPI 上のパッケージ名は
  **graphifyy**、コマンド名は `graphify`）。`graphify install` が claude の設定を書き換える
  ため、claude 本体を入れた**後**（同スクリプトの最後）に置く。
- uv 本体は aqua 管理（`astral-sh/uv`）なので、同スクリプトで aqua の bin を PATH に足している。
  uv が無い環境ではブロックごとスキップする。
- **バージョン追従／固定**はスクリプト中の `GRAPHIFY_VERSION` で切り替える。`latest` なら
  毎回 `uv tool install --upgrade` で最新へ、版を書けば（例 `0.9.13`）そこにピンする。
  値を書き換えると run_onchange で既存マシンでも再実行される。
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

## リポジトリごとのセットアップ（手動）

グラフ本体と git フックは**リポジトリごと**。自動化はせず、使いたいリポジトリで手動実行する。

| 手順 | コマンド | 何が起きるか |
| --- | --- | --- |
| 1. グラフ作成 | Claude Code で `/graphify .` | `graphify-out/` を生成。コードは AST のみ、ドキュメント／画像は LLM を使う |
| 2. git フック導入 | `graphify hook install` | post-commit / post-checkout フック + マージドライバを登録 |
| 3. 確認 | `graphify hook status` | フックとマージドライバの登録状態を表示 |

### `graphify hook install` が実際に触るもの

**カレントディレクトリから見て最も近い git リポジトリ**に対して、3 つのことをする。

- `.git/hooks/post-commit` — コミット後にグラフを再構築（バックグラウンド実行）
- `.git/hooks/post-checkout` — チェックアウト後にグラフを再構築
- マージドライバ登録 — `git config merge.graphify.{name,driver}` をリポジトリローカルに設定し、
  **追跡ファイルである `.gitattributes` に `graphify-out/graph.json merge=graphify` を追記**する

`core.hooksPath` は git 自身に解決させるので Husky 等と共存する（`.husky/_` を検出したら
親の `.husky/` に置く）。フックとマージドライバは `graphify install` 時の Python
インタプリタを絶対パスでピンするため、`graphify` が PATH に無い状況でも動く。
外すときは `graphify hook uninstall`（`.gitattributes` の他の行は保持される）。

### post-commit フックの挙動（commit はブロックされない）

- 再構築は**デタッチして実行**する（POSIX は `start_new_session`）ので、`git commit` は
  即座に返る。commit 時に増えるのはシェルスクリプトの数ミリ秒と Python 起動だけ。
- 再構築プロセスは `os.nice(10)` で優先度を落とす。既定タイムアウトは 600 秒。
- ログは `~/.cache/graphify-rebuild.log`。
- 走らない条件（自動スキップ）:
  - rebase / merge / cherry-pick の途中（`--continue` を妨げないため）
  - 変更が `graphify-out/` 配下だけのとき（再構築ループ防止）
  - `GRAPHIFY_SKIP_HOOK=1` のとき

### `graphify-out/` は gitignore しない

`graphify-out/` はグローバル gitignore（`dot_gitignore_global`）に**入れていない**。
`graph.json` をコミットして共有する運用で、そのために `hook install` がマージドライバ
（`graphify merge-driver`、2 つの `graph.json` を union マージする）を登録している。
`.codegraph/` は逆に gitignore 済み（SQLite の生成物で共有しない）。

副作用として、**コミットのたびにバックグラウンド再構築が `graph.json` を書き換えるので、
コミット直後に作業ツリーが汚れる**。再構築ループは防止されている（グラフだけの変更では
再発火しない）が、生成物を追跡している以上コミットし直す手間は残る。`git commit --amend`
で畳むか、区切りのいいタイミングだけコミットする運用になる。

## よく使うコマンド

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

## LLM を使う境界

| 対象 | LLM |
| --- | --- |
| コード（36 言語の tree-sitter 文法） | **使わない**。ローカル AST 解析で決定的 |
| `graphify update`（増分更新） | **使わない**。変更ファイルの AST 再抽出のみ |
| ドキュメント / PDF / 画像 | 使う（意味抽出） |
| 動画・音声 | ローカルの faster-whisper で文字起こし（API 呼び出しなし） |
| コミュニティ命名（クラスタのラベル付け） | 使う。`--no-label` で抑止、`--backend` / `--model` で選択 |

つまり**コードだけのリポジトリならトークンコストはほぼゼロ**で、PDF や画像を多く含む
リポジトリでは初回抽出が重くなる。

## 性能とコスト（CodeGraph との併用）

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

**PreToolUse フックを入れなかった理由（性能面）**: 入れると `Bash|Grep` と `Read|Glob` の
すべてに Python プロセスが 1 個生える。ガード自体は軽い（`graph.json` をパースせず
`is_file()` と文字列マッチのみ、`hook-guard` はスキルのバージョンチェックもスキップする）が、
Python インタプリタの起動が毎回乗る。graphify の `__main__` は `cli.py`・`install.py`
（いずれも 2000〜3000 行規模）をトップレベルで import するため、素の `python3` 起動
（この機体で warm 20〜30ms）より確実に大きい。加えて nudge テキストが `additionalContext`
として毎回入るのでトークンも増える。

## 環境変数

| 変数 | 効果 |
| --- | --- |
| `GRAPHIFY_OUT` | 出力ディレクトリ名の変更（既定 `graphify-out`） |
| `GRAPHIFY_SKIP_HOOK=1` | git フックによる再構築を一時的に止める |
| `GRAPHIFY_HOOK_STRICT` | PreToolUse の strict モードを再インストールなしで on/off |
| `GRAPHIFY_FORCE=1` | `update` / `extract` の増分ゲートとキャッシュを無視して完全再走査 |
| `GRAPHIFY_REBUILD_TIMEOUT` | フック再構築のタイムアウト秒（既定 600、`0` で無効） |
| `GRAPHIFY_REBUILD_MEMORY_LIMIT_MB` | 再構築プロセスのメモリ上限（macOS は `RLIMIT_DATA`、Linux は `RLIMIT_AS`） |
| `GRAPHIFY_MAX_WORKERS` | AST 抽出のサブプロセス数（既定は CPU 数） |

## 運用上の注意

- `graph.json` は**スナップショット**なので、`hook install` を入れていないリポジトリでは
  腐る。手で更新するなら `graphify update .`（LLM 不要・高速）を回す。
- グローバル `graphify install` は `~/.claude/CLAUDE.md` に登録行を追記しようとするが、
  chezmoi 側が同じ内容を宣言済みなので `already registered (no change)` になる。
  もし `USER_BLOCK` から `graphify` の文字列を消すと、追記と `chezmoi apply` の
  削除が交互に起きるので消さないこと。
- `graphify install --project` を実行したリポジトリでは `.claude/settings.json` が
  書き換わり、元ファイルが `.claude/settings.json.graphify-bak` に退避される。
