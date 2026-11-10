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
