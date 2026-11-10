# Renovate チートシート

依存の版を上げる PR は GitHub App の Renovate が出す。設定は `.github/renovate.json` だけで、
実行は Renovate 側（このリポジトリに workflow は無い）。

## 何を追っているか

| 対象 | 拾い方 |
| --- | --- |
| `dot_config/aquaproj-aqua/aqua.yaml` の registry と packages | preset `github>aquaproj/aqua-renovate-config` |
| `.github/workflows/*` の action | `config:recommended`（github-actions manager） |
| Intel Mac のフォント（`run_onchange_before_10-install-packages.sh.tmpl` の `*_VERSION`） | `customManagers`。直前の行の `# renovate: datasource=... depName=...` コメントで取得元を決める |
| 共有ストアの npm の CLI（`bootstrap/23-shared-npm.sh` の `NPM_GLOBALS="$NPM_GLOBALS <pkg>@<ver>"`。difit / cline） | `customManagers`（datasource `npm`）。`@<ver>` を付けた行だけを拾うので、版を固定しないものは追わない |
| 共有ストアの uv の CLI（`bootstrap/24-shared-uv.sh` の `UV_TOOLS="$UV_TOOLS <pkg>[extra,...]==<ver>"`。ansible / graphifyy） | `customManagers`（datasource `pypi`）。`depName` は extra を除いたパッケージ名。`==<ver>` を付けた行だけを拾う |
| 共有ストアの Rust の toolchain（`bootstrap/25-shared-rust.sh` の `RUST_VERSION="<ver>"`） | `customManagers`（datasource `github-releases`、`depName` は `rust-lang/rust`）。Rust のリリースタグ（`1.99.1`）を追う |

`NPM_GLOBALS` に足すときは、Renovate に拾わせたいなら 1 パッケージ 1 行で
`NPM_GLOBALS="$NPM_GLOBALS <pkg>@<ver>"` と書く（scope 付き `@scope/pkg@<ver>` も可）。`UV_TOOLS` も同様に
`UV_TOOLS="$UV_TOOLS <pkg>[extra,...]==<ver>"` と 1 パッケージ 1 行で書く。

## PR のまとめ方

- **minor / patch は種別を問わず 1 本の PR（`groupName: deps`）にまとめる。** タイトルは
  `chore(deps): 依存を更新する`。major は従来どおり依存ごとに別の PR になる。
- monorepo 単位の既定グループ（`group:monorepos`）は外してある。グループは上の `deps` だけ。
- **新しい PR を作るのは月曜 0〜8 時台（Asia/Tokyo）だけ。** 既に開いている PR の rebase や
  追加の更新の積み増しは毎回の実行で行う。
- aqua.yaml を変えた PR では `update-aqua-checksum.yaml` が `aqua-checksums.json` を作り直して
  同じブランチへ push する（まとめた PR でも同じ）。

## 版を止める・外す

`packageRules` に依存ごとの例外を書く。いまあるもの:

| 依存 | 扱い | 理由 |
| --- | --- | --- |
| `1password/cli` | 更新しない | GitHub リリースが無く版を解決できない |
| `simulot/immich-go` | `<1.0.0` | v 無しの古いタグ `1.21.3` を最新と誤認するため |

## 設定を変えたら

```sh
npx --yes --package renovate -- renovate-config-validator --strict .github/renovate.json
```

マージ後は Dependency Dashboard（issue）から実際にどう拾われたか確認できる。
