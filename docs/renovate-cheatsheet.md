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
| 共有ストアの agmsg（`bootstrap/22-shared-agmsg.sh` の `AGMSG_VERSION="<ver>"` と、直後の行の `AGMSG_COMMIT="<40桁>"`） | `customManagers`（datasource `github-tags`、`depName` は `fujibee/agmsg`、タグの `v` は `extractVersionTemplate` で外す）。2 行を 1 つの `matchStrings` で拾い、`AGMSG_COMMIT` は `currentDigest` として `autoReplaceStringTemplate` で版と一緒に書き換える。2 行の間に行を挟むと拾えない |
| Kiro CLI（`aqua.yaml` の `kiro.dev/kiro-cli@<ver>`、`registry: local`） | `customManagers` + `customDatasources.kiro`。aqua preset は `kiro.dev/...` を拾わないので専用に拾う。Kiro は GitHub Releases が無く、配布元の `manifest.json`（最新版だけを返す）を datasource にする。公開日時が無いので `minimumReleaseAgeBehaviour: timestamp-optional` |
| Codex（`aqua.yaml` の `openai/codex@rust-v<ver>`） | preset の専用 manager（タグの `rust-` を外して扱う）。同じ行を汎用 manager も `rust-v...` のまま拾い、タグ名が合わず誤った版を出すので、`packageRules` で `matchCurrentValue: /^rust-/` の汎用側を止める |
| 共有ストアの Terraform の版（`bootstrap/tenv-versions.txt`） | 追わない。プロジェクトの `required_version` と揃えて手で更新する |

agmsg の PR は、版と commit の両方が変わっているか確かめてからマージする（`bootstrap/22-shared-agmsg.sh` は、取得した tag の commit が `AGMSG_COMMIT` と違えば置かないので、片方だけ上がると共有側の更新が失敗する）。digest が更新されなかったときは、`curl -s https://api.github.com/repos/fujibee/agmsg/git/refs/tags/v<ver>` の `object.sha` を手で書く（注釈付きタグなら `git/tags/<sha>` の `object.sha`）。

`NPM_GLOBALS` に足すときは、Renovate に拾わせたいなら 1 パッケージ 1 行で
`NPM_GLOBALS="$NPM_GLOBALS <pkg>@<ver>"` と書く（scope 付き `@scope/pkg@<ver>` も可）。`UV_TOOLS` も同様に
`UV_TOOLS="$UV_TOOLS <pkg>[extra,...]==<ver>"` と 1 パッケージ 1 行で書く。

## PR のまとめ方

- **minor / patch は種別を問わず 1 本の PR（`groupName: deps`）にまとめる。** タイトルは
  `chore(deps): 依存を更新する`。major は従来どおり依存ごとに別の PR になる。
- まとめた PR の本文には `prBodyNotes` で「マージ後、どのマシンでも誰か 1 人が `chezmoi update` すれば
  共有ストアが揃い、他のユーザは次の起動から新しい版を使う」旨を足す（`docs/shared-store-cheatsheet.md`）。
- monorepo 単位の既定グループ（`group:monorepos`）は外してある。グループは上の `deps` だけ。
- **新しい PR を作るのは月曜 0〜8 時台（Asia/Tokyo）だけ。** 既に開いている PR の rebase や
  追加の更新の積み増しは毎回の実行で行う。
- aqua.yaml を変えた PR では `update-aqua-checksum.yaml` が `aqua-checksums.json` を作り直して
  同じブランチへ push する（まとめた PR でも同じ）。作るのは `aqua.yaml` の `checksum.supported_envs`
  （darwin / linux）の分だけ。Windows では aqua を使わないため、registry の Windows 版の定義が
  配布物と合わなくても（direnv v2.38 の `.exe` など）止まらない。

## 版を止める・外す

`packageRules` に依存ごとの例外を書く。いまあるもの:

| 依存 | 扱い | 理由 |
| --- | --- | --- |
| `1password/cli` | 更新しない | GitHub リリースが無く版を解決できない |
| `simulot/immich-go` | `<1.0.0` | v 無しの古いタグ `1.21.3` を最新と誤認するため |

## 設定を変えたら

```sh
npx --yes --package renovate -- renovate-config-validator --strict .github/renovate.json
bash tests/renovate/regex.test.sh   # customManagers の正規表現を対象ファイルへ当てる（bash tests/run.sh にも入っている）
```

`tests/renovate/regex.test.sh` は、`renovate.json` の `matchStrings` を Python の `re` に直して（JS 風の
`(?<name>` を `(?P<name>` へ）、NPM_GLOBALS / UV_TOOLS / RUST_VERSION / AGMSG_* / Kiro が期待どおりの
`depName` と `currentValue` で拾われることを確かめる。manager や対象行の書き方を変えたら一緒に直す。

マージ後は Dependency Dashboard（issue）から実際にどう拾われたか確認できる。
