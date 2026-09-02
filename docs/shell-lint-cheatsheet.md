# シェルスクリプト lint / format チートシート

`shellcheck` による静的解析と `shfmt` による整形。どちらも aqua 管理パッケージ。

対象ファイル: `dot_config/aquaproj-aqua/aqua.yaml`

## shellcheck

クォート漏れ・未定義変数・移植性の問題など、**動いてしまうが壊れている書き方**を拾う。

| コマンド | 役割 |
| --- | --- |
| `shellcheck FILE...` | 検査（既定は該当行を添えた表示） |
| `shellcheck -f gcc FILE...` | 1 issue 1 行（`file:line:col: level: msg [SCxxxx]`）。grep しやすい |
| `shellcheck -S error FILE...` | 指定レベル以上に絞る（`style` < `info` < `warning` < `error`） |
| `shellcheck -s bash FILE` | shebang を無視してシェルを指定 |
| `shellcheck -x FILE` | `source` 先のファイルも辿って検査 |
| `shellcheck -e SC2086 FILE` | 特定のコードを除外（`-i` は逆に指定したものだけ） |

issue が残ると終了コードが非ゼロになる。

### 指摘を抑制する

意図した書き方だと分かっているものは、**その行の直前**に理由付きで抑制する。

```sh
# ツールを足す場所なので、いまは 1 つでもループのままにする。
# shellcheck disable=SC2043
for tool in \
	ansible
```

shebang の直後に置くとファイル全体に効く。

### nvim との関係

nvim の `bashls`（mason 管理）は **PATH 上に `shellcheck` があれば自動で使う**。aqua で入れて
あるのはこれも兼ねている（mason の `ensure_installed` には含めない。
[nvim-cheatsheet.md](nvim-cheatsheet.md)）。

## shfmt

シェルスクリプトの整形。

| コマンド | 役割 |
| --- | --- |
| `shfmt -d FILE...` | 差分を表示（書き換えない） |
| `shfmt -l DIR` | 整形が要るファイルを列挙 |
| `shfmt -w FILE...` | 上書きして整形 |
| `shfmt -i 2 FILE` | インデントをスペース 2 に（既定の `-i 0` はタブ） |
| `shfmt -s FILE` | 簡約もする（`${a}` → `$a` など） |

> **リポジトリ全体へ `-w` をかけないこと。** タブ派・2 スペース派・4 スペース派が混在しており
> （どの `-i` を指定しても大半のファイルが `-l` に出る）、一括整形すると無関係な差分でコミットが
> 埋まる。触っているファイルだけを、そのファイルの既存の書き方に合わせた `-i` で整形する。

## このリポジトリを検査するときの注意

| 対象 | 扱い |
| --- | --- |
| `dot_local/bin/executable_*`（`#!/bin/bash` / `#!/bin/sh`） | そのまま検査できる |
| `private_dot_claude/hooks/executable_*.sh` | そのまま検査できる |
| `dot_local/bin/executable_portfwd` / `executable_*.py` / `executable_dji_workflow.py` | **Python スクリプト**。shellcheck は `SC1071` で解析自体を拒否し、shfmt も構文エラーになる。除外して `ruff` を使う |
| `.chezmoiscripts/*.sh.tmpl` | **Go テンプレートなので直接は検査できない。** `{{ template "shell-log" }}` のような記述が `SC1009` / `SC1054` / `SC1073` になる。展開してから通す（下記） |

シェルスクリプトをまとめて検査する（Python 製のものを除く）:

```sh
git ls-files 'dot_local/bin/executable_*' 'private_dot_claude/hooks/executable_*' \
  | grep -vE '\.py$|portfwd$' | xargs shellcheck -f gcc
```

> zsh では `$(...)` の結果が単語分割されないので、`shellcheck -f gcc $(git ls-files ...)` と
> 書くと全部つなげた 1 つのファイル名として渡り `does not exist` になる。上のように
> `xargs` へ渡すか `${(f)...}` で分割する。

`.chezmoiscripts` は `chezmoi execute-template` で展開してから渡す（`--source` を指すのは
`.chezmoitemplates/` の共有テンプレートを解決させるため）:

```sh
chezmoi execute-template --source "$PWD" < .chezmoiscripts/run_onchange_after_35-uv-tools.sh.tmpl \
  | shellcheck -f gcc -
```

## バージョンと配布

`dot_config/aquaproj-aqua/aqua.yaml` でピンし、`aqua-checksums.json` に sha256 を記録している。
版を足す / 上げるときは `aqua update-checksum -deep -prune` を
`dot_config/aquaproj-aqua` で回す（Renovate の PR では GitHub Actions が同じことをする。
`.github/workflows/update-aqua-checksum.yaml`）。

> 検証の強さはパッケージで違う。`mvdan/sh`（shfmt）は上流が公開する checksum をレジストリ
> 経由で検証する。`koalaman/shellcheck` はレジストリに検証設定が無いので、
> `aqua-checksums.json` に記録した sha256 だけが担保になる（`terraform-linters/tflint` は
> checksum に加えて GitHub Artifact Attestation と cosign も検証する）。

## 関連

- [nvim-cheatsheet.md](nvim-cheatsheet.md) — bashls / ruff（エディタ側の診断）
- [terraform-cheatsheet.md](terraform-cheatsheet.md) — 同じく aqua 管理の linter `tflint`
