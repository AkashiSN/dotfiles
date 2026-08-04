# dotfiles チートシート

各ツールのキーバインド・コマンド・設定挙動のリファレンス。

| ツール | チートシート | 主な設定ファイル |
| --- | --- | --- |
| Neovim | [nvim-cheatsheet.md](nvim-cheatsheet.md) | `dot_config/nvim/` |
| tmux | [tmux-cheatsheet.md](tmux-cheatsheet.md) | `dot_tmux.conf` |
| herdr（AI エージェント多重化） | [herdr-cheatsheet.md](herdr-cheatsheet.md) | `dot_config/herdr/config.toml` |
| gitui（git TUI） | [gitui-cheatsheet.md](gitui-cheatsheet.md) | `dot_config/gitui/theme.ron` |
| Ghostty | [ghostty-cheatsheet.md](ghostty-cheatsheet.md) | `dot_config/ghostty/config` |
| zsh | [zsh-cheatsheet.md](zsh-cheatsheet.md) | `dot_zshrc` / `dot_zshenv.tmpl` |
| AI Git / PR | [ai-git-cheatsheet.md](ai-git-cheatsheet.md) | `dot_local/bin/git-aicommit` / `gh-pr-aicreate` |
| Terraform（provider キャッシュ） | [terraform-cheatsheet.md](terraform-cheatsheet.md) | `dot_terraformrc.tmpl` / `dot_local/bin/tf-cache-prune` |
| uv（Python ツール / キャッシュ） | [uv-cheatsheet.md](uv-cheatsheet.md) | `.chezmoiscripts/run_onchange_after_35-uv-tools.sh.tmpl` / `dot_local/bin/uv-cache-prune` |
| AWS プロファイル切替 | [aws-cheatsheet.md](aws-cheatsheet.md) | `dot_local/bin/aws-switch` / `aws-login` / `aws-logout` / `dot_aws/modify_config` |
| portfwd（SSH ブラウザ自動FW） | [portfwd-cheatsheet.md](portfwd-cheatsheet.md) | `dot_local/bin/portfwd` / `portfwd-open` / `private_dot_ssh/private_config.tmpl` |
| dji_workflow（DJI 取り込み → Immich） | [dji-cheatsheet.md](dji-cheatsheet.md) | `dot_local/bin/dji_workflow.py` |
| agmsg（エージェント間メッセージ） | [agmsg-cheatsheet.md](agmsg-cheatsheet.md) | `.chezmoiscripts/run_onchange_after_40-ai-assistants.sh.tmpl`（herdr ペインでの codex↔claude 相互レビュー） |
| CodeGraph（コード知識グラフ / MCP） | [codegraph-cheatsheet.md](codegraph-cheatsheet.md) | `.chezmoiscripts/run_onchange_after_40-ai-assistants.sh.tmpl` / `private_dot_claude/settings.json.tmpl` / `modify_CLAUDE.md` |
| graphify（知識グラフ） | [graphify-cheatsheet.md](graphify-cheatsheet.md) | `.chezmoiscripts/run_onchange_after_40-ai-assistants.sh.tmpl` / `private_dot_claude/modify_CLAUDE.md` |

> これらは chezmoi のソースリポジトリ内のドキュメントで、ホームへは展開されない
> （`.chezmoiignore` で `docs` を除外）。設定を変更したらチートシートも更新すること（[CLAUDE.md](../CLAUDE.md) 参照）。
