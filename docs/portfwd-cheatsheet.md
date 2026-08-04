# portfwd（SSH ブラウザ自動フォワード）チートシート

SSH 先で `aws login` / `gh auth` などがブラウザを開こうとしたとき、その URL を
ローカルへ転送してローカルのブラウザを自動で開く仕組み。対象ホストは ssh config の
`SetEnv LC_PORTFWD_HOST` と `DynamicForward` でオプトインする。

## 仕組み

```
remote: ツールが $BROWSER=portfwd-open を起動
   └─ URL を 127.0.0.1:55999 へ POST （RemoteForward でローカルへ）
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
- リモートの `$BROWSER` は `dot_zshenv.tmpl` が `LC_PORTFWD_HOST` セット時のみ
  `~/.local/bin/portfwd-open` に向ける。

## ローカルの `portfwd` コマンド

| コマンド | 動作 |
| --- | --- |
| `portfwd serve` | 55999 で listen する常駐ループ（フォアグラウンド）。**サービスマネージャが起動する本体**なので手で叩くことはまず無い |
| `portfwd status` | 稼働状況を表示（`GET /health` の応答で判定） |

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
- リレーは通知ごとに張り、アイドル 180 秒で listener を閉じる。
- 環境変数: `PORTFWD_PORT`(既定 55999) で逆チャネルポート、`PORTFWD_OPEN_CMD` でブラウザ
  起動コマンド、`PORTFWD_LOG` でログファイル、`PORTFWD_SSH_CMD` で ssh コマンドを変更できる。
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

### 展開

`chezmoi apply` すると、Windows では `.ssh/` 内の必要ファイル（`config`・`*.bat`・
鍵ファイル `1password_AkashiSN.pub` / `1password_su-nishi.pub` / `gpg.pub` /
`allowed_signers`）と `.local/bin/portfwd` が展開され、
`run_onchange_after_56-portfwd-schtask.ps1` がタスクスケジューラへ登録する。鍵ファイルは
`private_config.tmpl` の `cloudsa` / `develop-server` が `IdentityFile
~/.ssh/1password_AkashiSN.pub` を参照しているため必須で、`.chezmoiignore` は
`env "SSH_CONNECTION"` のときだけこれらを除外する（ローカルの `chezmoi apply` では
`SSH_CONNECTION` が未設定なので除外されない）。シェル環境は WSL 側にあるため、それ以外は
展開しない。

### タスクの操作

| 操作 | コマンド |
| --- | --- |
| 状態確認 | `Get-ScheduledTask -TaskName portfwd \| Get-ScheduledTaskInfo` |
| 再起動 | `Stop-ScheduledTask -TaskName portfwd; Start-ScheduledTask -TaskName portfwd` |
| 停止（一時） | `Stop-ScheduledTask -TaskName portfwd` |
| 起動 | `Start-ScheduledTask -TaskName portfwd` |
| ログ | `%LOCALAPPDATA%\portfwd\portfwd.log` |

`pythonw.exe` は stderr を捨てるため、Windows では daemon が `PORTFWD_LOG`（既定は上記）へ
自分でログを書く。ログファイルが唯一の手がかりになる場面が多いので、切り分けはまず
そこから見る。

### 恒常的に落ちるときの調べ方

タスクの再起動回数（`RestartCount 99`）は有限で、尽きると **次回ログオンまたは次回
`chezmoi apply` まで daemon は停止したままになる**。次の 3 点で切り分ける。

1. `portfwd status` — `not-portfwd` なら他プロセスが 55999 を掴んでいる
2. `Get-ScheduledTask -TaskName portfwd | Get-ScheduledTaskInfo` の `State` と `LastTaskResult`
3. `%LOCALAPPDATA%\portfwd\portfwd.log`

## 対象ホストの追加手順

ssh config（`private_dot_ssh/private_config.tmpl`）の対象 Host ブロックに次を追加する。

```sshconfig
Host <alias>
    ...
    DynamicForward  127.0.0.1:<未使用ポート>
    SetEnv          LC_PORTFWD_HOST=<alias>
{{- if eq .chezmoi.os "windows" }}
    RemoteForward   127.0.0.1:55999 127.0.0.1:55999
{{- else }}
    Tag             portfwd
{{- end }}
```

- `DynamicForward` は **ホストごとに別ポート**を割り当てる。共通ブロックに書くと同時接続時に
  2 本目の bind が失敗する。bind address（`127.0.0.1:`）も明示する — daemon は IPv4 loopback で
  なければ reject する。
  - 使用中: `cloudsa` = 55888、`develop-server` = 55887
- 非 Windows は `Tag portfwd` を付けると `Match tagged portfwd` ブロックの
  `RemoteForward` と `ControlMaster` が効く。Windows は `Tag` が使えないため直接書く。

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
- 同じ callback ポートに **別ホスト**の通知が来たら reject する。張り替えると先行フローの
  ブラウザ callback を後発ホストへ誤配送してしまうため、奪わない。
- http/https 以外のスキームは開かない。
- reject / error は **HTTP 4xx** で返すため `portfwd-open` が非ゼロ終了する。これにより逆チャネルに
  届かない／弾かれた場合は各ツールが従来動作へフォールバックする（`aws login` は `--remote`）。
  - **限界**: SOCKS5 CONNECT の失敗はリレー確立後（通知に 200 を返した後）に起きるため、
    フォールバックには繋がらない。ログにだけ残る。

## 前提

- リモートでも chezmoi apply 済み（`portfwd-open` と `dot_zshenv` の BROWSER 設定が必要）。
- ローカルは macOS / Windows。Linux も daemon は動く（`xdg-open` を使う）が、常駐用の
  systemd user unit は未整備。
- 対象ホストの ssh 接続が `DynamicForward` の bind に成功していること。`ExitOnForwardFailure`
  は既定の `no` なので、bind に失敗しても ssh 自体は繋がる。daemon は毎回 probe するため、
  この場合は reject されてフォールバックする。
- sshd が `LC_*` を `AcceptEnv`（多くは既定で受理）。

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
