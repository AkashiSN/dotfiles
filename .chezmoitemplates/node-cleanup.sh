# shellcheck shell=bash
# ホームに残った fnm の既定の Node（default / lts-latest の alias とその指す版）を掃除する。bash。
# .chezmoiscripts の run_after_30 が source する（テンプレートの記法は含めず、tests/ からそのまま source できる）。
# 前提: bootstrap/lib.sh を source 済み（note / running_from_any / running_matching）。
#
# fnm はプロジェクトの .nvmrc 用に残す。消すのは、ユーザ単位の導入（fnm install --lts と
# fnm alias default lts-latest）が作る default / lts-latest の alias、その指す版、その版を指す他の
# alias だけ。それ以外の版と alias、fnm の本体、fnm が使う他のディレクトリ（multishells など）には触れない。

# _node_alias_version <fnm_dir> <alias のパス>
# alias（node-versions/<版>/installation への symlink）が指す版の名前を出す。読めなければ 1。
_node_alias_version() {
	local t v
	[ -L "$2" ] || return 1
	t="$(readlink "$2")" || return 1
	case "$t" in
	*/node-versions/*) ;;
	*) return 1 ;;
	esac
	v="${t##*/node-versions/}"
	v="${v%%/*}"
	case "$v" in
	"" | . | ..) return 1 ;;
	esac
	[ -d "$1/node-versions/$v" ] || return 1
	printf '%s\n' "$v"
}

# node_cleanup_home <fnm_dir>
# default / lts-latest の alias が指す版を、動いている node が無いときだけ消す。その版を指す alias
# （default / lts-latest を含む）も消す。消し終えた、または消すものが無ければ 0、動いているため
# 残したら 1 を返す。動いているかは次のどれかで見る。
#   - 実行ファイルが消す版の下にある（running_from_any / running_matching）
#   - 実行ファイルのパスに fnm_multishells や fnm の aliases が含まれる（running_matching）
# macOS の ps は PATH 上のリンク（fnm_multishells/<id>/bin/node や aliases/default/bin/node）で起動した
# プロセスをそのリンクのパスで出し、実体の版は出さない。リンクからは版を判別できないため、どれかが
# 動いていれば残す。
node_cleanup_home() {
	local fnm_dir="$1" a v vers="" busy=0
	local -a links=()
	for a in default lts-latest; do
		v="$(_node_alias_version "$fnm_dir" "$fnm_dir/aliases/$a")" || continue
		case " $vers " in
		*" $v "*) ;;
		*) vers="${vers:+$vers }$v" ;;
		esac
	done
	[ -n "$vers" ] || return 0

	for v in $vers; do
		running_from_any "$fnm_dir/node-versions/$v" && busy=1
		running_matching "$fnm_dir/node-versions/$v/" && busy=1
		running_matching "/fnm/node-versions/$v/" && busy=1
	done
	running_matching "/fnm_multishells/" && busy=1
	running_matching "$fnm_dir/aliases/" && busy=1
	running_matching "/fnm/aliases/" && busy=1
	if [ "$busy" -eq 1 ]; then
		note "fnm の node が動いているため、fnm の既定の Node ($vers) は次の chezmoi apply で消します"
		return 1
	fi

	# 消す版を指す alias を集める（default / lts-latest のほか、fnm install --lts が付けた名前も）。
	for a in "$fnm_dir"/aliases/*; do
		[ -L "$a" ] || continue
		v="$(_node_alias_version "$fnm_dir" "$a")" || continue
		case " $vers " in
		*" $v "*) links+=("$a") ;;
		esac
	done
	note "共有の Node を使うため、fnm の既定の Node を削除: $vers"
	[ "${#links[@]}" -eq 0 ] || rm -f "${links[@]}"
	for v in $vers; do
		rm -rf "${fnm_dir:?}/node-versions/$v"
	done
	return 0
}
