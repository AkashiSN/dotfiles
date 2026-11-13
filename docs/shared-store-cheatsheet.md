# 共有ストア チートシート

1 台のマシンの複数ユーザで、ツールの実体を `/opt` 以下に 1 つだけ置いて共有する仕組み（共有ストア）。版はマシンで 1 つになり、各ユーザの `chezmoi apply` が食い違いを見つけたときだけ、sudo で揃える。

## 構成

| パス | 内容 |
| --- | --- |
| `/opt/dotfiles-shared/state` | 共有側に版を出したかもしれない最も新しいコミット（`commit=` / `updated_by=` / `updated_at=` の 3 行）。ステップを流す前に書く |
| `/opt/dotfiles-shared/lock` | 更新を全ユーザで 1 本に絞る排他ロック（`flock`。無ければ `/usr/bin/perl` の flock）。中身は空で、更新を終えたプロセスが閉じると外れる |
| `/opt/dotfiles-shared/keys/<NN>` | ステップ `bootstrap/NN-*.sh` が揃えたときのピンのキー（`pins_key` の 12 桁） |
| `/opt/dotfiles-shared/pending/<NN>` | ステップ `NN` が使用中のため消し残したものがある印（次の apply で流し直す） |
| `bootstrap/NN-*.sh` | 共有側の 1 領域を揃えるステップ（番号順に実行） |
| `bootstrap/run-all.sh` | ステップを束ねる入口 |

所有者は `root`（グループは Linux が `root`、macOS が `wheel`）、権限は `755` / `644`。各ステップは置いた木に `chmod -R a+rX,go-w` をかけ、展開したアーカイブの権限に関わらず全ユーザが読めて root だけが書ける状態にする（aqua は `/opt/aquaproj-aqua`、npm / uv は置いた組（uv は Python の置き場も）、rust は `/opt/rustup` と `/opt/cargo`、tenv / agmsg も同じ）。パスは環境変数 `SHARED_ROOT`（既定 `/opt`）で変わる（テスト用）。

## apply のたびの確認

`.chezmoiscripts/run_after_15-shared-store.sh.tmpl`（darwin / linux、毎回実行）が `shared_store_trigger` を呼ぶ。

1. `bootstrap/run-all.sh --check` を呼び出したユーザの権限で流す。全ステップが一致なら何もせず終わる（sudo を呼ばない）。
2. 食い違いがあれば、ダウングレード判定 `shared_guard` を同じユーザの権限で行う。`stale` なら警告だけ出して終わる。
3. `ok` / `force` なら sudo を呼ぶ。`sudo --preserve-env=... bash bootstrap/run-all.sh` で、食い違うステップだけを番号順に揃える。`run-all.sh` はロック（`/opt/dotfiles-shared/lock`）を取ってから食い違いを数え直し、`state` が 2. で判定したときのままか確かめる。sudo の認証やロックを待つ間にほかのユーザが更新していたら、何もせず 4 で終わり、`shared_store_trigger` が 1 度だけ 1. から判定し直す（2 度目も変わっていれば次の apply に回す）。
4. 食い違いが消し残し（`pending/<NN>`）だけ（`--check` が 3）なら急がない。`sudo -n` が通るときだけ `sudo -n` で流し、通らなければパスワードを聞かず案内を 1 行出して終わる。

どの場合も `chezmoi apply` は止まらない（常に終了コード 0）。

## sudo を聞かれるとき

キーの食い違いがあり、かつダウングレードにならないときだけ（消し残しだけのときは聞かない）。次のときは sudo を呼ばず、警告して見送る（次の apply で再試行される）。

- `sudo -n true` が通らず、標準入力が端末でない（パスワードを聞けない）。
- sudo のパスワードを断られた、またはステップが失敗した。
- `DOTFILES_SHARED_SKIP=1 chezmoi apply`。共有ストアの更新、Homebrew の共有設定（`run_before_05`）、Claude Code の managed settings（`run_after_42`）のどれでも sudo を呼ばず、案内を 1 行出して終える。共有側が揃っていない間のユーザ側は、各ステップのユーザ単位の fallback で動く。

root の aqua へは、呼び出したユーザの `gh auth token` を `GITHUB_TOKEN` として環境変数で渡す（引数に載せない。ファイルにも残さない）。`aqua` の絶対パスは `AQUA_BIN` で渡す（初回の apply ではまだ PATH に無いため、PATH に無ければ `~/.local/bin` / `/opt/homebrew/bin` / `/usr/local/bin` からも探す。`run_after_20-aqua-verify` も同じ場所を PATH に足す）。

## ダウングレード防止（guard）

共有側を更新してよいのは、`HEAD` が `origin/main` に含まれ、かつ `state` のコミットが `HEAD` の祖先（または `state` が無い）のとき。git は root で動かさず（所有者違いで拒否されるため）、呼び出したユーザ側で判定して、結果を `DOTFILES_STATE_COMMIT`（`HEAD`）と `DOTFILES_STATE_SEEN`（判定に使った `state` のコミット。無ければ空）で渡す。

`run-all.sh` はロックを取ったあと、`state` が `DOTFILES_STATE_SEEN` と同じときだけ進む（違えば 4）。ステップを流す前に `state` を `HEAD` へ進め、途中のステップが失敗しても下げない。`state` は「共有側にこのコミットの版が出ているかもしれない」下限で、一部だけ新しい版になった共有側を、古い checkout が `behind-state` で巻き戻せないようにする。失敗したステップは食い違いのまま残り、同じコミット以降の apply が流し直す。

| 理由 | 意味 |
| --- | --- |
| `no-origin-main` | `origin/main` が無い（fork や別名のリモート）。新旧を判定できない |
| `not-on-origin-main` | `HEAD` が `origin/main` に含まれない |
| `behind-state` | 共有側がこの checkout より新しいコミットで更新済み |
| `state-commit-unknown` | `state` のコミットがこの checkout に無い |

無視して更新するなら `DOTFILES_SHARED_FORCE=1 chezmoi apply`。条件を見ずに更新し、`state` は書き換えない。

## 手動で実行する

```sh
bash bootstrap/run-all.sh --check; echo $?    # 0: 一致 / 1: キーの食い違い / 3: 消し残しだけ（root 不要、何も書かない）
sudo bash bootstrap/run-all.sh                 # 食い違うステップだけを揃える（1: ステップの失敗 / 4: 判定後に state が変わった）
```

`sudo` で直接流すと git 判定は行わず `state` も見ず書かない（`DOTFILES_STATE_COMMIT` が空のため）。ロックは取るので、ほかのユーザの apply が更新している間は待つ。`GITHUB_TOKEN` / `AQUA_BIN` が必要なステップは、`sudo --preserve-env=GITHUB_TOKEN,AQUA_BIN,DOTFILES_SRC` を付けて、環境変数を export したうえで流す。

## ステップの約束（`bootstrap/NN-*.sh`）

- 引数 `--check`: root なしで、共有側が `DOTFILES_SRC` のピンと一致すれば 0、食い違えば 1。何も書かない。
- 引数なし: root で共有側を揃える（冪等）。揃えたら `$SHARED_ROOT/dotfiles-shared/keys/NN` に `pins_key` の結果を書く。`--check` はこのキーとソースから計算したキーを比べる。
- 環境変数: `DOTFILES_SRC` / `AQUA_BIN` / `SHARED_ROOT` / `DOTFILES_SHARED_FORCE`。`GITHUB_TOKEN` は `run-all.sh` が `20`（共有 aqua）にだけ渡し、他のステップ（`--check` を含む）からは外す。
- 共有 aqua からツールを引くステップ（21 / 23 / 24 / 25）は、最初に `bootstrap/lib.sh` の `shared_aqua_current`（`20-shared-aqua.sh --check`）で共有 aqua がピンと揃っているかを見る。揃っていなければ理由を出して非 0 で終わる（20 が失敗した回は、後続がそろって「飛ばした」と出る）。
- ステップが失敗しても `run-all.sh` は後続を流す。失敗が 1 本でもあれば終了コード 1 で終わる（`state` は流す前に進めてあり、そのまま。失敗したステップは食い違いのまま残り、次の apply でやり直す）。実行後の `--check` が通らないステップ（キーの書き忘れ）も失敗として扱う。
- `run-all.sh` はステップ（と `--check`）をロックの fd を閉じて起動する。ステップが残したプロセスがロックを持ち続けないようにするため。
- 古い版を使用中のため消せなかったステップは、`bootstrap/lib.sh` の `gc_defer` で `/opt/dotfiles-shared/pending/<NN>` を置く。`run-all.sh --check` はキーが全て一致していてもこれがあれば 3 を返す（キーの食い違いもあれば 1）。次の apply（どのユーザのものでもよい。ダウングレード判定は通常どおり）で、`sudo -n` が通るときだけそのステップを流し直して使い終わったものを消す。パスワードは聞かない（通らなければ案内を 1 行出すだけで、キーの食い違いで sudo を通した apply か、資格情報がキャッシュされている間の apply で掃除される）。`run-all.sh` はステップを流す前に印を外し、まだ使用中ならステップが置き直す（失敗ではない）。
- ステップの `--check` の終了コードは 1 だけが食い違い。それ以外の非 0 はステップ自身の異常として終了コードつきで警告し、不一致として数える。

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
パッケージ（依存や github_release 以外の種別）には触らない。`cli/cli`（gh）の版も全て残す（aqua は
attestation の検証に自分で固定した版の gh を入れて使うため、消すと次の apply でまた取得し直す）。
`/opt/npm-global/<key>/bin/*`（npm の CLI のラッパー。node を絶対パスで exec する）のどれかが指している版も、
動いていなくても残す（23 は 1 つ前の組も残すので、その組が指す 1 つ前の node も残る。組が消えたあと、次に 20 を流したときに消える）。
いまの `nodejs/node` は `pkgs/http/nodejs.org/...` に入るのでこの掃除の対象外だが、github_release になっても壊さないための守り。

ユーザ側（`run_after_20-aqua-verify.sh.tmpl`、毎回実行）は、共有側（`config/aqua.yaml`）が在るときだけ
ホームの `pkgs` / `bin` を symlink にする。実ディレクトリなら `<dir>.old.<時刻>` へ退避し、
その下から動くプロセスが無ければ消す（動いていれば次回）。共有側が揃っていない（`config/aqua.yaml` と `/opt/dotfiles-shared/keys/20` のどちらかが無い）ときは、ホームの既存ファイルを消さず動かさず、
ホームの設定でユーザ単位の `aqua policy allow` / `aqua install -a` を行う（設定が変わったときだけ。`~/.cache/dotfiles/aqua-user.key` に置いたハッシュで判定する。未認証の gh は bootstrap タグだけ検証なしで入れ、`gh auth login` は案内だけ出して待たない）。

経緯: 以前は `run_onchange_after_20-aqua-install.sh.tmpl` が各ユーザのホームへ install し、未認証なら `gh auth login` を対話で呼んでいた。共有ストアへの移行で `run_after_20-aqua-verify.sh.tmpl` に置き換え、ユーザ側は install も対話もしない。

プロジェクトの `aqua.yaml`: `pkgs` は root 所有の共有ストアで、lazy install も無効（`AQUA_DISABLE_LAZY_INSTALL=true`）のため、プロジェクト側の `aqua.yaml` にあるツールはそのままでは入らない。次のどちらかで回避する。

- プロジェクトごとに別の `AQUA_ROOT_DIR` を使う（direnv の `.envrc` など）: `export AQUA_ROOT_DIR="$PWD/.aqua"` と `PATH_add "$PWD/.aqua/bin"`、`unset AQUA_DISABLE_LAZY_INSTALL`。
- 全員で使うツールなら、グローバルの `dot_config/aquaproj-aqua/aqua.yaml` に足す。

macOS の `ps` は退避前のパス（今は共有側への symlink）で起動したプロセスを区別できないため、aqua のツール（herdr など）が 1 つでも動いている限り `~/.local/share/aquaproj-aqua/{pkgs,bin}.old.*` は消さない。ユーザが消すまで残り得る。残した apply では大きさ（`du -sh`）と消すコマンドを 1 行で案内するので、退避前のツールを使うプロセスが無いこと（退避より前に起動したシェルの herdr などを再起動したこと）を確かめて `rm -rf ~/.local/share/aquaproj-aqua/{pkgs,bin}.old.*` で消す。

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
- **導入**: root が共有 aqua の node / npm（呼び出したユーザの `AQUA_BIN` を、`AQUA_ROOT_DIR` / `AQUA_GLOBAL_CONFIG` / `AQUA_POLICY_CONFIG` を共有側へ向けて引く）で `<key>` の中へ完成させ、成功したときだけ `current` を付け替えてキーを書く。失敗したらその組を消し、`current` とキーはそのまま非 0 で終わる（他のステップは続く）。共有 aqua がこのソースのピンと揃っていない（`config/aqua.yaml` が無い、または `20-shared-aqua.sh --check` が通らない。20 が失敗した回など）、または node が無いときは、明確なメッセージで失敗する。npm のキャッシュは一時ディレクトリで、終わったら消す。
- **GC**: 新しい組を入れたあと、1 つ前の組は残し、それ以前を消す。動いているプロセスがあるもの（実行ファイルが組の下、パスに `/npm-global/<key>/` を含む、`current/bin/<コマンド>` のリンクのパスと完全一致、`ps` の引数に組のパスを含む）は消さず、次回に回す。
- **PATH**: `env.sh` が、`/opt/npm-global/current/bin` と `keys/23` の両方が在るときだけ `~/.local/bin` の後ろに足す。
- **ユーザ側**（`run_after_30-node-default.sh.tmpl`、毎回実行）:
  - 揃っている間は、ホームの fnm の既定の Node だけを消す。対象は `aliases/default` と `aliases/lts-latest` が指す版（ユーザ単位の導入の `fnm install --lts` / `fnm alias default lts-latest` が作るもの）と、その版を指す alias（`default` / `lts-latest` / `lts-<名前>` など）。それ以外の版と alias、fnm 本体と他のディレクトリはプロジェクトの `.nvmrc` 用に残す。動いている node（実行ファイルが消す版の下、または macOS の `ps` が出す `fnm_multishells/` や `aliases/` のリンクのパス）があれば次の apply に回す。`default` / `lts-latest` が無い・版を指していないなら何もしない。消した版を指していた alias（`lts-latest` -> `aliases/default` のような alias を指す alias も含む）は、解決できなくなったものだけを消す。どの alias も指していない古い LTS の版（ユーザ単位の導入で過去に入ったもの）は残るので、要らなければ `fnm uninstall <版>` で消す。掃除を終えたら `~/.cache/dotfiles/node-home.cleaned` を置き、以後は自分で `fnm default` を付け直しても消さない（ユーザ単位の導入をした回にこの印を外す）。
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
| `/opt/uv/python/` | uv の Python の置き場（`UV_PYTHON_INSTALL_DIR`）。`cpython-<版>-...` が版ごとに入る。組の外の固定の場所で、ツールの版を上げても動かない |
| `/opt/uv/<key>/{tools,bin}` | 1 組。`tools` はツールの venv、`bin` は `python` / `python3` / `python3.N` と各ツールのコマンド。`.complete` |
| `/opt/uv/current` | 使う組を指す symlink（`<key>` への相対リンク）。`swap_symlink` で原子的に付け替える |
| `/opt/uv/{tools,bin}` | `current/{tools,bin}` への固定の symlink（付け替えても変わらない入口） |
| `/opt/dotfiles-shared/keys/24` | key（Python の版と `UV_TOOLS` のハッシュ 12 桁）。ディレクトリ名と同じ |

- **組の中へ直接入れる**: uv は venv のシェバンやコマンドの symlink に入れ先の絶対パスを書くので、入れてから動かさない。`<key>` の中へ `UV_TOOL_DIR` / `UV_PYTHON_BIN_DIR` / `UV_TOOL_BIN_DIR` を向けて入れる。
- **Python は組の外**: 各ユーザのプロジェクトの venv（`uv venv` / `uv sync`）も共有の Python のパスを記録する。Python を組の中に置くとツールの版を上げるたびに動いて古い組の GC で壊れるので、`/opt/uv/python/` に固定し、`UV_PYTHON_INSTALL_DIR` を向ける。`dot_python-version` の版を上げると新しい版が増える。古い版は、動いておらず、残る組のどの venv / bin のリンクも使っていないときだけ消す。**消えた版で作ったプロジェクトの venv は壊れる**（`uv sync` / `uv venv` で作り直す）。
- **導入**: root が共有 aqua の uv（`AQUA_BIN` と共有側の `AQUA_*`）で、ルートへ移り、一時の `UV_CACHE_DIR`・`UV_NO_CONFIG=1`・`UV_PYTHON_PREFERENCE=only-managed` で入れる。`UV_TOOLS` の各ツールのコマンドが `<key>/bin` に在り実行できると確かめてから完了にし、成功したときだけ `current` を付け替えてキーを書く。失敗したらその組を消し、`current` とキーはそのまま非 0 で終わる。共有 aqua がこのソースのピンと揃っていない（`config/aqua.yaml` が無い、または `20-shared-aqua.sh --check` が通らない。20 が失敗した回など）、または uv が無いときは明確なメッセージで失敗する。
- **GC**: 1 つ前の組は残し、それ以前を消す。動いているプロセスがあるもの（実行ファイルが組の下、パスに `/uv/<key>/` を含む、`/opt/uv/bin/<コマンド>` や組の `bin/<コマンド>` のリンクのパスと完全一致、`ps` の引数に組のパスを含む。Python のスクリプトは macOS の `ps` で comm がインタプリタ、スクリプトのパスは引数に出る）は消さず、次回に回す。macOS の `ps` はプロジェクトの venv のリンク（`.venv/bin/python`）を出すので、`bootstrap/lib.sh` の `running_*` は comm / 引数の第 1 語が symlink なら実体まで解決して照合する。
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

初めて共有側が揃った apply のあとは、新しいシェルを開く（`env.sh` が PATH に `/opt/uv/bin` を足すのは新しいシェルから。開いたままのシェルは `hash -r` では足りず、`exec $SHELL -l` でもよい）。
経緯: 以前は `run_onchange_after_35-uv-tools.sh.tmpl` が各ユーザのホームへ Python と ansible を、`run_after_40` が graphify を別に入れていた。共有ストア導入で、版の固定を `UV_TOOLS` にまとめ、root が 1 組だけ置く形へ移した。

## Rust の toolchain（`bootstrap/25-shared-rust.sh`）

Rust の toolchain を、共有 aqua の `rustup-init` で入れて `/opt/rustup` に置く。

| パス | 内容 |
| --- | --- |
| `bootstrap/25-shared-rust.sh` | ステップ。版は `RUST_VERSION="<ver>"` の行（Renovate が上げる）、コンポーネントは `RUST_COMPONENTS` |
| `/opt/rustup` | `RUSTUP_HOME`。toolchain と `settings.toml`（既定の toolchain） |
| `/opt/cargo/bin` | `cargo` / `rustc` / `rustup` などのプロキシ（`rustup-init` が置く） |
| `/opt/dotfiles-shared/keys/25` | key（`RUST_VERSION`・コンポーネント・`aqua.yaml` の `rust-lang/rustup@` の行のハッシュ 12 桁） |

- **導入**: root が、ルートへ移り、`RUSTUP_HOME=/opt/rustup` / `CARGO_HOME=/opt/cargo` で、`rustup-init -y --no-modify-path --profile minimal --default-toolchain none`、`rustup toolchain install <版> --profile minimal -c clippy -c rustfmt -c rust-docs` の順に流す。ユーザやルートの設定は読まない。`rustc` / `cargo` / `rustfmt` / `cargo-clippy` / `clippy-driver` が toolchain の `bin` で実行でき、プロキシが在ると確かめてから `rustup default <版>` を書き、キーを書く。失敗したら入れた toolchain を消し、既定とキーはそのまま非 0 で終わる。共有 aqua がこのソースのピンと揃っていない（`config/aqua.yaml` が無い、または `20-shared-aqua.sh --check` が通らない。20 が失敗した回など）、または `rustup-init` が無いときは明確なメッセージで失敗する。
- **GC**: 1 つ前の toolchain は残し、それ以前を消す。動いているプロセスがあるもの（実行ファイルが toolchain の下、パスに `/rustup/toolchains/<tc>/` を含む、`ps` の引数に含む）は消さず次回に回す。共有のプロキシ（`/opt/cargo/bin/*`）が動いているときは、macOS の `ps` がどの toolchain かを出さないことがあるので、そのたびの GC を見送る。消す候補が無ければ（現行と 1 つ前だけなら）、プロキシが動いていても次回へ回す印（`pending/25`）は置かない。
- **PATH / RUSTUP_HOME**: `env.sh` が、`/opt/rustup/toolchains`・`/opt/cargo/bin/cargo`・`keys/25` が揃っているときだけ `RUSTUP_HOME=/opt/rustup` にして、`/opt/cargo/bin` を `$CARGO_HOME/bin` の後ろに足す。`CARGO_HOME`（`~/.local/share/cargo`）はユーザごとのまま。
- **ユーザ側**（`run_after_32-rust-default.sh.tmpl`、毎回実行）:
  - 揃っている間は、ホームの掃除（`.chezmoitemplates/rust-cleanup.sh`）。`~/.local/share/cargo/bin` のうち `rustup` と同じ inode のもの（`rustup` 本体とハードリンクのプロキシ）と、`~/.local/share/rustup` を消す。`cargo install` したものは残す。動いている Rust があれば何も消さず次の apply に回す。
  - 揃っていない間は、固定の版をユーザ単位で入れる。`~/.cache/dotfiles/rust-user.key` のマーカーは成功したときだけ進める。ホームのものは消さない。
- **制限**: `/opt/rustup` は読み取り専用なので、プロジェクトの `rust-toolchain.toml` が別の toolchain を求めても各ユーザは入れられない。既定の toolchain は root が書く `settings.toml` から解決するので、`RUSTUP_TOOLCHAIN` の設定は要らない。回避策（プロジェクトだけ書ける `RUSTUP_HOME` にする、または共有のステップに足す）は [zsh-cheatsheet.md](zsh-cheatsheet.md#rust-の共有-toolchain)。

手で確かめる・やり直す:

```sh
rustc --version; echo $RUSTUP_HOME     # RUST_VERSION と /opt/rustup（新しいシェルで）
cat /opt/rustup/settings.toml; ls /opt/rustup/toolchains
cat /opt/dotfiles-shared/keys/25
# 共有側を作り直す（root）。次の apply で食い違いとして検出され、揃え直される
sudo rm -f /opt/dotfiles-shared/keys/25
# ユーザ側の fallback を再実行する（共有側が揃っていない間）
rm ~/.cache/dotfiles/rust-user.key
```

## Terraform の版（`bootstrap/21-shared-tenv.sh`）

Terraform の版を、共有 aqua の `tenv` で入れて `/opt/tenv` に置く。

| パス | 内容 |
| --- | --- |
| `bootstrap/21-shared-tenv.sh` | ステップ |
| `bootstrap/tenv-versions.txt` | 入れる版（1 行 1 版、`#` 以降はコメント）。プロジェクトの `required_version` と揃える |
| `/opt/tenv/Terraform/<版>/terraform` | `TENV_ROOT=/opt/tenv`。版ごとの実体 |
| `/opt/dotfiles-shared/keys/21` | key（版の一覧のハッシュ 12 桁） |

- **導入**: root が、ルートへ移り、共有 aqua の `tenv`（`AQUA_BIN` と共有側の `AQUA_*`）を `TENV_ROOT=/opt/tenv` / `TENV_VALIDATION=sha` で `tenv terraform install <版>`。各版の `terraform` が実行できると確かめてからキーを書く。失敗したら（元から無かった版の dir を消し）ほかの版とキーはそのまま非 0 で終わる。共有 aqua がこのソースのピンと揃っていない（`config/aqua.yaml` が無い、または `20-shared-aqua.sh --check` が通らない。20 が失敗した回など）、または `tenv` が無いときは明確なメッセージで失敗する。
- **GC**: 一覧に無い版を、動いていなければ消す（実行ファイルが版の下、パスに `/Terraform/<版>/` を含む、`ps` の引数に含む。macOS の `ps` は symlink 経由で起動したホームのパスを出すので、これで照合する）。動いていれば次回に回す。provider はユーザのキャッシュ（`~/.cache/terraform/plugin-cache`）から動くので対象外。
- **ユーザ側**（`run_after_21-tenv-verify.sh.tmpl`、毎回実行。`.chezmoitemplates/tenv-link.sh`）: 揃っている間（`keys/21` と `/opt/tenv/Terraform` が在る）、`~/.tenv/Terraform/<版>/terraform` を共有の実体への symlink にする。版のディレクトリはユーザ所有のままで、tenv が書く `last-use.txt` はホーム側に残る。共有が覆う版でホームに実ファイルがあれば、動いていなければ symlink に替える（動いていれば次回）。共有が覆わない版は残す。揃っていない間は何もしない（従来どおり tenv が自分で取る）。`env.sh` の変更は無い。使い方は [terraform-cheatsheet.md](terraform-cheatsheet.md#共有-tenv-ストア)。

手で確かめる・やり直す:

```sh
ls /opt/tenv/Terraform; cat /opt/dotfiles-shared/keys/21
readlink ~/.tenv/Terraform/*/terraform
terraform version                       # tenv-versions.txt の版
# 共有側を作り直す（root）。次の apply で食い違いとして検出され、揃え直される
sudo rm -f /opt/dotfiles-shared/keys/21
```

## agmsg の配布物（`bootstrap/22-shared-agmsg.sh`）

agmsg のソースを、版と commit を固定して `/opt/agmsg/<版>` に置く。各ユーザはここの `install.sh` を流して `~/.agents/skills/agmsg` へ入れる。

| パス | 内容 |
| --- | --- |
| `bootstrap/22-shared-agmsg.sh` | ステップ。版は `AGMSG_VERSION="<ver>"` と、直後の行の `AGMSG_COMMIT="<40桁>"`（Renovate が一緒に上げる） |
| `/opt/agmsg/<版>` | 配布物（`.git` なし。`.agmsg-commit` に取得した commit） |
| `/opt/agmsg/current` | 使う版を指す symlink（`<版>` への相対リンク）。`swap_symlink` で原子的に付け替える |
| `/opt/dotfiles-shared/keys/22` | key（版と commit のハッシュ 12 桁） |

- **導入**: root が、ルートへ移り、一時ディレクトリへ `git clone --depth 1 --branch v<版>` する。取得した `HEAD` が `AGMSG_COMMIT` と違えば、一時ディレクトリを捨て、`current` もキーもそのまま非 0 で終わる。一致すれば `.git` を消して `<版>` に置き、`current` を付け替えてキーを書く。同じ版が同じ commit で在れば取り直さない。
- **GC**: 現行と 1 つ前の版は残し、それ以前を、動いていなければ消す（`ps` の引数に `/agmsg/<版>/` を含む、実行ファイルが版の下）。agmsg は bash のスクリプトなので、パスは引数に出る。各ユーザの導入物は複製なので、古い版を消しても動き続ける。
- **ユーザ側**（`run_after_40-ai-assistants.sh.tmpl`）: 揃っている間（`keys/22` と `current/install.sh` が在る）は `current/install.sh --cmd agmsg`（導入済みなら `--update`）を流す。マーカー（`~/.cache/dotfiles/ai-agmsg.key`）のキーは `shared-1 <版> <commit>` で、版が上がると流し直す。失敗したらマーカーを進めない。揃っていない間は従来の `setup.sh`（キーは `<日付>`）。

手で確かめる・やり直す:

```sh
readlink /opt/agmsg/current; cat /opt/agmsg/current/VERSION /opt/agmsg/current/.agmsg-commit
cat ~/.agents/skills/agmsg/VERSION
# 共有側を作り直す（root）。次の apply で食い違いとして検出され、揃え直される
sudo rm -f /opt/dotfiles-shared/keys/22
# ユーザ側をやり直す
rm ~/.cache/dotfiles/ai-agmsg.key
```

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

## 2 ユーザでの通し検証（docker）

`tests/docker/run.sh` は、Ubuntu 24.04 のコンテナに `alice` / `bob`（どちらも NOPASSWD の sudo）を作り、作業ツリーの追跡ファイル（未コミットの変更を含む。未追跡は入らない）を main にした bare リポジトリを origin にして、2 人で `chezmoi init --apply` から順に流す。ホストの `/opt` やホームには触らない。Docker Desktop が動いていれば macOS からそのまま流せる（arm64 の Mac では arm64 の Linux になる）。

```sh
tests/docker/run.sh unit       # コンテナの中で bash tests/run.sh（Linux の /proc / ps の分岐）
tests/docker/run.sh            # 通し（e2e）。所要は回線しだいで 15〜30 分
tests/docker/run.sh all --keep # 両方。終わってもコンテナを残す（docker exec -it <名前> bash）
GITHUB_TOKEN="$(gh auth token)" tests/docker/run.sh --token   # API の rate limit に当たるときだけ
```

通し（`tests/docker/scenario.sh`）は aqua.yaml の `jqlang/jq` のピンを origin で動かし（起点 1.8.0 → 1.8.1 → 1.8.2 → 1.7.1。checksum もその場で足す）、次を `PASS:` / `FAIL:` で確かめる。

| 区切り | 確かめること |
| --- | --- |
| S1 / S2 | alice の init で共有側ができる（sudo で `run-all.sh` 1 回、`keys/20..25`、root 所有）。bob の init は共有側に触らない |
| S3 / RF1 | alice が update で上げたあと、bob が pull せずに apply: `behind-state` の警告、共有側は下がらず、bob の `jq` は新しい版 |
| RF3 | bob が古い版の jq を動かしたまま alice が上げると、その版は残る（`pending/20`）。jq が終わった後の apply（bob）で消える |
| RF2 | bob の NOPASSWD を外して非対話で update: 警告だけ、終了コード 0、共有側とホームから何も消えない |
| RF5 | origin を upstream へ改名したクローン: `origin/main が無い` と `DOTFILES_SHARED_FORCE=1` の案内。戻すと更新する |
| RF4 | gh はコンテナで未認証のまま（`--token` なし）。S1 で aqua のステップがどう振る舞ったかをログから出す |

sudo の実行は `/var/log/sudo.log`、各 apply のログは `/work/logs`（終了時に表示する一時ディレクトリへ取り出す）。

コンテナは `--cap-add SYS_PTRACE` で起動する。Linux の使用中の判定（`bootstrap/lib.sh` の `running_*`）は `/proc/<pid>/exe` を読むが、他ユーザのプロセスのそれを root が読むには `CAP_SYS_PTRACE` が要り、docker の既定では外れている（読めないと使用中を見落とし、消してしまう）。実機の root は持っているので問題にならない。共有ストアを docker のコンテナの中で使うときは同じ capability を付ける。

`dot_gitconfig` は `https://github.com/` を SSH へ書き換えるが、コンテナのユーザは GitHub の SSH 鍵を持たない。そのため `scenario.sh` は `GIT_CONFIG_COUNT` で `github.com/vercel-labs/` だけ https のままにする（`41-agent-browser` の `npx skills` が clone する）。実機で鍵を持たないユーザの制約は [multi-user-cheatsheet.md](multi-user-cheatsheet.md) を参照。
