# portfwd（SSH ブラウザ自動フォワード）チートシート

SSH 先で `aws login` / `gh auth` などがブラウザを開こうとしたとき、その URL を
ローカルへ転送してローカルのブラウザを自動で開く仕組み。対象ホストは ssh config の
`SetEnv LC_PORTFWD_HOST` と `DynamicForward` でオプトインする。

## 仕組み

```
remote: ツールが $BROWSER=portfwd-open を起動
   └─ URL を $XDG_RUNTIME_DIR/portfwd.sock へ POST （RemoteForward でローカルへ）
local : portfwd daemon が受信
   1. ssh -G <host> で設定を解決し、SetEnv LC_PORTFWD_HOST が host と一致するか検証
   2. authorize URL の redirect_uri（無ければ URL 自体）から localhost の callback ポート P を抽出
   3. dynamicforward から SOCKS ポート S を得て、SOCKS5 が応答するか probe
   4. 127.0.0.1:P で listen し、来た接続を S 経由でリモートの 127.0.0.1:P へ中継
   5. ローカルのブラウザで authorize URL を開く
```

- ツールがブラウザに渡すのは **認可サーバ上の authorize URL**（ホストは localhost ではない）で、
  コールバックは URL 内の `redirect_uri=http://127.0.0.1:P/...` に埋め込まれている。daemon は
  そこから P を取り出してリレーを張り、URL 自体はそのままローカルブラウザで開く。
- `ssh -D` の SOCKS プロキシは接続先を **SSH サーバ側から** 解決するため、SOCKS 経由で
  `127.0.0.1:P` へ CONNECT するとリモートの loopback に繋がる。これが `-L P:127.0.0.1:P` と
  等価になる。
- 逆チャネル（`RemoteForward /run/user/<uid>/portfwd.sock 127.0.0.1:55999`）で listen するのは
  **SSH 先の sshd**。ローカルの daemon が落ちていても listen 自体は成立するので、
  「繋がる＝生きている」ではない（後述の `/health` 判定はこのため）。
- Unix domain socket になるのは **SSH 先の listen 端だけ**で、ローカル側は TCP の
  `127.0.0.1:55999` のまま。daemon は AF_UNIX を一切扱わないので Windows でも同じ。
- リモートの `$BROWSER` は `dot_zshenv.tmpl` が `LC_PORTFWD_HOST` セット時のみ
  `~/.local/bin/portfwd-open` に向ける。ただし `$BROWSER` が既にセットされている場合
  （VSCode Remote 等が自前のヘルパを仕込んでいる場合）は上書きしない。あちらは自前の
  ポートフォワードで完結しており、奪うと逆に壊れるため。
- `aws-login` は逆チャネルを使うかどうかを、変数の有無ではなく `GET /health` の応答で判定する
  （`{"service":"portfwd",…}` が返るか）。`RemoteForward` の listen ソケットは SSH 先の sshd が
  持つため、connect だけではローカルの daemon が死んでいても成功してしまう。
  詳細は [aws-cheatsheet.md](aws-cheatsheet.md) の「SSH 先でのログイン」を参照。
- `/health` の待ち時間は `portfwd-open` の POST と同じ **5 秒**。ローカルの daemon は常駐サービスの
  起動直後などに応答へ数秒かかることがあり、短いと生きている逆チャネルを取り逃して `--remote` へ
  落ちる。判定に失敗したら `aws-login` が理由を `/dev/tty` へ出す（`aws-switch` は `aws-login` の
  出力を捨てるため、stderr では見えない）。

  ```sh
  curl -sS --max-time 5 --unix-socket "$XDG_RUNTIME_DIR/portfwd.sock" http://localhost/health
  # {"service": "portfwd", "relays": 0}
  ```

## ローカルの `portfwd` コマンド

| コマンド | 動作 |
| --- | --- |
| `portfwd serve` | 55999 で listen する常駐ループ（フォアグラウンド）。**サービスマネージャが起動する本体**なので手で叩くことはまず無い |
| `portfwd status` | 稼働状況を表示（`GET /health` の応答で判定） |

上表は macOS/Linux での書き方。Windows は `.local/bin/portfwd` に拡張子が無く、その
ディレクトリも PATH に無いため、`portfwd status` ではなく次の形で呼ぶ:

```powershell
py -3 "$env:USERPROFILE\.local\bin\portfwd" status
```

`portfwd status` の表示:

| 表示 | 意味 |
| --- | --- |
| `running (port 55999, relays N)` | 稼働中。N は張っているリレーの数 |
| `stopped (port 55999)` | ポートに繋がらない |
| `not-portfwd (port 55999)` | ポートは開いているが portfwd 以外が応答している |
| `timeout / unresponsive (port 55999)` | 応答が無い。通知処理中の `ssh -G` で待たされている可能性がある |

- daemon の寿命は **OS のサービスマネージャが管理する**（macOS は launchd、Windows は
  タスクスケジューラ）。ログイン時に起動し、落ちても再起動されるため、常時起動している。
  スクリプト自身にはアイドル自己終了も多重起動制御も無い。
- listen に失敗（他プロセスが 55999 を掴んでいる等）すると `serve` は非ゼロ終了し、
  サービスマネージャが間隔を空けて再試行する。
- リレーは通知ごとに張る。1 回も接続を捌いていない間はログイン・MFA 待ちのため 600 秒
  （旧 `ssh -L` の `ControlPersist 10m` 相当）、接続を 1 回でも捌いた後はアイドル 180 秒で
  listener を閉じる。
- 環境変数（ローカル側）: `PORTFWD_PORT`(既定 55999) で daemon が listen する TCP ポート、
  `PORTFWD_OPEN_CMD` でブラウザ起動コマンド、`PORTFWD_LOG` でログファイル、`PORTFWD_SSH_CMD`
  で ssh コマンドを変更できる。リモート側（`portfwd-open` / `aws-login`）は `PORTFWD_SOCK`
  で逆チャネルのソケットのパスを変えられる（既定 `$XDG_RUNTIME_DIR/portfwd.sock`、
  `XDG_RUNTIME_DIR` が無ければ `/run/user/<uid>/portfwd.sock`）。
- `chezmoi apply` で daemon が再起動した直後は、listen ソケットがまだ bind される前に
  `portfwd status` が一度だけ `stopped` を返すことがある。少し待って再実行すれば正しい
  結果になる。

### macOS: launchd の操作

| 操作 | コマンド |
| --- | --- |
| 状態確認 | `launchctl print gui/$(id -u)/com.snishi.portfwd` |
| 再起動 | `launchctl kickstart -k gui/$(id -u)/com.snishi.portfwd` |
| 停止（一時） | `launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.snishi.portfwd.plist` |
| 起動 | `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.snishi.portfwd.plist` |
| ログ | `~/Library/Logs/portfwd.log` |

plist または daemon 本体を変更したら `chezmoi apply` すれば
`run_onchange_after_55-portfwd-launchd.sh` が bootout → bootstrap で再ロードする。
登録スクリプトが daemon 本体のハッシュも含むのは、launchd が生きているプロセスを
再起動しないため、本体だけを更新したときも入れ替える必要があるから。

## Windows セットアップ

### 前提

- **AWS CLI と SSO profile は別途手動で設定しておくこと。** `dot_aws/create_config` の
  `credential_process = aws-login <profile>` は bash スクリプトを呼ぶため Windows では動かず、
  `.aws` は Windows へ展開しない。`cloudsa` への ssh が通ることが portfwd の前提になる。
- Python（管理者権限は不要）:
  ```powershell
  winget install Python.Python.3.13 --scope user
  ```
- OpenSSH は OS 同梱のもので足りる。ssh config は `Tag` / `Match tagged`（8.9+）を使わない
  形で生成されるため、同梱の 8.1 / 8.6 でも動く。
- **1Password SSH Agent を有効にしておくこと。** Windows の ssh config は `IdentityAgent` を
  出力しない。Microsoft OpenSSH は固定パイプ `\\.\pipe\openssh-ssh-agent` で待ち受け、
  1Password の agent がそれを引き継ぐため、パスを指定する必要が無いからだ（macOS/Linux は
  `~/.1password/agent.sock` を明示する）。裏を返すと、agent が有効でないと鍵ファイルと
  `IdentitiesOnly yes` だけが展開されて秘密鍵を取得できず、ssh 自体が通らない。手順は
  [1Password の公式ガイド](https://www.1password.dev/ssh/get-started)のとおり:
  1. `services.msc` の **OpenSSH Authentication Agent** を「スタートアップの種類」＝無効にし、
     実行中なら停止する（1Password が固定パイプを使えるようにするため）
  2. 1Password の 設定 > 開発者 で **SSH エージェントを使用** を有効にする
  3. 1Password を通知領域に常駐させておく（設定 > 一般）
  4. `ssh -T git@github.com` で agent 経由の認証が通ることを確認する

### 展開

> `run_after_56-portfwd-schtask.ps1.tmpl` はコメントを含めて ASCII のみで書く。
> chezmoi はレンダリング結果を BOM 無しで書き出し、Windows PowerShell 5.1 は BOM 無しの
> `.ps1` を ANSI コードページ（日本語環境では CP932）として読むため、非 ASCII バイトが
> 壊れてパースエラーになる。このリポジトリで唯一、日本語コメントを使わないファイル。

`chezmoi apply` すると、Windows では `.ssh/` 内の必要ファイル（`config`・`*.bat`・
鍵ファイル `1password_AkashiSN.pub` / `1password_su-nishi.pub` / `gpg.pub` /
`allowed_signers`）と `.local/bin/portfwd` が展開され、
`run_after_56-portfwd-schtask.ps1` がタスクスケジューラへ登録する。鍵ファイルは
`private_config.tmpl` の `cloudsa` / `develop-server` が `IdentityFile
~/.ssh/1password_AkashiSN.pub` を参照しているため必須で、`.chezmoiignore` は
`env "SSH_CONNECTION"` のときだけこれらを除外する（ローカルの `chezmoi apply` では
`SSH_CONNECTION` が未設定なので除外されない）。シェル環境は WSL 側にあるため、それ以外は
展開しない。

> **登録スクリプトは `run_onchange` ではなく `run_`（毎回実行）**。`run_onchange` は一度実行した
> 記録が entryState に残るだけなので、その後で手動削除されたタスクは二度と復活しない。毎回走らせる
> 代わりに、登録済みの内容（タスクの説明に埋めた daemon の SHA-256 + コマンドライン）と比較して
> **差があるときだけ登録し直す** — `Register-ScheduledTask -Force` は走行中の daemon を止めるため、
> 無条件に再登録すると中継中のポートフォワードが切れる。登録済みだが走っていないタスクは起動する
> （`RestartCount` が尽きて止まった daemon が `chezmoi apply` で戻る）。**無効化されたタスクは
> 利用者の判断なので触らない。**
>
> 非 Windows では中身が空になるが、毎回実行のため `.chezmoiignore` で
> `.chezmoiscripts/56-portfwd-schtask.ps1` を除外している（target 名は属性接頭辞を除いた形）。

### タスクの操作

| 操作 | コマンド |
| --- | --- |
| 状態確認 | `Get-ScheduledTask -TaskName portfwd \| Get-ScheduledTaskInfo` |
| 再起動 | `Stop-ScheduledTask -TaskName portfwd; Start-ScheduledTask -TaskName portfwd` |
| 停止（一時） | `Stop-ScheduledTask -TaskName portfwd` |
| 起動 | `Start-ScheduledTask -TaskName portfwd` |
| ログ | `Get-Content "$env:LOCALAPPDATA\portfwd\portfwd.log" -Tail 50 -Encoding UTF8` |

`pythonw.exe` は stderr を捨てるため、Windows では daemon が `PORTFWD_LOG`
（既定 `%LOCALAPPDATA%\portfwd\portfwd.log`）へ自分でログを書く。ログファイルが唯一の
手がかりになる場面が多いので、切り分けはまずそこから見る。

- **ログは UTF-8 で書かれる。** `cmd.exe` の `type` は cp932 で読むため
  `reject: cloudsa 縺ｯ portfwd ...` のように化けて reject の理由が読めない。
  PowerShell で `-Encoding UTF8` を付けて読む。
- **通知を 1 件処理するたびに 1 行増える。** 行が増えないなら通知自体が自分の PC まで
  届いていない（逆チャネルが別人のトンネルへ相乗りしていないか、ソケットのパスの uid を
  確認する）。

### 恒常的に落ちるときの調べ方

タスクの再起動回数（`RestartCount 99`）は有限で、尽きると **次回ログオンまたは次回
`chezmoi apply` まで daemon は停止したままになる**。次の 3 点で切り分ける。

1. `py -3 "$env:USERPROFILE\.local\bin\portfwd" status` — `not-portfwd` なら他プロセスが 55999 を掴んでいる
2. `Get-ScheduledTask -TaskName portfwd | Get-ScheduledTaskInfo` の `State` と `LastTaskResult`
3. `%LOCALAPPDATA%\portfwd\portfwd.log`

## 対象ホストの追加手順

ssh config（`private_dot_ssh/private_config.tmpl`）の対象 Host ブロックに次を追加する。

```sshconfig
Host <alias>
    ...
    DynamicForward  127.0.0.1:<未使用ポート>
    SetEnv          LC_PORTFWD_HOST=<alias>
    RemoteForward   /run/user/<サーバ上の uid>/portfwd.sock 127.0.0.1:55999
{{- if ne .chezmoi.os "windows" }}
    Tag             portfwd
{{- end }}
```

- `DynamicForward` は **ホストごとに別ポート**を割り当てる。共通ブロックに書くと同時接続時に
  2 本目の bind が失敗する。bind address（`127.0.0.1:`）も明示する — daemon は IPv4 loopback で
  なければ reject する。
  - 使用中: `cloudsa` = 55888、`develop-server` = 55887
- `RemoteForward` の listen 端は **そのサーバ上の自分の uid** のパスにする。共通ブロックへは
  括り出せない（uid がサーバごとに違うため）。値はログイン後に `id -u` で引く。
  - 使用中: `cloudsa` = 1002、`develop-server` = 1000
- `SetEnv` は**マッチする最初の 1 行しか効かない**。2 行目以降は値ごとにマージされるのではなく
  丸ごと捨てられるので、同じホストへ他の環境変数を渡すときは 1 行にまとめる。
- 非 Windows は `Tag portfwd` を付けると `Match tagged portfwd` ブロックの `ControlMaster` が
  効く。Windows は `Tag` が使えないので付けない（`RemoteForward` は元から Host ブロック側）。

## 逆チャネルがユーザごとに分かれる理由

逆チャネルの listen 端は **Unix domain socket**（`$XDG_RUNTIME_DIR/portfwd.sock`
= `/run/user/<uid>/portfwd.sock`）で、TCP ポートではない。

`127.0.0.1:<port>` はサーバ全体で 1 つしかない。複数人が使うサーバで全員が同じ
`RemoteForward 127.0.0.1:55999` を書くと、先に ssh を張った人の sshd がそのポートを占有し、
2 人目以降の bind は**黙って失敗する**（`ExitOnForwardFailure` は既定 `no` なので ssh 自体は
普通に繋がる）。その結果、2 人目の `portfwd-open` が投げた通知は**先客のトンネルを通って
別人の PC の daemon へ届く**。

このとき daemon の `SetEnv LC_PORTFWD_HOST` 照合が最後の砦になり、host が食い違えば reject
される。裏を返せば、**2 人が同じ別名（`cloudsa` など）を使っていれば照合は通ってしまう**。
そうなると認可ページは別人のブラウザで開き、その人が認証した結果の認可コードが SOCKS
リレー経由で**通知を出した側の `aws login` へ渡る**。

`/run/user/<uid>` は uid ごとに分かれていて権限は `0700`、ソケット自身も
`StreamLocalBindMask 0177` により `0600` になるため、取り違えが起こらない。
**TCP へのフォールバックは持たない。**黙って別人の PC へ届くより、明示的に壊れて
`aws login --remote` へ落ちる方が安全なため。

## 安全策

- daemon がリレーを張るのは **localhost の callback が見つかったときだけ**（`redirect_uri` か
  URL 自体が `127.0.0.1`/`localhost`）。それ以外の URL は転送せずブラウザで開くだけ
  （任意ポート転送の踏み台化防止）。
- `ssh -G <host>` の `SetEnv LC_PORTFWD_HOST` が通知の host と一致しなければ破棄する。
  これが「明示的にオプトインされたホストのみ」の担保で、callback の有無に関わらず必須。
- callback があるときは加えて、`dynamicforward` が 1 つだけ存在して IPv4 loopback に
  bind されていること、そのポートで SOCKS5 が greeting に応答することを確かめる。
  - この probe が保証するのは「そのポートで SOCKS5 が応答中」までで、**それが対象ホストの
    ssh 接続のものであることまでは証明しない**。SetEnv によるオプトインとホストごとの
    固定ポートと組み合わせて実用上十分、という位置づけ。
  - オプトイン検証は「通知が主張する host が portfwd 対象として設定されている」ことは
    確かめるが、**通知が実際にその host から届いたことまでは証明しない**。侵害された
    オプトイン済みホストが `{"host": "<別のオプトイン済みホスト>"}` を送れば、daemon は
    その別ホストのリモート loopback へ中継してしまう。
- 同じ callback ポートに **別ホスト**の通知が来たら reject する。張り替えると先行フローの
  ブラウザ callback を後発ホストへ誤配送してしまうため、奪わない。
- http/https 以外のスキームは開かない。
- reject / error は **HTTP 4xx** で返すため `portfwd-open` が非ゼロ終了する。これにより逆チャネルに
  届かない／弾かれた場合は各ツールが従来動作へフォールバックする（`aws login` は `--remote`）。
  - **限界**: SOCKS5 CONNECT の失敗はリレー確立後（通知に 200 を返した後）に起きるため、
    フォールバックには繋がらない。ログにだけ残る。

## 前提

- リモートでも chezmoi apply 済み（`portfwd-open` と `dot_zshenv` の BROWSER 設定が必要）。
  `portfwd-open` は Unix domain socket へ POST するので **`curl` が要る**（bash の `/dev/tcp`
  は TCP 専用）。
- ローカルは macOS / Windows。Linux も daemon は動く（`xdg-open` を使う）が、常駐用の
  systemd user unit は未整備。
- 対象ホストの ssh 接続が `DynamicForward` の bind に成功していること。`ExitOnForwardFailure`
  は既定の `no` なので、bind に失敗しても ssh 自体は繋がる。daemon は毎回 probe するため、
  この場合は reject されてフォールバックする。
- sshd が両方向のフォワードを許可していること（どちらも既定 `yes`）。リモートで確認:

  ```sh
  sshd -T | grep -E 'allowtcpforwarding|allowstreamlocalforwarding'
  ```

  | 設定 | 使う経路 |
  | --- | --- |
  | `AllowTcpForwarding yes` | `DynamicForward` の SOCKS5 リレー。`local` / `remote` のどちらか一方だけでは足りない |
  | `AllowStreamLocalForwarding yes` | 逆チャネルの `RemoteForward`（Unix domain socket） |

- sshd が `StreamLocalBindUnlink yes` であること。**既定は `no`** で、この場合 ssh が異常終了して
  `portfwd.sock` のファイルが残ると次の接続の bind が失敗し、**そのユーザの portfwd はログアウト
  まで復旧しない**。

  ```sh
  sshd -T | grep streamlocalbindunlink    # yes なら OK
  ```

  出なければ root で drop-in を置く。**設定は新規接続にしか効かない**ので、既存の ssh は
  張り直す:

  ```sh
  printf 'StreamLocalBindUnlink yes\n' | sudo tee /etc/ssh/sshd_config.d/11-streamlocal.conf
  sudo sshd -t && sudo systemctl reload sshd
  ```

  応急処置としては、残骸を消してから ssh を張り直してもよい（`rm -f /run/user/<uid>/portfwd.sock`）。
- sshd が `LC_*` を `AcceptEnv`（多くは既定で受理）。リモートで確認:
  `grep -ri acceptenv /etc/ssh/sshd_config /etc/ssh/sshd_config.d/`。
  無ければ追加する — `Include` 行がある構成なら `/etc/ssh/sshd_config.d/*.conf` に、
  無ければ `/etc/ssh/sshd_config` 本体に `AcceptEnv LANG LC_*` を追記し、
  `sshd -t` で検証してから `systemctl reload sshd`（`restart` ではなく `reload` を
  使うことで、reload 中も既存セッションを切らない）。**設定は新規接続にしか効かない**ため、
  開きっぱなしの ssh セッションは張り直す必要がある。
- `~/.config/portfwd/host` — herdr のように長時間動くサーバプロセスが新しいペインへ
  サーバ起動時点の環境を配る multiplexer では、サーバ起動時に `LC_PORTFWD_HOST` が
  無かった場合そのペインに変数が届かない。`herdr server stop` でサーバを再起動すれば
  その時点では直るが、サーバがまた変数無しで起動する状況が再発するたびに同じ問題が
  起きるため恒久対応にならない（herdr 自体には環境変数をペインへ引き継ぐ設定項目が
  無い）。値はホストごとに固定なので、`dot_zshenv.tmpl` が `LC_PORTFWD_HOST` が
  ある（＝プレーンな ssh セッションで `SetEnv` から渡った）ときにこのファイルへ
  自動で書き込み、無いときはここから復元する（詳細は同ファイルのコメント参照）。
  手動の作成は不要 — 対象ホストへ `chezmoi apply` 済みの状態で普通に ssh ログイン
  すれば 1 回で書き込まれ、以降は herdr のペインを含む全シェルで復元される。
  うまくいかないときは次を確認する:
  - リモートの `.zshenv` が最新か（そのホストで `chezmoi apply` を実行したか）
  - まだ一度もプレーンな ssh セッションでログインしていない（multiplexer のペインは
    ファイルを復元するだけで書き込まないため、先に 1 回の通常ログインが要る）
  - それでも駄目なら次の手動 `echo` でファイルを直接作れる（対話ログイン無しで
    seed したい場合のフォールバック）:
    ```sh
    mkdir -p ~/.config/portfwd
    echo <alias> > ~/.config/portfwd/host
    ```
  確認は multiplexer 上で新しいシェルを開いて `echo $LC_PORTFWD_HOST` を実行する。

## トラブルシューティング

### `portfwd-open` が 422 を返す／`LC_PORTFWD_HOST` が無いと報告する

次の順で切り分ける。

1. リモートで `echo $LC_PORTFWD_HOST` — 空なら sshd 側が変数を届けていない
   （上記の `AcceptEnv` を確認）。
2. ローカルで `ssh -G <host>` の `setenv` 行に `LC_PORTFWD_HOST=<alias>` があるか
   （無ければ ssh config 側の `SetEnv` が対象ホストに効いていない）。
3. ローカルの daemon ログ（`PORTFWD_LOG`。既定は macOS が
   `~/Library/Logs/portfwd.log`、Windows が `%LOCALAPPDATA%\portfwd\portfwd.log`）で
   reject/error の理由を確認する。

reject/error の理由は daemon ログだけでなく、`portfwd-open` 実行時のリモート側
stderr にもそのまま出る（`curl` 使用時・`/dev/tcp` フォールバック時のいずれも）ため、
リモートで直接メッセージを読めることが多い。

### `aws login` が `--remote` に落ちる（ブラウザが開かない）

逆チャネルの `/health` が通っていない。**`aws-login` が理由を端末へ出しているので、まずそれを読む**:

```
aws-login: portfwd 逆チャネルが使えません: <理由>。aws login --remote へフォールバックします。
```

| 出る理由 | 意味 | 対処 |
| --- | --- | --- |
| `LC_PORTFWD_HOST が空` | オプトインしていないセッション | ssh config の `SetEnv`（最初の 1 行しか効かない）と sshd の `AcceptEnv`（上の節） |
| `<path> がありません` | ソケットが作られていない | ローカルの ssh config の `RemoteForward` がそのパスを指していない（uid 違い）、または bind に失敗（残骸ファイル / `StreamLocalBindUnlink no`。`ExitOnForwardFailure` は既定 `no` なので、失敗しても ssh 自体は繋がる） |
| `curl がありません` | 逆チャネルへ POST する手段が無い | リモートに `curl` を入れる |
| `へ接続できません` | ソケットはあるが転送先が閉じている | ssh セッションが死んでいる。張り直す |
| `空応答です` | sshd は listen しているが転送先に誰もいない = **ローカルの daemon が落ちている** | 「[macOS: launchd の操作](#macos-launchd-の操作)」「[タスクの操作](#タスクの操作)」でログと状態を見る |
| `5 秒以内に応答しません` | daemon が停止中／応答不能 | 同上 |
| `応答が portfwd daemon のものではない` | ローカルの 55999 を別のプロセスが握っている | ローカルで 55999 の使用者を確認（`portfwd status` が `not-portfwd` を返す） |

手で確認するなら、SSH 先で:

```sh
ls -l "$XDG_RUNTIME_DIR/portfwd.sock"   # srw------- なら sshd が listen 中
curl -sS --max-time 5 --unix-socket "$XDG_RUNTIME_DIR/portfwd.sock" http://localhost/health
```

ソケットがそもそも出来ていないときは、ローカル側を次の順に見る。

| 見るもの | 期待 |
| --- | --- |
| `ssh -G <alias> \| grep remoteforward` | `remoteforward /run/user/<uid>/portfwd.sock [127.0.0.1]:55999` が出る |
| その `<uid>` | SSH 先で `id -u` した値と一致する（違うと他人のディレクトリへ bind しようとして失敗する） |
| ssh を張り直したか | **`RemoteForward` は接続時にしか要求されない。** config を書き換えただけでは効かず、`ControlPersist` で残っている master も畳む必要がある（`ssh -O exit <alias>`） |

**逆チャネルは「いまどれかのオプトインした ssh セッションが生きているか」だけに依存する。**
herdr のサーバは ssh セッションより長生きするため、ペインの中にいても逆チャネルが無い時間帯が
ありうる（逆に、いま繋いでいるのとは別の ssh セッションがソケットを握っていてもよい）。

### ssh セッションに `channel N: open failed: connect failed: Connection refused` が出る

daemon ログに次のような `SOCKS CONNECT 失敗` の行が同時に残っていて、かつ**認証自体は
成功している**なら、これは無害。

```
relay <port>: SOCKS CONNECT 失敗 (SOCKS プロキシが CONNECT 応答を送らず channel を
閉じました (リモート側がそのポートへの接続を拒否したと考えられる; ssh 自身の stderr に
channel N: open failed: connect failed: Connection refused と出ているはず))
```

リモートの OAuth callback サーバは認可コードを受け取った時点で終了するため、その後に
ブラウザが送る追加の接続（keep-alive・favicon 取得・リトライ等）は listen 先が無く、
OpenSSH はこの拒否を SOCKS5 のエラー応答ではなく channel のクローズで表現する。それが
`channel N: open failed` として ssh セッションに出る一方、daemon 側は「応答ヘッダを
読んでいる最中に接続が切れた」＝拒否として検出しログに残す。

無害なケースと本当の失敗の見分け方:

- **認証が最後まで完了しているか**（`aws login` / `gh auth` 等が成功で終わっているか）
- 同じ daemon ログに **`ok: relay <port> via <host>` の行があるか**（無ければリレー自体が
  張れておらず、これは別の問題）

この 2 点が揃っていれば無害。`channel N: open failed` は ssh クライアント自身が出す
メッセージで daemon 側からは制御できず、抑制する方法もない。

## 経緯

- **2026-06**: 初版。ControlMaster ソケット経由の `ssh -O forward` で callback ポートを
  `-L` フォワードしていた。ホスト識別は `Tag portfwd` + `ControlPath ~/.ssh/cm-%n` で、
  daemon は control socket の存在をオプトインの判定に使っていた。
- **2026-08**: Windows ネイティブ対応のため、動的フォワードを SOCKS5 リレー方式へ変更し、
  macOS も同じ実装に統一した。理由は次の 2 点。
  1. Windows の OpenSSH は ControlMaster に対応しておらず、config に書かれていると
     `getsockname failed: Not a socket` で接続自体が落ちる。`ssh -O forward` が使えない。
  2. Windows 同梱の OpenSSH は 8.1 / 8.6 が主流で `Tag` / `Match tagged`（8.9+）が使えない。
     管理者権限なしでは OS 同梱版の更新も当てにできない。

  あわせて、オプトインの判定を control socket の存在から `SetEnv LC_PORTFWD_HOST` の一致へ、
  `portfwd status` の判定を TCP connect から `GET /health` へ変更した（ポートを他プロセスが
  掴んでいるときに running と誤表示していたため）。`ControlMaster` は非 Windows に残して
  いるが、これは ssh 接続を再利用するための設定であり portfwd はもう依存しない。
- **2026-08（work 用 dotfiles からの取り込み）**: `aws-login` の逆チャネル判定も
  TCP connect から `GET /health` へ揃えた。`RemoteForward` の listen ソケットは SSH 先の
  sshd が持つため、ローカルの daemon が死んでいても connect は成功し、`portfwd-open` が
  `Empty reply from server` で落ちるまで気付けなかった。あわせて `dot_zshenv.tmpl` が
  既存の `$BROWSER` を上書きしないようにし、VSCode Remote 等の自前フォワードを壊さない
  ようにした（`aws-login` 側にも `$BROWSER` 経由で完結する分岐を追加）。
- **2026-09（work 用 dotfiles からの取り込み）**: 逆チャネルの listen 端を
  `RemoteForward 127.0.0.1:55999` から `/run/user/<uid>/portfwd.sock` へ移した。共有サーバでは
  loopback の TCP ポートが全ユーザで 1 つしかなく、先に ssh を張った人の sshd が占有して 2 人目
  以降の bind が黙って失敗し、通知が別人の PC の daemon へ届く事象が work 側で観測されたため
  （実測で uid 1002 の sshd-session が 55999 を握っていた）。`SetEnv` 照合が最後の砦になって
  reject されるが、2 人が同じ別名を使えば照合は通ってしまう。`portfwd-open` と `aws-login` は
  `curl --unix-socket` で叩くようになり、`PORTFWD_PORT` の上書きは `PORTFWD_SOCK` に替わった。
  TCP へのフォールバックは意図的に入れていない。あわせて `SetEnv` がマッチする最初の 1 行しか
  効かないこと（2 行目以降は丸ごと捨てられる）を ssh config と docs の注意書きへ足した。
  Windows の OpenSSH クライアントもこの形の `RemoteForward` を扱える（work 側で実機確認済み）。
  `RemoteForward <remote socket> <local host:port>` は **listen 側だけが Unix domain socket** で、
  クライアントは `streamlocal-forward@openssh.com` を要求したあと届いたチャネルをローカルの
  TCP へ繋ぐだけなので、Win32-OpenSSH 側の AF_UNIX 対応は関係しない（gpg-agent 転送と同じ形）。
- **2026-08**: `Host *` の keepalive を `ServerAliveInterval 1200` / `ServerAliveCountMax 12`
  から `30` / `3` へ短縮した。元の値は 20 分 × 12 回＝**4 時間**切断を検知せず、サーバ側も
  `ClientAliveInterval 0`（既定で無効）だったため、無言のネットワーク断で死んだ ssh 接続が
  何時間も残っていた。20 分間隔は多くの NAT のタイムアウトより長く接続維持の役にも立って
  いなかったため、短縮は NAT のマッピング維持も兼ねる。
  なおこの変更は当初「herdr が固まり以降の `ssh` が全部ハングする」現象の対策として入れたが、
  **その診断は誤りだった**。実際の原因は死んだ master の再利用ではなく、Kiro CLI のシェル統合
  （`kiro-cli-term` = figterm という pty プロキシ）が内側 pty を読まなくなり、その背圧で
  ControlMaster が mux socket への `write()` でブロックしてイベントループから出られなくなる
  デッドロックだった。TCP は生きたままなので keepalive では検知できない。詳細と切り分け手順は
  `docs/herdr-cheatsheet.md` の「herdr が固まり、そのホスト宛の ssh が全部ハングする」節。
  keepalive の短縮自体は本来の目的（死んだ接続の検知・NAT 維持）で有用なので残している。
