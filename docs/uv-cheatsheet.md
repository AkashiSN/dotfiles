# uv チートシート

Python パッケージ / CLI ツール管理（**uv**、aqua 管理パッケージ）と、そのキャッシュの掃除。

対象ファイル: `dot_config/uv/dot_python-version` /
`bootstrap/24-shared-uv.sh` / `.chezmoiscripts/run_after_35-uv-tools.sh.tmpl` /
`.chezmoitemplates/uv-cleanup.sh` / `dot_local/bin/executable_uv-cache-prune`

## 共有の Python と CLI ツール

既定の Python と、`uv tool` で配る CLI（ansible / graphify）は、root が `/opt/uv` に 1 組だけ置く
（`bootstrap/24-shared-uv.sh`。構成と手動操作は [shared-store-cheatsheet.md](shared-store-cheatsheet.md#uv-の-python-と-cli)）。
一覧と版は同スクリプトの `UV_TOOLS="$UV_TOOLS <pkg>[extra,...]==<ver>"` の行で固定し（Renovate が上げる）、
Python の版は `dot_config/uv/dot_python-version` の 1 か所。PATH は `~/.config/shell/env.sh` が、
`/opt/uv/bin` と `/opt/dotfiles-shared/keys/24` が在るときだけ `~/.local/bin` の後ろに足す。

`run_after_35-uv-tools.sh.tmpl`（毎回実行）の役目はユーザ側だけ。

- **共有側が揃っている間**: 取得せず、ホームの uv の掃除だけ行う（`.chezmoitemplates/uv-cleanup.sh`）。
  共有へ移したツール（`UV_TOOLS` の名前）の実体と `~/.local/bin` の symlink を消し、ユーザが自分で
  `uv tool install` したツールとその symlink は残す。残るツールが無ければホームの uv の Python と
  `python3` などの symlink も消す。ホームの uv の Python やツールが動いている間（実行ファイルが
  `~/.local/share/uv` の下、macOS の `ps` が出すリンクのパス、引数にスクリプトのパス）は何も消さず次の apply へ回す。
- **揃っていない間**（sudo を使えなかったなど）: 従来どおり `uv python install --default` と `UV_TOOLS` の各行を
  `uv tool install` でユーザ単位に入れる。`~/.cache/dotfiles/uv-user.key` のマーカーは成功したときだけ進める。ホームのものは消さない。

| コマンド | 役割 |
| --- | --- |
| `uv tool list` | 導入済みツールの一覧（共有のものは `UV_TOOL_DIR=/opt/uv/tools uv tool list`） |
| `uv tool install <pkg>` | 自分用のツールを追加（ホームへ入る。共有へ足すなら `UV_TOOLS` に行を足す） |
| `uv tool uninstall <pkg>` | 自分で入れたツールを削除 |

> uv 本体は aqua（`dot_config/aquaproj-aqua/aqua.yaml`）で管理。共有のツールを `uv tool upgrade` で
> 手更新しない（共有側は root だけが書く）。版を上げるときは `UV_TOOLS` の行を書き換える。
> `ansible` パッケージが出すコマンドは `ansible-community` だけ（`ansible` / `ansible-playbook` は
> `ansible-core` のもので PATH に出ない）。

## uv 管理の Python

### 既定のバージョン

`~/.config/uv/.python-version`（ソースは `dot_config/uv/dot_python-version`）に **3.13** を
書いてある。uv はカレントディレクトリから上へ `.python-version` を探し、見つからなければ
このグローバル pin を使うので、`uv venv` / `uv run` / `uv tool install` などが既定で 3.13 を選ぶ。
宣言が無いと uv は導入済み / ダウンロード可能なものから勝手に選ぶため、新しい版を入れた
時点で解決先が黙って動く。

### PATH 上の python / python3

グローバル pin は uv 自身の解決にしか効かず、それだけでは PATH 上の `python3` は macOS 同梱の
3.9 のまま（`python` に至ってはどこにも無い）。そこで
`--default` 付きでインストールし、共有側では `/opt/uv/bin`、ユーザ単位の fallback では
`~/.local/bin` に `python` / `python3` / `python3.13` の symlink を置く。

```sh
uv python install 3.13 --default --preview-features python-install-default
```

`~/.local/bin` は `.zshenv`（`dot_zshenv.tmpl`）で `/usr/bin` より前に入る。**対話シェルだけの
`rc.d` ではなく `.zshenv` に置いてあるのは、ssh の一発実行・スクリプト・他ツールからの起動でも
同じ `python3` を引かせるため。** `/usr/bin/python3` は消さないので、shebang に絶対パスを
書いているものは影響を受けない。`#!/usr/bin/env python3` のスクリプトは uv の版で動く。

版の宣言は `dot_config/uv/dot_python-version` の 1 か所だけ。共有側は key（Python の版と `UV_TOOLS` のハッシュ）が
変わると新しい組を作り、ユーザ単位の fallback はテンプレート展開で版を埋め込む。
`--default` は uv でまだ experimental なため preview feature を明示している。

> 既定を変えるときは `uv python pin --global <ver>` を手で叩かず、
> `dot_config/uv/dot_python-version` を書き換えて `chezmoi apply` する（同じファイルを chezmoi が
> 管理しているので手で叩いても戻る）。`uv python find -v` に
> `Using Python request ... from version file at .../.config/uv/.python-version` が出れば効いている。

3.11+ を要求するものとして、`codex-bedrock` が `~/.codex/config.toml` に Bedrock オーバレイを
被せるとき `tomllib` を使う（詳細は
[zsh チートシート](zsh-cheatsheet.md#codex-bedrock-が一時-codex_home-を使う理由)）。

| コマンド | 役割 |
| --- | --- |
| `uv python find` | いま解決される Python のパスを表示 |
| `uv python list` | 導入済み / ダウンロード可能なバージョンの一覧 |
| `uv python pin <ver>` | **そのプロジェクトだけ**変える（カレントに `.python-version` を作る） |
| `uv python install <ver>` | バージョンを先に入れておく |

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

## 経緯

以前は `run_onchange_after_35-uv-tools.sh.tmpl` が、各ユーザの `~/.local/share/uv` に Python を入れ、
`uv tool install ansible` を実行していた。graphify は `run_after_40-ai-assistants.sh.tmpl` が
`uv tool install --upgrade graphifyy[sql,terraform]`（版は latest）で別に入れていた。共有ストア導入で、
版の固定を `UV_TOOLS` にまとめ、root が `/opt/uv` に 1 組だけ置く形へ移した。
