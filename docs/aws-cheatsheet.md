# AWS プロファイル切り替え チートシート

AWS CLI の `aws login`（新機能）と `credential_process` を使って AWS プロファイルを
切り替えるためのヘルパースクリプト群。`dot_local/bin/executable_aws-{switch,login,logout}`
（→ `~/.local/bin/aws-*`）。

> かつては MFA + STS（`get-session-token` / `assume-role`）方式だったが廃止。
> 現在は `aws login` に一本化し、MFA はブラウザでのログイン時に処理される。

## 前提となる仕組み（direnv + dotenv）

これらのスクリプトは **現在のシェルに `export` しない**。代わりに `${USER_DIR}/.env`
（`USER_DIR` 未設定時は `~`）の `export AWS_PROFILE=...` 行を書き換え、反映は direnv に任せる。

```
aws-switch <profile>
   │  └─ aws-login <profile> で `aws login` 認証
   └─ ${USER_DIR}/.env の AWS 行を書き換え (export AWS_PROFILE=<profile>)
        │
        ▼ 次のプロンプトで direnv が発火
~/.envrc が `dotenv` で ${USER_DIR}/.env を読み込む
        │
        ▼
シェル環境に AWS_PROFILE が入る → 以降の aws/SDK がそのプロファイルを使う
```

ポイント:

- **実行直後の同じコマンド内では効かない。** `.env` を direnv が読み直す「次のプロンプト以降」で
  有効になる。スクリプト実行 → Enter で空プロンプトに戻る、で反映される。
- `~/.envrc`（chezmoi: `dot_envrc`）の中身は `dotenv` の一行のみ。これが `${USER_DIR}/.env` を読む。
- `USER_DIR` は共有ユーザー環境などで `.env` とロックファイルを分離するための変数。
  ローカルでは未設定でよく、その場合 `~` が使われる。
- 必要パッケージ（aqua 管理）: `direnv`、`peco`、`aws` CLI v2。
- `flock`（aws-login の多重ログイン防止）は **aqua に無い**。Linux は `util-linux` 同梱、
  macOS は Homebrew で導入する（`run_onchange_before_10-install-packages.sh.tmpl` の FORMULAE）。

### 初期セットアップ

```sh
chezmoi apply                 # ~/.envrc / ~/.local/bin/aws-* / ~/.aws/config を展開
direnv allow ~                # ~/.envrc を許可（または対象ディレクトリで allow）
touch ~/.env                  # 無ければ作成（aws-switch が追記する先）
```

## スクリプト

| コマンド | 役割 |
| --- | --- |
| `aws-switch [profile] [role_arn]` | プロファイルを切り替える（必要なら assume role）。`.env` を書き換え |
| `aws-login <profile>` | 認証本体。`credential_process` として AWS CLI から自動で呼ばれる |
| `aws-logout [profile]` / `aws-logout --all` | セッションと `-signin` プロファイルを破棄し、`.env` の AWS 行を削除 |

### aws-switch

```sh
aws-switch                       # peco でプロファイルを選択（-signin は除外）
aws-switch my-profile            # プロファイル指定で切り替え
aws-switch my-profile <role_arn> # assume role 付きで切り替え
```

- ロール ARN の決定順: `第2引数` → プロファイルの `assume_role_arn` 属性 → どちらも無ければ
  IAM ユーザー権限のまま。
- assume role 時はブラウザでの認証画面で **ユーザーではなく対象ロールを選ぶ** 必要がある
  （スクリプトが警告を表示する）。

### aws-login

- 直接叩くことは少ない。`~/.aws/config` の `credential_process` に登録され、
  AWS CLI/SDK が認証情報を要求したタイミングで自動実行される。
- ベースプロファイル名に `-signin` サフィックスを付けたプロファイルでセッションを管理する。
- **キャッシュの有無ではなく、`aws sts get-caller-identity` で「いま実際に通るか」を検証する。**
  期限切れ/権限喪失のキャッシュは無効と判定してブラウザログインへ進む。`get-caller-identity` は
  IAM 権限不要なので、失敗＝トークンが無効/期限切れ を意味する（signin プロファイルは
  `credential_process` を持たないため、この STS 呼び出しは `aws-login` に戻らず再帰しない）。
- STS が **到達不能**（ネットワーク断など）の一時エラーのときは、ログインせずキャッシュ済み
  認証情報で続行する（期限内の作業を不要なログインで止めない）。
- `AWS_LOGIN_SKIP_VERIFY=1` を付けると STS 検証を省略し、従来の「設定があれば OK」動作に戻せる。
- `flock` で排他制御し、複数プロセスが同時にログイン画面を開くのを防ぐ。

#### SSH 先でのログイン（`--remote` 自動切替）

通常の `aws login` は **ローカルに OAuth コールバックサーバを立て localhost へリダイレクト**
する方式のため、SSH 先ではブラウザも開かず URL も完結しない。`aws-login` は
`$SSH_CONNECTION` を見て SSH セッションを検出すると、自動で `aws login --remote` に切り替える。

- `--remote` はコールバックを使わず、**URL を表示して認証コードの貼り付けを促す**方式:

  ```
  Browser will not be automatically opened.
  Please visit the following URL:
  https://<region>.signin.amazonaws.com/authorize?...
  Please enter the authorization code displayed in the browser:
  ```

  手元の PC のブラウザで URL を開き、ログイン後に表示される認証コードを端末に貼り付ける。
- URL とコード入力プロンプトは制御端末（`/dev/tty`）へ直結するので、`aws-switch` が
  `aws-login` の出力を捨てていても見える（= `aws-switch` 経由でも SSH ログインできる）。
- ローカル（非 SSH）では従来どおりブラウザが自動で開く。

### aws-logout

```sh
aws-logout my-profile   # 特定プロファイルからログアウト
aws-logout              # 環境変数 AWS_PROFILE のプロファイルからログアウト
aws-logout --all        # すべての -signin プロファイルを掃除
```

- `.env` の AWS 行を消すので、次のプロンプト以降はプロファイル無指定（既定）に戻る。

## ~/.aws/config の構成と制約

スクリプトは `~/.aws/config` の構造に強く依存している。プロファイルは大きく2種類:

### ベースプロファイル `[profile <name>]`（手元で管理する側）

| 属性 | 必須 | 説明 |
| --- | --- | --- |
| `credential_process` | **必須** | `aws-login <name>` を指定。これが無いと `aws login` 認証が走らない。`<name>` はプロファイル名と一致させる（`aws-login` が `<name>-signin` を組み立てる起点になる） |
| `region` | 推奨 | 例: `ap-northeast-1`。未設定なら `aws-login` が東京を補完する |
| `assume_role_arn` | 任意 | **AWS CLI 標準ではない独自属性**。設定すると `aws-switch` が自動で Assume Role Mode に入り、ブラウザで選ぶべきロール ARN を表示する |

```ini
[profile my-profile]
region = ap-northeast-1
credential_process = aws-login my-profile
assume_role_arn = arn:aws:iam::123456789012:role/Admin   # 任意
```

制約・注意:

- **`credential_process` の値はプロファイル名と一致させる。** `aws-login <name>` の `<name>` が
  `<name>-signin` セッションプロファイルのキーになるため、ズレるとセッションが混線する。
- **ベースプロファイル名を `-signin` で終わらせない。** `-signin` はセッション用の予約サフィックスで、
  peco 候補からも除外される（`aws-switch` / `aws configure list-profiles | grep -v signin`）。
- `assume_role_arn` を設定しても **このスクリプトが ARN を直接 assume するわけではない**。
  分岐に関わらず実行されるのは同じ `aws-login <name>` で、ARN は「ブラウザでどのロールを選ぶか」の
  リマインダーとして表示されるだけ。実際のロール選択は `aws login` のブラウザ認証側で行う。
- `assume_role_arn` は標準キーではないため `aws` CLI からは無視される。手書きで `~/.aws/config` に
  足すか、恒久管理したいなら `dot_aws/modify_config` の管理キーに追加する（下記）。

### セッションプロファイル `[profile <name>-signin]`（自動生成・触らない側）

- `aws-login` が初回に作成し、`aws login` のセッション（`region` / `login_session`）を保持する。
- **手で作成・編集しない。** 破棄は `aws-logout` / `aws-logout --all` に任せる
  （`-signin` セクションを config から削除する）。
- ベース権限と Assume Role 権限を別キャッシュで持てるよう、プロファイルごとに分離されている。

## ~/.aws/config の管理（chezmoi modify_）

`~/.aws/config` は実行時に各スクリプトと `aws login` が書き換える（`-signin`/`-admin` セクションや
`login_session` の追記）。そのためファイル全体を chezmoi 管理にするとドリフトとセッション破壊が起きる。

## 典型フロー

```sh
aws-switch                  # peco でプロファイル選択 → aws login 認証 → .env 更新
# Enter（プロンプトに戻ると direnv が AWS_PROFILE を反映）
aws s3 ls                   # 切り替えたプロファイルで実行
aws-logout --all            # 終わったらセッションを破棄
```
