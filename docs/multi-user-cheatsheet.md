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
| `personal` | 個人のホストと鍵（AkashiSN）を使うか（yes / no） | yes |
| `work.*` | work 環境の識別子（使わないなら空） | 空 |

## git の identity

`dot_gitconfig.tmpl` は `[user] name / email / signingkey` を上の data から組み立てる。

- `git.signingkey` が空なら、`[user] signingkey`・`[commit] gpgsign`・`[gpg "ssh"]` を出力しない（署名なしのコミットになる）。
- `[data.git]` がまだ無い config（`chezmoi init` を再実行する前）でも、従来と同じ値で展開する。既存ユーザの `~/.gitconfig` は変わらない。
- 値を変えるときは `~/.config/chezmoi/chezmoi.toml` の `[data.git]` を直接編集するか、ファイルを消して `chezmoi init` をやり直す。

## personal（個人のホストと鍵）

`personal` は `~/.ssh` に作者個人の Host 定義と鍵を出すかどうかを決める。既定は `true`（作者本人。従来と同じ展開）。他のユーザは `chezmoi init` で `no` と答える。`[data]` に `personal` が無い config（init 前）は `true` として扱う。

`personal = false` のとき出さないもの。

- `~/.ssh/config` の個人の Host（`gw-suita` / `ix2215-suita` / `er-x-suita` / `truenas-suita` / `gw-tokyo` / `ix2215-tokyo` / `develop-server` / `truenas`）と、`172.16.*` 宛の `Match` による踏み台設定。
- `gitlab.com` / `gist.github.com` の `IdentityFile`。`github.com` は `github.com-AkashiSN` の別名と鍵指定を外し、ssh-agent / 既定の鍵に任せる。
- `.ssh/1password_AkashiSN.pub` / `.ssh/allowed_signers` / `.ssh/authorized_keys` / `.ssh/gpg.pub`（`.chezmoiignore` で除外）。

`work.*` の Host は `personal` と独立に、`work.*` が設定されていれば出る。

## テスト

```sh
bash tests/run.sh   # tests/**/*.test.sh を順に実行
```
