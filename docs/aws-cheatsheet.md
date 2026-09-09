# AWS プロファイル切り替え チートシート

AWS CLI の `aws login`（新機能）と `credential_process` を使って AWS プロファイルを
切り替えるためのヘルパースクリプト群。`dot_local/bin/executable_aws-{switch,login,logout}`
（→ `~/.local/bin/aws-*`）。

> かつては MFA + STS（`get-session-token` / `assume-role`）方式だったが廃止。
> 現在は `aws login` に一本化し、MFA はブラウザでのログイン時に処理される。

> `.env` とロックファイルの置き場所は、かつて `USER_DIR`（未設定時 `~`）で切り替えていた。
> 共有ユーザー環境で 1 つの `$HOME` を複数人が使う構成を想定した変数だったが、実際には
> ユーザーごとに `$HOME` が分かれるため使い道が無く、廃止して `$HOME` 直書きに戻した。

## 前提となる仕組み（direnv + dotenv）

これらのスクリプトは **現在のシェルに `export` しない**。代わりに `$HOME/.env` の
`export AWS_PROFILE=...` 行を書き換え、反映は direnv に任せる。

```
aws-switch <profile>
   │  └─ aws-login <profile> で `aws login` 認証
   └─ $HOME/.env の AWS_PROFILE 行を書き換え (export AWS_PROFILE=<profile>)
        │
        ▼ 次のプロンプトで direnv が発火
~/.envrc が `dotenv` で $HOME/.env を読み込む
        │
        ▼
シェル環境に AWS_PROFILE が入る → 以降の aws/SDK がそのプロファイルを使う
```

ポイント:

- **実行直後の同じコマンド内では効かない。** `.env` を direnv が読み直す「次のプロンプト以降」で
  有効になる。スクリプト実行 → Enter で空プロンプトに戻る、で反映される。
- `~/.envrc`（chezmoi: `dot_envrc`）の中身は `dotenv` の一行のみ。これが `$HOME/.env` を読む。
- `.env` と `aws-login` のロックファイル（`~/.aws/.aws-login-<profile>.lock`）はどちらも
  `$HOME` 直下。ユーザーごとに `$HOME` が分かれるので、置き場所を切り替える変数は持たない。
- `.env` の書き換え対象は `AWS_PROFILE` 行だけ。`aws-switch` / `aws-logout` が消すのも
  `^(export )?AWS_PROFILE=` にマッチする行に限られるので、`CODEX_BEDROCK_AWS_PROFILE` の
  ように名前に `AWS` を含む別の変数を `.env` に置いても巻き込まれない。
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
| `aws-switch [profile] [role_name]` | プロファイルを切り替える（必要なら assume role）。`.env` を書き換え |
| `aws-login <profile>` | 認証本体。`credential_process` として AWS CLI から自動で呼ばれる |
| `aws-logout [profile]` / `aws-logout --all` | セッションと `-signin` プロファイルを破棄し、`.env` の `AWS_PROFILE` 行と認証情報キャッシュを削除 |
| `aws-auth-ensure <profile> [用途]` | そのプロファイルがいま認証済みかを確かめ、未認証なら認証する。TUI アプリを起動する前に通す |

### aws-login の認証情報キャッシュ

`aws-login` は出力した認証情報を `~/.aws/.aws-login-<profile>.creds.json`（パーミッション
600）に残し、`Expiration` まで 120 秒以上あればそれを返して即座に終える。**キャッシュに
当たると 2.4 秒が 0.02 秒になる。**

これが要るのは `credential_process` が「必要なとき 1 回」呼ばれるとは限らないため。発行される
認証情報の寿命（約 15 分）が botocore の advisory refresh window（900 秒）を下回っていると、
SDK は署名のたびに更新を試み、しかも access key / secret / token の各プロパティ参照で個別に
呼ぶので、**1 回の署名で数回** `aws-login` が起動する。通常経路は `aws` CLI を 2 回起動する
（`export-credentials` 0.7 秒 + `sts get-caller-identity` 0.9 秒）ため、これが十数秒に膨らみ、
MCP サーバーのように起動時へ署名が集中する利用者は接続タイムアウト（30 秒）に掛かる。

期限が近づけば通常経路へ落ち、`aws` CLI が新しいセッションを発行してキャッシュも更新される
ので、自動更新の仕組みは変わらない。キャッシュを返す間は STS 検証を挟まないが、認証情報の
寿命そのものが短いので窓は限られ、途中で無効化された場合も API が認証エラーを返すだけで
復旧できる。`aws-logout` はトークンを破棄してもキャッシュの `Expiration` を縮められないため、
ログアウト時にファイルごと消している。

キャッシュが壊れている・空・`Expiration` が無いときは通常経路へ落ちるので、消して困ることは
無い。挙動を疑ったら消してよい。

```sh
rm -f ~/.aws/.aws-login-<profile>.creds.json
```

### aws-switch

```sh
aws-switch                        # peco でプロファイルを選択（-signin は除外）
aws-switch my-profile             # プロファイル指定で切り替え
aws-switch my-profile <role_name> # assume role 付きで切り替え（ARN ではなくロール名）
```

- ロール名の決定順: `第2引数` → プロファイルの `assume_role_name` 属性 → どちらも無ければ
  IAM ユーザー権限のまま。
- assume role 時はブラウザでの認証画面で **ユーザーではなく対象ロールを選ぶ** 必要がある
  （スクリプトが警告を表示する）。
- peco の選択を **キャンセル**（Ctrl+C / ESC / 候補ゼロのまま Enter）すると
  `Profile selection cancelled. Nothing changed.` を出して終了ステータス 1 で中断する。
  `.env` は書き換えず、`aws-login` も呼ばない（現在のプロファイルはそのまま）。
  - peco はキャンセル時の終了コードが 0 になることがあり `set -e` では捕まらないため、
    選択結果が空かどうかで中断を判定している。防御として `aws-login` 側も空のプロファイル名を
    拒否する（空だと `-signin` という別プロファイルを掴んでしまうため）。

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
- `AWS_LOGIN_NO_INTERACTIVE=1` を付けると、未認証でもログインへ進まず `/dev/tty` へ何も書かずに
  エラー終了する。代わりに認証を人へ渡す（下の
  [走行中に認証が切れたとき](#走行中に認証が切れたとき)）。
- `flock` で排他制御し、複数プロセスが同時にログイン画面を開くのを防ぐ。ロックが空いていれば
  黙って取る。取れなかったときだけ「誰が握っているのか」を出してから最大 60 秒待つ。
  保持者は `lsof`（無ければ Linux の `/proc/<pid>/fd`）でロックファイルを開いているプロセスを
  引いて求める。**`/proc/locks` は見ない** — あちらが載せるのはロックを作った pid で、`flock(1)`
  経由だとその補助プロセスは既に終了しており、実際に押さえているのは fd を継いだ側になる。
  挙げた pid のどれにも制御端末が無く、かつどれかが init 配下なら、待っても空かない見込みとして
  `kill` のコマンドまで出す（端末を持つプロセスが 1 つでも混ざっていれば pid を並べるだけ）。
- **ログインが完結しなかったときは終了コード 1 を返す。** `aws login` は、
  `Profile <name>-signin is already configured ... overwrite? (y/n)` に `n` と答えたときのように、
  ログインしないまま 0 で戻ることがある。そこで `aws login` の終了コードではなく、最後に
  認証情報を取り出せたかどうかで判定し、取れなければ `.expired` を置いて失敗として終える
  （認証できていないのに呼び出し元が先へ進まないため）。

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

ただし「ローカルのブラウザを開けて localhost コールバックも戻ってくる」経路があるときは
`--remote` を付けず、通常のコールバック方式をそのまま使う。判定順は次のとおり。

| 順 | 条件 | 使うコマンド |
| --- | --- | --- |
| 1 | portfwd 逆チャネルが**生きている**（`LC_PORTFWD_HOST` あり かつ 逆チャネルのソケット越しの `GET /health` が `{"service":"portfwd",…}` を返す） | `aws login`（`$BROWSER=portfwd-open` がローカルのブラウザを開く） |
| 2 | `$BROWSER` が空でなく `portfwd-open` 以外（VSCode Remote 等） | `aws login`（`$BROWSER` ヘルパ + 自動ポートフォワードで完結） |
| 3 | それ以外の SSH セッション | `aws login --remote` |
| 4 | 非 SSH | `aws login` |

- 1 の判定に connect ではなく `GET /health` を使うのは、逆チャネルのソケットを
  **SSH 先の sshd が**持つため。ローカルの daemon が死んでいても connect は成功してしまい、
  実際には `portfwd-open` が空応答で落ちて認証が完結しない。
  仕組みは [portfwd-cheatsheet.md](portfwd-cheatsheet.md) を参照。
- 1 の `/health` の待ち時間は `portfwd-open` の POST と同じ **5 秒**。ローカルの daemon は常駐
  サービスの起動直後などに応答へ数秒かかることがあり、短いと生きている逆チャネルを取り逃して
  `--remote` へ落ちる。
- **フォールバックした理由は `/dev/tty` へ出る**ので、`aws-switch` 経由でも見える:

  ```
  aws-login: portfwd 逆チャネルが使えません: /run/user/1002/portfwd.sock が空応答です。listen はして
  いるのでローカルの portfwd daemon が落ちています。aws login --remote へフォールバックします。
  ```

  接続不可 / 空応答 / 無応答 / 別サービスの応答 を区別して出すので、
  [portfwd-cheatsheet.md](portfwd-cheatsheet.md) の「`aws login` が `--remote` に落ちる」の
  切り分けをやり直さずに済む（非 SSH のローカル実行では逆チャネルを使わないのが正常なので出さない）。
- 2 で `portfwd-open` を除外するのは、`.zshenv` が `LC_PORTFWD_HOST` の存在だけで `$BROWSER` を
  `portfwd-open` に向けるため。逆チャネルが死んでいる場合はここを素通りして 3 の `--remote` へ
  落とす。あわせて、VSCode の `$BROWSER` ヘルパが出す Node の `DEP0169` 警告は
  `NODE_OPTIONS=--no-deprecation` でこの分岐に限り抑止する。

### aws-auth-ensure

```sh
aws-auth-ensure cdx-pre-dev            # 未認証ならその場でログインする
aws-auth-ensure cdx-pre-dev "Bedrock"  # 第 2 引数はメッセージに出す用途ラベル
```

AWS CLI/SDK は認証情報が要るまで `credential_process`（= `aws-login`）を呼ばない。そのため
**未認証のまま TUI アプリを起動すると、画面が立ったあとでログイン URL が `/dev/tty` へ割り込み、
表示が崩れる**。起動前にここを通し、まだきれいな端末でログインを済ませておく。

- `~/.env` は書き換えない。「いま選ばれているプロファイルを認証するだけ」で、選択そのものを
  変えたいときは `aws-switch` を使う。
- 判定は `aws-login` と同じ順序（認証情報キャッシュに余裕があれば認証済み → 無ければ
  `<profile>-signin` で `sts get-caller-identity`）。認証済みならキャッシュ読みだけで済み、
  `aws` CLI も起動しない。
- 未認証のときの動きは端末の有無で変わる。

  | 状況 | 動き |
  | --- | --- |
  | 端末あり | どのプロファイルが何用で未認証かを出してから `aws-login` を実行 |
  | 端末なし（VS Code 拡張ホスト / agmsg の spawn）または `AWS_LOGIN_NO_INTERACTIVE=1` | 打つべき `aws-login <profile>` を案内して終了コード 1 |

- 終了コードは `0` = 認証済み / `1` = 未認証のまま / `2` = 使い方の誤り。呼び出し側は、
  そのプロファイルが無いと動かないなら `1` で止め、無くても縮退運転できるなら警告にとどめる。
- `aws` が PATH に無ければ何も判定せず素通しする（呼び出し元の起動を巻き添えにしない）。

いま通しているのは Bedrock の起動経路（[zsh-cheatsheet.md](zsh-cheatsheet.md#bedrock-起動で使う-aws-プロファイル)）。
`claude-bedrock-wrapper` と `codex-bedrock` は Bedrock 用プロファイルが未認証ならアプリを起動しない。
`codex-bedrock-spawn` はペインを作る前に通す（spawn 先の codex は `codex-bedrock` を通らないため）。

### 走行中に認証が切れたとき

起動前チェックだけでは、**アプリが走っている最中に期限が切れたとき**を取りこぼす。子プロセスから
`credential_process` が呼ばれ、結局 TUI の中に URL が描かれてしまう。herdr は再接続しても
アプリを起動し直さないので、起動前チェックにも二度と当たらない。

そこで TUI アプリを起動する側は `AWS_LOGIN_NO_INTERACTIVE=1` を export する。これが立っている
`aws-login` はその場でログインせず、**認証を人へ渡す 2 つの道**を取る。

| 何が起きるか | どこで見えるか |
| --- | --- |
| herdr セッション内なら、`AWS login: <profile>` というタブを開いて `aws-auth-ensure` を走らせ、そこへフォーカスを移す。あわせて herdr の通知を出す | herdr のタブ |
| `~/.aws/.aws-login-<profile>.expired` を置く | Claude Code の statusLine が `⚠ AWS 未認証: <profile>` と出す（statusLine は Claude Code にしか無いので、codex で気づく手掛かりはタブだけ） |

呼び出し元には待たせず失敗を返す。MCP の接続タイムアウトは 30 秒しかなく、人の認証を待って
ブロックする方が体験が悪いため。**認証が通れば次の呼び出しで復帰する**（`credential_process` の
失敗は botocore に負のキャッシュとして残らない）。

開いたタブは herdr サーバが起こすので `AWS_LOGIN_NO_INTERACTIVE` を継承せず、ふつうの端末として
上のログイン分岐（portfwd 逆チャネル / `$BROWSER` / `--remote`）がそのまま働く。**どの方式で
ログインするかを新しく判断しなくて済むのが、タブへ委譲する一番の利点。**

`credential_process` は 1 回の署名で何度も呼ばれるので、タブが湧かないよう抑えてある。

- `~/.aws/.aws-login-<profile>.handoff` に `<pane_id> <epoch>` を残し、そのペインがまだ開いて
  いれば新しく開かない
- ペインが閉じていても 60 秒は開き直さない（ユーザが閉じたのに湧き続けるのを防ぐ）
- 同時呼び出しは `flock` で 1 つに絞る

`.expired` は認証が通った時点で `aws-login` / `aws-auth-ensure` が消す。別経路（手打ちの
`aws login` など）で入り直して取り残された場合は、statusLine が creds キャッシュの期限を見て
自分で消す（[claude-compact-cheatsheet.md](claude-compact-cheatsheet.md#statusline-の表示)）。

`AWS_LOGIN_NO_INTERACTIVE` が唯一のゲートなので、**herdr のペインで普通に `aws s3 ls` を叩いて
期限切れになった場合は今までどおりその場でログインする**。タブは湧かない。

期限切れではなく**別タブで `aws-logout` した**ときも同じ経路に乗る
（[走行中のアプリを置いてログアウトしたとき](#走行中のアプリを置いてログアウトしたとき)）。

### aws-logout

```sh
aws-logout my-profile   # 特定プロファイルからログアウト
aws-logout              # 環境変数 AWS_PROFILE のプロファイルからログアウト
aws-logout --all        # すべての -signin プロファイルを掃除
```

破棄するものは 4 つ。

| 対象 | 効き方 |
| --- | --- |
| `.env` の `AWS_PROFILE` 行 | 次のプロンプト以降はプロファイル無指定（既定）に戻る |
| ログインセッション（`aws logout`） | トークンそのものが失効する |
| `~/.aws/.aws-login-<profile>.creds.json` | [認証情報キャッシュ](#aws-login-の認証情報キャッシュ)。消さないと期限まで無効な creds を返し続ける |
| `~/.aws/config` の `[profile <name>-signin]` | セクションごと削除（`--all` なら `-signin` 全部） |

ベースプロファイル `[profile <name>]` は残る。`-signin` も次の `aws-login` が作り直すので、
手当ては要らない。

#### 走行中のアプリを置いてログアウトしたとき

`aws-logout` が触るのはファイルだけで、**走っているプロセスの環境変数は書き換わらない**。
`claude-bedrock-wrapper` 経由の Claude Code なら `AWS_PROFILE`（Bedrock 用）はプロセス内に残るため、
打った瞬間には何も起きず、**次に認証情報を更新しようとした時点で失敗する**（認証情報の寿命は
約 15 分なので、それが猶予の上限）。そこから先は
[走行中に認証が切れたとき](#走行中に認証が切れたとき)と同じ経路に乗る。

- Bedrock 呼び出しが認証エラーになる。`AWS_LOGIN_NO_INTERACTIVE=1` が効いているので、
  TUI の中にログイン URL は描かれない
- `AWS login: <profile>` タブが開き、statusLine に `⚠ AWS 未認証: <profile>` が出る
- そのタブでログインし直せば、**Claude Code を起動し直さずに**次の呼び出しから復帰する

ただし `~/.env` の行は戻らない。走っているプロセスは自分の環境変数を持っているので影響を
受けないが、この後に起動するシェルはプロファイル無指定（既定）になる。作業を続けるなら
タブでのログインで終わらせず、`aws-switch <profile>` まで打って `~/.env` を戻しておく。

## ~/.aws/config の構成と制約

スクリプトは `~/.aws/config` の構造に強く依存している。プロファイルは大きく2種類:

### ベースプロファイル `[profile <name>]`（手元で管理する側）

| 属性 | 必須 | 説明 |
| --- | --- | --- |
| `credential_process` | **必須** | `aws-login <name>` を指定。これが無いと `aws login` 認証が走らない。`<name>` はプロファイル名と一致させる（`aws-login` が `<name>-signin` を組み立てる起点になる） |
| `region` | 推奨 | 例: `ap-northeast-1`。未設定なら `aws-login` が東京を補完する |
| `assume_role_name` | 任意 | **AWS CLI 標準ではない独自属性**。値は ARN ではなくロール名だけ。設定すると `aws-switch` が自動で Assume Role Mode に入り、ブラウザで選ぶべきロール名を表示する |

```ini
[profile my-profile]
region = ap-northeast-1
credential_process = aws-login my-profile
assume_role_name = Admin   # 任意。ARN ではなくロール名
```

制約・注意:

- **`credential_process` の値はプロファイル名と一致させる。** `aws-login <name>` の `<name>` が
  `<name>-signin` セッションプロファイルのキーになるため、ズレるとセッションが混線する。
- **ベースプロファイル名を `-signin` で終わらせない。** `-signin` はセッション用の予約サフィックスで、
  peco 候補からも除外される（`aws-switch` / `aws configure list-profiles | grep -v signin`）。
- `assume_role_name` を設定しても **このスクリプトが直接 assume するわけではない**。
  分岐に関わらず実行されるのは同じ `aws-login <name>` で、ロール名は「ブラウザでどのロールを選ぶか」の
  リマインダーとして表示されるだけ。実際のロール選択は `aws login` のブラウザ認証側で行う。
- **ARN ではなくロール名を持つ**のは、ブラウザのロール選択画面がロール名で選ばせるため。
  account id を含む ARN を書いても画面のどれを選ぶかは分からず、config に account id が残るだけ。
  （以前は `assume_role_arn` に ARN を書く方式だった。`~/.aws/config` に古い属性名が残っていると
  Assume Role Mode に入らないので、`assume_role_name` へ書き換える）
- `assume_role_name` は標準キーではないため `aws` CLI からは無視される。手書きで `~/.aws/config`
  に足す。

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
