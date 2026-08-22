# zsh チートシート

zsh 設定（`dot_zshrc` / `dot_zshenv.tmpl`）のエイリアス・関数・キーバインドをまとめたリファレンス。

- プラグイン管理: **sheldon**（fzf-tab / zsh-autosuggestions 等）
- プロンプト: **starship**（SSH/root 接続時はプロンプト先頭に `user@host` を表示。ローカル通常時は非表示）
- ディレクトリ移動: `AUTO_PUSHD` 有効（`cd` 履歴がスタックに積まれる）
- エディタ: `nvim`（`EDITOR` / `VISUAL`。`dot_zshenv.tmpl` で設定。非インタラクティブ実行にも適用）
- ロケール: `LANG=ja_JP.UTF-8`（`dot_zshenv.tmpl` で設定。全シェル/スクリプトに適用）
- Rust: toolchain は **rustup**（aqua 管理）で導入。`cargo`/`rustc` は `$CARGO_HOME/bin`（=`~/.local/share/cargo/bin`）を PATH に追加。実体は run_onchange の `32-rust-default` が `rustup-init` で provisioning
- Terraform: `TF_PLUGIN_CACHE_DIR`（=`~/.cache/terraform/plugin-cache`）を `dot_zshenv.tmpl` で設定し、provider をプロジェクト間で共有。詳細は [terraform-cheatsheet.md](terraform-cheatsheet.md)
- 構成: `dot_zshrc` はローダー。実体は `~/.config/zsh/rc.d/*.zsh`（`00-options` / `10-path` / `20-completion` / `25-ssh-agent` / `30-plugins` / `40-tools` / `50-functions` / `60-aliases` / `70-keybindings`）を番号順に zcompile + source

> 表記: `C-]` = Ctrl+]、`S-...` = Shift。エイリアス/関数の一部は対応ツール（terraform/kubectl 等）が
> インストールされている場合のみ有効。CLI は aqua（`dot_config/aquaproj-aqua/aqua.yaml`）で管理。

---

## エイリアス

### 共通

| エイリアス | 実体 |
| --- | --- |
| `vi` / `vim` | `nvim` |
| `tf` | `terraform`（terraform がある場合） |
| `k` | `kubectl`（kubectl がある場合） |
| `rsync` | `rsync -azP` |
| `conv-utf8` | カレント以下の全ファイルを UTF-8 / LF へ変換（nkf） |

### macOS

| エイリアス | 実体 |
| --- | --- |
| `ls` | `ls -G`（色付き） |
| `ll` | `ls -lG` |
| `la` | `ls -laG` |
| `brew` | Homebrew を素の PATH で実行 |

### Linux

| エイリアス | 実体 |
| --- | --- |
| `ls` | `ls --color=auto` |
| `ll` | `ls -alF` |
| `la` | `ls -A` |
| `l` | `ls -CF` |
| `ffmpeg-qsv` | Intel QSV ハードウェアエンコード付き ffmpeg |

---

## 関数

| コマンド | 動作 |
| --- | --- |
| `latex [args]` | Docker（akashisn/latexmk）で latexmk をビルド |
| `pdfcrop [args]` | Docker で PDF の余白をクロップ |
| `search <word>...` | カレント以下のファイルパスを複数語で AND 絞り込み（クォート出力） |
| `convert-crlf-to-lf` | CRLF のファイルを検出して LF へ一括変換（nkf） |
| `peco-src` | `ghq` 管理リポジトリを peco で選んで `cd`（キー: `C-]`） |
| `agmsg-bridge-reap` | agmsg Codex monitor の残留 `codex-bridge.js`（孤児のみ）を回収。ログイン時に自動実行。詳細は [agmsg チートシート](agmsg-cheatsheet.md#codex-monitor-モードbeta) |
| `claude [args]` | `claude` をラップし、**SSH 接続先で引数なしの素の起動**のときだけ `--remote-control` を自動付与（claude.ai / モバイル等のリモートからそのインタラクティブセッションを操作可能。セッション名プレフィックスは claude 既定でホスト名）。引数付き（プロンプト・`-p`/`--print`・`mcp`/`update` 等のサブコマンド・`-c`/`--resume` 等）は素通し。ローカルや非対話シェルでは実バイナリのまま無変更 |
| `claude-bedrock [args]` | claude.ai 障害時に Claude Code を Amazon Bedrock（グローバル推論プロファイル）へ切り替えて起動。env をその呼び出しに限って渡すので通常の `claude` は claude.ai のまま。使う AWS プロファイルは `CLAUDE_CODE_BEDROCK_AWS_PROFILE`（既定 `cdx-pre-dev`）で `AWS_PROFILE` を常に上書きするので、対話中に `aws-switch` で選んでいるプロファイルには影響されない。認証は `aws-login`（credential_process）が担う（追加ログイン不要）。リージョン/モデルは下表の `CLAUDE_CODE_BEDROCK_*` で上書き可。`claude`（関数）経由なので SSH 素起動なら Remote Control も乗る |
| `codex [args]` | `codex` をラップし、起動直前に `codex-appserver-evict` で共有 app-server の `CODEX_HOME` を照合する。食い違う app-server（＝ Bedrock 用に残ったもの）を畳んで作り直させ、素の codex が黙って Bedrock で走るのを防ぐ。app-server に繋がない呼び出し（`exec` / `login` / `--version` など）では何もしない |
| `codex-bedrock [args]` | codex を Amazon Bedrock へ切り替えて起動（`~/.local/bin/codex-bedrock`）。通常の `codex` はサブスク（OpenAI ログイン）のまま。`CODEX_HOME` をプロジェクトごとの一時 home へ向け、その `config.toml` を「素の config ＋ `~/.codex/bedrock.config.toml`」にする。使う AWS プロファイルは `CODEX_BEDROCK_AWS_PROFILE`（既定 `cdx-pre-dev`）で `AWS_PROFILE` に渡し、その `credential_process = aws-login` が認証を担う。リージョン/モデルを変えるときは `dot_codex/private_bedrock.config.toml` を編集 |
| `codex-bedrock-spawn <name> [opts]` | agmsg の codex エージェントを Bedrock で動く状態で herdr のペインに立ち上げる（`~/.local/bin/codex-bedrock-spawn`）。内部で `spawn.sh` を呼ぶ。`--team` / `--project` / `--direction` 以外の引数は spawn.sh へ素通し（`--boot-prompt` など）。片付けは素の agmsg と同じ `despawn.sh <team> <self> <name> --force` |
| `term-reset` | 端末のマウス報告 / フォーカス報告 / 括弧付き貼り付け / Kitty keyboard protocol（`\e[<u` で pop、`\e[=0;1u` でフラグ 0）を無効化して端末状態を復旧。SSH 異常切断でリモートの nvim 等が有効化した端末モードが居残り、キー入力で `15;1:3u` 等・マウスで `0;129;39M` 等が漏れたときに叩く（素の端末でも無害）。詳細は [herdr チートシート](herdr-cheatsheet.md#ssh-異常切断後の端末化けterm-reset) |
| `herdr [args]` / `ssh [args]` | ローカルシェルでのみ実バイナリをラップし、戻り際に必ず `term-reset` する（`herdr --remote` / `ssh` 先の異常切断による端末化けを自動復旧）。herdr は内部で自前の ssh を exec するため `herdr` 自体もラップ対象。リモートシェル（`$SSH_CONNECTION` あり）ではラップしない |

### SSH セッションでの `$BROWSER` 自動切替（portfwd）

portfwd でオプトインした SSH セッションでは `$BROWSER` が自動で `~/.local/bin/portfwd-open` にセットされ、`aws login` / `gh auth` 等がブラウザを開こうとするとローカルのブラウザが開く（`dot_zshenv.tmpl` の `LC_PORTFWD_HOST` チェックによる）。`$BROWSER` が既にセットされている場合（VSCode Remote 等が自前のヘルパを仕込んでいる場合）は上書きしない。詳細は [portfwd-cheatsheet.md](portfwd-cheatsheet.md) を参照。

### bedrock 起動で使う AWS プロファイル

`claude-bedrock` / `codex-bedrock` はそれぞれ専用の環境変数で `AWS_PROFILE` を決める（未設定なら
既定値）。対話中に `aws-switch` で選んでいるプロファイルは無視され、bedrock 用は常にこの専用
プロファイルに固定される（両者ともサブシェルに閉じ込めるので対話シェルの `AWS_PROFILE` は不変）。

| 変数 | 既定値 | 対象 |
| --- | --- | --- |
| `CLAUDE_CODE_BEDROCK_AWS_PROFILE` | `cdx-pre-dev` | `claude-bedrock` |
| `CODEX_BEDROCK_AWS_PROFILE` | `cdx-pre-dev` | `codex-bedrock` |

### `claude-bedrock` のリージョン/モデル上書き変数

呼び出し前に export しておくと既定値を上書きできる（未設定なら既定値）。
`AWS_REGION` はグローバルプロファイルでも SigV4 署名用に具体リージョンが必要（ルーティングは
グローバルプロファイルが自動）。

| 変数 | 既定値 |
| --- | --- |
| `CLAUDE_CODE_BEDROCK_REGION` | `us-east-1` |
| `CLAUDE_CODE_BEDROCK_OPUS_MODEL` | `global.anthropic.claude-opus-5[1m]` |
| `CLAUDE_CODE_BEDROCK_SONNET_MODEL` | `global.anthropic.claude-sonnet-5[1m]` |
| `CLAUDE_CODE_BEDROCK_HAIKU_MODEL` | `global.anthropic.claude-haiku-4-5-20251001-v1:0` |

> 内部で `CLAUDE_CODE_USE_BEDROCK=1` と上記モデルを `ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU}_MODEL` に
> 渡して `claude` を起動する。Bedrock 連携の詳細は [AWS チートシート](aws-cheatsheet.md) の認証フロー（`aws-switch` / `aws-login`）も参照。

### `codex-bedrock` のリージョンとモデル

`~/.codex/bedrock.config.toml`（`dot_codex/private_bedrock.config.toml`）に直接書く。既定は
`us-east-1` / `openai.gpt-5.6-sol`。**`openai.gpt-5.6-sol` を提供しているのは `us-east-1` と
`us-east-2` だけ**で、他リージョンの `bedrock-mantle` エンドポイントは
`404 The model 'openai.gpt-5.6-sol' does not exist` を返す。`us-west-2` では
`openai.gpt-5.6-terra` / `openai.gpt-5.6-luna` なら通る。

`aws bedrock list-foundation-models` にモデルが載っていても mantle エンドポイントで使えるとは
限らないので、リージョンやモデルを変えるときは `bedrock-mantle.<region>.api.aws/openai/v1/responses`
へ実際に投げて 200 が返ることを確認する。

### `codex-bedrock` が一時 `CODEX_HOME` を使う理由

Bedrock 設定を渡す経路に `--profile` は使えない。`--profile` は runtime コマンド専用で `codex app-server`
が受け取らないためだ（付けると許可コマンドの一覧を添えてエラーになる）。agmsg の monitor モードが有効な
プロジェクトでは `~/.agents/bin/codex`（shim）が対話起動を `codex-monitor.sh` へ流し、共有 app-server を
立てて TUI を `codex --remote ws://...` で繋ぐので、モデル解決と認証は app-server 側の設定で決まる。
`--profile bedrock` は TUI にしか効かず、表示だけ Bedrock provider になって実際はサブスク側で走り、
`The 'openai.gpt-5.6-sol' model is not supported when using Codex with a ChatGPT account.` になる。

`--profile` を環境変数で渡すこともできない。codex 0.149.0 に `--profile` 相当の環境変数は無く
（`CODEX_PROFILE` / `CODEX_CONFIG_PROFILE` は無視される）、旧 v1 の `profile = "..."` キーも
`legacy 'profile = "..."' config is no longer supported` で拒否される。

そこで `CODEX_HOME` を使う。これは環境変数なので子プロセスへ継承され、app-server にも同じ設定が乗る。
`codex-bedrock` はプロジェクトごとに `$TMPDIR/codex-bedrock/<sha1(プロジェクトパス)>` を用意し、そこへ:

- `config.toml` — 素の `~/.codex/config.toml` に `~/.codex/bedrock.config.toml` を被せて生成。MCP サーバ・
  フックの trust hash・`projects` の trust_level・サンドボックスの writable roots はそのまま引き継ぐ
- `AGENTS.md` / `hooks.json` / `skills/` — 実 home からコピー
- `sessions` — 実 home の `sessions` への symlink。agmsg の codex ドライバが rollout を
  `$HOME/.codex/sessions` に決め打ちで探すため、張らないと Bedrock セッションのトランスクリプトを見失う
- `auth.json` — **置かない**。Bedrock は SigV4 認証なので不要で、一時領域に資格情報を撒かずに済む

`config.toml` を合成するとき、`hooks.state` のうち**グローバル `hooks.json` を指す信頼キーは一時 home の
パスへ付け替える**。信頼キーはフックファイルの絶対パスを含むので、付け替えないと `~/.codex/hooks.json`
（herdr の agent-state フック）が毎回「Hooks need review」で止まる。中身が変わっていればハッシュが合わず
従来どおり確認が出るので、信頼を素通しにしているわけではない。

一時 home のパスは `pwd -P` で**シンボリックリンクを解決した形**にする。codex は信頼キーを解決後の絶対
パスで持つため、macOS の `/var` → `/private/var` を揃えないとキーが一致しない（`TMPDIR` 末尾の `/` も同様に
落とす）。

#### `config.toml` の合成

TOML はトップレベルキーを最初のテーブルヘッダより前にしか書けないので、両ファイルを「テーブル前」と
「テーブル以降」に割って組み直す。オーバレイで定義済みのトップレベルキー（`model`）は素の config 側から
落とす（重複キーは TOML のエラーになる）。読み込んで書き直すのではなく**行を並べ替える**ので、コメントと
codex 自身が書いた整形はそのまま残る。

割る位置は行の見た目では決められない。素の `config.toml` は codex が書き換えるファイルで、複数行配列や
複数行文字列の中に `[` で始まる行が来ることがあるからだ。実際、行ベースで判定した初版は次の入力で
`Cannot overwrite a value` の壊れた TOML を吐いた:

```toml
matrix = [
[1, 2],          # ← ここをテーブルヘッダと誤読する
]
model = "gpt-5.6-sol"   # ← 以降はテーブル部扱いになり、落とされない
```

そこで**位置決めを `tomllib` にさせている**。「先頭から N 行がパースできる」＝ N 行目は文の切れ目、という
性質を使い、切れ目でありかつ `[` で始まる行だけをテーブルヘッダと見なす。値の途中の行は prefix が
パースできないので自動的に除かれる。同じ性質でトップレベル部を文単位に割り、各文が定義したキーを
パース結果の差分から取る（キー名の正規表現も要らない）。最後に合成結果をもう一度パースし、オーバレイの
値がそのまま出ているかまで確かめてから書き出す。

`tomllib` は Python 3.11 以降の標準ライブラリ。macOS 同梱の `python3` は 3.9 なので、
`run_onchange_after_35-uv-tools.sh.tmpl` が `uv python install` で 3.11+ を 1 つ確保する
（[uv チートシート](uv-cheatsheet.md#uv-管理の-python)）。合成に third-party パッケージは使わない
（オフラインで動かなくなるのを避けるため）。実 config で実測 15ms 程度。

一時 home は使い捨てで、参照している codex が居なくなったものは次回の `codex-bedrock` 起動時に回収する。
セッション履歴やスレッド DB は実 home と別になる（`sessions` だけ共有）。

### app-server の取り合いを防ぐ（`codex-appserver-evict`）

app-server は `$SKILL_DIR/run/codex-app-server.<sha1(プロジェクトパス)>` でキーされ、再利用の判定は
「pid 生存 / ポート応答 / コマンド名一致」だけで設定を見ていない。よって同じプロジェクトで素の codex と
Bedrock 版を混ぜると、先に起動した側の app-server を後から起動した側が黙って再利用する。**素の codex が
Bedrock 用 app-server を拾う向き**は課金先が変わるので特に厄介。

`codex-appserver-evict <期待する CODEX_HOME> [codex の引数...]` が起動直前にこれを潰す。`pgrep` と `lsof`
でそのプロジェクト（＝ cwd 一致）の app-server を特定し、`ps eww` でその `CODEX_HOME` を読んで、期待と
違えば畳む。agmsg の run ディレクトリ名には依存せず codex 自身のプロセス署名だけを見ているので、agmsg 側の
命名が変わっても壊れない。`codex` 関数と `codex-bedrock` の両方から呼ぶので、どちら向きの取り違えも防げる。

同じ種類（同じ `CODEX_HOME`）なら畳まないため、同一プロジェクトで codex-bedrock を並行起動しても
app-server を共有できる。逆に、種類をまたいで切り替えるときは**開いていた側のセッションが切れる**。

### agmsg spawn で Bedrock の codex をペインに出す

`codex-bedrock-spawn <name>` を使う。herdr のペインの中から実行すること。

```sh
codex-bedrock-spawn reviewer
#   → spawned codex 'reviewer' (team dotfiles) in herdr pane wQ:p7
#       CODEX_HOME  /private/var/folders/.../codex-bedrock/<sha1>
#       AWS_PROFILE cdx-pre-dev
```

送信・確認・片付けは素の agmsg と同じ（`delivery.sh status` → `send.sh` →
`despawn.sh ... --force`）。手順の全体は [~/.claude/CLAUDE.md](../private_dot_claude/modify_CLAUDE.md)
の「codex にレビューを依頼するときの手順」にある。

素の `spawn.sh codex <name>` では Bedrock にならない。TUI が共有 app-server へ `--remote` で繋がる以上、
`CODEX_HOME` を Bedrock 用の一時 home へ向けるしかないが、spawn.sh 側にその隙が無いためだ:

- spawn.sh の herdr パス（`launch_in_herdr`）は `herdr pane split` を **`--env` 無しで**呼ぶ
- マニフェスト（`drivers/types/codex/type.conf`）の `cli=codex` は固定で差し替えられない
- codex に `--profile` 相当の環境変数は無い

`codex-bedrock-spawn` がやっていることは 4 つ:

1. `codex-bedrock --print-home` で一時 home を用意（codex は起動しない）
2. `codex-appserver-evict` で食い違う app-server を畳む
3. `herdr pane split --env CODEX_HOME=... --env AWS_PROFILE=...` でペインを作る
4. `HERDR_ENV` / `HERDR_PANE_ID` を落として `spawn.sh ... --terminal "herdr pane run <pane> {cmd}"` を呼ぶ

4 で env を落とすのは、spawn の配置優先度が **`$TMUX` → herdr → `--terminal` テンプレート**で、
落とさないと herdr パスが先に勝って env 無しのペインを作り直してしまうため。

テンプレート経路は placement レコードを書かないので、`despawn --force` が `no placement record` で
失敗する。`codex-bedrock-spawn` は herdr パスと同じ形式（`herdr:<pane_id>\t<project>\tcodex`）で
自分で書いている。

> **経緯**: 以前は codex の AWS プロファイルを `dot_codex/private_bedrock.config.toml` に
> `profile = "cdx-pre-dev"` とハードコードし、`claude-bedrock` は `aws-switch` で選んだ
> `AWS_PROFILE` を流用（未設定ならエラー停止）していた。その後、両者を専用環境変数
> `{CODEX,CLAUDE_CODE}_BEDROCK_AWS_PROFILE`（既定 `cdx-pre-dev`）で切り替える方式に統一し、codex 側は
> config から `profile` を削除して `AWS_PROFILE` 経由に一本化した。あわせて claude 側の上書き変数を
> `CLAUDE_BEDROCK_*` から公式 `CLAUDE_CODE_*` に揃えるため `CLAUDE_CODE_BEDROCK_*` へ改名した。

> **経緯**: codex 側の Bedrock 切り替えは当初 `codex --profile bedrock` を呼ぶ zsh 関数だった。agmsg の
> monitor モードでは app-server が `--profile` を受け取らないため Bedrock 設定が乗らず、TUI の表示だけ
> Bedrock provider になって実際はサブスクで走る（`... is not supported when using Codex with a ChatGPT
> account.`）。いったん `AGMSG_CODEX_SHIM_DISABLE=1` で shim ごと迂回したが、それだと Bedrock セッション中に
> agmsg のリアルタイム受信が切れる。そこで一時 `CODEX_HOME` 方式へ移し、関数を `~/.local/bin/codex-bedrock`
> スクリプトに格上げしたうえで、app-server の取り合いを `codex-appserver-evict` で塞いだ。
>
> リージョンも当初 `us-west-2` だったが、`openai.gpt-5.6-sol` が 404 になるため `us-east-1` へ移した。

---

## キーバインド

| キー | 動作 |
| --- | --- |
| `C-]` | `peco-src`: ghq リポジトリを peco で絞り込んで移動 |
| `Home` | 行頭へ |
| `End` | 行末へ |
| `Delete` | カーソル位置の文字を削除 |
| `C-r` | fzf 履歴検索（`fzf --zsh`） |
| `C-t` | fzf でファイル/ディレクトリをコマンドラインへ挿入 |
| `M-c` | fzf でサブディレクトリへ `cd` |

その他、sheldon 経由の **zsh-autosuggestions**（履歴・補完ベースの候補をグレー表示、`→` で確定）と
**fzf-tab**（Tab 補完を fzf UI で選択）が有効。さらに **fzf**（aqua 管理）のキーバインドと `**<Tab>` 補完が有効（`fzf --zsh`）。

---

## 補完・ヒストリの挙動（抜粋）

| 設定 | 内容 |
| --- | --- |
| 大文字小文字 | 区別せず補完（`m:{a-z}={A-Z}`） |
| メニュー補完 | fzf-tab の UI で選択（`cd` はディレクトリを `ls` プレビュー） |
| ヒストリ | 100 万件保存、セッション間で共有（`SHARE_HISTORY`）、重複除去 |
| スペル訂正 | 無効（`CORRECT` off） |
| ベル | 鳴らさない（`NO_BEEP`） |

---

## 連携ツール（自動初期化）

インストールされていれば `.zshrc` が自動で初期化する。

| ツール | 役割 |
| --- | --- |
| `starship` | プロンプト |
| `direnv` | ディレクトリ単位の環境変数 |
| `fnm` | Node バージョン管理（`--use-on-cd`、nvim/mason が node を発見できるよう初期化） |
| `tenv` | Terraform/OpenTofu バージョン管理（自動インストール有効） |
| gcloud / aws / kubectl | 各 CLI の補完 |
| gh / uv / rg / fd / fnm / aqua / starship / tenv | zsh ネイティブ補完。aqua 更新時に chezmoi が `~/.local/share/zsh/site-functions/_<name>` を生成 |

> 補完の内訳: `gh`/`uv`/`rg`/`fd`/`fnm`/`aqua`/`starship`/`tenv` は fpath へ事前生成、
> `terraform`/`aws` は bash 動的補完（`complete -C`）、`fzf`/`gcloud`/`kubectl` は source 方式。

> CLI ツール自体は **aqua**（`dot_config/aquaproj-aqua/aqua.yaml`）で宣言的に管理。

### SSH エージェント（`25-ssh-agent.zsh`）

対話シェル起動時に SSH エージェントを用意する（`$SSH_CONNECTION` が無いローカルシェルが対象）。
プラグインを clone する `30-plugins`（sheldon）より前に走らせるため、番号は `25`。

| 条件 | 挙動 |
| --- | --- |
| `~/.1password/agent.sock` がある | 1Password の SSH エージェントを使う（`SSH_AUTH_SOCK` をそこへ向ける） |
| 使える agent が既にある（forward された agent 等、`ssh-add -l` が成功） | そのまま利用（上書きしない） |
| どちらも無い（開発サーバ等） | 通常の `ssh-agent` を常駐起動し既定鍵（`~/.ssh/id_ed25519` 等）を `ssh-add`。socket は `${XDG_RUNTIME_DIR:-$HOME}/.ssh-agent.env` に保存して以降のシェルで再利用（多重起動しない） |

> **初回ログインで sheldon のプラグイン clone が `Auth(-16)` で落ちる時**もこれが原因。
> `dot_gitconfig.tmpl` の `insteadOf` が https を SSH へ書き換えるため、agent が無いと
> clone できない。`25-ssh-agent` が `30-plugins` より前に走ることで解決している。

> **gitui の push が `bad credentials` で失敗する時**はこれが原因。gitui は libgit2 経由で
> SSH 鍵を **agent 経由でしか使えず**、鍵ファイルを直読みしない。上記フォールバックで
> agent に鍵が載るので、**新しいシェルを開いて**（または `exec zsh`）から gitui を起動すれば通る。
> 詳細は [gitui チートシート](gitui-cheatsheet.md#push-が-bad-credentials-で失敗する)。
