# shellcheck shell=bash
# 共有 tenv ストアの terraform を、ユーザの TENV_ROOT の版のディレクトリへ symlink する。bash。
# .chezmoiscripts の run_after_21 が source する（テンプレートの記法は含めず、tests/ からそのまま source できる）。
# 前提: bootstrap/lib.sh を source 済み（note / running_exact / running_matching / running_args_matching）。
#
# 版のディレクトリはユーザ所有の実ディレクトリで、その中の terraform だけを共有の実体への symlink にする。
# tenv が実行のたびに書く last-use.txt がホーム側に落ち、読み取り専用の共有側への書込警告が出ない。

# _tenv_busy <版> <ユーザ側の terraform のパス>: その版の terraform が動いていれば 0。
_tenv_busy() {
	running_exact "$2" && return 0
	running_matching "/Terraform/$1/" && return 0
	running_args_matching "/Terraform/$1/" && return 0
	return 1
}

# tenv_link_shared <共有の Terraform ディレクトリ> <ユーザの Terraform ディレクトリ>
# - 共有に実行できる terraform がある版: ユーザ側に実ファイルがあれば（動いていない限り）消して symlink にする。
#   動いていれば残して次の apply に回す。共有が覆わない版は触らない。
# - 共有から消えた版を指す symlink（dangling）は外す。
tenv_link_shared() {
	local shared="$1" user="$2" dir ver src dst target
	mkdir -p "$user" 2>/dev/null || {
		note "$user を作成できません。共有 tenv は使えません"
		return 0
	}
	for dir in "$shared"/*/; do
		[ -d "$dir" ] || continue
		ver="$(basename "$dir")"
		src="${dir%/}/terraform"
		[ -x "$src" ] || continue
		dst="$user/$ver/terraform"
		if [ -L "$dst" ]; then
			[ "$(readlink "$dst")" = "$src" ] || ln -sfn "$src" "$dst"
			continue
		fi
		if [ -e "$dst" ]; then
			if _tenv_busy "$ver" "$dst"; then
				note "Terraform $ver が動いているため、ホームの実体は次の chezmoi apply で共有へ替えます"
				continue
			fi
			note "共有の Terraform を使うため削除: $dst"
			rm -f "$dst"
		fi
		mkdir -p "$user/$ver" 2>/dev/null || {
			note "警告: $user/$ver を作成できません"
			continue
		}
		ln -sfn "$src" "$dst" 2>/dev/null || note "警告: $dst の symlink 作成に失敗しました"
	done
	for dst in "$user"/*/terraform; do
		[ -L "$dst" ] || continue
		target="$(readlink "$dst")"
		case "$target" in
		"$shared"/*) ;;
		*) continue ;;
		esac
		[ -e "$dst" ] && continue
		note "共有から消えた版の symlink を削除: $dst"
		rm -f "$dst"
		rmdir "$(dirname "$dst")" 2>/dev/null || true
	done
}
