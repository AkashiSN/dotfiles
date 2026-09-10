# work 用 dotfiles との同期

この dotfiles には対になる **work 用 dotfiles**（`github.kddi.com/kddi-cdx/cloudsa-dotfiles`）が
ある。同じ役割のスクリプトを両方が持っていて、片方で直した改良をもう一方へ運ぶ。ここはその
運び方と、揃えると決めた規約をまとめたもの。

## リポジトリの場所

| どれ | 場所 | 用途 |
| --- | --- | --- |
| このリポジトリ | `~/.local/share/chezmoi` | 個人用。**公開リポジトリ**（`github.com/AkashiSN/dotfiles`） |
| work（実体） | `cloudsa:/home/su-nishi/Project/src/github.kddi.com/kddi-cdx/cloudsa-dotfiles` | 作業も commit もここでする |
| work（手元の読み取り用クローン） | `~/Project/src/github.kddi.com/kddi-cdx/cloudsa-dotfiles` | 比較用。`git pull` で GHE から引くだけ |

`cloudsa` への SSH は `ssm-proxy.sh` 経由なので、先に AWS の認証が要る
（[aws-cheatsheet.md](aws-cheatsheet.md#aws-auth-ensure)）。

```sh
aws-auth-ensure cdx-arise-pre-dev "ssh cloudsa"
ssh cloudsa
```

## 揃えると決めたこと

| 項目 | どちらに揃えるか | 理由 |
| --- | --- | --- |
| OS 依存の書き方（`ps` / `lsof` / `date` / bash 3.2） | **この dotfiles** | mac と Linux の両方で動く superset。work（Linux）でもそのまま動く |
| 整形 | **`shfmt` の既定（`-i 0` = タブ）** | フラグ無しで回せる。詳細は [shell-lint-cheatsheet.md](shell-lint-cheatsheet.md#このリポジトリの整形規約) |
| Bedrock 用 AWS プロファイル | **既定を持たず `~/.env` から解決** | 公開リポジトリにアカウント名を焼かない。意図しないアカウントを触らない |
| 環境固有の機能 | **揃えない** | work の AWS MCP / Grafana / EKS、こちらの superpowers / ghostty / 個人ツールなど。共有コアの外に置く |

**公開リポジトリへ持ち込まないもの**: 業務アカウント名・ホスト名・社内 URL・runbook の類。
work から取り込むときは、コード本体だけを取ってコメントの固有名詞は落とす。

## work → こちらへ取り込む

work 側の変更は GHE に push されているので、手元のクローンを更新してから読む。

```sh
D=~/Project/src/github.kddi.com/kddi-cdx/cloudsa-dotfiles
git -C "$D" pull
git -C "$D" log --oneline -10
git -C "$D" show <commit>
```

まだ push されていないなら、サーバで直接見る:

```sh
ssh cloudsa 'cd /home/su-nishi/Project/src/github.kddi.com/kddi-cdx/cloudsa-dotfiles && git log --oneline -5'
```

取り込むときは**そのまま貼らない**。この repo 側の携帯実装（`ps` / BSD `date` 互換）と、
公開リポジトリに置けない固有名詞を落としたうえで移植する。移植したら mac で実際に動かし、
`shellcheck` と `shfmt -l` を通してからコミットする。

## こちらから work へ配る

work は `scp` で直接置き換える（実体はサーバ側）。

```sh
R=/home/su-nishi/Project/src/github.kddi.com/kddi-cdx/cloudsa-dotfiles
scp dot_local/bin/executable_aws-login "cloudsa:$R/dot_local/bin/executable_aws-login"

ssh cloudsa "export PATH=\$HOME/.local/share/aquaproj-aqua/bin:\$PATH; cd $R \
  && git diff --name-only | xargs shellcheck -f gcc \
  && git diff --name-only | xargs shfmt -l \
  && git status --porcelain"
```

コミットメッセージは長くなるのでファイルにして渡す（`scp msg.txt cloudsa:/tmp/` →
`git commit -F /tmp/msg.txt`）。**push は自分でする**。

## 差分の測り方

work のツリーを手元へ取ってから、コメントと空行を除いた行数で並べる。整形は揃えてあるので、
ここに出る行がそのまま「実装の違い」になる。

```sh
SP=$(mktemp -d)
scp -q -r cloudsa:/home/su-nishi/Project/src/github.kddi.com/kddi-cdx/cloudsa-dotfiles/dot_local/bin "$SP/work-bin"

for f in "$SP"/work-bin/*; do
  n=$(basename "$f")
  [ -f "dot_local/bin/$n" ] || continue
  c=$(diff -u "$f" "dot_local/bin/$n" | grep '^[+-][^+-]' | sed 's/^[+-][[:space:]]*//' | grep -vc '^\(#\|$\)')
  [ "$c" -gt 0 ] && printf '%4s  %s\n' "$c" "$n"
done | sort -rn
```

`0` 行のファイルは byte 単位で同じか、コメントだけの差。片側にしか無いファイルは
`diff -rq --exclude=.git` の `Only in` で見る。

## 経緯

2026-09-10 に、それまで別々に育っていた共有スクリプトを次の 3 段階で揃えた。

1. 両リポジトリを `shfmt` の既定（タブ）へ一括整形（このリポジトリ `8f7c21c` / work `0abc44f`）
2. OS 依存の実装をこのリポジトリの移植版へ統一（work `f273518`）
3. Bedrock 用プロファイルの既定ハードコードを外し `~/.env` 解決へ（このリポジトリ `ab2a248` / work `afc2750`）

これで `dot_local/bin` の共有スクリプトはコメントを含めてほぼ同一になり、以後は差分＝実装の
違いだけになる。
