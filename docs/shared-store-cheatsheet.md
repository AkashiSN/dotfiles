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
- ステップ失敗で `run-all.sh` は止まり、`state` を書かない。実行後の `--check` が通らないステップ（キーの書き忘れ）も失敗として扱う。
