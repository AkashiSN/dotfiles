# Ghostty チートシート

ターミナルエミュレータ Ghostty（macOS）の設定（`dot_config/ghostty/config`）リファレンス。
この設定にカスタムキーバインドは定義しておらず、内容は**外観・連携の設定が中心**。
キー操作は Ghostty のデフォルトに従う。

> macOS 以外では `.chezmoiignore` により適用されない（macOS 専用設定）。

---

## 設定内容

| 項目 | 値 | 理由 |
| --- | --- | --- |
| `term` | `xterm-256color` | SSH + tmux 互換のため標準 terminfo を使用（`xterm-ghostty` はリモート Linux に無く tmux 起動が失敗する） |
| `font-family` | `Menlo` | 本文フォント。アイコン（nvim-web-devicons）は Symbols Nerd Font へ自動フォールバック |
| `font-size` | `13` | |
| `theme` | `Catppuccin Mocha` | nvim（catppuccin）と色味を統一 |
| `grapheme-width-method` | `legacy` | 文字幅を wcwidth 互換で計算。default（`unicode`）だと codex 等の TUI と全角／Ambiguous 幅文字（日本語・`•` `─` 等）の幅判定がズレ、ストリーミング再描画の消し残し（行の重複表示）が起きるため |
| `shell-integration` | `zsh` | zsh のシェル統合 |
| `clipboard-write` / `clipboard-read` | `allow` | OSC52 クリップボード（nvim の yank ↔ システムクリップボード） |

---

## よく使うキー（Ghostty 標準・この設定では未定義）

⚠️ 以下は **この設定ファイルで定義したものではなく**、Ghostty が標準で持つ macOS デフォルトキー。
バージョンやキーボード設定で異なる場合があるため、確定情報は公式ドキュメントで確認すること。

| キー | 動作 |
| --- | --- |
| `Cmd-T` | 新しいタブ |
| `Cmd-N` | 新しいウィンドウ |
| `Cmd-D` | ペインを右に分割 |
| `Cmd-Shift-D` | ペインを下に分割 |
| `Cmd-W` | ペイン / タブを閉じる |
| `Cmd-[` / `Cmd-]` | 前 / 次のペインへ |
| `Cmd-+` / `Cmd--` | フォント拡大 / 縮小 |
| `Cmd-K` | 画面クリア（スクロールバックも） |
| `Cmd-,` | 設定ファイルを開く |
| `Cmd-Shift-,` | 設定を再読み込み |

> 正確な一覧・カスタマイズは [Ghostty 公式ドキュメント](https://ghostty.org/docs) を参照。
> 普段の分割・ペイン移動は tmux 側（`Ctrl-a` prefix）で行う運用のため、Ghostty 側の
> 分割は使わないことが多い。
