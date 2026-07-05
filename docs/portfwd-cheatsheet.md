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
| `portfwd ensure` | 未起動なら daemon をバックグラウンド起動（冪等）。ssh の `LocalCommand` から自動実行される |
| `portfwd serve` | 55999 で listen する常駐ループ（フォアグラウンド） |
| `portfwd stop` | daemon を停止 |
| `portfwd status` | 稼働状況を表示 |

- daemon は **対象ホストへの SSH（`~/.ssh/cm-*` control socket）が全て切れてから** アイドル
  30 分で自己終了する。SSH セッションが生きている間は idle でも終了しない（生存中に daemon
  だけ落ちると、RemoteForward は accept するのに転送先が居ず、リモート側が
  `curl: (56) Connection reset by peer` で失敗するため）。`-L` フォワードは
  `ControlPersist 10m` 失効で閉じる。
- 万一 SSH 生存中に daemon が落ちていたら（旧版で 30 分アイドル終了した後など）、ローカルで
  `portfwd ensure`（または対象ホストへ新規 ssh）すれば復活する。
- 環境変数: `PORTFWD_PORT`(既定 55999) で逆チャネルポートを変更可。

## 対象ホストの追加手順

ssh config（`private_dot_ssh/private_config`）の対象 Host ブロックに 2 行追加:

```sshconfig
Host <alias>
    ...
    Tag    portfwd
    SetEnv LC_PORTFWD_HOST=<alias>
```

共通設定は `Match tagged portfwd` ブロックに集約済み（`ControlMaster`/`ControlPath`/
`RemoteForward`/`LocalCommand` など）。タグを付けるだけで有効になる。

## 安全策

- daemon が `-L` を張るのは **localhost の callback が見つかったときだけ**（`redirect_uri` か
  URL 自体が `127.0.0.1`/`localhost`）。それ以外の URL は reject し、転送もブラウザ起動もしない
  （任意ポート転送・任意 URL オープンの踏み台化防止）。
- `LC_PORTFWD_HOST` に対応する control socket が無ければ通知は破棄。
- reject / error は **HTTP 4xx** で返すため `portfwd-open` が非ゼロ終了する。これにより逆チャネルに
  届かない／弾かれた場合は各ツールが従来動作へフォールバックする（`aws login` は `--remote`）。

## 前提

- リモートでも chezmoi apply 済み（`portfwd-open` と `dot_zshenv` の BROWSER 設定が必要）。
- ローカルは macOS（`open` コマンド / Python3）。
- OpenSSH 8.9+（`Tag` / `Match tagged`）。
- sshd が `LC_*` を `AcceptEnv`（多くは既定で受理）。
