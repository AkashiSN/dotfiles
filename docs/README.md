# dotfiles チートシート

各ツールのキーバインド・コマンド・設定挙動のリファレンス。

| ツール | チートシート | 主な設定ファイル |
| --- | --- | --- |
| Neovim | [nvim-cheatsheet.md](nvim-cheatsheet.md) | `dot_config/nvim/` |
| tmux | [tmux-cheatsheet.md](tmux-cheatsheet.md) | `dot_tmux.conf` |
| Ghostty | [ghostty-cheatsheet.md](ghostty-cheatsheet.md) | `dot_config/ghostty/config` |
| zsh | [zsh-cheatsheet.md](zsh-cheatsheet.md) | `dot_zshrc` / `dot_zshenv.tmpl` |
| AI Git / PR | [ai-git-cheatsheet.md](ai-git-cheatsheet.md) | `dot_local/bin/git-aicommit` / `gh-pr-aicreate` |
| AWS プロファイル切替 | [aws-cheatsheet.md](aws-cheatsheet.md) | `dot_local/bin/aws-switch` / `aws-login` / `aws-logout` / `dot_aws/modify_config` |

> これらは chezmoi のソースリポジトリ内のドキュメントで、ホームへは展開されない
> （`.chezmoiignore` で `docs` を除外）。設定を変更したらチートシートも更新すること（[CLAUDE.md](../CLAUDE.md) 参照）。
