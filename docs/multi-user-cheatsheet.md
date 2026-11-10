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
- `[data.git]` がまだ無い config（`chezmoi init` を再実行する前）でも、従来と同じ値で展開する。darwin/arm64 では共有 Homebrew 用の `[safe]` が加わる（下の Homebrew の節）。
- 値を変えるときは `~/.config/chezmoi/chezmoi.toml` の `[data.git]` を直接編集するか、ファイルを消して `chezmoi init` をやり直す。

## personal（個人のホストと鍵）

`personal` は `~/.ssh` に作者個人の Host 定義と鍵を出すかどうかを決める。既定は `true`（作者本人。従来と同じ展開）。他のユーザは `chezmoi init` で `no` と答える。`[data]` に `personal` が無い config（init 前）は `true` として扱う。

`personal = false` のとき出さないもの。

- `~/.ssh/config` の個人の Host（`gw-suita` / `ix2215-suita` / `er-x-suita` / `truenas-suita` / `gw-tokyo` / `ix2215-tokyo` / `develop-server` / `truenas`）と、`172.16.*` 宛の `Match` による踏み台設定。
- `gitlab.com` / `gist.github.com` の `IdentityFile`。`github.com` は `github.com-AkashiSN` の別名と鍵指定を外し、ssh-agent / 既定の鍵に任せる。
- `.ssh/1password_AkashiSN.pub` / `.ssh/1password_su-nishi.pub` / `.ssh/allowed_signers` / `.ssh/authorized_keys` / `.ssh/gpg.pub`（`.chezmoiignore` で除外）。

`work.*` の Host は `personal` と独立に、`work.*` が設定されていれば出る。

## Homebrew（Apple Silicon の共有）

Apple Silicon Mac では `/opt/homebrew` を 1 つだけ置き、OS のグループ（既定 `brew`、環境変数 `BREW_GROUP` で変更）でユーザ間に共有する。所有者は最初に入れたユーザのままで、グループと権限だけを調える。

- **仕組み**: `.chezmoiscripts/run_before_05-homebrew-shared.sh.tmpl` が、グループ作成（`dseditgroup`）・自分の追加・`chgrp -R` / `chmod -R g+w`・ディレクトリへの setgid（`chmod g+s`）を行う。`/opt/homebrew` がすでに「グループ `brew`・g+w・setgid・現プロセスが所属」なら何もせず、sudo も呼ばない。`run_before`（毎回実行）なので、Homebrew 未導入（初回 apply）・sudo を使えない・再ログイン前、のどれで飛ばした回も次の apply で再試行する。Homebrew 未導入なら何もしない（`run_onchange_before_10` が入れる）。
- **共通の関数**: `.chezmoitemplates/homebrew-shared.sh` の `brew_shared`（`umask 002` で brew を呼ぶ）と `homebrew_shared_ok [prefix]`（共有済みか）。`before_05` / `before_10` が取り込む。
- **sudo**: 設定が要るときだけ使う。`sudo -n true` が通るか、TTY があるときに進む。どちらも無ければ警告して飛ばす。
- **グループ追加後は再ログインが要る**: 追加しただけでは動いているプロセスの所属は変わらない。`id -Gn` に `brew` が出るまで、`before_10` は `/opt/homebrew/Cellar` に書けないとして formula / cask を飛ばし（残りの手順は続ける）、警告して正常終了する。`before_10` は `run_onchange` で、飛ばした回も実行済みと記録されるため、再ログイン後は `chezmoi state delete-bucket --bucket=scriptState && chezmoi apply` で冪等な `run_onchange` スクリプトを 1 回やり直す。
- **対話シェルの `brew`**: zsh の関数 `brew` が `umask 002` のサブシェルで `command brew` を呼ぶ。作るファイルが他のユーザにも書き込み可になる。
- **git**: `dot_gitconfig.tmpl` が darwin/arm64 で `[safe] directory = /opt/homebrew` と `/opt/homebrew/Library/Taps/*` を出す。他ユーザ所有の brew の git が「dubious ownership」で拒まれない。
- **Intel Mac は対象外**: MacPorts を使う（[zsh-cheatsheet](zsh-cheatsheet.md#macos-のパッケージ管理)）。

> Homebrew はこの構成（1 つの prefix を複数ユーザで書き換える）を公式にはサポートしない。`brew update` や permission まわりで想定外の挙動が出ることがあり、自己責任で使う。

### 戻し方

共有をやめるときは、所有者のまま権限を戻す。先に `ls -ld /opt/homebrew` で元のグループを確認し、それへ戻す。

```sh
ls -ld /opt/homebrew                                # 変更前に元のグループを控える
sudo find /opt/homebrew -type d -exec chmod g-s {} +
sudo chmod -R g-w /opt/homebrew
sudo chgrp -R <元のグループ> /opt/homebrew
sudo dseditgroup -o edit -d <ユーザ> -t user brew   # 各ユーザをグループから外す
sudo dseditgroup -o delete brew                     # グループ自体を消す場合
```

`run_before_05` は毎回の apply で `homebrew_shared_ok` を見て、偽なら共有の設定をやり直す。やめたままにするなら `.chezmoiignore` で `run_before_05` を除外する。

## 2 人目のユーザで気をつけること

静的な洗い出しで見つけた、コードを変えずに運用で避ける点。実機（`risa` での初回 apply）で確かめる前提。

- **`gh auth login` は自分で通す**: 共有 aqua の更新（`bootstrap/20-shared-aqua.sh`）は、更新を起こしたユーザの `gh auth token` を使って attestation を検証する。gh の認証は `~/.config/gh` に置かれるユーザごとの状態で、`risa` 自身の GitHub アカウントで通す。未認証だと `run_after_20-aqua-verify` が案内を出す（apply は止まらない）。先に端末で `gh auth login` を済ませてから `chezmoi init --apply` すると、共有側の更新が検証つきで通る。
- **GitHub への SSH 鍵**: `dot_gitconfig.tmpl` は `https://github.com/` を `git@github.com:` へ書き換え、`run_onchange_after_60-git-remote-ssh` は chezmoi ソースの origin を SSH へ切り替える。`risa` が GitHub に登録した SSH 鍵（1Password の ssh-agent など）を持たないと、`chezmoi update` や clone が失敗する。
- **署名と 1Password**: `git.signingkey` が空なら署名の設定（`gpg.ssh.program = op-ssh-sign`）は出ない。1Password を使わないユーザは空のままにする。`run_onchange_after_50-macos` の `op-ssh-sign` / ssh-agent のシンボリックリンクは、実体があるときだけ作る。
- **portfwd のポート 55999 は固定**: `portfwd serve` は `127.0.0.1:55999` で listen する（`PORTFWD_PORT` で変更可）。2 人が同時にログインしていると、後から起動した側の bind が失敗して LaunchAgent が再起動を繰り返す。リモート側の `RemoteForward` も 55999 固定なので、同時に使うなら片方のユーザは portfwd を使わない（plist を除外する）か、`PORTFWD_PORT` と ssh config の両方を変える。
- **portfwd の launchd 登録**: `launchctl bootstrap gui/<uid>` は、そのユーザの GUI セッションが無いと失敗する。`risa` は GUI ログインした状態で apply する。
- **`/tmp` の固定名**: `run_onchange_before_10-install-packages` の aqua / ffmpeg の一時ファイル（Linux と Intel Mac の経路）が `/tmp/aqua.tar.gz` などの固定名。同時に 2 人が走らせると衝突するが、apply を同時に実行しなければ起きない。Apple Silicon の macOS は通らない。
- **Homebrew グループ追加後の再ログイン**: [Homebrew](#homebrew-apple-silicon-の共有) を参照。
- **共有の対象外（計画 2）**: aqua は `/opt/aquaproj-aqua` の共有ストアに移った（[shared-store-cheatsheet.md](shared-store-cheatsheet.md)）。npm / uv / rust も共有に移った。AI CLI は未対応で、今は各ユーザの `$HOME` 配下に入る。
- **終了案内**: `run_once_after_90-final-notice` はログインシェルが zsh でないときの `usermod`（Linux 用）と `direnv allow ~` だけを案内する。macOS の新規ユーザは既定が zsh で、案内は出ない。

## テスト

```sh
bash tests/run.sh   # tests/**/*.test.sh を順に実行
```
