# Claude Code の plugin チートシート

`~/.claude/settings.json` の `enabledPlugins` / `extraKnownMarketplaces` で配る plugin について。

対象ファイル: `private_dot_claude/modify_settings.json.tmpl`

## 仕組み

`enabledPlugins` に書いた plugin は、`extraKnownMarketplaces` に marketplace が登録されていれば
Claude Code が起動時に自動で取得する（`~/.claude/plugins/cache/` に入り、`installed_plugins.json`
に記録される）。`claude-plugins-official` は組み込みなので登録は要らない。

| コマンド | 役割 |
| --- | --- |
| `claude plugin list` | 導入済み plugin と有効/無効 |
| `claude plugin marketplace list` | 登録済み marketplace |
| `claude plugin marketplace add <owner>/<repo>` | marketplace を取得（settings に宣言済みなら「declared in user settings」と出る） |
| `claude plugin install <plugin>@<marketplace>` | 取得を待たずその場で入れる |

## 配っているもの

| plugin | marketplace | 用途 | 前提 |
| --- | --- | --- | --- |
| `code-simplifier` | `claude-plugins-official`（組み込み） | 変更したコードの簡素化 | なし |
| `gopls-lsp` | `claude-plugins-official`（組み込み） | Go の LSP 連携 | なし |
| `superpowers` | `claude-plugins-official`（組み込み） / `superpowers-marketplace` | ブレインストーミング・TDD などの process skill 群 | なし |
| `natural-japanese` | `natural-japanese`（[coji/natural-japanese](https://github.com/coji/natural-japanese)） | 日本語文書の執筆・校正と AI 臭さの検出（`/natural-japanese`） | `uv` |

`natural-japanese` の検査スクリプト（`lint.py` / `outline.py` / `terms.py`）は PEP 723 の
インラインメタデータを持ち、`uv run` が実行時に sudachipy などを取ってくる。`uv` は aqua 管理
なので追加の手当ては要らない（[uv-cheatsheet.md](uv-cheatsheet.md)）。

## 追加・削除するとき

- plugin を足すときは `enabledPlugins` と `extraKnownMarketplaces` の**両方**を更新し、
  上の表にも行を足す。
- **登録の無い marketplace を `enabledPlugins` に書いても、エラーにはならず黙って取得されない。**
  組み込みの `claude-plugins-official` が登録不要なので気づきにくい。追加したら
  `claude plugin list` に出るところまで確認する。
- `modify_settings.json.tmpl` は現物へ**再帰マージ**する（`jq '. * $managed'`）ので、
  `enabledPlugins` から行を消しても現物からは消えない。宣言を落とすときは
  `~/.claude/settings.json` 側も手で消す:

  ```sh
  jq 'del(.enabledPlugins["<plugin>@<marketplace>"])' ~/.claude/settings.json > /tmp/s \
    && mv /tmp/s ~/.claude/settings.json
  ```

## 関連

- [claude-compact-cheatsheet.md](claude-compact-cheatsheet.md) — 同じ `settings.json` の hook / statusLine
- [codegraph-cheatsheet.md](codegraph-cheatsheet.md) — plugin ではなく MCP サーバとして入れているもの
