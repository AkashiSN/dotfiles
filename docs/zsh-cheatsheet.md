# zsh チートシート

zsh 設定（`dot_zshrc` / `dot_zshenv.tmpl`）のエイリアス・関数・キーバインドをまとめたリファレンス。

- プラグイン管理: **sheldon**（fzf-tab / zsh-autosuggestions 等）
- プロンプト: **starship**（SSH/root 接続時はプロンプト先頭に `user@host` を表示。ローカル通常時は非表示）
- ディレクトリ移動: `AUTO_PUSHD` 有効（`cd` 履歴がスタックに積まれる）
- エディタ: `nvim`（`EDITOR` / `VISUAL`。`dot_zshenv.tmpl` で設定。非インタラクティブ実行にも適用）
- ロケール: `LANG=ja_JP.UTF-8`（`dot_zshenv.tmpl` で設定。全シェル/スクリプトに適用）
- Rust: toolchain は **rustup**（aqua 管理）で導入。`cargo`/`rustc` は `$CARGO_HOME/bin`（=`~/.local/share/cargo/bin`）を PATH に追加。実体は run_onchange の `32-rust-default` が `rustup-init` で provisioning
- 構成: `dot_zshrc` はローダー。実体は `~/.config/zsh/rc.d/*.zsh`（`00-options` / `10-path` / `20-completion` / `30-plugins` / `40-tools` / `50-functions` / `60-aliases` / `70-keybindings`）を番号順に zcompile + source

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
| `codex-bedrock [args]` | codex を Amazon Bedrock へ切り替えて起動（`codex --profile bedrock`）。通常の `codex` はサブスク（OpenAI ログイン）のまま。Bedrock 設定は `~/.codex/bedrock.config.toml`（`dot_codex/private_bedrock.config.toml`）にプロファイルとして分離してあり、`--profile` でベース設定の上にレイヤする。使う AWS プロファイルは `CODEX_BEDROCK_AWS_PROFILE`（既定 `cdx-pre-dev`）で `AWS_PROFILE` に渡し（サブシェルに閉じ込め対話シェルは汚さない）、その `credential_process = aws-login` が認証を担う。リージョン/モデルを変えるときはプロファイルファイルを直接編集 |

### SSH セッションでの `$BROWSER` 自動切替（portfwd）

portfwd でオプトインした SSH セッションでは `$BROWSER` が自動で `~/.local/bin/portfwd-open` にセットされ、`aws login` / `gh auth` 等がブラウザを開こうとするとローカルのブラウザが開く（`dot_zshenv.tmpl` の `LC_PORTFWD_HOST` チェックによる）。詳細は [portfwd-cheatsheet.md](portfwd-cheatsheet.md) を参照。

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
| `CLAUDE_CODE_BEDROCK_OPUS_MODEL` | `global.anthropic.claude-opus-4-8` |
| `CLAUDE_CODE_BEDROCK_SONNET_MODEL` | `global.anthropic.claude-sonnet-4-6` |
| `CLAUDE_CODE_BEDROCK_HAIKU_MODEL` | `global.anthropic.claude-haiku-4-5-20251001-v1:0` |

> 内部で `CLAUDE_CODE_USE_BEDROCK=1` と上記モデルを `ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU}_MODEL` に
> 渡して `claude` を起動する。Bedrock 連携の詳細は [AWS チートシート](aws-cheatsheet.md) の認証フロー（`aws-switch` / `aws-login`）も参照。

> **経緯**: 以前は codex の AWS プロファイルを `dot_codex/private_bedrock.config.toml` に
> `profile = "cdx-pre-dev"` とハードコードし、`claude-bedrock` は `aws-switch` で選んだ
> `AWS_PROFILE` を流用（未設定ならエラー停止）していた。その後、両者を専用環境変数
> `{CODEX,CLAUDE_CODE}_BEDROCK_AWS_PROFILE`（既定 `cdx-pre-dev`）で切り替える方式に統一し、codex 側は
> config から `profile` を削除して `AWS_PROFILE` 経由に一本化した。あわせて claude 側の上書き変数を
> `CLAUDE_BEDROCK_*` から公式 `CLAUDE_CODE_*` に揃えるため `CLAUDE_CODE_BEDROCK_*` へ改名した。

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
