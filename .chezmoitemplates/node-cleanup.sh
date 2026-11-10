# shellcheck shell=bash
# ホームに残った fnm の Node（node-versions と default などの aliases）を掃除する。bash。
# .chezmoiscripts の run_after_30 が source する（テンプレートの記法は含めず、tests/ からそのまま source できる）。
# 前提: bootstrap/lib.sh を source 済み（note / running_from_any / running_matching）。
#
# fnm の本体と、fnm が使う他のディレクトリ（multishells など）には触れない。プロジェクトで使う版は
# 各自が fnm install で入れ直す。

# _node_dir_has_entries <dir>: <dir> に（隠しファイルを含め）何かあれば 0。
_node_dir_has_entries() {
	local f
	for f in "$1"/* "$1"/.[!.]* "$1"/..?*; do
		[ -e "$f" ] || [ -L "$f" ] || continue
		return 0
	done
	return 1
}

# node_cleanup_home <fnm_dir>
# <fnm_dir>/node-versions と <fnm_dir>/aliases を、動いている node が無いときだけ消す。
# 動いているかは次のどれかで見る。
#   - 実行ファイルが node-versions の下にある（running_from_any）
#   - 実行ファイルのパスに node-versions や fnm_multishells が含まれる（running_matching）
# macOS の ps は PATH 上のリンク（fnm_multishells/<id>/bin/node）で起動したプロセスをそのリンクの
# パスで出し、実体の node-versions は出さない。fnm_multishells は fnm が各シェルに作るリンクの置き場。
node_cleanup_home() {
	local fnm_dir="$1" busy=0
	# fnm env は空の node-versions / aliases をシェルごとに作り直す。空なら消すものは無い。
	_node_dir_has_entries "$fnm_dir/node-versions" || _node_dir_has_entries "$fnm_dir/aliases" || return 0
	running_from_any "$fnm_dir/node-versions" && busy=1
	if [ "$busy" -eq 0 ]; then
		running_matching "$fnm_dir/node-versions/" && busy=1
	fi
	if [ "$busy" -eq 0 ]; then
		running_matching "/fnm/node-versions/" && busy=1
	fi
	if [ "$busy" -eq 0 ]; then
		running_matching "/fnm_multishells/" && busy=1
	fi
	if [ "$busy" -eq 1 ]; then
		note "fnm の node が動いているため、fnm の Node は次の chezmoi apply で消します"
		return 0
	fi
	note "共有の Node を使うため削除: $fnm_dir/node-versions, $fnm_dir/aliases"
	rm -rf "$fnm_dir/node-versions" "$fnm_dir/aliases"
}
