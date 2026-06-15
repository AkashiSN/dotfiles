# zshrc モジュール分割 + aqua ツール補完 設計書

- 日付: 2026-06-15
- 対象: `dot_zshrc`, `dot_config/sheldon/plugins.toml`, `dot_config/zsh/rc.d/*`(新規), chezmoi script(新規), `docs/zsh-cheatsheet.md`

## 目的

1. 単一の `dot_zshrc`(約390行)を機能別モジュールに分割し、各ファイルを単一責務にして見通しを良くする。
2. aqua 管理ツールのうち補完を生成できるものを網羅し、shell でタブ補完を効かせる。

## 決定事項（ブレインストーミング結果）

- 構造: **モジュール分割**（単一ファイル維持ではなく）
- 補完範囲: **aqua 管理全ツールを網羅**（生成可能なもの）
- 補完の仕組み: **fpath に事前生成**（起動時生成ではなく chezmoi の run スクリプト）

## ツールの補完分類（実機調査済み）

| 区分 | ツール | 方式 |
| --- | --- | --- |
| fpath 事前生成（`#compdef`） | gh, uv, fnm, aqua, starship, rg, fd, tenv | chezmoi script が `~/.local/share/zsh/site-functions/_<name>` を生成 |
| bash 動的補完（`complete -C`、要 bashcompinit・実行時） | terraform, aws | モジュール内に残す（fpath 化不可） |
| source 専用（hook/keybind 同梱） | fzf(`--zsh`), gcloud, kubectl | モジュール内でロード（kubectl は非 aqua のためキャッシュ source 継続） |
| 補完生成不可 | ghq, go, peco, yt-dlp, direnv(hook のみ) | 対象外 |

生成コマンド確認結果:
- `gh completion -s zsh`, `uv generate-shell-completion zsh`, `fnm completions --shell zsh`,
  `aqua completion zsh`, `starship completions zsh`, `rg --generate=complete-zsh`,
  `fd --gen-completions zsh`, `tenv completion zsh` → いずれも先頭 `#compdef`（fpath 可）
- `fzf --zsh` → key-bindings 同梱の source 専用
- `ghq` / `go` / `yt-dlp` / `peco` → 補完生成コマンドなし

## モジュール構成

`dot_config/zsh/rc.d/`（chezmoi 展開後 `~/.config/zsh/rc.d/*.zsh`）。

| ファイル | 内容（現 zshrc からの移動元 行番号目安） |
| --- | --- |
| `00-options.zsh` | TERM/WORDCHARS, colors, setopt 群, HISTORY 設定, LISTMAX/DIRSTACKSIZE (12-73) |
| `10-path.zsh` | LOCAL_PREFIX 系 export, FPATH/MANPATH 等, mkdir, GOPATH/GHQ_ROOT, rancher/yarn PATH, profile.d, command-not-found (80-111, 168-170, 243, 250) |
| `20-completion.zsh` | 補完 zstyle 群, fzf-tab スタイル, `_load_completion` ヘルパ定義 (18-24, 128-141) |
| `30-plugins.zsh` | sheldon(autosuggest 変数+`sheldon source`=compinit), starship, direnv hook, fnm env (118-160, 252-255) |
| `40-tools.zsh` | terraform/aws `complete -C`, fzf `--zsh`(キャッシュ source), gcloud completion.inc, kubectl(キャッシュ+alias k), tenv env 変数, alias tf, ssh-agent (189-236, 360-364) |
| `50-functions.zsh` | peco-src(+bindkey C-]), latex, pdfcrop, tssh(+compdef), convert-crlf-to-lf, search, ide (173-306) |
| `60-aliases.zsh` | OS 別 ls 系, rsync, conv-utf8, EDITOR/VISUAL, vi/vim, WSL 調整 (313-353, 339-342) |
| `70-keybindings.zsh` | bindkey(Home/Del/End), xmodmap (382-392) |

`dot_zshrc` はローダーに縮小:
1. macOS のとき `/etc/zshrc` を読む
2. `~/.config/zsh/rc.d/*.zsh` を番号順に走査し、stale なら zcompile してから source
3. 自身（`.zshrc`）を再コンパイル

### ロード順序の制約

- `10-path`(FPATH 設定) → `30-plugins`(compinit が fpath を読む) → `40-tools`(bashcompinit 後に `complete -C`)。
- ファイル番号順で依存が満たされる。zstyle は遅延参照のため `20` が plugins より前でも問題なし。

## 新規 chezmoi スクリプト

`.chezmoiscripts/run_onchange_after_25-zsh-completions.sh.tmpl`:
- aqua.yaml のハッシュをコメントに埋め込みトリガー化（aqua install=20 の後に実行）
- `~/.local/share/zsh/site-functions/` に gh/uv/fnm/aqua/starship/rg/fd/tenv の `_<name>` を生成（各 `command -v` ガード、PATH に `~/.local/bin` と aqua bin を通す）
- 生成後 `~/.zcompdump*` を削除し、次回 compinit で確実に拾わせる

## ドキュメント更新

`docs/zsh-cheatsheet.md`:
- 構成説明に「`~/.config/zsh/rc.d/` のモジュール分割」を追記
- 「連携ツール（自動初期化）」に補完対象ツール（gh/uv/fnm/aqua/rg/fd/starship 等）と
  「補完は aqua 更新時に chezmoi が site-functions へ生成」の注記を追加

## 受け入れ基準

- `zsh -ic 'exit'` がエラーなく起動し、起動時間が現状から大きく劣化しない
- 分割前後でエイリアス・関数・キーバインド・setopt・zstyle が等価（消失なし）
- `~/.local/share/zsh/site-functions/_gh` 等が生成され、`gh <Tab>` などで補完候補が出る
- terraform/aws/kubectl/gcloud の既存補完が引き続き機能
- `docs/zsh-cheatsheet.md` が実装と一致
```
