#!/usr/bin/env bash
# Apple Silicon の Homebrew を共有する仕組み（before_05 の展開と homebrew-shared.sh の関数）。
set -u
# shellcheck source=../lib.sh
. "$(dirname "$0")/../lib.sh"

# (a) before_05 が darwin/arm64 では /bin/sh のスクリプトを出す
if [ "$(uname -sm)" = "Darwin arm64" ]; then
	out="$(chezmoi_render "$REPO/.chezmoiscripts/run_before_05-homebrew-shared.sh.tmpl")" || fail "render before_05"
	[ -n "$out" ] || fail "before_05 is empty on darwin/arm64"
	assert_eq "#!/bin/sh" "$(printf '%s\n' "$out" | head -n 1)" "before_05 shebang"
	assert_contains "$out" "homebrew_shared_ok" "before_05 includes the shared functions"
fi

# (a2) before_05 を偽の sudo / dseditgroup で流す（prefix は一時ディレクトリへ差し替える）
if [ "$(uname -sm)" = "Darwin arm64" ]; then
	b5="$(mktemp -d)"
	script="$b5/before05.sh"
	printf '%s\n' "$out" | sed -e "s#^PREFIX=/opt/homebrew\$#PREFIX=$b5/prefix#" >"$script"
	grep -q "^PREFIX=$b5/prefix" "$script" || fail "before_05: prefix の差し替えに失敗"
	mkdir -p "$b5/prefix" "$b5/stubs"
	chmod 755 "$b5/prefix"
	# 偽 sudo: 引数を記録し、FAKE_SUDO_FAIL に "<最初の非オプション引数>" か "-v" が入っていれば失敗する。
	cat >"$b5/stubs/sudo" <<'FAKE'
#!/bin/sh
echo "sudo $*" >>"$CALLS"
case " ${FAKE_SUDO_FAIL:-} " in *" $1 "*) exit 1 ;; esac
exit 0
FAKE
	cat >"$b5/stubs/dseditgroup" <<'FAKE'
#!/bin/sh
echo "dseditgroup $*" >>"$CALLS"
exit "${FAKE_DSEDIT_RC:-0}"
FAKE
	chmod +x "$b5/stubs/sudo" "$b5/stubs/dseditgroup"
	export CALLS="$b5/calls"
	run05() {
		: >"$CALLS"
		BREW_GROUP="${RUN_GROUP:-brew}" PATH="$b5/stubs:/usr/bin:/bin" sh "$script" </dev/null 2>&1
	}

	# sudo -v（認証）を断られたら 0 で終え、以降の sudo を呼ばない
	rc=0
	o="$(FAKE_SUDO_FAIL="-v" run05)" || rc=$?
	assert_eq "0" "$rc" "before_05: sudo -v が失敗しても 0"
	assert_contains "$o" "見送りました" "before_05: sudo -v の失敗を案内する"
	assert_eq "sudo -v" "$(grep '^sudo' "$CALLS" | grep -v '^sudo -n' | tr '\n' ';' | sed 's/;$//')" "before_05: sudo -v の失敗後は sudo を呼ばない"

	# 途中の sudo（chgrp）が失敗しても 0 で終え、後続の sudo を呼ばない
	rc=0
	o="$(FAKE_SUDO_FAIL="chgrp" run05)" || rc=$?
	assert_eq "0" "$rc" "before_05: sudo chgrp が失敗しても 0"
	assert_contains "$o" "見送りました" "before_05: chgrp の失敗を案内する"
	assert_eq "sudo chgrp -R brew $b5/prefix" "$(grep '^sudo' "$CALLS" | tail -n 1)" "before_05: chgrp の失敗後は sudo を呼ばない"

	# 全部通れば chmod / find まで呼ぶ
	rc=0
	o="$(run05)" || rc=$?
	assert_eq "0" "$rc" "before_05: 成功で 0"
	assert_contains "$(cat "$CALLS")" "sudo find $b5/prefix -type d -exec chmod g+s {} +" "before_05: setgid まで流す"

	# 共有済みの FS で、グループに登録済みだが未ログイン（id -Gn に出ない）なら、sudo を呼ばず案内だけ出す
	g0="$(id -gn)"
	chgrp "$g0" "$b5/prefix"
	chmod 2775 "$b5/prefix"
	if [ -g "$b5/prefix" ]; then
		# shellcheck disable=SC2016 # 偽 id の中で展開する
		printf '#!/bin/sh\n[ "$1" = -Gn ] && { echo other; exit 0; }\nexec /usr/bin/id "$@"\n' >"$b5/stubs/id"
		chmod +x "$b5/stubs/id"
		rc=0
		o="$(RUN_GROUP="$g0" run05)" || rc=$?
		assert_eq "0" "$rc" "before_05: 登録済み・未ログインで 0"
		assert_contains "$o" "再ログイン後に有効" "before_05: 登録済み・未ログインは再ログインを案内する"
		assert_not_contains "$(cat "$CALLS")" "sudo" "before_05: 登録済み・未ログインは sudo を呼ばない"
		assert_contains "$(cat "$CALLS")" "dseditgroup -o checkmember -m $(id -un) $g0" "before_05: dseditgroup checkmember で登録を確かめる"
		# 未登録なら sudo で追加へ進む
		rc=0
		o="$(FAKE_DSEDIT_RC=1 RUN_GROUP="$g0" run05)" || rc=$?
		assert_eq "0" "$rc" "before_05: 未登録で 0"
		assert_contains "$(cat "$CALLS")" "sudo dseditgroup -o edit -a $(id -un) -t user $g0" "before_05: 未登録ならグループへ追加する"
		rm -f "$b5/stubs/id"
	else
		echo "SKIP: この FS では chmod g+s が効かない"
	fi
	rm -rf "$b5"
fi

# (b) brew_shared は umask 002 で brew を呼ぶ
# shellcheck source=../../.chezmoitemplates/homebrew-shared.sh
. "$REPO/.chezmoitemplates/homebrew-shared.sh"
# shellcheck disable=SC2329 # brew_shared から呼ばれる
brew() { umask; }
(umask 022 && assert_eq "0002" "$(brew_shared check)" "brew_shared runs brew with umask 002")
unset -f brew

# (c) homebrew_shared_ok: グループ・g+w・setgid・プロセスのグループ所属
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
grp="$(id -gn)"
export BREW_GROUP="$grp"

mkdir "$tmp/none"
chgrp "$grp" "$tmp/none"
chmod 755 "$tmp/none"
homebrew_shared_ok "$tmp/none" && fail "g+w も setgid も無いのに真"
echo "PASS: no g+w / no setgid is false"

mkdir "$tmp/gw"
chgrp "$grp" "$tmp/gw"
chmod 775 "$tmp/gw"
homebrew_shared_ok "$tmp/gw" && fail "setgid が無いのに真"
echo "PASS: g+w without setgid is false"

mkdir "$tmp/ok"
chgrp "$grp" "$tmp/ok"
chmod 775 "$tmp/ok"
chmod g+s "$tmp/ok"
if [ -g "$tmp/ok" ]; then
	homebrew_shared_ok "$tmp/ok" || fail "g+w と setgid があるのに偽"
	echo "PASS: g+w and setgid is true"
	BREW_GROUP="no-such-group-xyz" homebrew_shared_ok "$tmp/ok" && fail "グループが違うのに真"
	echo "PASS: other group is false"
else
	echo "SKIP: この FS では chmod g+s が効かない"
fi

homebrew_shared_ok "$tmp/missing" && fail "存在しない prefix で真"
echo "PASS: missing prefix is false"
