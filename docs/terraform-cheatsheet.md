# Terraform チートシート

`tenv` によるバージョン管理と、provider のダウンロードキャッシュについて。

対象ファイル: `dot_terraformrc.tmpl` / `dot_zshenv.tmpl` /
`.chezmoiscripts/run_onchange_after_36-terraform-plugin-cache.sh.tmpl` /
`dot_local/bin/executable_tf-cache-prune` / `dot_config/zsh/rc.d/40-tools.zsh`

## provider キャッシュ

`terraform init` は既定でプロジェクトごとに provider をダウンロードし、
`.terraform/providers/` へ展開する。同じ provider を使うプロジェクトが増えるほど
ダウンロードと容量が重複するため、ユーザー共通のキャッシュを 1 か所に置く。

```
${XDG_CACHE_HOME:-$HOME/.cache}/terraform/plugin-cache
```

キャッシュに存在する provider は再ダウンロードされず、可能な場合は
プロジェクト側の `.terraform/providers/` から **symlink** が張られる（実体は 1 つだけ）。

### 設定は 2 か所

| 場所 | 設定 | 効く範囲 |
| --- | --- | --- |
| `~/.terraformrc`（`dot_terraformrc.tmpl`） | `plugin_cache_dir` | terraform 本体が読むので、zsh を経由しない実行でも効く |
| `~/.zshenv`（`dot_zshenv.tmpl`） | `TF_PLUGIN_CACHE_DIR` | zsh を起点とする全プロセス（非インタラクティブ含む） |

両方に同じパスを書いている。**環境変数のほうが CLI 設定ファイルより優先される**ため、
仮に食い違っても環境変数側の値が使われる。

### ディレクトリは事前に作る

terraform はキャッシュディレクトリを自分では作らず、存在しないと
`Invalid plugin cache directory` で `init` が失敗する。
`chezmoi apply` 時に `run_onchange_after_36-terraform-plugin-cache.sh.tmpl` が `mkdir -p` する。

### 依存ロックファイルとの関係

terraform はロックファイル（`.terraform.lock.hcl`）のチェックサムと一致する
キャッシュのみを使うので、キャッシュを有効にしてもロックファイルの整合性は保たれる。
`plugin_cache_may_break_dependency_lock_file` は公式が「例外的な状況専用・将来のバージョンでは
無視される」としているため設定していない。

## tf-cache-prune

terraform はキャッシュに置いた provider を**自分では削除しない**ので、古いバージョンが
溜まり続ける。掃除は `tf-cache-prune`（`dot_local/bin/executable_tf-cache-prune`）で行う。

```sh
tf-cache-prune                # ドライラン: provider ごとのサイズ・バージョン一覧と削除候補
tf-cache-prune -y             # 各 provider の最新 1 バージョンだけ残して削除
tf-cache-prune --keep 2 -y    # 最新 2 バージョンを残す
tf-cache-prune --all -y       # キャッシュを丸ごと空にする
```

| オプション | 意味 |
| --- | --- |
| `--keep N` | provider ごとに残す最新バージョン数（既定: 1） |
| `--all` | キャッシュを丸ごと空にする |
| `-y` / `--yes` | 実際に削除する。**付けない限りドライラン** |
| `-h` / `--help` | ヘルプ |

出力例:

```
terraform provider cache: /Users/you/.cache/terraform/plugin-cache (合計 1.2G)

registry.terraform.io/hashicorp/aws
  delete  5.9.0                  300M
  delete  5.20.0                 310M
  keep    5.31.0                 320M

削除対象: 2 バージョン / 約 610M
ドライランです。実際に削除するには -y を付けてください。
```

ポイント:

- キャッシュの構造は `<host>/<namespace>/<name>/<version>/<os_arch>/` で、
  `<version>` の階層を単位に削除する。
- 新旧の比較は `sort -V`（辞書順ではないので `5.9.0 < 5.20.0 < 5.31.0` が正しく並ぶ）。
- 削除で空になった `<name>` / `<namespace>` / `<host>` の階層も畳む。
- **削除するとリンク切れが起きる。** キャッシュは symlink の実体側なので、消した provider を
  使っていたプロジェクトは `.terraform/providers/` が壊れる。そのプロジェクトで
  `terraform init` をやり直せば復旧する。

## バージョン管理（tenv）

| 変数 / コマンド | 役割 |
| --- | --- |
| `tenv` | Terraform / OpenTofu のバージョン管理（aqua 管理パッケージ） |
| `TENV_AUTO_INSTALL=true` | 必要なバージョンを自動インストール（`40-tools.zsh`） |
| `TENV_VALIDATION=sha` | ダウンロードを SHA で検証（`40-tools.zsh`） |

## エイリアス・補完

| 項目 | 内容 |
| --- | --- |
| `tf` | `terraform` のエイリアス（`40-tools.zsh`、terraform がある場合のみ） |
| 補完 | terraform は bash 動的補完（`complete -o nospace -C terraform terraform`）。tenv は fpath へ事前生成 |

## トラブルシュート

| 症状 | 対処 |
| --- | --- |
| `Invalid plugin cache directory` | キャッシュディレクトリが無い。`chezmoi apply` するか `mkdir -p "$TF_PLUGIN_CACHE_DIR"` |
| `.terraform/providers` のリンク切れ | `tf-cache-prune` で消した後に起きる。該当プロジェクトで `terraform init` |
| キャッシュが効いていない | `echo $TF_PLUGIN_CACHE_DIR` を確認。空なら `.zshenv` が読まれていない（新しいシェルを開く） |
| キャッシュを一時的に無効化したい | `TF_PLUGIN_CACHE_DIR= terraform init`（その実行だけ空にする） |

## 関連

- [uv-cheatsheet.md](uv-cheatsheet.md) — 同じ流儀の `uv-cache-prune`（uv のキャッシュ掃除）
