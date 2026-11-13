# bootstrap/*.sh が source する、共有ストアのダウングレード防止の関数。単体では実行しない。
# Linux と macOS (bash 3.2 / BSD コマンド) の両方で動く。呼び出し側の set -eu 下でも動く。
# shellcheck shell=bash

# shared_guard <repo_dir> <state_file>
# 共有側を更新してよいかを 1 行で出す。ok / force は終了コード 0、stale:<理由> は 1。
# fetch はしない。ローカルの origin/main を見る（呼び出し側が pull 済みである前提）。
shared_guard() {
	local repo="$1" state="$2" recorded
	if [ "${DOTFILES_SHARED_FORCE:-}" = 1 ]; then
		echo force
		return 0
	fi
	if ! git -C "$repo" rev-parse --verify -q refs/remotes/origin/main >/dev/null 2>&1; then
		echo "stale:no-origin-main"
		return 1
	fi
	if ! git -C "$repo" merge-base --is-ancestor HEAD refs/remotes/origin/main 2>/dev/null; then
		echo "stale:not-on-origin-main"
		return 1
	fi
	recorded="$(state_commit "$state")"
	if [ -n "$recorded" ]; then
		if ! git -C "$repo" cat-file -e "${recorded}^{commit}" 2>/dev/null; then
			echo "stale:state-commit-unknown"
			return 1
		fi
		if ! git -C "$repo" merge-base --is-ancestor "$recorded" HEAD 2>/dev/null; then
			echo "stale:behind-state"
			return 1
		fi
	fi
	echo ok
}

# shared_guard_hint <理由>
# stale の理由を日本語 1 行で説明し、DOTFILES_SHARED_FORCE=1 の案内を添えて出す。
shared_guard_hint() {
	local why
	case "$1" in
	no-origin-main) why="origin/main が無いため、共有側が新しいか判定できません" ;;
	not-on-origin-main) why="HEAD が origin/main に含まれないため、共有側を更新しません" ;;
	behind-state) why="共有側は、この checkout より新しいコミットで更新済みです" ;;
	state-commit-unknown) why="共有側の記録コミットがこの checkout に無いため、新旧を判定できません" ;;
	*) why="共有側を更新できません ($1)" ;;
	esac
	printf '%s。無視して更新するなら DOTFILES_SHARED_FORCE=1 を付けて実行してください\n' "$why"
}

# state_commit <state_file>
# 記録されたコミットを出す。ファイルが無い、または commit= 行が無ければ何も出さない。
state_commit() {
	[ -f "$1" ] || return 0
	sed -n 's/^commit=//p' "$1" | head -n 1
}

# state_write <state_file> <commit>
# commit / updated_by / updated_at の 3 行を原子的に書く（同じディレクトリの一時ファイルを mv）。
# 親ディレクトリが無ければ作る。
state_write() {
	local file="$1" commit="$2" dir tmp
	dir="$(dirname "$file")"
	mkdir -p "$dir"
	tmp="$(mktemp "$dir/.state.XXXXXX")"
	{
		printf 'commit=%s\n' "$commit"
		printf 'updated_by=%s\n' "${SUDO_USER:-$(id -un)}"
		printf 'updated_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	} >"$tmp"
	chmod 644 "$tmp"
	mv "$tmp" "$file"
}
