# shellcheck shell=bash
# ホームに残った rustup の toolchain とプロキシを掃除する。bash。
# .chezmoiscripts の run_after_32 が source する（テンプレートの記法は含めず、tests/ からそのまま source できる）。
# 前提: bootstrap/lib.sh を source 済み（note / running_from_any / running_matching / running_exact / running_args_matching）。
#
# CARGO_HOME/bin のうち消すのは rustup 本体と、そのハードリンク（cargo / rustc などのプロキシ）だけ。
# 名前ではなく inode で見分けるので、cargo install したもの（別のファイル）は残る。

# _rust_busy <rustup_home> <cargo_bin>: ホームの Rust が動いていれば 0。
# macOS の ps は PATH 上のプロキシ（CARGO_HOME/bin/cargo など）で起動したプロセスをそのパスで出し、
# 実体の toolchain は出さないことがある。toolchain の rustc は toolchains の下のパスで出る。
_rust_busy() {
	local rh="$1" cb="$2" f
	running_from_any "$rh" && return 0
	running_matching "$rh/" && return 0
	running_args_matching "$rh/" && return 0
	# cargo install したもの（別のファイル）は消さないので、動いていても数えない。
	for f in "$cb"/*; do
		[ -e "$f" ] || continue
		[ "$f" -ef "$cb/rustup" ] || continue
		running_exact "$f" && return 0
	done
	return 1
}

# rust_cleanup_home <rustup_home> <cargo_bin>
# 動いている Rust（rustc / cargo / rust-analyzer など）がある間は何も消さず、次の apply へ回す。
rust_cleanup_home() {
	local rh="$1" cb="$2" f
	[ -d "$rh" ] || [ -e "$cb/rustup" ] || return 0
	if _rust_busy "$rh" "$cb"; then
		note "ホームの Rust が動いているため、共有へ移した分は次の chezmoi apply で消します"
		return 0
	fi
	if [ -e "$cb/rustup" ]; then
		for f in "$cb"/*; do
			[ "$f" = "$cb/rustup" ] && continue
			[ "$f" -ef "$cb/rustup" ] || continue
			note "共有の Rust を使うため削除: $f"
			rm -f "$f"
		done
		note "共有の Rust を使うため削除: $cb/rustup"
		rm -f "$cb/rustup"
	fi
	if [ -d "$rh" ]; then
		note "共有の Rust を使うため削除: $rh"
		rm -rf "$rh"
	fi
}
