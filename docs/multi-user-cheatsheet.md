# マルチユーザ チートシート

1 台のマシンを複数ユーザで使い、それぞれが自分のホームへこのリポジトリを `chezmoi apply` するときの手引き。

## 2 人目のユーザの始め方

```sh
chezmoi init <このリポジトリ>   # 下の「chezmoi init で聞かれる値」に答える
chezmoi diff                    # 展開内容を確認
chezmoi apply
```

`chezmoi init` の回答は `~/.config/chezmoi/chezmoi.toml` の `[data]` に保存される。`promptStringOnce` なので、一度答えれば再実行しても聞かれない。

## chezmoi init で聞かれる値

| data キー | 聞かれる内容 | 既定値 |
| --- | --- | --- |
| `git.name` | git の名前 | dotfiles 作者の名前 |
| `git.email` | git のメールアドレス | dotfiles 作者のメール |
| `git.signingkey` | git の署名鍵（SSH 公開鍵の文字列。署名しないなら空） | dotfiles 作者の公開鍵 |
| `work.*` | work 環境の識別子（使わないなら空） | 空 |

## git の identity

`dot_gitconfig.tmpl` は `[user] name / email / signingkey` を上の data から組み立てる。

- `git.signingkey` が空なら、`[user] signingkey`・`[commit] gpgsign`・`[gpg "ssh"]` を出力しない（署名なしのコミットになる）。
- `[data.git]` がまだ無い config（`chezmoi init` を再実行する前）でも、従来と同じ値で展開する。既存ユーザの `~/.gitconfig` は変わらない。
- 値を変えるときは `~/.config/chezmoi/chezmoi.toml` の `[data.git]` を直接編集するか、ファイルを消して `chezmoi init` をやり直す。

## テスト

```sh
bash tests/run.sh   # tests/**/*.test.sh を順に実行
```
