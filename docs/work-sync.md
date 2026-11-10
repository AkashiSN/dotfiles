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
| AI CLI（claude / codex / codegraph）の版 | **マシンで 1 つ（それぞれの `aqua.yaml` のピン）** | 共有ストアの導入で、同じマシンの全ユーザが同じ版を使う。こちらと work は別の repo なので、ピンの版は Renovate の更新タイミングで一時的にずれてよい。Kiro CLI は両方 `registry.yaml` の local 定義（Linux のみ）で、macOS だけこちらが公式インストーラ |
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
| `executable_difit` / `executable_herdr-difit` | **こちらが新しい（2026-09-16）。** ラッパーが `--host` 未指定時に `--host 127.0.0.1` を足す（difit の既定 `localhost` は `::1` が先に返る Linux で IPv6 loopback にしか bind されず、portfwd の中継が refused になる）。work へ配る側。work 側は同じ症状が出るはずなので、配るときは `docs/git-diff-cheatsheet.md` の落とし穴も一緒に運ぶ |
| `executable_codex-spawn` | **こちらが新しい（2026-09-16）。** (1) spawn のあと seat（`run/role-session.<team>__<name>`）を自分で書く。agmsg 1.3.0 の codex スキル本文が `codex-record-session.sh` の引数指定を落とし、codex が引数無しで実行して seat が古いまま残り、bridge が前回のスレッドへ配信していた。(2) Bedrock 経路の env 付きペイン＋`--terminal {cmd}` テンプレートをやめ、両経路とも `spawn.sh` の herdr driver に委譲する。1.3.0 の plain driver は `{cmd}` テンプレートの witness に macOS の tty しか受け付けず、Linux の herdr では失敗するため。Bedrock の `CODEX_HOME` は新設の PATH ラッパーが付ける。work へ配る側。`docs/agmsg-cheatsheet.md` の seat の節と `codex-review` スキルも一緒に運ぶ |
| `dot_local/libexec/codex-dispatch/executable_codex` / `dot_config/shell/env.sh.tmpl` の `_path_add` | **こちらにしか無い（2026-09-16）。** シムと `codex-monitor.sh` が本体として解決する位置に置く PATH ラッパー。マーカーが無ければ `codex-bedrock --print-home` の一時 home を `CODEX_HOME` に載せて本体を exec する。work へ配る側（env.sh の PATH 追加とセット） |
| `executable_codex-appserver-evict` | **こちらが新しい（2026-09-16）。** app-server の cwd を Linux では `/proc/<pid>/cwd` で読む（`lsof` の無いホストで 127 になり、Bedrock 経路の `codex-spawn` が evict で止まっていた）。mac は従来どおり `lsof`。work へ配る側 |
| `executable_herdr-difit` | state file の pid が difit か確かめる実装。work は `/proc/<pid>/cmdline`、こちらは `ps -p <pid> -o args=`（mac で同じ判定になる携帯実装） |
| `.chezmoiscripts/run_onchange_after_45-agmsg-reset.sh.tmpl` | **こちらには無い。** 共有ホストの全ユーザで agmsg の状態（チーム登録・履歴・一時 home）を一掃するための管理スクリプト。こちらは単一ユーザで登録も既にリポジトリごとに 1 チームなので持ち込まない（`docs/admin-runbook.md` も同様） |
| `executable_aws-switch` / `executable_aws-logout` | 関連ドキュメントの参照先（work は `aws-add-profile.md` と `.chezmoitemplates/aws-config-managed.ini`、こちらは `dot_aws/create_config.tmpl`）。work 側にだけ後続行の無いコメントが残っている |
| `executable_aws-auth-ensure` / `executable_claude-bedrock` | `awsAuthRefresh` の設定の置き場を指すコメント（上の「揃えると決めたこと」） |
| `private_dot_claude/hooks/executable_pr-refresh-check.sh` | hook の登録場所を指すコメント（work は policy 層、こちらは `modify_settings.json.tmpl`） |
| `private_dot_claude/hooks/executable_worktree-enter-reminder.sh` | **こちらが新しい（2026-11-12）。** 解いたパスが `git worktree list` に載る worktree と一致したときだけ示し、引用符・`cd`・`||` などで確実に解けない入力は一覧確認へ回す（work 側は、引用符付きのパスや `cd other && git worktree add wt`、`printf` の中の記述で、実在する別のディレクトリへの EnterWorktree を指示する）。work へ配る側。ほかに登録場所を指すコメントの差分がある。こちらの「worktree を作ったらセッションごと移る」の指示は policy の `CLAUDE.md` ではなく `private_dot_claude/modify_CLAUDE.md` に置いた |
| `executable_difit` | 共有側の実体 `/opt/npm-global/current/bin/difit` が在ればそれを使うところは work と同じ。こちらは共有側が揃っていない間（ユーザ単位の fallback）のため、無いときは fnm の `aliases/default` の下を見る。work へ配るときはこの fallback を外してよい |
| `bootstrap/23-shared-npm.sh` | **こちらが新しい（2026-11-10）。** (1) `mv -T` を `swap_symlink` に置き換え（macOS は BSD の `ln -sfhn`）。(2) `readlink -f` を使わず、npm の bin の実体は `pwd -P` で解決する（macOS の `/var` -> `/private/var` を含む）。(3) 組は `$SHARED_ROOT/npm-global/<key>` の中で完成させ、失敗したらその組を消して `current` とキーに触れない。(4) npm のキャッシュは一時ディレクトリで、終わったら消す。(5) 古い組の掃除は 1 つ前を残し、それ以前は `running_from_any` / `running_matching` / `running_exact`（`current/bin/<コマンド>` のリンクのパス）/ `ps` の引数で動作中を見て、動いていれば次回に回す。(6) key は node のピン（`aqua.yaml` の `nodejs/node@...`）と `NPM_GLOBALS` から決める（`--check` で見られる）。(7) node/npm は呼び出しユーザの `AQUA_BIN` で共有 aqua の設定から引く。`NPM_GLOBALS` は **こちらは `difit` と `cline` だけ**。work の `@drawio/mcp`（こちらの drawio は Claude Code のプラグイン経由で npm の CLI は使わない）、`@mermaid-js/mermaid-cli`（使わない）、`agent-browser`（こちらは `aqua.yaml` の `vercel-labs/agent-browser` で入れる）は持ち込まない |
| `.chezmoiscripts/run_after_30-node-default.sh.tmpl` | **こちらが新しい（2026-11-10）。** 共有側が揃っている間は fnm の Node を消すだけ（動いていれば次回。macOS の `ps` が出すリンクのパス `fnm_multishells/` も見る）。揃っていない間は work と違い、従来どおり fnm の LTS と `NPM_GLOBALS` をユーザ単位で入れる（`~/.cache/dotfiles/node-user.key` のマーカーを成功時だけ進める）。work は共有側が常にある前提 |
| `executable_claude-bedrock` / `executable_codex-bedrock` / `executable_codex-wrapper` / `dot_local/libexec/codex-dispatch/executable_codex` の `AQUA_GLOBAL_CONFIG` | **こちらが新しい（2026-11-10）。** どちらも共有 aqua ストアの claude / codex を aqua-proxy 経由で起動するので `AQUA_GLOBAL_CONFIG` を export する点は揃った。こちらは共有側が揃っていない間（sudo を使えなかったときのホーム aqua）も動くよう、`.chezmoitemplates/aqua-shared-env` と同じ判定（共有ストアが揃い、ホームの pkgs が共有側への symlink のときだけ共有側の設定、それ以外はホームの設定）を 4 本に同じブロックで持ち、`AQUA_ROOT_DIR` / `AQUA_POLICY_CONFIG` も渡す。work は共有側が常にある前提の 1 行（ホームの設定を既定にする）。work へ配るときはこのブロックに置き換えてよい |
| `executable_claude-bedrock` | **こちらが正しい（2026-11-09）。** work の Haiku の既定が `global.anthropic.claude-haiku-5-5[1m}`（`]` が `}`）になっている。work へ配る側 |

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
| `codex-spawn` のチーム解決 | `whoami.sh` が `agent=` / `multiple=` を返すときだけ採用し、`suggest=` / `not_joined=`（未参加）では止める。`suggest=` の `teams=` を拾うと別リポのチームへ join させていた |
| `codex-spawn` の配信モード | 起動先が `monitor` でなければ `delivery.sh set monitor codex` してから spawn する（`.codex/hooks.json` は gitignore 済みで worktree に付いてこない）。こちらではマーカー判定より前に置き、素の `spawn.sh` へ委譲する経路でも効くようにした。同日 work へも配った（work の d9f52d3） |
| `codex-spawn` の `TMPDIR` | `spawn.sh` へ `TMPDIR=${XDG_RUNTIME_DIR:-~/.cache/agmsg}` を渡す。共有ホストで `${TMPDIR:-/tmp}/agmsg-spawn` が他ユーザの所有になる問題。mac では `$TMPDIR` が元からユーザ専用だが、差分を作らないためそのまま揃えた |
| `codex-bedrock` の `sessions` | 一時 home の `sessions` symlink のリンク先 `~/.codex/sessions` を先に作る（無いと `thread-store internal error: File exists`） |
| `aws-login` のリージョン | 先頭で `AWS_REGION` / `AWS_DEFAULT_REGION` を捨てる。`claude-bedrock` の `AWS_REGION=us-east-1` 配下では signin の更新が毎回 `INVALID_REQUEST` で弾かれていた。「更新が一瞬だけ弾かれる」と読んでいた失敗はこれだった（aws-cheatsheet の節を書き換えた） |
| docs / codex-review スキル | 「チームはリポジトリごとに 1 つ」「worktree では新チームを作らない」「フックは worktree ごとに要る」と、未参加時・`mode: off` 時の分岐 |

work の `docs/claude-settings.md` に足された「popup へ来るのはログインセッションが切れたときだけ」は、
こちらでは `docs/herdr-cheatsheet.md` の popup の節に置いた。

2026-11-09 に、2026-09-17 以降の work 側（b23ba02..6c03a76）を取り込んだ。

| 取り込んだもの | 中身 |
| --- | --- |
| `herdr-here`（aaec3cc） | popup をフォーカス中ペインの前面プロセスの cwd で開く（Claude Code が worktree へ移っていればその worktree）。`config.toml` の popup 5 つを経由させた |
| `herdr-difit` の `base`（aaec3cc） | 一覧の先頭にベースブランチとの差分（`--merge-base --include-untracked`） |
| worktree へ移らせる hook と指示（a193a18） | `worktree-enter-reminder.sh`。登録はユーザ層、指示は `modify_CLAUDE.md` |
| `claude` 関数の `rehash` | 覚えている実体が消えていたら PATH を引き直す |
| `.gitignore_global` の `.superpowers/` | — |
| `claude-bedrock` の既定モデル | 5-5 系へ。work の Haiku の誤記（`[1m}`）は直して取り込んだ |
| herdr integration の `run_after_`（8937733） | apply のたびにフックを入れ直し、herdr 本体の更新に追従 |
| `git-commit` / `gh-pr-create` スキル（7cf1373） | そのまま |
| Renovate（f762ad7 / 8602da7 の一部） | minor / patch を 1 本の PR にまとめる・月曜だけ新規 PR・`NPM_GLOBALS` の custom manager。CodeArtifact・自前 workflow・`/opt` 向けの manager（Kiro / Rust / agmsg / uv tool）は取り込まない |

取り込まなかったもの: `/opt` へ寄せる複数ユーザ化（共有 aqua ストア、`/opt/npm-global` / `/opt/uv` /
`/opt/rustup` / `/opt/agmsg`、`bootstrap/` 一式、各ラッパーの `AQUA_GLOBAL_CONFIG`。のち 2026-11-10 の共有ストア導入で `aqua` 系と `/opt/npm-global`（`bootstrap/23-shared-npm.sh`）、`/opt/uv`（`bootstrap/24-shared-uv.sh`）は取り込んだ。uv の `UV_TOOLS` は work の AWS MCP サーバー（`mcp-proxy-for-aws-cli` / `awslabs.aws-pricing-mcp-server`）を入れず、ansible と graphifyy だけ。Renovate の uv の manager は取り込んだ）は、Mac での設計を
別に詰めてから入れる。Splunk / `tunnel` / Grafana / gcx / deploy の CI / dnf-automatic / EC2 /
sshd / `create-slides` / `drawio` スキル / Windows は work 固有なので対象外。
