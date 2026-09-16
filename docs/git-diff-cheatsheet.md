# git 差分レビュー チートシート

git の差分を読む・レビューする・コミットまで持っていくための 2 つのツール。**用途で使い分ける**。

| ツール | 出す先 | 起動キー | 向いている場面 |
| --- | --- | --- | --- |
| [difit](https://github.com/yoshiko-pg/difit) | 手元 PC のブラウザ | `<prefix> d` | エージェントが書いた差分に行コメントを付けながらレビューする |
| [gitui](https://github.com/gitui-org/gitui) | 端末内の TUI | `<prefix> shift+d` | サッと差分を見る / hunk 単位でステージしてコミットする |

> 起動キーはどちらも herdr の popup（[herdr チートシート](herdr-cheatsheet.md#カスタムコマンドpopup)）。
> **よく使う方（ブラウザ）を打ちやすい `d` に置いている**（`m` = mo / `shift+m` = glow と同じ並べ方）。
> herdr 既定では `shift+d` が「ワークスペースを閉じる」なので、そちらは `shift+q` へ退避させている。

- **difit の導入**: npm グローバル（`.chezmoiscripts/run_onchange_after_30-node-default.sh.tmpl` の
  `NPM_GLOBALS`）。aqua に無いため npm 配布を使う。`chezmoi apply` で入る（node は fnm の
  LTS で、difit は node 21 以上を要求する）
- **gitui の導入**: aqua で管理（`dot_config/aquaproj-aqua/aqua.yaml` の `gitui-org/gitui`）
- **設定**: difit に設定ファイルは無く、挙動は CLI オプションだけで決まる。gitui はテーマだけ
  配っている（`dot_config/gitui/theme.ron`。詳細は [gitui](#gitui端末内-tui) の節）

---

## difit（手元 PC のブラウザ）

[difit](https://github.com/yoshiko-pg/difit) は git の差分を **GitHub の PR 画面のような UI** で読む
ローカル専用のレビューツール。行にコメントを付け、`Copy Prompt` でその文脈ごとエージェントへ
渡せるのが gitui との違い。サーバは difit を動かしているホストに立ち、画面はブラウザへ出る
（SSH 先で使うときは portfwd が中継して**手元 PC のブラウザ**が開く）。

**コメントは動いているサーバが持つ**。ブラウザの `Copy Prompt` / `Copy All Prompt` で
エージェントへ渡す形が本筋。

### `<prefix> d`（herdr の popup）

popup で動くのは `~/.local/bin/herdr-difit`（chezmoi ソース = `dot_local/bin/executable_herdr-difit`）。
`fzf` で見たい差分を選ぶだけの橋渡しで、選び終わると popup は閉じ、表示は手元 PC のブラウザ側で続く。
popup は**フォーカス中ペインの作業ディレクトリ**で開くので、エージェントを動かしているリポジトリの
まま一覧が出る（git リポジトリの外だと理由を出して止まる）。

#### 選べるもの

一覧は「未コミットの 3 通り」→「`git log`（新しい順）」の並び。1 列目がそのまま difit へ渡る引数。

| 選ぶもの | difit に渡る引数 | 中身 |
| --- | --- | --- |
| `.` | `.` | 未コミット全部（staged + working） |
| `staged` | `staged` | ステージ済みだけ |
| `working` | `working` | 未ステージだけ |
| コミット 1 つ | `<sha>` | そのコミットが入れた差分 |
| コミット 2 つ（`Tab`） | `<新しい方> <古い方>` | その 2 コミット間の差分 |

#### キー（fzf の中で押す）

| キー | 動作 |
| --- | --- |
| `Enter` | 決定（カーソル位置、または `Tab` で選んだもの） |
| `Tab` | 選択のトグル。**コミットを 2 つ選ぶと範囲比較**になる |
| `Ctrl-R` | 差分を選ばずに、**今動いている difit のタブを開き直す** |
| `Esc` | 何もせず popup を閉じる |

- 一覧は新しい順なので、`Tab` で 2 つ選ぶと**上に選んだ方が比較の起点**になる。
- **未コミットの 3 つは範囲比較に混ぜられない**（`.` と コミットの 2 つ選択はエラーで止まる）。
- 3 つ以上選ぶとエラーで止まる。difit が受け取れるのは最大 2 つまで。
- プレビューは `git diff` / `git show`（`--stat --patch`）。

#### 未追跡ファイル

git の既定では `git add` していないファイルは差分に出ない。エージェントが作った新規ファイルを
読み落とすのが痛いので、**`.` と `working` を選んだときだけ `--include-untracked` を付けている**
（コミットを選んだときは意味が無いので付けない）。

#### 選ぶたびに前のサーバは落ちる

difit は `mo` と違い**呼ぶたびに別のサーバを立てる**。放っておくと選んだ回数ぶん node の
プロセスが残るので、`herdr-difit` は起動した pid と URL を
`$XDG_RUNTIME_DIR/herdr-difit.state`（無ければ `$TMPDIR`。macOS はこちら）に残し、
**次に選んだときに前のものを落とす**。
結果、ユーザごとに difit は常に 1 つ・同じポートになる。

- 前のサーバに溜めたものは引き継がれない。**別の差分へ移る前に、必要なら
  ブラウザで `Copy All Prompt`** しておく。
- state の pid が別プロセスに使い回されていた場合に備え、`ps -p <pid> -o args=` が difit か
  確かめてから `kill` する（`/proc` の無い macOS でも同じ判定になる）。
- 2 つの差分を同時に開きたいときは popup ではなく[直接叩く](#直接叩く)（2 つ目は difit が
  ポートを繰り上げる。狙ったポートにしたいなら `--port` を明示する）。


### 直接叩く

`~/.local/bin/difit` はラッパー。実体（npm グローバルの difit）を**ユーザごとのポートで**起動する。

```sh
difit                       # HEAD（既定）
difit .                     # 未コミット全部
difit staged                # ステージ済みだけ
difit HEAD~3                # 3 つ前のコミット
difit feature main          # feature と main の差分
difit feature main --merge-base   # 分岐点からの差分
difit --pr https://github.com/owner/repo/pull/123   # PR（GitHub Enterprise も可。`gh` 経由）
```

| オプション | 既定 | 意味 |
| --- | --- | --- |
| `--port <port>` | `4966`（ラッパーが `difit-port` の値を渡す） | 希望ポート。埋まっていると繰り上がる |
| `--host <host>` | `localhost`（ラッパーが `127.0.0.1` を渡す） | bind アドレス。`localhost` は Node が OS の名前解決順で bind するため、`::1` が先に返るホストでは IPv6 loopback だけになる |
| `--no-open` | open する | ブラウザを開かない |
| `--background` | off | サーバを切り離し、`{"port":..,"url":..,"pid":..}` を出して終わる |
| `--keep-alive` | off | ブラウザが切れてもサーバを残す |
| `--include-untracked` | off | 未追跡ファイルも差分に含める |
| `--merge-base` | off | 比較の基点を `git merge-base` で解決する |
| `--context <lines>` | git の既定（3） | 変更行の周りに出す行数 |
| `--clean` | off | 既存のコメントを消して始める |
| `--comment <json>` | — | コメントを流し込んで始める（繰り返し可） |
| `--pr <url>` | — | PR を対象にする（差分の取得は `gh` を呼ぶ） |

動いているサーバのコメントは CLI からも触れる: `difit comment add` / `get` /
`resolve <threadId...>`（対象は `--port` で指定。JSON の形は `difit comment add --help`）。

> **`--port` を 2 回渡してはいけない。** 後勝ちにならず、エラーも出さずに**既定の 4966 に落ちる**。
> ラッパーは呼び出し側が `--port` を書いているときは自分の分を足さないので、
> `difit --port 5000` と明示すればそちらが使われる。`--host` も同じ扱いで、呼び出し側が
> 書いていないときだけラッパーが `--host 127.0.0.1` を足す（理由は[落とし穴](#落とし穴)）。


### ポートの決め方（`difit-port`）

`~/.local/bin/difit-port` が 1 行で返す。ラッパーがこの値を `--port` に渡す。

| 優先順 | 値 |
| --- | --- |
| 1 | `$DIFIT_PORT`（`~/.env` に書けば direnv が読む） |
| 2 | `4966 + (uid - 1000)`（uid が 1000..1499 のとき） |
| 3 | `4966 + (uid % 500)`（範囲外の uid） |

difit の既定は 4966 で、`mo` の帯（6275..6774）と重ならない 4966..5465 に収まる。
複数ユーザがいるホストで全員が 4966 から始めると、difit が繰り上げるたびに自分のポートが
変わって「どれが自分のものか」が分からなくなるため、uid で固定する
（[Markdown プレビュー チートシート](markdown-preview-cheatsheet.md) の `mo-port` と同じ考え方。
ただし difit は他人のサーバへ**ぶら下がることはない** — 必ず自分のサーバを立てる）。


### なぜ手元 PC のブラウザで開くのか

`herdr-difit` は `--no-open` で difit を起動し、返ってきた JSON の `url` を自分で
`$BROWSER` へ渡す。portfwd 対象セッションでは `$BROWSER=~/.local/bin/portfwd-open` になっている
ため、URL がそのまま手元 PC へ渡る（[portfwd チートシート](portfwd-cheatsheet.md)）。

```
herdr-difit（<prefix> d）
  └─ difit --background --no-open …   → {"url":"http://127.0.0.1:4968",…}
       └─ $BROWSER=portfwd-open → 手元 PC の daemon
            1. http://127.0.0.1:4968/ を「ローカルのページ」と判定
            2. 手元の 127.0.0.1:4968 を listen し、SOCKS 経由で SSH 先の 4968 へ中継
            3. 手元 PC の既定ブラウザで開く
```

difit 自身に開かせず `--no-open` にしているのは、**実際に listen したポートを URL として
受け取ってから開きたい**ため。希望ポートが埋まっていると difit は繰り上げるので、
`difit-port` が決めた値とずれることがあり、JSON の `url` が唯一の正解になる。


### 落とし穴

- **popup で difit を直に動かすとペインが触れなくなる**。difit は前面に留まってサーバを持つので、
  herdr のセッションモーダルな popup を占有してしまう。`herdr-difit` が `--background` で
  切り離しているのはこのため。
- **portfwd 非対象のセッションでは開かない**。`LC_PORTFWD_HOST` が来ていないと `$BROWSER` が
  設定されず、difit は立つのに手元 PC へ URL が渡らない。`herdr-difit` はこのとき警告と URL を
  出して `[Enter]` で止まる。
- **popup は herdr サーバ起動時の環境を継承する**。portfwd 非対象のセッションで herdr を
  起動していると `$BROWSER` が渡らないので、portfwd 対象のセッションで `herdr server stop` →
  `herdr` と起動し直す（`herdr server reload-config` では環境は入れ替わらない）。
- **`localhost` に bind すると portfwd 経由で `connection refused` になるホストがある**。difit の
  `--host` 既定は `localhost` で、Node はこれを OS の名前解決の順で bind する。Ubuntu 等
  `getent ahosts localhost` が `::1` を先頭に返すホストでは `[::1]:<port>` にしか listen せず、
  portfwd の page リレー（SSH 先の `127.0.0.1:<port>` へ SOCKS CONNECT）が拒否される。手元の
  ブラウザは開くのに `localhost:<port>` が refused、手元の portfwd ログに
  `SOCKS CONNECT 失敗` → `転送先が listen していないため終了` と残るのがこの症状。
  ラッパーが `--host 127.0.0.1` を足して IPv4 loopback に固定しているので、**素の difit
  （npm global の実体）を直接呼ばない**。呼ぶなら `--host 127.0.0.1` を明示する。
- **同じホストの他のローカルユーザは、ポートを知っていれば接続できる**（difit に認証は無い）。
  `--host` はラッパーが渡す `127.0.0.1` のままにし、複数ユーザがいるホストでは見せたくない差分を
  開かない。
- **`.` / `working` を開いたまま作業を進めたら、ブラウザを再読み込みする**。サーバは要求のたびに
  git を読み直すので、再読み込みすれば最新のワークツリーの差分になる（`<prefix> d` から
  選び直す必要は無い）。
- **`--pr` は `gh` を呼ぶ**（無いと `spawnSync gh ENOENT`）。そのため GitHub Enterprise の
  PR URL でも差分が出る（その host に対して `gh` の認証が済んでいること）。

---

## gitui（端末内 TUI）

ターミナルの git TUI [gitui](https://github.com/gitui-org/gitui)。端末内でサッと差分を見る /
hunk 単位でステージしてコミットまで持っていく側。行コメント付きのレビューは difit に任せる。

- **テーマ**: `~/.config/gitui/theme.ron`（chezmoi ソース = `dot_config/gitui/theme.ron`）
  - 部分指定でデフォルトにマージされる。指定しないキーは gitui 既定色のまま。
  - 下部コマンドバーを端末背景に透過（`cmdbar_bg: Reset`）して Catppuccin Mocha で
    水色帯 + 白文字の低コントラストを解消している。

> キー記法: 下部コマンドバーの記号 `⎋` = **Esc**、`⏎` = **Enter**、`^X` = **Ctrl+X**。
> Shift 併用キーは表では `Shift+X` と記す。

### 最重要: コミットメッセージ画面から抜ける／確定する

コミットエディタ（`c` で開く）で迷いやすいポイント。下欄の記号の意味を覚える。

| キー（下欄の表示） | 動作 |
| --- | --- |
| `Esc`（`⎋ close`） | **エディタを閉じる（キャンセル）**。記号 `⎋` が Esc。 |
| `Ctrl+D`（`^D commit`） | **コミットを確定する**。 |
| `Enter`（`⏎`） | メッセージ内で**改行**（確定ではない）。 |

> 落とし穴: Enter は改行なので、押しても確定しない。**確定は Ctrl+D、中断は Esc**。
> 「閉じられない」と感じたら Esc（`⎋`）。


### push が bad credentials で失敗する

gitui は **libgit2 経由で SSH 認証**し、SSH 鍵を **ssh-agent 経由でしか使えない**
（`~/.ssh/id_ed25519` などの鍵ファイルを直読みしない。git CLI は直読みするので CLI では push できる）。
そのため **ssh-agent が無い / 鍵が未登録**だと push が `push failed, bad credentials` になる。

- 対処は zsh 側で自動化済み: 1Password が無いホストでは対話シェル起動時に通常の
  `ssh-agent` を常駐させ既定鍵を `ssh-add` する（`dot_config/zsh/rc.d/25-ssh-agent.zsh`）。
- 反映するには **新しいシェルを開く**（または `exec zsh`）→ その中から gitui を起動する。
- 確認: `ssh-add -l` に鍵が出ていれば OK。出ていなければ `eval "$(ssh-agent -s)" && ssh-add` で手動登録。

> 詳細は [zsh チートシート](zsh-cheatsheet.md#ssh-エージェント25-ssh-agentzsh)。


### タブ切り替え

| キー | タブ |
| --- | --- |
| `1` | Status（作業ツリー / ステージ） |
| `2` | Log（コミット履歴） |
| `3` | Files（ツリー） |
| `4` | Stashing（stash 作成） |
| `5` | Stashes（stash 一覧） |
| `Tab` / `Shift+Tab` | 次 / 前のタブへトグル |


### 共通

| キー | 動作 |
| --- | --- |
| `↑ ↓ ← →` | 移動 / パネル間フォーカス移動 |
| `Enter` | 選択項目を開く / ステージ・アンステージ |
| `Esc`（`⎋`） | popup / 画面を閉じる |
| `H` | ヘルプ（全キーバインド一覧） |
| `Q` | gitui を終了 |
| `Ctrl+C` | 強制終了 |
| `F5` | 表示を更新（refresh） |


### Status タブ（ステージング・コミット）

| キー | 動作 |
| --- | --- |
| `Enter` | 選択ファイルをステージ / アンステージ |
| `A` | すべてステージ |
| `Shift+D` | 変更を破棄（reset item） |
| `S` | 差分内の選択行だけステージ（hunk/line stage） |
| `D` | 差分内の選択行だけ破棄（reset lines） |
| `C` | コミットメッセージエディタを開く |
| `Ctrl+A` | 直前コミットを amend |
| `E` | 選択ファイルを `$EDITOR` で開く |

> `S` / `D` は diff パネルにフォーカスがある時の行単位操作。ファイル一覧では
> `Enter` がファイル単位のステージ／アンステージ。


### Log タブ（履歴）

| キー | 動作 |
| --- | --- |
| `Enter` | コミット詳細 / 差分を開く |
| `Shift+S` | そのコミットを checkout |
| `Shift+R` | そのコミットへ reset |
| `Shift+B` | blame（Files 側で選択したファイル） |
| `Y` | コミットハッシュをコピー |


### ブランチ・リモート

| キー | 動作 |
| --- | --- |
| `B` | ブランチ一覧を開く（選択・切替） |
| `C` | 新規ブランチ作成（ブランチ一覧内） |
| `Shift+D` | ブランチ削除（ブランチ一覧内） |
| `P` | push |
| `F` | pull |
| `Shift+F` | fetch |

> 同じ文字でも「どのパネル・popup にいるか」で意味が変わる（例: `C` は Status では
> コミット、ブランチ一覧では新規作成、`Shift+D` は Status では破棄、ブランチ一覧では削除）。
> 迷ったら常に**下部コマンドバーの表示**が現在の文脈での有効キー。


### Stashing / Stashes

| キー | 動作 |
| --- | --- |
| `S` | 現在の変更を stash に保存（Stashing タブ） |
| `Enter` / `→` | stash を開く（Stashes タブ） |
| `A` | stash を適用（apply） |
| `Shift+D` | stash を破棄（drop） |


### 検索・その他

| キー | 動作 |
| --- | --- |
| `F` | ファイル検索（Files / Status のファイル絞り込み） |
| `Ctrl+F` | commit hook（verify）のトグル |
| `Y` | 選択内容をコピー |

> キーバインドは `~/.config/gitui/key_bindings.ron` で上書き可能（本 dotfiles では未設定＝デフォルト）。
> 記号は `theme.ron` ではなく key config 側の設定。現在の一覧は gitui 内で `H`（ヘルプ）でも確認できる。


### 変更履歴・経緯

- 下部コマンドバーの可読性対策として `theme.ron` を追加し、`cmdbar_bg` /
  `cmdbar_extra_lines_bg` を `Reset`（端末背景に透過）、`command_fg` を `White` に設定。
  背景に Catppuccin Mocha の ANSI Blue（水色 `#89b4fa`）が入ると白文字と低コントラスト
  になり見にくかったため。ほかの色は gitui 既定にマージされる。
