# 共有ストア チートシート

1 台のマシンの複数ユーザで、ツールの実体を `/opt` 以下に 1 つだけ置いて共有する仕組み（共有ストア）。版はマシンで 1 つになり、各ユーザの `chezmoi apply` が食い違いを見つけたときだけ、sudo で揃える。

## 構成

| パス | 内容 |
| --- | --- |
| `/opt/dotfiles-shared/state` | 共有側を最後に更新したコミット（`commit=` / `updated_by=` / `updated_at=` の 3 行） |
| `/opt/dotfiles-shared/keys/<NN>` | ステップ `bootstrap/NN-*.sh` が揃えたときのピンのキー（`pins_key` の 12 桁） |
| `bootstrap/NN-*.sh` | 共有側の 1 領域を揃えるステップ（番号順に実行） |
| `bootstrap/run-all.sh` | ステップを束ねる入口 |

所有者は `root`（グループは Linux が `root`、macOS が `wheel`）、権限は `755` / `644`。パスは環境変数 `SHARED_ROOT`（既定 `/opt`）で変わる（テスト用）。

## apply のたびの確認

`.chezmoiscripts/run_after_15-shared-store.sh.tmpl`（darwin / linux、毎回実行）が `shared_store_trigger` を呼ぶ。

1. `bootstrap/run-all.sh --check` を呼び出したユーザの権限で流す。全ステップが一致なら何もせず終わる（sudo を呼ばない）。
2. 食い違いがあれば、ダウングレード判定 `shared_guard` を同じユーザの権限で行う。`stale` なら警告だけ出して終わる。
3. `ok` / `force` なら sudo を呼ぶ。`sudo --preserve-env=... bash bootstrap/run-all.sh` で、食い違うステップだけを番号順に揃える。

どの場合も `chezmoi apply` は止まらない（常に終了コード 0）。

## sudo を聞かれるとき

食い違いがあり、かつダウングレードにならないときだけ。次のときは sudo を呼ばず、警告して見送る（次の apply で再試行される）。

- `sudo -n true` が通らず、標準入力が端末でない（パスワードを聞けない）。
- sudo のパスワードを断られた、またはステップが失敗した。

root の aqua へは、呼び出したユーザの `gh auth token` を `GITHUB_TOKEN` として環境変数で渡す（引数に載せない。ファイルにも残さない）。`aqua` の絶対パスは `AQUA_BIN` で渡す。

## ダウングレード防止（guard）

共有側を更新してよいのは、`HEAD` が `origin/main` に含まれ、かつ `state` のコミットが `HEAD` の祖先（または `state` が無い）のとき。更新したら `state` に `HEAD` を書く。git は root で動かさず（所有者違いで拒否されるため）、呼び出したユーザ側で判定して結果を `DOTFILES_STATE_COMMIT` で渡す。

| 理由 | 意味 |
| --- | --- |
| `no-origin-main` | `origin/main` が無い（fork や別名のリモート）。新旧を判定できない |
| `not-on-origin-main` | `HEAD` が `origin/main` に含まれない |
| `behind-state` | 共有側がこの checkout より新しいコミットで更新済み |
| `state-commit-unknown` | `state` のコミットがこの checkout に無い |

無視して更新するなら `DOTFILES_SHARED_FORCE=1 chezmoi apply`。条件を見ずに更新し、`state` は書き換えない。

## 手動で実行する

```sh
bash bootstrap/run-all.sh --check; echo $?    # 0: 一致 / 1: 食い違い（root 不要、何も書かない）
sudo bash bootstrap/run-all.sh                 # 食い違うステップだけを揃える
```

`sudo` で直接流すと git 判定は行わず `state` も書かない（`DOTFILES_STATE_COMMIT` が空のため）。`GITHUB_TOKEN` / `AQUA_BIN` が必要なステップは、`sudo --preserve-env=GITHUB_TOKEN,AQUA_BIN,DOTFILES_SRC` を付けて、環境変数を export したうえで流す。

## ステップの約束（`bootstrap/NN-*.sh`）

- 引数 `--check`: root なしで、共有側が `DOTFILES_SRC` のピンと一致すれば 0、食い違えば 1。何も書かない。
- 引数なし: root で共有側を揃える（冪等）。揃えたら `$SHARED_ROOT/dotfiles-shared/keys/NN` に `pins_key` の結果を書く。`--check` はこのキーとソースから計算したキーを比べる。
- 環境変数: `DOTFILES_SRC` / `AQUA_BIN` / `GITHUB_TOKEN` / `SHARED_ROOT` / `DOTFILES_SHARED_FORCE`。
- ステップが失敗しても `run-all.sh` は後続を流す。失敗が 1 本でもあれば `state` を書かず、終了コード 1 で終わる（次の apply でやり直す）。実行後の `--check` が通らないステップ（キーの書き忘れ）も失敗として扱う。
- `--check` の終了コードは 1 だけが食い違い。それ以外の非 0 はステップ自身の異常として終了コードつきで警告し、不一致として数える。

## aqua（`bootstrap/20-shared-aqua.sh`）

| パス | 内容 |
| --- | --- |
| `/opt/aquaproj-aqua/pkgs` | aqua の実体（`AQUA_ROOT_DIR` を `/opt/aquaproj-aqua` にして root が install） |
| `/opt/aquaproj-aqua/bin` | aqua-proxy の symlink 群 |
| `/opt/aquaproj-aqua/config/` | `aqua.yaml` / `registry.yaml` / `aqua-policy.yaml` / `aqua-checksums.json`（`dot_config/aquaproj-aqua/` の同名ファイルのコピー） |
| `/opt/dotfiles-shared/keys/20` | 上の 4 ファイルをこの順に連結した `pins_key` |
| `~/.local/share/aquaproj-aqua/{pkgs,bin}` | `/opt/aquaproj-aqua/{pkgs,bin}` への symlink（ホームの `AQUA_ROOT_DIR`。metadata などの書き込みはホーム側に残る） |

流れ: 新しい config を `config.new/` に置き、そこを向けて `AQUA_BIN`（呼び出したユーザの aqua）を root で使い、`aqua policy allow` のあと `aqua install -a`。成功したときだけ `config/` へ移してキーを書く（`aqua.yaml` を最後に移す）。失敗したら `config/` は元のままで `config.new/` も消す。root の aqua は `cd /` してから動かす（作業ディレクトリの `aqua.yaml` を拾わないため）。
`GITHUB_TOKEN` が空のときは、bootstrap タグの gh だけ検証なしで入れてから、残りを検証つきで入れる。
検証つきの install が失敗したらこのステップだけ失敗し、他のステップ（npm / uv / rust）は続く。
`AQUA_BIN` が空か実行できなければ、メッセージを出して失敗する。

古い版の掃除（読めないときは残す方針）: `pkgs/github_release/<host>/<owner>/<repo>/<version>/` のうち、共有の
`aqua.yaml` に `- name: <owner>/<repo>@<version>`（引用符なし、version に `/` や空白なし、行末コメントのみ可）
として載っているパッケージの、載っていない版を消す。次のどれかに当てはまるパッケージは全ての版を残す。
引用符つきの name、`version:` が別行、`/` を含む版、コメントだけの言及、別の形でも同じ名前が出てくる、
設定の版と同名の dir が無い（version_prefix つきのタグ）。その版の下から動いているプロセスがあれば
（全ユーザ）消さず次回に回す。macOS の ps は symlink 経由の起動パスを出すため、
`.../aquaproj-aqua/pkgs/github_release/...` を含むパスでも照合する。`aqua.yaml` に名前が出てこない
パッケージ（依存や github_release 以外の種別）には触らない。

ユーザ側（`run_after_20-aqua-verify.sh.tmpl`、毎回実行）は、共有側（`config/aqua.yaml`）が在るときだけ
ホームの `pkgs` / `bin` を symlink にする。実ディレクトリなら `<dir>.old.<時刻>` へ退避し、
その下から動くプロセスが無ければ消す（動いていれば次回）。共有側が揃っていない（`config/aqua.yaml` と `/opt/dotfiles-shared/keys/20` のどちらかが無い）ときは、ホームの既存ファイルを消さず動かさず、
ホームの設定でユーザ単位の `aqua policy allow` / `aqua install -a` を行う（設定が変わったときだけ。`~/.cache/dotfiles/aqua-user.key` に置いたハッシュで判定する。未認証の gh は bootstrap タグだけ検証なしで入れ、`gh auth login` は案内だけ出して待たない）。

経緯: 以前は `run_onchange_after_20-aqua-install.sh.tmpl` が各ユーザのホームへ install し、未認証なら `gh auth login` を対話で呼んでいた。共有ストアへの移行で `run_after_20-aqua-verify.sh.tmpl` に置き換え、ユーザ側は install も対話もしない。

プロジェクトの `aqua.yaml`: `pkgs` は root 所有の共有ストアで、lazy install も無効（`AQUA_DISABLE_LAZY_INSTALL=true`）のため、プロジェクト側の `aqua.yaml` にあるツールはそのままでは入らない。次のどちらかで回避する。

- プロジェクトごとに別の `AQUA_ROOT_DIR` を使う（direnv の `.envrc` など）: `export AQUA_ROOT_DIR="$PWD/.aqua"` と `PATH_add "$PWD/.aqua/bin"`、`unset AQUA_DISABLE_LAZY_INSTALL`。
- 全員で使うツールなら、グローバルの `dot_config/aquaproj-aqua/aqua.yaml` に足す。

macOS では、使用中のプロセスが残るため `~/.local/share/aquaproj-aqua/{pkgs,bin}.old.*` が何度かの apply をまたいで残ることがある。動いているものが無いことを確かめて `rm -rf ~/.local/share/aquaproj-aqua/{pkgs,bin}.old.*` で消してよい。

手で掃除する:

```sh
# 共有側を作り直す（root）。次の apply で食い違いとして検出され、揃え直される
sudo rm -f /opt/dotfiles-shared/keys/20
# 退避が残っていれば（使用中だったもの）、プロセスが無いことを確かめてから消す
ls -d ~/.local/share/aquaproj-aqua/*.old.*
```

戻し方（共有をやめて各ユーザのホームに戻す）:

```sh
rm ~/.local/share/aquaproj-aqua/pkgs ~/.local/share/aquaproj-aqua/bin   # symlink を外す
sudo mv /opt/aquaproj-aqua /opt/aquaproj-aqua.disabled                   # 共有側を無効にする
# env.sh の判定が外れ、ホームの設定（~/.config/aquaproj-aqua）へ戻る。ツールは
# aqua install -a （AQUA_ROOT_DIR をホームに向けた通常の環境）で入れ直す
```

## npm の CLI（`bootstrap/23-shared-npm.sh`）

difit / cline のように npm で配られる CLI を、共有 aqua の Node で入れて `/opt/npm-global` に置く。

| パス | 内容 |
| --- | --- |
| `bootstrap/23-shared-npm.sh` | ステップ。一覧と版は `NPM_GLOBALS="$NPM_GLOBALS <pkg>@<ver>"` の行（Renovate が上げる） |
| `/opt/npm-global/<key>/` | 1 組。`prefix/`（`npm install -g --prefix` の結果）、`bin/`（共有の node を絶対パスで呼ぶラッパー）、`.complete` |
| `/opt/npm-global/current` | 使う組を指す symlink（`<key>` への相対リンク）。`swap_symlink` で原子的に付け替える |
| `/opt/dotfiles-shared/keys/23` | key（node のピンと `NPM_GLOBALS` のハッシュ 12 桁）。ディレクトリ名と同じ |

- **key**: `aqua.yaml` の `nodejs/node@<版>` の行と `NPM_GLOBALS` の行から決まる。どちらかを変えると `--check` が 1 を返し、次の apply で新しい key の組を作る。変わらなければ取得しない。
- **導入**: root が共有 aqua の node / npm（呼び出したユーザの `AQUA_BIN` を、`AQUA_ROOT_DIR` / `AQUA_GLOBAL_CONFIG` / `AQUA_POLICY_CONFIG` を共有側へ向けて引く）で `<key>` の中へ完成させ、成功したときだけ `current` を付け替えてキーを書く。失敗したらその組を消し、`current` とキーはそのまま非 0 で終わる（他のステップは続く）。共有 aqua が揃っていない（`keys/20` が無い）、または node が無いときは、明確なメッセージで失敗する。npm のキャッシュは一時ディレクトリで、終わったら消す。
- **GC**: 新しい組を入れたあと、1 つ前の組は残し、それ以前を消す。動いているプロセスがあるもの（実行ファイルが組の下、パスに `/npm-global/<key>/` を含む、`current/bin/<コマンド>` のリンクのパスと完全一致、`ps` の引数に組のパスを含む）は消さず、次回に回す。
- **PATH**: `env.sh` が、`/opt/npm-global/current/bin` と `keys/23` の両方が在るときだけ `~/.local/bin` の後ろに足す。
- **ユーザ側**（`run_after_30-node-default.sh.tmpl`、毎回実行）:
  - 揃っている間は、ホームの fnm の `node-versions` と `aliases` を消す（fnm 本体と他のディレクトリは残す。プロジェクトで使う版は各自が `fnm install` で入れ直す）。動いている node（実行ファイルが `node-versions` の下、または macOS の `ps` が出す `fnm_multishells/` のリンクのパス）があれば次の apply に回す。
  - 揃っていない間（`current/bin` か `keys/23` が無い）は fnm の LTS と `NPM_GLOBALS`（`bootstrap/23-shared-npm.sh` の行）をユーザ単位で入れる。`~/.cache/dotfiles/node-user.key` のマーカーは成功したときだけ進める。fnm の Node は消さない。`~/.local/bin/difit` は共有側の実体が在ればそちらを使う。
- **入れるもの**: `difit` と `cline` だけ。work の `@drawio/mcp` / `@mermaid-js/mermaid-cli` / `agent-browser` は、こちらでは使っていない（agent-browser は `aqua.yaml`）ので入れない（[work-sync.md](work-sync.md)）。

手で掃除する・やり直す:

```sh
# 共有側を作り直す（root）。次の apply で食い違いとして検出され、揃え直される
sudo rm -f /opt/dotfiles-shared/keys/23
# 組を確認する。current と 1 つ前以外は、動いているプロセスが無ければ消してよい
ls -l /opt/npm-global
# 古い組を手で消す（使用中でないことを確かめてから）
sudo rm -rf /opt/npm-global/<key>
# ユーザ側の fallback を再実行する（共有側が揃っていない間）
rm ~/.cache/dotfiles/node-user.key
```

経緯: 以前は `run_onchange_after_30-node-default.sh.tmpl` が各ユーザの fnm の node に difit を `npm install -g` で入れ、cline は `run_after_40` が別に入れていた。共有ストア導入で、版の固定を `NPM_GLOBALS` にまとめ、root が 1 組だけ置く形へ移した。

## uv の Python と CLI（`bootstrap/24-shared-uv.sh`）

既定の Python と、`uv tool` で配る CLI（ansible / graphify）を、共有 aqua の uv で入れて `/opt/uv` に置く。

| パス | 内容 |
| --- | --- |
| `bootstrap/24-shared-uv.sh` | ステップ。一覧と版は `UV_TOOLS="$UV_TOOLS <pkg>[extra,...]==<ver>"` の行（Renovate が上げる）。Python の版は `dot_config/uv/dot_python-version` |
| `/opt/uv/<key>/{python,tools,bin}` | 1 組。`python` は uv の Python、`tools` はツールの venv、`bin` は `python` / `python3` / `python3.N` と各ツールのコマンド。`.complete` |
| `/opt/uv/current` | 使う組を指す symlink（`<key>` への相対リンク）。`swap_symlink` で原子的に付け替える |
| `/opt/uv/{python,tools,bin}` | `current/{python,tools,bin}` への固定の symlink（付け替えても変わらない入口） |
| `/opt/dotfiles-shared/keys/24` | key（Python の版と `UV_TOOLS` のハッシュ 12 桁）。ディレクトリ名と同じ |

- **組の中へ直接入れる**: uv は venv のシェバンやコマンドの symlink に入れ先の絶対パスを書くので、入れてから動かさない。`<key>` の中へ `UV_PYTHON_INSTALL_DIR` / `UV_TOOL_DIR` / `UV_PYTHON_BIN_DIR` / `UV_TOOL_BIN_DIR` を向けて入れる。
- **導入**: root が共有 aqua の uv（`AQUA_BIN` と共有側の `AQUA_*`）で、ルートへ移り、一時の `UV_CACHE_DIR`・`UV_NO_CONFIG=1`・`UV_PYTHON_PREFERENCE=only-managed` で入れる。`UV_TOOLS` の各ツールのコマンドが `<key>/bin` に在り実行できると確かめてから完了にし、成功したときだけ `current` を付け替えてキーを書く。失敗したらその組を消し、`current` とキーはそのまま非 0 で終わる。共有 aqua が揃っていない（`keys/20` が無い）、または uv が無いときは明確なメッセージで失敗する。
- **GC**: 1 つ前の組は残し、それ以前を消す。動いているプロセスがあるもの（実行ファイルが組の下、パスに `/uv/<key>/` を含む、`/opt/uv/bin/<コマンド>` や組の `bin/<コマンド>` のリンクのパスと完全一致、`ps` の引数に組のパスを含む。Python のスクリプトは macOS の `ps` で comm がインタプリタ、スクリプトのパスは引数に出る）は消さず、次回に回す。
- **PATH**: `env.sh` が、`/opt/uv/bin` と `keys/24` の両方が在るときだけ `~/.local/bin` の後ろに足す。`codex-bedrock` は PATH 上の `python3`（3.11+）を探すので、この `python3` で動く。
- **ユーザ側**（`run_after_35-uv-tools.sh.tmpl`、毎回実行）:
  - 揃っている間は、ホームの uv の掃除（`.chezmoitemplates/uv-cleanup.sh`）。共有へ移したツールの実体と `~/.local/bin` の symlink を消し、ユーザが自分で入れたツールは残す。残るツールが無ければホームの Python と `python3` などの symlink も消す。動いているもの（実行ファイルが `~/.local/share/uv` の下、macOS の `ps` が出すリンクのパス、引数にスクリプトのパス）があれば何も消さず次の apply に回す。
  - 揃っていない間（`bin` か `keys/24` が無い）は `uv python install --default` と `UV_TOOLS` をユーザ単位で入れる。`~/.cache/dotfiles/uv-user.key` のマーカーは成功したときだけ進める。ホームのものは消さない。
- **graphify の登録**: `graphify install`（ユーザ単位）は `run_after_40` が行う。実体は上の `UV_TOOLS`。

手で確かめる・やり直す:

```sh
command -v python3 graphify          # /opt/uv/bin/...（ansible パッケージのコマンドは ansible-community）
readlink /opt/uv/current; cat /opt/dotfiles-shared/keys/24
UV_TOOL_DIR=/opt/uv/tools uv tool list
# 共有側を作り直す（root）。次の apply で食い違いとして検出され、揃え直される
sudo rm -f /opt/dotfiles-shared/keys/24
# 古い組を手で消す（使用中でないことを確かめてから）
sudo rm -rf /opt/uv/<key>
# ユーザ側の fallback を再実行する（共有側が揃っていない間）
rm ~/.cache/dotfiles/uv-user.key
```

経緯: 以前は `run_onchange_after_35-uv-tools.sh.tmpl` が各ユーザのホームへ Python と ansible を、`run_after_40` が graphify を別に入れていた。共有ストア導入で、版の固定を `UV_TOOLS` にまとめ、root が 1 組だけ置く形へ移した。

## AI エージェントの CLI（`aqua.yaml` と `run_after_40-ai-assistants.sh.tmpl`）

Claude Code / Codex / CodeGraph / Kiro CLI（Linux）の実体は、共有 aqua ストア（上の節）に入る。
`dot_config/aquaproj-aqua/aqua.yaml` の「AI エージェントの CLI と周辺ツール」にピンがあり、Kiro だけ local registry（`registry.yaml`、Linux のみ）の定義。
macOS の Kiro CLI は公式インストーラの `/Applications/Kiro CLI.app` のまま。

ユーザ側（`run_after_40-ai-assistants.sh.tmpl`、毎回実行）は取得せず、次だけを行う。

- ホームに残った公式インストーラの実体を掃除する（`.chezmoitemplates/ai-cleanup.sh` の `ai_cleanup_home`）。そのコマンドを aqua が提供しているとき（`aqua which <cmd>` が aqua の `pkgs` 配下の実在するファイルを返すとき。共有側でもホームのフォールバックでもよい）だけ消す。aqua が提供しなければ何も消さない。`~/.local/bin` のリンクは、aqua が提供していれば動作中でも外す（動いているプロセスは実体を開いたまま、新しい起動は aqua へ向かう）。実体のディレクトリは、動作中でないときだけ消す。動作中とは、実行ファイルが実体の下にある（`running_from_any` / `running_matching`）か、実行ファイルのパスがそのコマンドのリンク（`~/.local/bin/claude` / `codex` / `codegraph`、`~/.agents/bin/codex`）と完全に一致する（`running_exact`。macOS の `ps` はリンクで起動したプロセスをリンクのパスで出す）こと。動作中なら実体は次の apply で消す。方針を入れる前から動いている Claude Code は自動更新で `~/.local/bin/claude` を作り直すことがあるが、次の apply が片付ける。設定・認証・履歴には触れない。
- 登録（`codegraph install --yes` / `graphify install` / agmsg / Kiro のシェル統合の解除）。時間のかかるものは `~/.cache/dotfiles/ai-<名前>.key` のマーカーで、キーが変わったときだけ流す。ステップは途中のコマンドが 1 つでも失敗するか前提（npm / uv / codegraph）が欠けると非 0 で終わり、そのときマーカーは進めない（agmsg は `curl -o` で落としてから実行する）。codegraph の登録のキーには `aqua.yaml` のピンの版を含み、版が上がると流し直す。

自己更新は止める: Claude Code は managed settings の `env.DISABLE_AUTOUPDATER`、Codex は `bootstrap/31-codex-policy.sh` が置く管理者設定の `check_for_update_on_startup = false`、CodeGraph / Kiro は `env.sh` の `CODEGRAPH_NO_UPDATE_CHECK` / `KIRO_NO_AUTO_UPDATE`。

### Codex の管理者設定（`bootstrap/31-codex-policy.sh`）

| パス | 内容 |
| --- | --- |
| `bootstrap/codex/managed_config.toml` | ソース。`check_for_update_on_startup = false` |
| `/etc/codex/managed_config.toml` | 置き場所（root 所有、644）。OpenAI のドキュメント（Managed configuration の Locations）で Linux / macOS とも `/etc/codex/managed_config.toml`。パスは `CODEX_MANAGED_DIR` で変わる（テスト用） |
| `/opt/dotfiles-shared/keys/31` | ソースの `pins_key` |

`--check` は、キーが一致し、置き場所のファイルがソースと同一のときだけ 0。管理者設定は各ユーザの `~/.codex/config.toml` より優先される。

経緯: 以前は claude / codex / codegraph / kiro を公式インストーラで各ユーザのホームへ入れ、本体が自己更新していた。共有 aqua へ移し、掃除は「aqua が提供しているときだけ」に絞った（共有側が無く、ホームの aqua も入れられていない間に公式の実体を消して使えなくなるのを避ける）。
