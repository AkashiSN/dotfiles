#!/usr/bin/env bash
# テスト共通のヘルパー。各 *.test.sh から source する。

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO

fail() {
	echo "FAIL: $1" >&2
	[ -n "${2:-}" ] && printf '%s\n' "$2" >&2
	exit 1
}

assert_eq() {
	[ "$1" = "$2" ] || fail "$3" "expected: $1
actual:   $2"
	echo "PASS: $3"
}

assert_contains() {
	case "$1" in
	*"$2"*) echo "PASS: $3" ;;
	*) fail "$3" "missing: $2
in:
$1" ;;
	esac
}

assert_not_contains() {
	case "$1" in
	*"$2"*) fail "$3" "unexpected: $2
in:
$1" ;;
	*) echo "PASS: $3" ;;
	esac
}

# chezmoi の --promptString / --promptBool は data のキーではなくプロンプト文言で照合される。
# data キー（git.name 等）をプロンプト文言へ引く。未登録のキーは文言そのものとして扱う。
# 文言は .chezmoi.toml.tmpl のプロンプトと完全に一致させる。ずれると回答が当たらず、
# エラーにならないまま既定値に落ちる。
_prompt_text() {
	case "$1" in
	git.name) echo "git の名前" ;;
	git.email) echo "git のメールアドレス" ;;
	git.signingkey) echo "git の署名鍵（SSH 公開鍵。署名しないなら空）" ;;
	personal) echo "個人のホストと鍵（AkashiSN）を使うか" ;;
	*) echo "$1" ;;
	esac
}

# 真偽値のプロンプト（promptBoolOnce）になる data キー。--promptBool で答える。
_is_bool_key() {
	case "$1" in
	personal) return 0 ;;
	*) return 1 ;;
	esac
}

# chezmoi_config <出力先 toml> [key=value ...]
# .chezmoi.toml.tmpl を --init で展開して、一時 config を <出力先 toml> へ書く。
# key=value は prompt への回答（例: git.name=Risa personal=false）。渡さない key は既定値になる。
# 実機の chezmoi.toml は読まない。
chezmoi_config() {
	local out="$1" strs="" bools="" kv key tmp
	shift
	for kv in "$@"; do
		key="${kv%%=*}"
		if _is_bool_key "$key"; then
			bools="${bools:+$bools,}$(_prompt_text "$key")=${kv#*=}"
		else
			strs="${strs:+$strs,}$(_prompt_text "$key")=${kv#*=}"
		fi
	done
	tmp="$(mktemp -d)"
	: >"$tmp/empty.toml"
	chezmoi --config "$tmp/empty.toml" execute-template --init \
		${strs:+--promptString "$strs"} ${bools:+--promptBool "$bools"} \
		<"$REPO/.chezmoi.toml.tmpl" >"$out"
	local rc=$?
	rm -rf "$tmp"
	return $rc
}

# chezmoi_render <template-file> [key=value ...]
# chezmoi_config で作った一時 config の data で <template-file> を展開して標準出力へ出す。
chezmoi_render() {
	local tmpl="$1" tmp rc
	shift
	tmp="$(mktemp -d)"
	if ! chezmoi_config "$tmp/chezmoi.toml" "$@"; then
		rm -rf "$tmp"
		return 1
	fi
	chezmoi --source "$REPO" --config "$tmp/chezmoi.toml" execute-template <"$tmpl"
	rc=$?
	rm -rf "$tmp"
	return $rc
}

# chezmoi_managed [key=value ...]
# 一時 config と一時 destination で、管理対象ファイルの一覧（destination 相対）を出す。
chezmoi_managed() {
	local tmp rc
	tmp="$(mktemp -d)"
	if ! chezmoi_config "$tmp/chezmoi.toml" "$@"; then
		rm -rf "$tmp"
		return 1
	fi
	chezmoi --source "$REPO" --config "$tmp/chezmoi.toml" --destination "$tmp/dest" managed --include files
	rc=$?
	rm -rf "$tmp"
	return $rc
}

# fake_shared_aqua_step <bootstrap dir>
# <bootstrap dir>/20-shared-aqua.sh に偽物を置く。--check は $SHARED_ROOT/dotfiles-shared/keys/20 が
# "k20" のときだけ通る（共有 aqua がピンと揃っている扱い）。21 / 23 / 24 / 25 のテストが使う。
fake_shared_aqua_step() {
	cat >"$1/20-shared-aqua.sh" <<'FAKE'
#!/usr/bin/env bash
[ "${1:-}" = --check ] || exit 1
[ "$(cat "$SHARED_ROOT/dotfiles-shared/keys/20" 2>/dev/null)" = k20 ]
FAKE
}

# assert_stale_shared_aqua_skips <step> <keys/20 のパス> <作ってはいけないパス...>
# keys/20 がピンと食い違う（20 が失敗した回）と、ステップが案内を出して非 0 で終わり、何も作らないこと。
assert_stale_shared_aqua_skips() {
	local step="$1" k20="$2" out rc=0 p
	shift 2
	echo stale >"$k20"
	out="$(AQUA_BIN="${fakeaqua:-/bin/true}" bash "$step" 2>&1)" || rc=$?
	echo k20 >"$k20"
	[ "$rc" -ne 0 ] || fail "$(basename "$step"): 共有 aqua が古いのに成功した"
	assert_contains "$out" "ピンと揃っていない" "$(basename "$step"): 共有 aqua が古ければ理由を出して飛ばす"
	for p in "$@"; do
		[ ! -e "$p" ] || fail "$(basename "$step"): 共有 aqua が古いのに $p を作った"
	done
}
