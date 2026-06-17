# CLAUDE.md

このリポジトリは [chezmoi](https://www.chezmoi.io/) で管理される dotfiles。

## リポジトリの約束

- ソースファイル名は chezmoi 命名規則に従う: `dot_` → `.`、`private_` → 権限制限、
  `.tmpl` → テンプレート展開。**ホームの `~/.zshrc` ではなくソースの `dot_zshrc` を編集する。**
- ホームへ展開したくないファイルは `.chezmoiignore` に追加する（`README.md` / `CLAUDE.md` / `docs` は展開対象外）。
- CLI ツールは [aqua](https://aquaproj.github.io/)（`dot_config/aquaproj-aqua/aqua.yaml`）で宣言的に管理。
  パッケージを追加するときは末尾に並べず、**用途に合った既存グループ**（言語ランタイム /
  git / shell / editor / secrets / cloud / network / local registry など、
  `# --- ... ---` のコメント区切り）に挿入する。合うグループが無ければ新しいグループ区切りを
  作る。バージョンは `aqua g <pkg>` で確認したものをピンする。

## チートシートを最新に保つ（重要）

`docs/` 配下に各ツールのチートシートがある。**対応する設定を変更したら、同じ作業の中で
チートシートも必ず更新すること**（キーバインドの追加・変更・削除、起動方法やコマンドの
変更、挙動が変わる設定など）。設定とドキュメントを乖離させない。

| 設定ファイル | 更新するチートシート |
| --- | --- |
| `dot_config/nvim/**` | `docs/nvim-cheatsheet.md` |
| `dot_tmux.conf` | `docs/tmux-cheatsheet.md` |
| `dot_config/ghostty/config` | `docs/ghostty-cheatsheet.md` |
| `dot_zshrc` / `dot_zshenv.tmpl` | `docs/zsh-cheatsheet.md` |
| `dot_local/bin/executable_git-aicommit` / `executable_gh-pr-aicreate`（git/gh の AI alias 含む） | `docs/ai-git-cheatsheet.md` |
| `dot_local/bin/executable_aws-switch` / `executable_aws-login` / `executable_aws-logout` / `dot_aws/modify_config` | `docs/aws-cheatsheet.md` |

新しいツールのキーバインド設定を追加したときは、`docs/` に新しいチートシートを作り、
`docs/README.md` の一覧にも追記する。

チェック観点:
- キーマップ（キー・モード・動作）が表と一致しているか
- 起動コマンド / エイリアス / 関数の追加・改名・削除を反映したか
- 特徴的な挙動（自動化・トグル・連携）の説明が実装と合っているか
