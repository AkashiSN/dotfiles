# gitui チートシート

ターミナルの git TUI [gitui](https://github.com/gitui-org/gitui) の起動・キーバインド・設定挙動のリファレンス。
herdr の popup から差分確認・ステージング・コミットに使う。

- **導入**: aqua で管理（`dot_config/aquaproj-aqua/aqua.yaml` の `gitui-org/gitui`）
- **テーマ**: `~/.config/gitui/theme.ron`（chezmoi ソース = `dot_config/gitui/theme.ron`）
  - 部分指定でデフォルトにマージされる。指定しないキーは gitui 既定色のまま。
  - 下部コマンドバーを端末背景に透過（`cmdbar_bg: Reset`）して Catppuccin Mocha で
    水色帯 + 白文字の低コントラストを解消している。

> キー記法: 下部コマンドバーの記号 `⎋` = **Esc**、`⏎` = **Enter**、`^X` = **Ctrl+X**。
> Shift 併用キーは表では `Shift+X` と記す。

---

## 最重要: コミットメッセージ画面から抜ける／確定する

コミットエディタ（`c` で開く）で迷いやすいポイント。下欄の記号の意味を覚える。

| キー（下欄の表示） | 動作 |
| --- | --- |
| `Esc`（`⎋ close`） | **エディタを閉じる（キャンセル）**。記号 `⎋` が Esc。 |
| `Ctrl+D`（`^D commit`） | **コミットを確定する**。 |
| `Enter`（`⏎`） | メッセージ内で**改行**（確定ではない）。 |

> 落とし穴: Enter は改行なので、押しても確定しない。**確定は Ctrl+D、中断は Esc**。
> 「閉じられない」と感じたら Esc（`⎋`）。

---

## タブ切り替え

| キー | タブ |
| --- | --- |
| `1` | Status（作業ツリー / ステージ） |
| `2` | Log（コミット履歴） |
| `3` | Files（ツリー） |
| `4` | Stashing（stash 作成） |
| `5` | Stashes（stash 一覧） |
| `Tab` / `Shift+Tab` | 次 / 前のタブへトグル |

---

## 共通

| キー | 動作 |
| --- | --- |
| `↑ ↓ ← →` | 移動 / パネル間フォーカス移動 |
| `Enter` | 選択項目を開く / ステージ・アンステージ |
| `Esc`（`⎋`） | popup / 画面を閉じる |
| `H` | ヘルプ（全キーバインド一覧） |
| `Q` | gitui を終了 |
| `Ctrl+C` | 強制終了 |
| `F5` | 表示を更新（refresh） |

---

## Status タブ（ステージング・コミット）

| キー | 動作 |
| --- | --- |
| `Enter` | 選択ファイルをステージ / アンステージ |
| `A` | すべてステージ |
| `Shift+D` | 変更を破棄（reset item） |
| `S` | 差分内の選択行だけステージ（hunk/line stage） |
| `D` | 差分内の選択行だけ破棄（reset lines） |
| `C` | コミットメッセージエディタを開く |
| `Ctrl+A` | 直前コミットを amend |
| `E` | 選択ファイルを `$EDITOR` で開く |

> `S` / `D` は diff パネルにフォーカスがある時の行単位操作。ファイル一覧では
> `Enter` がファイル単位のステージ／アンステージ。

---

## Log タブ（履歴）

| キー | 動作 |
| --- | --- |
| `Enter` | コミット詳細 / 差分を開く |
| `Shift+S` | そのコミットを checkout |
| `Shift+R` | そのコミットへ reset |
| `Shift+B` | blame（Files 側で選択したファイル） |
| `Y` | コミットハッシュをコピー |

---

## ブランチ・リモート

| キー | 動作 |
| --- | --- |
| `B` | ブランチ一覧を開く（選択・切替） |
| `C` | 新規ブランチ作成（ブランチ一覧内） |
| `Shift+D` | ブランチ削除（ブランチ一覧内） |
| `P` | push |
| `F` | pull |
| `Shift+F` | fetch |

> 同じ文字でも「どのパネル・popup にいるか」で意味が変わる（例: `C` は Status では
> コミット、ブランチ一覧では新規作成、`Shift+D` は Status では破棄、ブランチ一覧では削除）。
> 迷ったら常に**下部コマンドバーの表示**が現在の文脈での有効キー。

---

## Stashing / Stashes

| キー | 動作 |
| --- | --- |
| `S` | 現在の変更を stash に保存（Stashing タブ） |
| `Enter` / `→` | stash を開く（Stashes タブ） |
| `A` | stash を適用（apply） |
| `Shift+D` | stash を破棄（drop） |

---

## 検索・その他

| キー | 動作 |
| --- | --- |
| `F` | ファイル検索（Files / Status のファイル絞り込み） |
| `Ctrl+F` | commit hook（verify）のトグル |
| `Y` | 選択内容をコピー |

> キーバインドは `~/.config/gitui/key_bindings.ron` で上書き可能（本 dotfiles では未設定＝デフォルト）。
> 記号は `theme.ron` ではなく key config 側の設定。現在の一覧は gitui 内で `H`（ヘルプ）でも確認できる。

---

## 変更履歴・経緯

- 下部コマンドバーの可読性対策として `theme.ron` を追加し、`cmdbar_bg` /
  `cmdbar_extra_lines_bg` を `Reset`（端末背景に透過）、`command_fg` を `White` に設定。
  背景に Catppuccin Mocha の ANSI Blue（水色 `#89b4fa`）が入ると白文字と低コントラスト
  になり見にくかったため。ほかの色は gitui 既定にマージされる。
