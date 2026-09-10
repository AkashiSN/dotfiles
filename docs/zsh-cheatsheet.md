# zsh チートシート

zsh 設定（`dot_zshrc` / `dot_zshenv.tmpl` / `dot_config/shell/`）のエイリアス・関数・キーバインドをまとめたリファレンス。

- プラグイン管理: **sheldon**（`zsh-completions` の fpath 追加と compinit）
- プロンプト: **starship**（SSH/root 接続時はプロンプト先頭に `user@host` を表示。ローカル通常時は非表示）
- ディレクトリ移動: zsh 既定どおり（`AUTO_PUSHD` は外した。`cd -` は直前のディレクトリへ戻るだけ）
- エディタ: `nvim`（`EDITOR` / `VISUAL`。`dot_config/shell/env.sh.tmpl` で設定。zsh・bash 共通、非インタラクティブ実行にも適用）
- ロケール: `LANG=ja_JP.UTF-8`（`dot_config/shell/env.sh.tmpl` で設定。全シェル/スクリプトに適用）
- Python: `~/.local/bin` を `dot_config/shell/env.sh.tmpl` で `/usr/bin` より前に置くので、`python` / `python3` は uv が `--default` で入れた版（`dot_config/uv/dot_python-version` の 3.13）になる。`env.sh` に置くのは非対話シェル（ssh の一発実行・スクリプト・他ツールからの起動）や bash でも同じ処理系を引かせるため。詳細は [uv-cheatsheet.md](uv-cheatsheet.md)
- Rust: toolchain は **rustup**（aqua 管理）で導入。`cargo`/`rustc` は `$CARGO_HOME/bin`（=`~/.local/share/cargo/bin`）を PATH に追加。実体は run_onchange の `32-rust-default` が `rustup-init` で provisioning
- Terraform: `TF_PLUGIN_CACHE_DIR`（=`~/.cache/terraform/plugin-cache`）を `dot_config/shell/env.sh.tmpl` で設定し、provider をプロジェクト間で共有。詳細は [terraform-cheatsheet.md](terraform-cheatsheet.md)
- 構成: 環境変数と alias は zsh・bash 共通の `~/.config/shell/{env,aliases}.sh`（[シェルの役割分担](#シェルの役割分担)）。`dot_zshrc` はローダーで、対話専用の実体は `~/.config/zsh/rc.d/*.zsh`（`00-options` / `10-path` / `20-completion` / `25-ssh-agent` / `30-plugins` / `40-tools` / `50-functions` / `60-aliases` / `70-keybindings`）を番号順に zcompile + source

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
| `claude [args]` | **既定で Amazon Bedrock（グローバル推論プロファイル）へ向ける。** `~/.local/bin/claude-bedrock` 経由で起動し、起動前に AWS プロファイルの認証を確かめる。恒久的に素（claude.ai 認証）へ戻すときは `touch ~/.config/zsh/no-claude-bedrock`、一度だけの迂回は `command claude`。素で起動するときは、**SSH 接続先で引数なしの素の起動**のときだけ `--remote-control` を自動付与する（claude.ai / モバイル等のリモートからそのインタラクティブセッションを操作可能。Bedrock 経路でも `claude-bedrock` が同じ規則を持つ）。引数付き（プロンプト・`-p`/`--print`・`mcp`/`update` 等のサブコマンド・`-c`/`--resume` 等）は素通し |
| `claude-bedrock [args]` | Claude Code を Amazon Bedrock（グローバル推論プロファイル）で起動するスクリプト（`~/.local/bin/claude-bedrock`）。対話シェルの `claude` もここを通る。使う AWS プロファイルは `CLAUDE_CODE_BEDROCK_AWS_PROFILE`。設定しておけば対話中に `aws-switch` で選んでいるプロファイルに影響されず、未設定なら `AWS_PROFILE`（無ければ `~/.env`）に従う。既定値はハードコードしていないので、どちらも無ければ起動しない。認証は `aws-login`（credential_process）が担う（追加ログイン不要）。ただし**起動前に `aws-auth-ensure` でそのプロファイルが認証済みかを確かめ、未認証なら起動しない**（[aws-cheatsheet.md](aws-cheatsheet.md#aws-auth-ensure)）。リージョン/モデルは下表の `CLAUDE_CODE_BEDROCK_*` で上書き可。SSH 接続先の引数なし起動には `claude`（関数）と同じ規則で `--remote-control` を足す |
| `codex [args]` | **既定で Amazon Bedrock へ向ける。** `~/.local/bin/codex-bedrock` 経由で起動する。恒久的に素（OpenAI サブスク認証）へ戻すときは `touch ~/.config/zsh/no-codex-bedrock`（agmsg の spawn も一緒に戻る）、一度だけの迂回は `command codex`。素で起動するときは、その前に `codex-appserver-evict` で共有 app-server の `CODEX_HOME` を照合し、食い違う app-server（＝ Bedrock 用に残ったもの）を畳んで作り直させる（素の codex が黙って Bedrock で走るのを防ぐ）。app-server に繋がない呼び出し（`exec` / `login` / `--version` など）では何もしない |
| `codex-bedrock [args]` | codex を Amazon Bedrock で起動するスクリプト（`~/.local/bin/codex-bedrock`）。対話シェルの `codex` もここを通る。`CODEX_HOME` をプロジェクトごとの一時 home へ向け、その `config.toml` を「素の config ＋ `~/.codex/bedrock.config.toml`」にする。使う AWS プロファイルは `CODEX_BEDROCK_AWS_PROFILE`、無ければ `AWS_PROFILE`（どちらも無ければ起動しない）。それを `AWS_PROFILE` として渡し、その `credential_process = aws-login` が認証を担う。ただし**起動前に `aws-auth-ensure` でそのプロファイルが認証済みかを確かめ、未認証なら起動しない**（[aws-cheatsheet.md](aws-cheatsheet.md#aws-auth-ensure)）。リージョン/モデルを変えるときは `dot_codex/private_bedrock.config.toml` を編集 |
| `codex-bedrock-spawn <name> [opts]` | agmsg の codex エージェントを Bedrock で動く状態で herdr のペインに立ち上げる（`~/.local/bin/codex-bedrock-spawn`）。内部で `spawn.sh` を呼ぶ。ペインを作る前に `aws-auth-ensure` で Bedrock 用プロファイルの認証を済ませる（spawn 先の codex は `codex-bedrock` を通らないため）。`~/.config/zsh/no-codex-bedrock` があるときは素の `spawn.sh` へそのまま委譲する（＝ OpenAI サブスクの codex を spawn する）。`--team` / `--project` / `--direction` 以外の引数は spawn.sh へ素通し（`--boot-prompt` など）。片付けは素の agmsg と同じ `despawn.sh <team> <self> <name> --force` |
| `term-reset` | 端末のマウス報告 / フォーカス報告 / 括弧付き貼り付け / Kitty keyboard protocol（`\e[<u` で pop、`\e[=0;1u` でフラグ 0）を無効化して端末状態を復旧。SSH 異常切断でリモートの nvim 等が有効化した端末モードが居残り、キー入力で `15;1:3u` 等・マウスで `0;129;39M` 等が漏れたときに叩く（素の端末でも無害）。詳細は [herdr チートシート](herdr-cheatsheet.md#ssh-異常切断後の端末化けterm-reset) |
| `herdr [args]` / `ssh [args]` | ローカルシェルでのみ実バイナリをラップし、戻り際に必ず `term-reset` する（`herdr --remote` / `ssh` 先の異常切断による端末化けを自動復旧）。herdr は内部で自前の ssh を exec するため `herdr` 自体もラップ対象。リモートシェル（`$SSH_CONNECTION` あり）ではラップしない |

**`claude-bedrock` は関数ではなくスクリプト**（`~/.local/bin/claude-bedrock`）。env の組み立てと
AWS プロファイルの解決は `~/.local/bin/claude-bedrock-wrapper`（`<claude 実行ファイル> [args...]`
を受け取って exec する）に一本化してあり、`claude-bedrock` はそこへ PATH 上の `claude` を渡すだけ。
分けてあるのは、VS Code 拡張の `claudeCode.claudeProcessWrapper` が**シェルを経由せず実行ファイルの
パス**を spawn するため（zsh 関数や alias では届かない）。

> **VS Code は既定では Bedrock にしていない**（手元の VS Code は claude.ai のサブスクリプションで
> 使うため）。拡張から Bedrock で動かしたいときだけ、`Library/Application Support/Code/User/settings.json`
> に次を足す。拡張はシェルを経由しないので、zsh の `claude` 関数（Remote Control 付与）も通らない。
>
> ```json
> "claudeCode.claudeProcessWrapper": "/Users/<user>/.local/bin/claude-bedrock-wrapper"
> ```
>
> なお `claudeProcessWrapper` が効くのは**拡張自身が spawn するプロセス**だけで、エディタ右上の
> Claude Code アイコン（`claude-vscode.terminal.open`）は統合ターミナルへリテラル `claude` を流す
> 別実装のため、この設定を見ない。アイコンから Bedrock で起動したいときは、ターミナルで
> `claude-bedrock` を打つ。

### SSH セッションでの `$BROWSER` 自動切替（portfwd）

portfwd でオプトインした SSH セッションでは `$BROWSER` が自動で `~/.local/bin/portfwd-open` にセットされ、`aws login` / `gh auth` 等がブラウザを開こうとするとローカルのブラウザが開く（`dot_config/shell/env.sh.tmpl` の `LC_PORTFWD_HOST` チェックによる）。`$BROWSER` が既にセットされている場合（VSCode Remote 等が自前のヘルパを仕込んでいる場合）は上書きしない。詳細は [portfwd-cheatsheet.md](portfwd-cheatsheet.md) を参照。

### bedrock 起動で使う AWS プロファイル

`claude-bedrock` / `codex-bedrock` はそれぞれ専用の環境変数で `AWS_PROFILE` を決める。専用変数を
`~/.env` に書いておけば、対話中に `aws-switch` で切り替えても bedrock 用はそこに固定される
（`claude-bedrock` は自分のプロセス内、`codex-bedrock` はサブシェルに閉じ込めるので、どちらも
対話シェルの `AWS_PROFILE` は不変）。**既定のプロファイルはハードコードしていない**ので、専用変数も
`AWS_PROFILE` も無ければ起動せずに終わる（意図しないアカウントを黙って触らないため）。
**対話シェルの `claude` / `codex` は既定でこの経路を通る**ので、素で使いたいときは下のマーカーを置く。

| 変数 | 未設定のとき | 対象 |
| --- | --- | --- |
| `CLAUDE_CODE_BEDROCK_AWS_PROFILE` | `AWS_PROFILE` →（それも無ければ）`~/.env` の値 | `claude-bedrock` |
| `CODEX_BEDROCK_AWS_PROFILE` | `AWS_PROFILE` | `codex-bedrock` / `codex-bedrock-spawn` |

`claude-bedrock` と `codex-bedrock` は起動前に `aws-auth-ensure` を通す。未認証のまま起動すると、
TUI が立ったあとで `credential_process`（`aws-login`）がログイン URL を `/dev/tty` へ出して画面が
崩れるため。未認証ならそこで止まる（Bedrock 用プロファイルが無いと動かないので、警告では済ませない）。
確かめるのはどちらも Bedrock 用の 1 つだけ。あわせて配下へ `AWS_LOGIN_NO_INTERACTIVE=1` を撒き、
走行中に期限が切れても画面の中に URL を描かせない。切れたときは herdr のタブと statusLine で人へ渡る
（[aws-cheatsheet.md](aws-cheatsheet.md#走行中に認証が切れたとき)）。

> `.expired` を読む statusLine は Claude Code にしか無いので、codex で走行中に切れたときに気づく
> 手掛かりは herdr のタブだけになる。

#### 素のバイナリへ戻す（マーカー）

| 置くファイル | 効果 |
| --- | --- |
| `~/.config/zsh/no-claude-bedrock` | 対話シェルの `claude` が claude.ai 認証の素のバイナリで起動する |
| `~/.config/zsh/no-codex-bedrock` | 対話シェルの `codex` と `codex-bedrock-spawn` が OpenAI サブスク認証の素の codex で起動する |

一度だけ迂回するなら `command claude` / `command codex`（関数ごと素通しするので、起動前の認証
確認も通らない）。マーカーは chezmoi の管理外なので、置く / 消すのはマシンごとの判断。

**関数が効くのは対話 zsh だけ。** Claude Code 自身が走らせるシェルは `CLAUDE_CODE_SHELL=/bin/bash`
なので、Claude Code の Bash ツールから `claude` / `codex` を叩いても素のバイナリが動く。VS Code
拡張の spawn は `claudeProcessWrapper`、agmsg の spawn は `codex-bedrock-spawn` で手当てしている。

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
`us-east-2` / `openai.gpt-5.6-sol`。**`openai.gpt-5.6-sol` を提供しているのは `us-east-1` と
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
`codex-bedrock` はプロジェクトごとに `~/.cache/codex-bedrock/<sha1(プロジェクトパス)>`
（`$XDG_CACHE_HOME` があればその下）を用意し、そこへ:

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

置き場をホーム配下にしているのは、**codex が一時ディレクトリ配下の `CODEX_HOME` を「一時的なもの」と
みなし、PATH ヘルパー（`apply_patch` など）を作らない**ため。`$TMPDIR` に置くとこれらが効かない。

一時 home のパスは `pwd -P` で**シンボリックリンクを解決した形**にする。codex は信頼キーを解決後の絶対
パスで持つため、macOS の `/var` → `/private/var` のような表記違いがあるとキーが一致しない。

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

#### 一時 home の回収と作り直し

回収も作り直しも起動時に行う（終了時ではないので、異常終了して残ったものも次の起動で片付く）。判断は
3 つの条件を組み合わせる:

- **参照している codex が居るか** — 生きている `codex` プロセスの `CODEX_HOME` を `ps eww` で集めて照合する。
  走っている codex の下で `config.toml` を書き換えると、codex が書き戻す実行時状態を壊す
- **用意してから 2 分（`FRESH_MIN`）以内か** — home を用意し終えてから codex がプロセス一覧に出るまでの窓を
  守る。この間の home は「誰も使っていない」ように見えるが、これから使われる
- **合成のもとが新しいか** — 素の `config.toml` か `bedrock.config.toml` が合成済みより新しいときだけ
  作り直す。毎回作り直すと、codex がその home に書いた信頼（プロジェクト・フックの trust）が起動のたびに
  失われ、そのつど確認を聞かれる

同時起動は `~/.cache/codex-bedrock/.lock` の `flock` で直列化する。無いと、並行起動した 2 つが揃って
「誰も使っていない」と判定し、同じ home を消して作り直し、一方の作りかけをもう一方が消してしまう。
作るときは別ディレクトリ（`.build.<pid>`）で組み立ててから rename するので、途中で失敗しても欠けたものが
home として残らない。

セッション履歴やスレッド DB は実 home と別になる（`sessions` だけ共有）。

### app-server の取り合いを防ぐ（`codex-appserver-evict`）

app-server は `$SKILL_DIR/run/codex-app-server.<sha1(プロジェクトパス)>` でキーされ、再利用の判定は
「pid 生存 / ポート応答 / コマンド名一致」だけで設定を見ていない。よって同じプロジェクトで素の codex と
Bedrock 版を混ぜると、先に起動した側の app-server を後から起動した側が黙って再利用する。**素の codex が
Bedrock 用 app-server を拾う向き**は課金先が変わるので特に厄介。

`codex-appserver-evict <期待する CODEX_HOME> [codex の引数...]` が起動直前にこれを潰す。`pgrep` と `lsof`
でそのプロジェクト（＝ cwd 一致）の app-server を特定し、`ps eww` でその `CODEX_HOME` を読んで、期待と
違えば畳む。候補は `ps -o args=` で**argv がちょうど `codex app-server ...` の形か**まで確かめる。
`pgrep -f` はコマンドライン全体への部分一致なので、その文字列を含むだけの無関係なプロセス（このスクリプトを
探して走らせているシェル自身を含む）まで挙がり、cwd もプロジェクトと一致してしまうため。agmsg の run ディレクトリ名には依存せず codex 自身のプロセス署名だけを見ているので、agmsg 側の
命名が変わっても壊れない。`codex` 関数と `codex-bedrock` の両方から呼ぶので、どちら向きの取り違えも防げる。

同じ種類（同じ `CODEX_HOME`）なら畳まないため、同一プロジェクトで codex-bedrock を並行起動しても
app-server を共有できる。逆に、種類をまたいで切り替えるときは**開いていた側のセッションが切れる**。

### agmsg spawn で Bedrock の codex をペインに出す

`codex-bedrock-spawn <name>` を使う。herdr のペインの中から実行すること。`~/.config/zsh/no-codex-bedrock`
があるときは素の `spawn.sh` へ委譲するので、**手打ちの `codex` と spawn がマーカー 1 つで一緒に
切り替わる**。

```sh
codex-bedrock-spawn reviewer
#   → spawned codex 'reviewer' (team dotfiles) in herdr pane wQ:p7
#       CODEX_HOME  /Users/<user>/.cache/codex-bedrock/<sha1>
#       AWS_PROFILE <bedrock 用プロファイル>
```

送信・確認・片付けは素の agmsg と同じ（`delivery.sh status` → `send.sh` →
`despawn.sh ... --force`）。手順の全体は [~/.claude/CLAUDE.md](../private_dot_claude/modify_CLAUDE.md)
の「codex にレビューを依頼するときの手順」にある。

素の `spawn.sh codex <name>` では Bedrock にならない。TUI が共有 app-server へ `--remote` で繋がる以上、
`CODEX_HOME` を Bedrock 用の一時 home へ向けるしかないが、spawn.sh 側にその隙が無いためだ:

- spawn.sh の herdr パス（`launch_in_herdr`）は `herdr pane split` を **`--env` 無しで**呼ぶ
- マニフェスト（`drivers/types/codex/type.conf`）の `cli=codex` は固定で差し替えられない
- codex に `--profile` 相当の環境変数は無い

`codex-bedrock-spawn` がやっていることは 5 つ:

1. `aws-auth-ensure` で Bedrock 用プロファイルの認証を済ませる（未認証ならここでログインし、
   通らなければ spawn しない）
2. `codex-bedrock --print-home` で一時 home を用意（codex は起動しない）
3. 一時 home の `config.toml` にこのプロジェクトの `trust_level = "trusted"` を書く
4. `codex-appserver-evict` で食い違う app-server を畳む
5. `herdr pane split --env CODEX_HOME=... --env AWS_PROFILE=... --env AWS_LOGIN_NO_INTERACTIVE=1` で
   ペインを作る
6. `HERDR_ENV` / `HERDR_PANE_ID` を落として `spawn.sh ... --terminal "herdr pane run <pane> {cmd}"` を呼ぶ

1 が要るのは、spawn 先の codex が `codex-bedrock` を通らないため（`spawn.sh` は `type.conf` の
`cli=codex` を非対話 bash のブートスクリプトから直接 exec する）。スクリプトが持つ起動前チェックは
spawn には効かないので、人の居るこのペインで先に通しておく。5 の `AWS_LOGIN_NO_INTERACTIVE` は、
走行中に期限が切れたときログイン URL を spawn 先のペインへ描かせないため（代わりに herdr のタブへ
委譲される）。

3 は agmsg の配信フックのため。codex はプロジェクトを信頼するまでプロジェクトローカルの config /
hooks / exec policy を読まないので、`.codex/hooks.json` が効かない。書くのは揮発する一時 home の
`config.toml` だけで、素の `~/.codex/config.toml` には触らない（信頼するのは agmsg が立ち上げた
この codex に限る）。一時 home を作り直した直後は、codex が一度だけフックの確認を出す。

6 で env を落とすのは、spawn の配置優先度が **`$TMUX` → herdr → `--terminal` テンプレート**で、
落とさないと herdr パスが先に勝って env 無しのペインを作り直してしまうため。

テンプレート経路は placement レコードを書かないので、`despawn --force` が `no placement record` で
失敗する。`codex-bedrock-spawn` は herdr パスと同じ形式（`herdr:<pane_id>\t<project>\tcodex`）で
自分で書いている。既存レコードは常に上書きする——前の異常終了で古い pane_id が残っていると、
`despawn --force` がそちらを畳んで今のペインを取り逃がすため。途中で失敗したときは、作ったペインと
書きかけのレコードを畳んでから終わる。

> **経緯**: 以前は codex の AWS プロファイルを `dot_codex/private_bedrock.config.toml` に
> `profile = "<profile>"` とハードコードし、`claude-bedrock` は `aws-switch` で選んだ
> `AWS_PROFILE` を流用（未設定ならエラー停止）していた。その後、両者を専用環境変数
> `{CODEX,CLAUDE_CODE}_BEDROCK_AWS_PROFILE` で切り替える方式に統一し、codex 側は
> config から `profile` を削除して `AWS_PROFILE` 経由に一本化した。あわせて claude 側の上書き変数を
> `CLAUDE_BEDROCK_*` から公式 `CLAUDE_CODE_*` に揃えるため `CLAUDE_CODE_BEDROCK_*` へ改名した。

> **経緯**: codex 側の Bedrock 切り替えは当初 `codex --profile bedrock` を呼ぶ zsh 関数だった。agmsg の
> monitor モードでは app-server が `--profile` を受け取らないため Bedrock 設定が乗らず、TUI の表示だけ
> Bedrock provider になって実際はサブスクで走る（`... is not supported when using Codex with a ChatGPT
> account.`）。いったん `AGMSG_CODEX_SHIM_DISABLE=1` で shim ごと迂回したが、それだと Bedrock セッション中に
> agmsg のリアルタイム受信が切れる。そこで一時 `CODEX_HOME` 方式へ移し、関数を `~/.local/bin/codex-bedrock`
> スクリプトに格上げしたうえで、app-server の取り合いを `codex-appserver-evict` で塞いだ。
>
> リージョンも当初 `us-west-2` だったが、`openai.gpt-5.6-sol` が 404 になるため `us-east-1` へ移し、
> その後 work 側の dotfiles と揃えて `us-east-2` にした。

---

## キーバインド

| キー | 動作 |
| --- | --- |
| `Tab` | 1 回目で一意に決まるところまで補完して候補一覧を表示。2 回目以降は一覧の選択が動き、行のテキストも同時に置き換わる |
| `Enter`（一覧表示中） | 選択中の候補で確定（実行はもう一度 `Enter`） |
| `↑` `↓` `←` `→`（一覧表示中） | 選択を移動 |
| `C-g`（一覧表示中） | 選択を取り消して `Tab` を押す前の行へ戻す |
| `**` + `Tab` | fzf でファイル/ディレクトリを絞り込んで挿入（`fzf --zsh`） |
| `C-]` | `peco-src`: ghq リポジトリを peco で絞り込んで移動 |
| `Home` | 行頭へ |
| `End` | 行末へ |
| `Delete` | カーソル位置の文字を削除 |
| `C-r` | fzf 履歴検索（`fzf --zsh`） |
| `C-t` | fzf でファイル/ディレクトリをコマンドラインへ挿入 |
| `M-c` | fzf でサブディレクトリへ `cd` |

`Tab` は zsh 標準の menu selection（`zstyle ':completion:*' menu select`）に一本化してある。1 回目の `Tab` で
候補の共通接頭辞まで挿入して一覧を出し（`AUTO_LIST` + `unsetopt LIST_AMBIGUOUS`）、2 回目からは `AUTO_MENU` が
一覧の選択を動かす。**一覧のハイライトと行のテキストは常に同じものを指す**ので、見えている候補が
そのまま入る。`bindkey` で `Tab` に何かを割り当てることはしていない。

候補は補完システムのタグごとにグループへ分かれて並ぶ（`group-name ''`）。ヒストリは混ぜていない
（履歴からの検索は `C-r`）。

`**<Tab>` 補完と `C-r` / `C-t` / `M-c` は **fzf**（aqua 管理、`fzf --zsh`）のもので、`Tab` は fzf の
`fzf-completion` を経由して素の補完へ落ちる。

---

## 補完・ヒストリの挙動（抜粋）

| 設定 | 内容 |
| --- | --- |
| 大文字小文字 | 区別せず補完（`m:{a-z}={A-Z}`） |
| メニュー補完 | zsh 標準の menu selection。1 回目の `Tab` で共通接頭辞＋一覧、2 回目以降で選択が巡回 |
| ヒストリ | 100 万件保存、セッション間で共有（`SHARE_HISTORY`）、重複除去 |
| スペル訂正 | 無効（`CORRECT` off） |
| ベル | 鳴らさない（`NO_BEEP`） |

---

## シェルの役割分担

ログインシェルは **zsh のまま**。一方 Claude Code の Bash ツールは
`CLAUDE_CODE_SHELL=/bin/bash`（`~/.claude/settings.json` の `env`。ソースは
`private_dot_claude/modify_settings.json.tmpl`）により **常に bash** で走る。同じマシンで
2 つのシェルが動くため、設定を「両シェルが見る共通の土台」と「zsh 専用の対話部分」に分けている。

### 全体像

```
                    ~/.config/shell/env.sh        ← POSIX sh。両シェルの唯一の env 源
                       ↑ source          ↑ source
                   ~/.zshenv           ~/.bashrc
                （zsh 固有のみ）          + aliases.sh
                       ↓                 + direnv hook bash / fnm env
   ~/.zshrc → rc.d/*.zsh                ~/.bash_profile
   （対話専用。bash へは持っていかない）   ├ 対話 → exec zsh -l（今までどおり）
                                          └ 非対話 → . ~/.bashrc（Claude の経路）
```

`~/.config/shell/env.sh` の実体は chezmoi テンプレート（`dot_config/shell/env.sh.tmpl`）。
Homebrew の prefix がアーキテクチャで変わるためテンプレートにしてある。

### なぜ Claude は bash なのか

Claude が bash の手癖でコマンドを書き、それが zsh で実行されると、エラーにならないまま
挙動だけが変わる事故が起きる。手元で実測した差分は以下（`zsh -f` と `bash --norc`）。

| # | 差分 | bash | zsh |
| --- | --- | --- | --- |
| 1 | マッチ 0 件の glob | パターンが literal で渡る（`ls` がエラー） | `no matches found` でコマンド自体を実行しない |
| 2 | `$VAR` の単語分割 | 分割する（3 引数） | 分割しない（1 引数） |
| 3 | 配列の添字 | 0 始まり | 1 始まり（`${arr[0]}` が空） |
| 4 | `echo "a\tb"` | `\t` のまま | 実タブに解釈 |
| 5 | `echo x \| read v` | `v` は空 | `v=x`（パイプの最終要素が現在のシェルで走る） |

2 と 3 は「エラーにならず、意図と違う対象に対して成功する」型なので特に気づきにくい。
1 は `NULL_GLOB` を[既定から外した](#既定から外さないオプション)ことで「黙って引数が消える」
から「その場で止まる」に変わったが、bash とは依然として違う。

### どこに何を書くか

| 書きたいもの | 置き場所 |
| --- | --- |
| 環境変数 / PATH | `~/.config/shell/env.sh`（ソースは `dot_config/shell/env.sh.tmpl`） |
| 両シェル共通の alias | `~/.config/shell/aliases.sh` |
| 両シェル共通の振る舞いが要るもの | まず `~/.local/bin/` のスクリプト化を検討する |
| 補完 / prompt / キーバインド / ZLE | `~/.config/zsh/rc.d/` |

`~/.local/bin/` のスクリプトにするのは、VS Code / Kiro 拡張の spawn や agmsg の `spawn.sh` の
ようにシェルの rc を経由しない起動経路にも届かせるため（`mo` / `claude-bedrock` /
`codex-bedrock` が該当）。

### env.sh の触ってはいけない不変条件

- **`MANPATH` / `INFOPATH` の末尾の空要素（コロン）を壊さない。** man と GNU info はパス中の
  空要素を「ここに組み込みの既定を挿入する」という意味で扱うため、これが無いと自前のパスで
  既定がまるごと置き換わり、`man ls` のような標準マニュアルが引けなくなる。`env.sh` は
  最後にまとめて末尾コロンを足す（先に `MANPATH=":"` を代入する形は zsh の
  `typeset -U manpath` に潰されるので不可）。
- **`LD_LIBRARY_PATH` / `LIBRARY_PATH` / `PKG_CONFIG_PATH` / `C_INCLUDE_PATH` /
  `CPLUS_INCLUDE_PATH` には逆に空要素を足さない。** 動的リンカ・プリプロセッサ・pkg-config に
  とって空要素は「カレントディレクトリ」を意味し、意図せずカレントのライブラリ/ヘッダを拾う
  経路ができる。`MANPATH` に揃えて対称化したくなっても、この 5 つには足さない。
- **PATH への追加は `_path_add`（move-to-front）を使う。** `~/.zshenv` が先に走らせる
  `path_helper` が `/etc/paths.d` 由来の `/opt/homebrew/bin` を PATH の**後方**へ入れるため、
  「既出なら何もしない」実装だと Homebrew のコマンドが `/usr/bin` より後ろに残り、`git` などが
  macOS 同梱の版に解決されてしまう。`_prepend`（既出なら何もしない）は空要素の意味を持つ
  `MANPATH` / `INFOPATH` 側で使う。

### 禁止事項

- `~/.bashrc`（`dot_bashrc`）に `shopt -s nullglob` を書かない。`IFS` を変えない。
  上の 1 番の事故を bash 側へ持ち込むことになる。
- `~/.config/shell/*.sh` は **POSIX sh** で書く。`[[ ]]` / 配列 / `local` は bash・zsh 拡張で、
  `sh` として source されると構文エラーになる。

---

## 既定から外さないオプション

`00-options.zsh` に置いてよいのは「表示・補完・履歴」だけで、**コマンドの引数や意味を
変えるオプションは置かない**。zsh の既定から外すと、bash の書き方で書かれたコマンドが
黙って違う対象に対して成功する。過去にここで on にしていたが、事故のもとなので外した
（zsh の既定はすべて off）。

| オプション | 実測した影響 |
| --- | --- |
| `NULL_GLOB` | マッチ 0 件で引数ごと消える → `grep p *.md` が stdin でハングする |
| `BRACE_CCL` | `{json}` が `j n o s` の 4 引数に化ける |
| `MARK_DIRS` | glob 結果が `sub` → `sub/`（rsync は末尾の / で意味が変わる） |
| `MAGIC_EQUAL_SUBST` | `--out=~/x` が `--out=/home/you/x` に展開される |
| `NUMERIC_GLOB_SORT` | glob の並びが f1,f10,f2 → f1,f2,f10 に変わる |

あわせて、対話時の安全網を消していた `AUTO_RESUME` / `RM_STAR_SILENT` と、`cd -` の意味を
変える `AUTO_PUSHD` / `PUSHD_IGNORE_DUPS`、`!` を履歴展開する `HIST_EXPAND` も外した。
実際の端末の `TERM` を無条件に上書きしていた `export TERM=xterm-256color`（ghostty 側で
`term = xterm-256color` を設定済みなので二重）と、zsh では効かない bash 変数
`HISTTIMEFORMAT`（書式も誤り）も削除済み。

### `/etc/profile.d` の読み込み（`10-path.zsh`）

`/etc/profile.d/*.sh` は sh 向けのサードパーティスクリプト群。zsh は既定の `NOMATCH` により
マッチ 0 件の glob をエラーにするため、そのまま source すると失敗するものがある
（`debuginfod.sh` が実例）。`10-path.zsh` は `emulate -L sh` を関数内だけに閉じて sh 意味論に
切り替え、その中で source することでこれを避けている。

**`NULL_GLOB` を外すまでは、この非互換は `NULL_GLOB`（マッチ 0 件で引数ごと消える）の副作用で
偶然隠れており、気づかれていなかった。** `NULL_GLOB` を既定から外したことでこの非互換が
露出したため、sh 意味論での実行に切り替えた。

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
