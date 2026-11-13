#!/usr/bin/env bash
# tests/docker/run.sh がコンテナの中（root）で流す、共有ストアの 2 ユーザ通し。
#   scenario.sh unit|e2e|all
# /work/repo.bundle（refs/e2e/src）を main にした bare リポジトリ /srv/dotfiles.git を origin にする。
# ピンを変えるのは jq（aqua.yaml の jqlang/jq）。起点を jq-1.8.0 にして、1.8.1 → 1.8.2 → 1.7.1 と動かす。
# 各確認は "PASS:" / "FAIL:" の 1 行で出し、ログは /work/logs に残す。
# shellcheck disable=SC2012  # ls は表示用（名前は版やキーだけ）
set -u

ORIGIN=/srv/dotfiles.git
LOGS=/work/logs
JQ_DIR=/opt/aquaproj-aqua/pkgs/github_release/github.com/jqlang/jq
STATE=/opt/dotfiles-shared/state
mkdir -p "$LOGS"
failures=0
seq=0

section() { printf '\n######## %s\n' "$1"; }
pass() { echo "PASS: $1"; }
failed() {
	echo "FAIL: $1"
	failures=$((failures + 1))
}
# check <説明> <コマンド...>: コマンドが 0 なら PASS。
check() {
	local d="$1"
	shift
	if "$@"; then pass "$d"; else failed "$d"; fi
}
# evidence <ファイル> <grep の正規表現>: 証跡として一致した行を出す（色と aqua の INF 行は落とす）。
evidence() {
	sed 's/\x1b\[[0-9;]*m//g' "$1" | grep -v ' INF ' | grep -E -- "$2" | sed 's/^/    > /' || true
}

# dot_gitconfig は https://github.com/ を SSH へ書き換えるが、コンテナのユーザは GitHub の SSH 鍵を持たない
# （docs/multi-user-cheatsheet.md の前提）。41-agent-browser の npx skills が clone する
# vercel-labs だけは、より長い一致で https のままにする。
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=url.https://github.com/vercel-labs/.insteadOf
export GIT_CONFIG_VALUE_0=https://github.com/vercel-labs/

# as <user> <command...>: そのユーザのログインシェルで流す。端末なし。GITHUB_TOKEN は引数に載せずに渡す。
as() {
	local u="$1"
	shift
	sudo --preserve-env=GITHUB_TOKEN,GIT_CONFIG_COUNT,GIT_CONFIG_KEY_0,GIT_CONFIG_VALUE_0 -iu "$u" "$@" </dev/null
}

# chez <user> <init|apply|update> [args...]: chezmoi を流し、ログを残して終了コードを返す。
LAST_LOG=""
chez() {
	local u="$1" cmd="$2" rc=0 strs
	shift 2
	seq=$((seq + 1))
	LAST_LOG="$LOGS/$(printf '%02d' "$seq")-$u-$cmd.log"
	if [ "$cmd" = init ]; then
		strs="work サーバのユーザ名（使わないなら空のまま Enter）=,work サーバのインスタンス ID=,work サーバでの uid=,work サーバへ ssh するときの AWS プロファイル=,work 用 GitHub Enterprise のホスト名=,Bedrock を呼ぶときの AWS プロファイル=,git の名前=$u,git のメールアドレス=$u@example.invalid,git の署名鍵（SSH 公開鍵。署名しないなら空）="
		as "$u" chezmoi init --apply --promptString "$strs" \
			--promptBool "個人のホストと鍵（AkashiSN）を使うか=false" "$@" "file://$ORIGIN" >"$LAST_LOG" 2>&1 || rc=$?
	else
		as "$u" chezmoi "$cmd" "$@" >"$LAST_LOG" 2>&1 || rc=$?
	fi
	echo "  ($u: chezmoi $cmd → 終了コード $rc, ログ $LAST_LOG)"
	return "$rc"
}

# bump <jq の版>: origin の main に jq のピンを変えるコミットを積み、その sha を出す。
# aqua-checksums.json には linux の 2 アーキテクチャ分の checksum を足す（require_checksum のため）。
bump() {
	local v="$1" w
	w="$(mktemp -d)"
	git clone -q "$ORIGIN" "$w/r"
	sed -i -E "s|^(  - name: jqlang/jq@)[^ ]+|\1$v|" "$w/r/dot_config/aquaproj-aqua/aqua.yaml"
	python3 - "$v" "$w/r/dot_config/aquaproj-aqua/aqua-checksums.json" <<'PY'
import hashlib, json, sys, urllib.request
v, p = sys.argv[1], sys.argv[2]
d = json.load(open(p))
ids = {c["id"] for c in d["checksums"]}
for asset in ("jq-linux-arm64", "jq-linux-amd64"):
    i = f"github_release/github.com/jqlang/jq/{v}/{asset}"
    if i in ids:
        continue
    b = urllib.request.urlopen(f"https://github.com/jqlang/jq/releases/download/{v}/{asset}").read()
    d["checksums"].append({"id": i, "checksum": hashlib.sha256(b).hexdigest().upper(), "algorithm": "sha256"})
d["checksums"].sort(key=lambda c: c["id"])
open(p, "w").write(json.dumps(d, indent=2) + "\n")
PY
	git -C "$w/r" -c user.name=e2e -c user.email=e2e@example.invalid commit -qam "test: jq を $v にする"
	git -C "$w/r" push -q origin HEAD:main
	git -C "$w/r" rev-parse HEAD
	rm -rf "$w"
}

state_commit() { sed -n 's/^commit=//p' "$STATE" 2>/dev/null; }
jq_versions() { ls "$JQ_DIR" 2>/dev/null | tr '\n' ' '; }
# has_only <版>: 共有側の jq の版がそれ 1 つだけなら 0。
has_only() { [ "$(jq_versions)" = "$1 " ]; }
# runall_count <user>: そのユーザが sudo で run-all.sh を流した回数。
runall_count() { grep -c " : $1 : .*COMMAND=.*bootstrap/run-all.sh" /var/log/sudo.log 2>/dev/null || true; }
# user_jq <user>: そのユーザのシェルで解決される jq の版。
user_jq() { as "$1" zsh -c 'jq --version' 2>&1; }
src_head() { as "$1" git -C "/home/$1/.local/share/chezmoi" rev-parse HEAD; }
# snapshot <file>: 共有側とホームのファイル一覧（掃除で消えたものが無いかを比べる）。
snapshot() {
	{
		find /opt -mindepth 1 -maxdepth 4 2>/dev/null
		find /home/bob/.local /home/bob/.cargo /home/bob/.agents -maxdepth 4 2>/dev/null
	} | grep -v -e '/\.cache/' -e '/\.local/share/chezmoi/' | sort >"$1"
}

setup_origin() {
	section "origin を用意（/srv/dotfiles.git、main = 検証するソース）"
	git init -q --bare -b main "$ORIGIN"
	git -C "$ORIGIN" fetch -q /work/repo.bundle refs/e2e/src:refs/heads/main
	# root 所有の bare リポジトリを各ユーザが clone できるようにする（ユーザのリポジトリは対象外）。
	git config --system --add safe.directory "$ORIGIN"
	git -C "$ORIGIN" log --oneline -1
}

run_unit() {
	section "Step 1: bash tests/run.sh（alice、Linux）"
	local log="$LOGS/unit.log" rc=0
	chmod 644 /work/repo.bundle
	as alice git init -q unit-src
	as alice git -C unit-src fetch -q /work/repo.bundle refs/e2e/src
	as alice git -C unit-src checkout -q FETCH_HEAD
	as alice bash -c 'cd unit-src && bash tests/run.sh' >"$log" 2>&1 || rc=$?
	grep -E '^(== |FAIL|ALL PASS)' "$log" | sed 's/^/    > /'
	check "tests/run.sh が Linux で全 PASS" [ "$rc" -eq 0 ]
	as alice rm -rf unit-src
}

run_e2e() {
	local base b1 b2 b3 pid snap_before snap_after
	chmod 644 /work/repo.bundle
	setup_origin
	base="$(bump jq-1.8.0)"
	echo "  起点: jq-1.8.0 ($base)"

	section "S1: alice が chezmoi init --apply（共有側を作る。sudo で run-all.sh を 1 回）"
	chez alice init
	check "S1: apply は 0 で終わる" [ $? -eq 0 ]
	evidence "$LAST_LOG" '共有|aqua|GITHUB_TOKEN|gh|失敗|見送|飛ばし'
	echo "  state: $(tr '\n' ' ' <"$STATE" 2>/dev/null)"
	echo "  jq の版: $(jq_versions)"
	ls -l /opt/dotfiles-shared/keys 2>/dev/null | sed 's/^/    > /'
	check "S1: state は origin/main ($base)" [ "$(state_commit)" = "$base" ]
	check "S1: 共有側に jq-1.8.0" [ -d "$JQ_DIR/jq-1.8.0" ]
	check "S1: alice の run-all.sh（sudo）は 1 回" [ "$(runall_count alice)" = 1 ]
	check "S1: /opt/aquaproj-aqua は root 所有" [ "$(stat -c %U /opt/aquaproj-aqua)" = root ]
	check "S1: alice の jq は 1.8.0" [ "$(user_jq alice)" = jq-1.8.0 ]
	local k
	for k in 20 21 22 23 24 25; do
		check "S1: keys/$k がある" [ -f "/opt/dotfiles-shared/keys/$k" ]
	done
	echo "  alice の which: $(as alice zsh -c 'which -a jq difit uv cargo terraform 2>&1' | tr '\n' ' ')"

	section "S2: bob が chezmoi init --apply（共有側に触らない）"
	chez bob init
	check "S2: apply は 0 で終わる" [ $? -eq 0 ]
	evidence "$LAST_LOG" '共有|失敗|見送|飛ばし'
	check "S2: bob は run-all.sh を流さない" [ "$(runall_count bob)" = 0 ]
	check "S2: state は変わらない" [ "$(state_commit)" = "$base" ]
	check "S2: bob の jq は共有の 1.8.0" [ "$(user_jq bob)" = jq-1.8.0 ]
	echo "  bob の pkgs: $(readlink /home/bob/.local/share/aquaproj-aqua/pkgs)"

	section "S3: origin の jq を 1.8.1 に上げ、alice が chezmoi update"
	b1="$(bump jq-1.8.1)"
	echo "  B1: $b1"
	chez alice update
	evidence "$LAST_LOG" '共有|jq|古い版|使用中|失敗'
	check "S3: state は B1" [ "$(state_commit)" = "$b1" ]
	check "S3: 共有側に jq-1.8.1" [ -d "$JQ_DIR/jq-1.8.1" ]
	check "S3: jq-1.8.0 は消える" [ ! -e "$JQ_DIR/jq-1.8.0" ]
	echo "  jq の版: $(jq_versions)"

	section "RF1: bob が pull せずに chezmoi apply（stale:behind-state、共有側は下がらない）"
	chez bob apply
	check "RF1: apply は 0 で終わる" [ $? -eq 0 ]
	evidence "$LAST_LOG" '共有|DOTFILES_SHARED_FORCE'
	echo "  bob の HEAD: $(src_head bob)（origin/main は $b1）"
	check "RF1: bob の checkout は古いまま" [ "$(src_head bob)" != "$b1" ]
	# fetch もしていないので、state のコミットは bob のクローンに無い（state-commit-unknown）。
	check "RF1: state-commit-unknown の警告（FORCE の案内つき）" grep -q '記録コミットがこの checkout に無いため.*DOTFILES_SHARED_FORCE=1' "$LAST_LOG"
	check "RF1: state は B1 のまま" [ "$(state_commit)" = "$b1" ]
	check "RF1: 共有側は jq-1.8.1 のまま（下がらない）" has_only jq-1.8.1
	echo "  bob の aqua which jq: $(as bob zsh -c 'aqua which jq' 2>&1)"
	check "RF1: bob の jq は新しい 1.8.1" [ "$(user_jq bob)" = jq-1.8.1 ]
	check "RF1: bob は run-all.sh を流さない" [ "$(runall_count bob)" = 0 ]
	echo "  bob が fetch だけして（merge しない）chezmoi apply"
	as bob git -C /home/bob/.local/share/chezmoi fetch -q origin
	chez bob apply
	evidence "$LAST_LOG" '共有|DOTFILES_SHARED_FORCE'
	check "RF1: behind-state の警告" grep -q 'この checkout より新しいコミットで更新済み' "$LAST_LOG"
	check "RF1: fetch 後も state は B1 のまま" [ "$(state_commit)" = "$b1" ]
	check "RF1: fetch 後も共有側は jq-1.8.1 のまま" has_only jq-1.8.1
	check "RF1: fetch 後も bob は run-all.sh を流さない" [ "$(runall_count bob)" = 0 ]

	section "RF3: bob が jq-1.8.1 を動かしたまま、alice が 1.8.2 へ上げる"
	rm -f /tmp/jqfifo
	mkfifo -m 666 /tmp/jqfifo
	as bob zsh -c 'exec jq . /tmp/jqfifo' >/dev/null 2>&1 &
	for _ in 1 2 3 4 5 6 7 8 9 10; do
		pid="$(pgrep -u bob -f 'jq . /tmp/jqfifo' | tail -n 1)"
		[ -n "$pid" ] && [ "$(readlink "/proc/$pid/exe" 2>/dev/null)" != "" ] && break
		sleep 1
	done
	echo "  bob の jq: pid=$pid exe=$(readlink "/proc/$pid/exe")"
	check "RF3: bob の jq は jq-1.8.1 の実体から動く" grep -q '/jq-1.8.1/' <<<"$(readlink "/proc/$pid/exe")"
	b2="$(bump jq-1.8.2)"
	echo "  B2: $b2"
	chez alice update
	evidence "$LAST_LOG" '古い版|使用中|jq'
	check "RF3: state は B2" [ "$(state_commit)" = "$b2" ]
	check "RF3: jq-1.8.2 が入る" [ -d "$JQ_DIR/jq-1.8.2" ]
	check "RF3: 使用中の jq-1.8.1 は残る" [ -d "$JQ_DIR/jq-1.8.1" ]
	check "RF3: 使用中のため残した旨を出す" grep -q '使用中のため残します' "$LAST_LOG"
	echo "  jq の版: $(jq_versions)"
	ls /opt/dotfiles-shared/pending 2>/dev/null | sed 's/^/    > pending: /'
	# 書き手を開いて閉じると jq は EOF で終わる。
	: >/tmp/jqfifo
	sleep 1
	check "RF3: bob の jq は終わった" [ ! -e "/proc/$pid" ]
	echo "  bob が chezmoi update（どのユーザの apply でもよい）"
	chez bob update
	evidence "$LAST_LOG" '共有|古い版|使用中|削除'
	check "RF3: bob の apply で jq-1.8.1 が消える" [ ! -e "$JQ_DIR/jq-1.8.1" ]
	check "RF3: jq-1.8.2 は残る" [ -d "$JQ_DIR/jq-1.8.2" ]
	echo "  jq の版: $(jq_versions)"
	echo "  bob の run-all.sh 回数: $(runall_count bob)"

	section "RF2: bob の sudo を使えなくして、非対話で chezmoi update（警告だけ、0、何も消さない）"
	b3="$(bump jq-1.7.1)"
	echo "  B3: $b3"
	sed -i 's/^bob ALL=(ALL) NOPASSWD: ALL$/# bob は sudo を使えない/' /etc/sudoers.d/e2e
	check "RF2: bob の sudo -n は失敗する" bash -c '! sudo -u bob sudo -n true 2>/dev/null'
	snap_before="$LOGS/rf2-before.txt"
	snap_after="$LOGS/rf2-after.txt"
	snapshot "$snap_before"
	chez bob update
	check "RF2: apply は 0 で終わる" [ $? -eq 0 ]
	evidence "$LAST_LOG" '共有|sudo|失敗|削除'
	snapshot "$snap_after"
	check "RF2: sudo を使えない旨の警告" grep -q 'sudo を使えません' "$LAST_LOG"
	check "RF2: state は B2 のまま" [ "$(state_commit)" = "$b2" ]
	check "RF2: 共有側は jq-1.8.2 のまま" has_only jq-1.8.2
	if diff "$snap_before" "$snap_after" | grep '^<' >"$LOGS/rf2-removed.txt"; then
		sed 's/^/    > 消えた: /' "$LOGS/rf2-removed.txt" | head -20
		failed "RF2: 共有側とホームから消えたものは無い"
	else
		pass "RF2: 共有側とホームから消えたものは無い"
	fi
	echo "  bob の jq: $(user_jq bob)（共有側の版を使い続ける）"
	sed -i 's/^# bob は sudo を使えない$/bob ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers.d/e2e

	section "RF5: origin/main の無いクローン（alice、remote を upstream に改名）"
	as alice git -C /home/alice/.local/share/chezmoi remote rename origin upstream
	as alice git -C /home/alice/.local/share/chezmoi pull -q upstream main
	chez alice apply
	check "RF5: apply は 0 で終わる" [ $? -eq 0 ]
	evidence "$LAST_LOG" '共有|DOTFILES_SHARED_FORCE'
	check "RF5: origin/main が無い旨と FORCE の案内" grep -q 'origin/main が無いため.*DOTFILES_SHARED_FORCE=1' "$LAST_LOG"
	check "RF5: state は B2 のまま" [ "$(state_commit)" = "$b2" ]
	as alice git -C /home/alice/.local/share/chezmoi remote rename upstream origin
	as alice git -C /home/alice/.local/share/chezmoi fetch -q origin
	chez alice apply
	check "RF5: origin を戻すと更新する（state は B3）" [ "$(state_commit)" = "$b3" ]
	check "RF5: 共有側は jq-1.7.1" [ -d "$JQ_DIR/jq-1.7.1" ]

	section "RF4: 未認証の gh"
	if [ -n "${GITHUB_TOKEN:-}" ]; then
		echo "  GITHUB_TOKEN を渡したため、未認証の分岐は S1 では通っていない"
	fi
	as alice zsh -c 'gh auth status' >"$LOGS/gh-status.log" 2>&1 && echo "  alice の gh: 認証済み" || echo "  alice の gh: 未認証"
	evidence "$LOGS/01-alice-init.log" 'GITHUB_TOKEN|bootstrap|attestation|検証|gh '
	echo "  S1 の各ステップの結果は上の S1 の PASS / FAIL を参照（keys/20..25）"
}

case "${1:-e2e}" in
unit) run_unit ;;
e2e) run_e2e ;;
all)
	run_unit
	run_e2e
	;;
*)
	echo "不明なモード: $1" >&2
	exit 2
	;;
esac

section "結果"
if [ "$failures" -eq 0 ]; then
	echo "ALL PASS"
else
	echo "FAIL: $failures 件"
	exit 1
fi
