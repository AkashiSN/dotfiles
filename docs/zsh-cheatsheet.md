# zsh チートシート

zsh 設定（`dot_zshrc` / `dot_zshenv.tmpl`）のエイリアス・関数・キーバインドをまとめたリファレンス。

- プラグイン管理: **sheldon**（fzf-tab / zsh-autosuggestions 等）
- プロンプト: **starship**（SSH/root 接続時はプロンプト先頭に `user@host` を表示。ローカル通常時は非表示）
- ディレクトリ移動: `AUTO_PUSHD` 有効（`cd` 履歴がスタックに積まれる）
- エディタ: `nvim`（`EDITOR` / `VISUAL`）
- ロケール: `LANG=ja_JP.UTF-8`（`dot_zshenv.tmpl` で設定。全シェル/スクリプトに適用）
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
| `ide [path...]` | nvim を VSCode ライクな IDE レイアウトで起動（`NVIM_IDE=1 nvim`）。SSH 経由（かつ tmux 外）のときは作業ディレクトリ単位の tmux セッションで包んで切断耐性を付ける（切断後は同じ場所で再度 `ide` すれば復帰）。詳細は [Neovim チートシート](nvim-cheatsheet.md) |
| `ssh <host>` | ローカルでは関数でラップされ、戻り際に必ず `term-reset` を実行（リモートで `ide` の tmux を起動したまま Broken pipe で切れても端末が化けない）。リモートシェルでは素の ssh のまま |
| `term-reset` | 端末のマウストラッキング/フォーカス報告/括弧付き貼り付けを無効化して復旧。SSH 異常切断後にクリックで `0;129;39M` 等が出て操作不能になったときに実行（ローカルの `ssh`/`tssh` 経由なら自動。それ以外で踏んだら手動で） |
| `latex [args]` | Docker（akashisn/latexmk）で latexmk をビルド |
| `pdfcrop [args]` | Docker で PDF の余白をクロップ |
| `search <word>...` | カレント以下のファイルパスを複数語で AND 絞り込み（クォート出力） |
| `convert-crlf-to-lf` | CRLF のファイルを検出して LF へ一括変換（nkf） |
| `peco-src` | `ghq` 管理リポジトリを peco で選んで `cd`（キー: `C-]`） |
| `agmsg-bridge-reap` | agmsg Codex monitor の残留 `codex-bridge.js`（孤児のみ）を回収。ログイン時に自動実行。詳細は [agmsg チートシート](agmsg-cheatsheet.md#codex-monitor-モードbeta) |
| `claude-bedrock [args]` | claude.ai 障害時に Claude Code を Amazon Bedrock（グローバル推論プロファイル）へ切り替えて起動。env をその呼び出しに限って渡すので通常の `claude` は claude.ai のまま。認証は `aws-login`（credential_process）+ `AWS_PROFILE` を流用（追加ログイン不要）。事前に `aws-switch` で Bedrock アクセス権のあるプロファイルを選択しておく。リージョン/モデルは下表の `CLAUDE_BEDROCK_*` で上書き可 |
| `ide-bedrock [path...]` | `ide` を Bedrock 環境で起動する版。Bedrock 用 env を export してから `ide` を呼ぶので、nvim が継承し IDE ペインの `claude` も Bedrock になる（通常の `ide` の `claude` は claude.ai のまま）。設定は `claude-bedrock` と共通（下表の `CLAUDE_BEDROCK_*`）。既存 tmux/ide セッションへ復帰する claude は起動時の env のまま＝切り替えにはセッションを畳んで再実行 |

### `claude-bedrock` / `ide-bedrock` の上書き変数

両関数で共通。呼び出し前に export しておくと既定値を上書きできる（未設定なら既定値）。
`AWS_REGION` はグローバルプロファイルでも SigV4 署名用に具体リージョンが必要（ルーティングは
グローバルプロファイルが自動）。`AWS_PROFILE`（または AWS 認証情報）が無いと起動前にエラーで止まる。

| 変数 | 既定値 |
| --- | --- |
| `CLAUDE_BEDROCK_REGION` | `us-east-1` |
| `CLAUDE_BEDROCK_OPUS_MODEL` | `global.anthropic.claude-opus-4-8` |
| `CLAUDE_BEDROCK_SONNET_MODEL` | `global.anthropic.claude-sonnet-4-6` |
| `CLAUDE_BEDROCK_HAIKU_MODEL` | `global.anthropic.claude-haiku-4-5-20251001-v1:0` |

> 内部で `CLAUDE_CODE_USE_BEDROCK=1` と上記モデルを `ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU}_MODEL` に
> 渡して `claude` を起動する。Bedrock 連携の詳細は [AWS チートシート](aws-cheatsheet.md) の認証フロー（`aws-switch` / `aws-login`）も参照。

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
