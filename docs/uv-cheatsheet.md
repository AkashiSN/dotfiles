# uv チートシート

Python パッケージ / CLI ツール管理（**uv**、aqua 管理パッケージ）と、そのキャッシュの掃除。

対象ファイル: `.chezmoiscripts/run_onchange_after_35-uv-tools.sh.tmpl` /
`dot_local/bin/executable_uv-cache-prune`

## uv 管理の CLI ツール

Python 製の CLI は `uv tool install` で入れる（venv が分離されるので依存が衝突しない）。
インストールするツールは `run_onchange_after_35-uv-tools.sh.tmpl` のリストで宣言し、
`chezmoi apply` で冪等に導入される。バイナリは `~/.local/bin` に置かれる。

| コマンド | 役割 |
| --- | --- |
| `uv tool list` | 導入済みツールの一覧 |
| `uv tool install <pkg>` | ツールを追加（スクリプトのリストに書けば apply で自動化される） |
| `uv tool upgrade --all` | 全ツールを更新 |
| `uv tool uninstall <pkg>` | ツールを削除 |

> uv 本体は aqua（`dot_config/aquaproj-aqua/aqua.yaml`）で管理。ツールを恒久的に追加する
> ときは、手で `uv tool install` するだけでなくスクリプトのリストにも追記すること。

## uv 管理の Python

同じスクリプトの末尾で、**tomllib を持つ Python（3.11+）を 1 つ確保**する。

```sh
uv python find '>=3.11' >/dev/null 2>&1 || uv python install 3.13
```

macOS 同梱の `python3` は 3.9 で `tomllib` が無く、`codex-bedrock` が
`~/.codex/config.toml` に Bedrock オーバレイを被せるときに TOML パーサを使えない
（詳細は [zsh チートシート](zsh-cheatsheet.md#codex-bedrock-が一時-codex_home-を使う理由)）。
条件を満たす処理系が既にあれば何もしないので、余計なダウンロードは起きない。

| コマンド | 役割 |
| --- | --- |
| `uv python list` | 導入済み / ダウンロード可能な Python の一覧 |
| `uv python find '>=3.11'` | 条件を満たす処理系のパスを返す（未導入ならダウンロードせず失敗） |
| `uv python install <ver>` | 指定バージョンを導入 |

## キャッシュ

uv はダウンロードした wheel / sdist・展開済みアーカイブ・ビルド済み環境を
`~/.cache/uv`（`uv cache dir` で確認、`UV_CACHE_DIR` で変更可）に貯める。
放っておくと数百 MB〜数 GB になる。

主なバケット:

| バケット | 中身 |
| --- | --- |
| `archive-v0` | 展開済みパッケージの実体。**通常ここが一番大きい** |
| `environments-v2` | `uv run` / `uvx` が作った一時環境 |
| `simple-vNN` | パッケージインデックスのレスポンス。`NN` は uv 側のフォーマット版 |
| `wheels-v6` / `sdists-v9` | ダウンロードした配布物 |
| `interpreter-v4` | 検出した Python インタプリタの情報 |

**キャッシュを消しても作成済みの venv は壊れない。** uv はキャッシュから venv へ
ハードリンク / CoW で展開するため、キャッシュ側を消してもリンク先の実体は残る
（terraform の provider キャッシュが symlink で参照されるのとは異なる）。
影響は「次回の同期で再ダウンロードが要る」だけ。

## uv-cache-prune

```sh
uv-cache-prune           # ドライラン: キャッシュ先・合計サイズ・バケット別の内訳を表示
uv-cache-prune -y        # uv cache prune（未参照エントリと不要になった環境を削除）
uv-cache-prune --all -y  # uv cache clean（キャッシュを丸ごと削除）
```

| オプション | 意味 |
| --- | --- |
| `--all` | 丸ごと削除（`uv cache clean`） |
| `-y` / `--yes` | 実際に削除する。**付けない限りドライラン** |
| `-h` / `--help` | ヘルプ |

出力例:

```
uv cache: /Users/you/.cache/uv (合計 467M)

  archive-v0                   450M
  environments-v2              7.8M
  simple-v21                   4.7M
  simple-v24                   4.2M
  ...

実行されるコマンド: uv cache prune
ドライランです。実際に削除するには -y を付けてください。
```

ポイント:

- **削除は uv 本体（`uv cache prune` / `uv cache clean`）に任せている。** どのエントリが
  まだ参照されているかは uv しか判断できないため、スクリプトはディレクトリを直接消さない。
  スクリプトが足しているのは「サイズと内訳の可視化」「ドライラン既定」「解放量の表示」。
- キャッシュ先は `uv cache dir` から取るので、`UV_CACHE_DIR` や `uv.toml` の設定も反映される。
- `prune` は未参照エントリだけを消すので、日常的にはこちらで足りる。古い `simple-vNN` の
  ような世代違いのバケットごと落としたいときは `--all`。

## 関連

- [terraform-cheatsheet.md](terraform-cheatsheet.md) — 同じ流儀の `tf-cache-prune`
  （ただし terraform のキャッシュは symlink 参照なので、消すと `terraform init` のやり直しが要る）
