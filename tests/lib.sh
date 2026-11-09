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

# chezmoi の --promptString は data のキーではなくプロンプト文言で照合される。
# data キー（git.name 等）をプロンプト文言へ引く。未登録のキーは文言そのものとして扱う。
_prompt_text() {
	case "$1" in
	git.name) echo "git の名前" ;;
	git.email) echo "git のメールアドレス" ;;
	git.signingkey) echo "git の署名鍵（SSH 公開鍵。署名しないなら空）" ;;
	*) echo "$1" ;;
	esac
}

# chezmoi_render <template-file> [key=value ...]
# .chezmoi.toml.tmpl を --init で展開して一時 config を作り、その data で
# <template-file> を展開して標準出力へ出す。key=value は promptStringOnce への回答
# （例: git.name=Risa）。渡さない key は既定値になる。実機の chezmoi.toml は読まない。
chezmoi_render() {
	local tmpl="$1" prompts="" kv tmp
	shift
	for kv in "$@"; do
		prompts="${prompts:+$prompts,}$(_prompt_text "${kv%%=*}")=${kv#*=}"
	done
	tmp="$(mktemp -d)"
	: >"$tmp/empty.toml"
	chezmoi --config "$tmp/empty.toml" execute-template --init ${prompts:+--promptString "$prompts"} \
		<"$REPO/.chezmoi.toml.tmpl" >"$tmp/chezmoi.toml" || return 1
	chezmoi --source "$REPO" --config "$tmp/chezmoi.toml" execute-template <"$tmpl"
	local rc=$?
	rm -rf "$tmp"
	return $rc
}
