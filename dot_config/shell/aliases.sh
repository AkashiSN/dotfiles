# ~/.config/shell/aliases.sh — zsh / bash 共通の alias。POSIX sh。
#
# ここに置いてよいのは「両シェルで同じ意味になる alias」だけ。zsh の補完設定や
# ZLE と結びつくものは ~/.config/zsh/rc.d/ に置く。
#
# 条件付きの alias を `command -v ... && alias ...` で書かないこと。コマンドが無いホストでは
# その行(= ファイル最終行)の終了ステータスが非 0 になり、source した側の戻り値まで非 0 に
# なる。if で包めば常に 0 で返る。
# shellcheck shell=sh

case "$(uname)" in
Darwin)
	alias ls="ls -G"
	alias ll="ls -lG"
	alias la="ls -laG"
	# brew は Homebrew 自身が入れたツールだけを見せる。GNU 版や aqua のバイナリが
	# 混ざると、brew のビルドが意図しない実装を引く。
	alias brew="PATH=/opt/homebrew/bin:/usr/local/sbin:/usr/local/bin:/sbin:/usr/sbin:/bin:/usr/bin brew"
	;;
Linux)
	alias ls='ls --color=auto'
	alias ll='ls -alF'
	alias la='ls -A'
	alias l='ls -CF'
	# 定義時に $HOME / $PATH を畳み込む。sudo env へ渡す値はこのシェルのものを使いたい。
	# shellcheck disable=SC2139
	alias ffmpeg-qsv="sudo env PATH=$HOME/.local/bin:$PATH env LD_LIBRARY_PATH=$HOME/.local/lib:$LD_LIBRARY_PATH env LIBVA_DRIVERS_PATH=$HOME/.local/lib env LIBVA_DRIVER_NAME=iHD ffmpeg"
	;;
esac

alias rsync="rsync -azP"
alias conv-utf8='find . -type f -exec nkf --overwrite -w -Lu {} \;'

alias vi=nvim
alias vim=nvim

# terraform / kubectl の短縮。補完の登録は zsh 側(rc.d/40-tools.zsh)にある。
# alias だけをここへ置くのは、Claude が bash で `tf plan` と打てるようにするため。
if command -v terraform >/dev/null 2>&1; then
	alias tf="terraform"
fi
if command -v kubectl >/dev/null 2>&1; then
	alias k="kubectl"
fi

# WSL 用の調整
case "$(uname -r)" in
*microsoft*)
	# 定義時にユーザ名を畳み込む。
	# shellcheck disable=SC2139
	alias code="/mnt/c/Users/$(whoami)/AppData/Local/Programs/Microsoft\ VS\ Code/bin/code"
	unalias docker 2>/dev/null || true
	unalias docker-compose 2>/dev/null || true
	;;
esac
