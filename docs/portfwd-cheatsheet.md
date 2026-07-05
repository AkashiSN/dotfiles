# portfwd（SSH ブラウザ自動フォワード）チートシート

SSH 先で `aws login` / `gh auth` などがブラウザを開こうとしたとき、その URL を
ローカルへ転送してローカルのブラウザを自動で開く仕組み。対象ホストは ssh config の
`Tag portfwd` でオプトインする。

## 仕組み

```
remote: ツールが $BROWSER=portfwd-open を起動
   └─ URL を 127.0.0.1:55999 へ POST （RemoteForward でローカルへ）
local : portfwd daemon が受信
   1. authorize URL の redirect_uri（無ければ URL 自体）から localhost の callback ポート P を抽出
   2. ssh -O forward -L P:127.0.0.1:P -S ~/.ssh/cm-<host> <host>
   3. open <url>  （ローカルブラウザで authorize URL を開く）
```

- ツールがブラウザに渡すのは **認可サーバ上の authorize URL**（ホストは localhost ではない）で、
  コールバックは URL 内の `redirect_uri=http://127.0.0.1:P/...` に埋め込まれている。daemon は
  そこから P を取り出して `-L` を張り、URL 自体はそのままローカルブラウザで開く。

- リモートの `$BROWSER` は `dot_zshenv.tmpl` が `LC_PORTFWD_HOST` セット時のみ
  `~/.local/bin/portfwd-open` に向ける。
- ホスト識別は `SetEnv LC_PORTFWD_HOST=<alias>` + `ControlPath ~/.ssh/cm-%n`。

## ローカルの `portfwd` コマンド

| コマンド | 動作 |
| --- | --- |
| `portfwd serve` | 55999 で listen する常駐ループ（フォアグラウンド）。**launchd が起動する本体**なので手で叩くことはまず無い |
| `portfwd status` | 稼働状況を表示（127.0.0.1:55999 へ接続できるかで判定） |

- daemon の寿命は **launchd が管理する**（`~/Library/LaunchAgents/com.snishi.portfwd.plist`）。
  `RunAtLoad` でログイン時に起動し、`KeepAlive` で落ちても再起動するため、常時起動している。
  スクリプト自身にはアイドル自己終了も多重起動制御も無い（launchd に一本化したので廃止した）。
- listen に失敗（他プロセスが 55999 を掴んでいる等）すると `serve` は非ゼロ終了するが、
  launchd が `ThrottleInterval`（10s）を空けて再試行する。
- `-L` フォワードは通知ごとに張り、`ControlPersist 10m` 失効で閉じる。
- 環境変数: `PORTFWD_PORT`(既定 55999) で逆チャネルポートを変更可。

### launchd の操作

| 操作 | コマンド |
| --- | --- |
| 状態確認 | `launchctl print gui/$(id -u)/com.snishi.portfwd` |
| 再起動 | `launchctl kickstart -k gui/$(id -u)/com.snishi.portfwd` |
| 停止（一時） | `launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.snishi.portfwd.plist` |
| 起動 | `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.snishi.portfwd.plist` |
| ログ | `~/Library/Logs/portfwd.log` |

plist を変更したら `chezmoi apply` すれば `run_onchange_after_55-portfwd-launchd.sh` が
bootout → bootstrap で自動的に再ロードする。

## 対象ホストの追加手順

ssh config（`private_dot_ssh/private_config`）の対象 Host ブロックに 2 行追加:

```sshconfig
Host <alias>
    ...
    Tag    portfwd
    SetEnv LC_PORTFWD_HOST=<alias>
```

共通設定は `Match tagged portfwd` ブロックに集約済み（`ControlMaster`/`ControlPath`/
`RemoteForward`）。タグを付けるだけで有効になる。daemon 起動は ssh 側では行わず launchd 常駐に任せる。

## 安全策

- daemon が `-L` を張るのは **localhost の callback が見つかったときだけ**（`redirect_uri` か
  URL 自体が `127.0.0.1`/`localhost`）。それ以外の URL は reject し、転送もブラウザ起動もしない
  （任意ポート転送・任意 URL オープンの踏み台化防止）。
- `LC_PORTFWD_HOST` に対応する control socket が無ければ通知は破棄。
- reject / error は **HTTP 4xx** で返すため `portfwd-open` が非ゼロ終了する。これにより逆チャネルに
  届かない／弾かれた場合は各ツールが従来動作へフォールバックする（`aws login` は `--remote`）。

## 前提

- リモートでも chezmoi apply 済み（`portfwd-open` と `dot_zshenv` の BROWSER 設定が必要）。
- ローカルは macOS（`open` / Python3 / launchd 常駐）。Linux 対応は将来 systemd user unit を
  追加する想定（daemon コードは OS 非依存。`PORTFWD_OPEN_CMD=xdg-open` で `open` を差し替え）。
- OpenSSH 8.9+（`Tag` / `Match tagged`）。
- sshd が `LC_*` を `AcceptEnv`（多くは既定で受理）。
