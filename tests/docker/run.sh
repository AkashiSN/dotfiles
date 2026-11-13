#!/usr/bin/env bash
# 共有ストア（/opt）を Linux（docker）の 2 ユーザで通しで確かめる。ホストの /opt やホームには触らない。
#
#   tests/docker/run.sh [unit|e2e|all] [--keep] [--token]
#     unit     コンテナの中で bash tests/run.sh を alice で流す（Linux の /proc と ps の分岐）
#     e2e      tests/docker/scenario.sh の通し（既定）。alice / bob の順序、sudo を使えない apply、
#              使用中の古い版、未認証の gh、origin/main の無いクローン
#     all      unit のあとに e2e
#     --keep   終わってもコンテナを消さない（docker exec -it <名前> bash で調べ、docker rm -f で消す）
#     --token  呼び出し元の環境変数 GITHUB_TOKEN をコンテナへ渡す（値は引数にもファイルにも書かない）。
#              例: GITHUB_TOKEN="$(gh auth token)" tests/docker/run.sh --token
#
# ソースは作業ツリーの追跡ファイル（未コミットの変更を含む。git stash create）。未追跡のファイルは入らない。
# コンテナの中では bare リポジトリ /srv/dotfiles.git を origin にし、alice / bob が chezmoi init --apply する。
# ログは最後に表示する一時ディレクトリへ取り出す。終了コードは失敗した確認があれば 1。
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
image=dotfiles-e2e:local
name="dotfiles-e2e-$$"

mode=e2e
keep=0
token=0
for a in "$@"; do
	case "$a" in
	unit | e2e | all) mode="$a" ;;
	--keep) keep=1 ;;
	--token) token=1 ;;
	-h | --help)
		sed -n '2,15p' "$0"
		exit 0
		;;
	*)
		echo "不明な引数: $a" >&2
		exit 2
		;;
	esac
done
if [ "$token" -eq 1 ] && [ -z "${GITHUB_TOKEN:-}" ]; then
	echo "--token には環境変数 GITHUB_TOKEN が要ります" >&2
	exit 2
fi

out="$(mktemp -d)"
# shellcheck disable=SC2329  # trap から呼ぶ
cleanup() {
	if [ "$keep" -eq 1 ]; then
		echo "コンテナを残しました: ${name}（docker rm -f ${name} で消す）"
	else
		docker rm -f "$name" >/dev/null 2>&1 || true
	fi
}
trap cleanup EXIT

echo "==> イメージを作る ($image)"
docker build -q -t "$image" "$here" >/dev/null

# 作業ツリーの追跡ファイル（未コミットを含む）を 1 コミットにして bundle へ入れる。
rev="$(git -C "$repo" stash create)"
[ -n "$rev" ] || rev="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" update-ref refs/e2e/src "$rev"
git -C "$repo" bundle create "$out/repo.bundle" refs/e2e/src >/dev/null 2>&1
git -C "$repo" update-ref -d refs/e2e/src

echo "==> コンテナを起動 ($name)"
envs=()
[ "$token" -eq 0 ] || envs=(-e GITHUB_TOKEN)
# root が他ユーザのプロセスの /proc/<pid>/exe を読むには CAP_SYS_PTRACE が要る（docker の既定では外れている）。
# 実機の root は持っているので、使用中の判定（bootstrap/lib.sh の running_*）を実機と同じ条件で確かめるために足す。
docker run -d --cap-add SYS_PTRACE --name "$name" ${envs[@]+"${envs[@]}"} "$image" >/dev/null
docker exec "$name" mkdir -p /work
docker cp "$out/repo.bundle" "$name:/work/repo.bundle"
docker cp "$here/scenario.sh" "$name:/work/scenario.sh"

rc=0
docker exec "$name" bash /work/scenario.sh "$mode" || rc=$?
docker cp "$name:/work/logs" "$out/logs" >/dev/null 2>&1 || true
rm -f "$out/repo.bundle"
echo "ログ: $out/logs"
exit "$rc"
