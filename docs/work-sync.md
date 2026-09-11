# work 用 dotfiles との同期

この dotfiles には対になる **work 用 dotfiles**（`cloudsa-dotfiles`。work 用の GitHub Enterprise にある）が
ある。同じ役割のスクリプトを両方が持っていて、片方で直した改良をもう一方へ運ぶ。ここはその
運び方と、揃えると決めた規約をまとめたもの。

> このリポジトリは公開なので、**work 側の組織名・ホスト名・サーバ上のパス・ユーザ名は書かない**。
> 以下では次の 2 つを使う。実際の値は手元の `~/.ssh/config` と `ghq` のパスから補う。
>
> - `$WORK` … work 用 dotfiles の**手元の読み取り用クローン**（`ghq` 管理のパス）
> - `$RWORK` … **サーバ上の実体**のパス（`cloudsa` のホームの下）
>
> ```sh
> WORK=$(ghq list -p | grep cloudsa-dotfiles)
> RWORK=$(ssh cloudsa 'ls -d ~/Project/src/*/*/cloudsa-dotfiles')
> ```

## work 環境の識別子の置き場

サーバのインスタンス ID・ユーザ名・uid・AWS プロファイル・GitHub Enterprise のホスト名は、
**ソースに書かず** `~/.config/chezmoi/chezmoi.toml` の `[data.work]` に置く（`chezmoi init` が
`promptStringOnce` で聞いて生成する。一度答えれば再実行しても聞かれない）。

| キー | 使うところ |
| --- | --- |
| `user` / `instance` / `uid` | `private_dot_ssh/private_config.tmpl` の `cloudsa` ブロックと鍵の参照 |
| `profile` | 同上の `ProxyCommand`（ssh の踏み台で使う AWS プロファイル）と `dot_aws/create_config.tmpl` |
| `bedrock` | `dot_aws/create_config.tmpl` と `create_dot_env.tmpl`（Bedrock の接続先プロファイル） |
| `ghe` | `private_dot_ssh/private_config.tmpl` の GitHub Enterprise ブロック |

値が無いマシンでは、これらを使う Host 定義とプロファイル定義をまるごと出力しない。

## リポジトリの場所

| どれ | 場所 | 用途 |
| --- | --- | --- |
| このリポジトリ | `~/.local/share/chezmoi` | 個人用。公開リポジトリ |
| work（実体） | `cloudsa:$RWORK` | 作業も commit もここでする |
| work（手元のクローン） | `$WORK` | 比較用。`git pull` で GHE から引くだけ |

`cloudsa` への SSH は `ssm-proxy.sh` 経由なので、先に AWS の認証が要る
（[aws-cheatsheet.md](aws-cheatsheet.md#aws-auth-ensure)）。使うプロファイルは `~/.ssh/config` の
`ProxyCommand` の引数にある。

```sh
aws-auth-ensure <ProxyCommand のプロファイル> "ssh cloudsa"
ssh cloudsa
```

## 揃えると決めたこと

| 項目 | どちらに揃えるか | 理由 |
| --- | --- | --- |
| OS 依存の書き方（`ps` / `lsof` / `date` / bash 3.2） | **この dotfiles** | mac と Linux の両方で動く superset。work（Linux）でもそのまま動く |
| 整形 | **`shfmt` の既定（`-i 0` = タブ）** | フラグ無しで回せる。詳細は [shell-lint-cheatsheet.md](shell-lint-cheatsheet.md#このリポジトリの整形規約) |
| Bedrock 用 AWS プロファイル | **既定を持たず `~/.env` から解決** | 公開リポジトリにアカウント名を焼かない。意図しないアカウントを触らない |
| 環境固有の機能 | **揃えない** | work の AWS MCP / Grafana / EKS、こちらの superpowers / ghostty / 個人ツールなど。共有コアの外に置く |
| Claude Code の設定の置き場 | **揃えない** | work は policy 層（`managed-settings.json`）へまとめて置く。こちらの policy 層は sudo が要るうえ「忘れても破れない禁止事項」の場所なので、機能設定（`awsAuthRefresh` など）は `private_dot_claude/modify_settings.json.tmpl` のユーザ層に置く |

**どちらの向きにも持ち込まないもの**: work へは個人リポジトリの名前や URL を、こちらへは
組織名・サーバのパス・アカウント名を書かない。取り込むときはコード本体だけを取り、
コメントの固有名詞は落とす。

## work → こちらへ取り込む

work 側の変更は GHE に push されているので、手元のクローンを更新してから読む。

```sh
git -C "$WORK" pull
git -C "$WORK" log --oneline -10
git -C "$WORK" show <commit>
```

まだ push されていないなら、サーバで直接見る:

```sh
ssh cloudsa "cd $RWORK && git log --oneline -5"
```

取り込むときは**そのまま貼らない**。この repo 側の携帯実装（`ps` / BSD `date` 互換）へ寄せ、
公開リポジトリに置けない固有名詞を落としたうえで移植する。移植したら mac で実際に動かし、
`shellcheck` と `shfmt -l` を通してからコミットする。

## こちらから work へ配る

work は `scp` で直接置き換える（実体はサーバ側）。

```sh
scp dot_local/bin/executable_aws-login "cloudsa:$RWORK/dot_local/bin/executable_aws-login"

ssh cloudsa "export PATH=\$HOME/.local/share/aquaproj-aqua/bin:\$PATH; cd $RWORK \
  && git diff --name-only | xargs shellcheck -f gcc \
  && git diff --name-only | xargs shfmt -l \
  && git status --porcelain"
```

コミットメッセージは長くなるのでファイルにして渡す（`scp msg.txt cloudsa:/tmp/` →
`git commit -F /tmp/msg.txt`）。**push は自分でする**。

## 差分の測り方

work のツリーを手元へ取ってから、コメントと空行を除いた行数で並べる。整形は揃えてあるので、
ここに出る行がそのまま「実装の違い」になる。

```sh
SP=$(mktemp -d)
scp -q -r "cloudsa:$RWORK/dot_local/bin" "$SP/work-bin"

for f in "$SP"/work-bin/*; do
  n=$(basename "$f")
  [ -f "dot_local/bin/$n" ] || continue
  c=$(diff -u "$f" "dot_local/bin/$n" | grep '^[+-][^+-]' | sed 's/^[+-][[:space:]]*//' | grep -vc '^\(#\|$\)')
  [ "$c" -gt 0 ] && printf '%4s  %s\n' "$c" "$n"
done | sort -rn
```

`0` 行のファイルは byte 単位で同じか、コメントだけの差。片側にしか無いファイルは
`diff -rq --exclude=.git` の `Only in` で見る。

**意図して残している差分**（次に測るときに取り込み漏れと取り違えないように）。

| ファイル | 差分の中身 |
| --- | --- |
| `executable_herdr-difit` | state file の pid が difit か確かめる実装。work は `/proc/<pid>/cmdline`、こちらは `ps -p <pid> -o args=`（mac で同じ判定になる携帯実装） |
| `executable_claude-bedrock` | **こちらが新しい。** SSH 接続先での引数なし起動に `--remote-control` を足す判定と、`command -v claude` での実体解決を持つ。work へ配る側 |
| `executable_codex-bedrock-spawn` | **こちらが新しい。** 起動先を `monitor` にする処理を `no-codex-bedrock` マーカーの判定より前に置き、素の `spawn.sh` へ委譲する経路でも効くようにしている（work は Bedrock 経路の 4 番目）。work へ配る側 |
| `.chezmoiscripts/run_onchange_after_45-agmsg-reset.sh.tmpl` | **こちらには無い。** 共有ホストの全ユーザで agmsg の状態（チーム登録・履歴・一時 home）を一掃するための管理スクリプト。こちらは単一ユーザで登録も既にリポジトリごとに 1 チームなので持ち込まない（`docs/admin-runbook.md` も同様） |
| `executable_aws-switch` / `executable_aws-logout` | 関連ドキュメントの参照先（work は `aws-add-profile.md` と `.chezmoitemplates/aws-config-managed.ini`、こちらは `dot_aws/create_config.tmpl`）。work 側にだけ後続行の無いコメントが残っている |
| `executable_aws-auth-ensure` / `executable_claude-bedrock-wrapper` | `awsAuthRefresh` の設定の置き場を指すコメント（上の「揃えると決めたこと」） |
| `private_dot_claude/hooks/executable_pr-refresh-check.sh` | hook の登録場所を指すコメント（work は policy 層、こちらは `modify_settings.json.tmpl`） |

## 経緯

2026-09-10 に、それまで別々に育っていた共有スクリプトを次の 3 段階で揃えた。

1. 両リポジトリを `shfmt` の既定（タブ）へ一括整形（このリポジトリ `8f7c21c`）
2. OS 依存の実装をこのリポジトリの移植版へ統一
3. Bedrock 用プロファイルの既定ハードコードを外し `~/.env` 解決へ（このリポジトリ `ab2a248`）

これで `dot_local/bin` の共有スクリプトはコメントを含めてほぼ同一になり、以後は差分＝実装の
違いだけになる。

同日、揃えたあとに work 側で育っていた分を取り込んだ。

| 取り込んだもの | 中身 |
| --- | --- |
| `aws-login` の委譲と判断ログ | 認証切れの委譲を herdr の popup へ（`aws-auth-handoff` / `herdr-api` / `dot_config/herdr/plugins/aws-login` を新規に持ち込み、`platforms` に `darwin` を足した）。更新の直列化・リトライ・見送り判定と `~/.aws/.aws-login.log` |
| `aws-auth-ensure --wait` | Claude Code の `awsAuthRefresh` から呼ばれる待ちモード。設定はこちらではユーザ層へ置いた |
| difit 一式 | `difit` / `difit-port` / `herdr-difit` と `<prefix> d` / `shift+d` の入れ替え（`close_workspace` は `shift+q` へ退避）。`/proc` 依存を `ps` へ寄せた |
| `tf-cache-prune` | `TF_PLUGIN_CACHE_DIR` の所在を指すコメントの修正（`.zshenv` → `~/.config/shell/env.sh`） |

`mo` / `mo-port` の 371b26a（ポート決定の説明を mac も含む書き方へ）は、こちらの文面へ揃えた
変更だったので取り込むものが無かった。work 側の `eice` / `windows-setup` はこちらに対応する
ファイルが無いので対象外。

2026-09-11 に、翌日分（work の 6c35d82 / b00f450 / de6b11c）を取り込んだ。

| 取り込んだもの | 中身 |
| --- | --- |
| `codex-bedrock-spawn` のチーム解決 | `whoami.sh` が `agent=` / `multiple=` を返すときだけ採用し、`suggest=` / `not_joined=`（未参加）では止める。`suggest=` の `teams=` を拾うと別リポのチームへ join させていた |
| `codex-bedrock-spawn` の配信モード | 起動先が `monitor` でなければ `delivery.sh set monitor codex` してから spawn する（`.codex/hooks.json` は gitignore 済みで worktree に付いてこない）。こちらではマーカー判定より前に置いた（上の表） |
| `codex-bedrock-spawn` の `TMPDIR` | `spawn.sh` へ `TMPDIR=${XDG_RUNTIME_DIR:-~/.cache/agmsg}` を渡す。共有ホストで `${TMPDIR:-/tmp}/agmsg-spawn` が他ユーザの所有になる問題。mac では `$TMPDIR` が元からユーザ専用だが、差分を作らないためそのまま揃えた |
| `codex-bedrock` の `sessions` | 一時 home の `sessions` symlink のリンク先 `~/.codex/sessions` を先に作る（無いと `thread-store internal error: File exists`） |
| `aws-login` のリージョン | 先頭で `AWS_REGION` / `AWS_DEFAULT_REGION` を捨てる。`claude-bedrock-wrapper` の `AWS_REGION=us-east-1` 配下では signin の更新が毎回 `INVALID_REQUEST` で弾かれていた。「更新が一瞬だけ弾かれる」と読んでいた失敗はこれだった（aws-cheatsheet の節を書き換えた） |
| docs / codex-review スキル | 「チームはリポジトリごとに 1 つ」「worktree では新チームを作らない」「フックは worktree ごとに要る」と、未参加時・`mode: off` 時の分岐 |

work の `docs/claude-settings.md` に足された「popup へ来るのはログインセッションが切れたときだけ」は、
こちらでは `docs/herdr-cheatsheet.md` の popup の節に置いた。
