# 60-aliases.zsh — エイリアスと基本 env。

case "$(uname)" in
Darwin)
  alias ls="ls -G"
  alias ll="ls -lG"
  alias la="ls -laG"
  alias brew="PATH=/opt/homebrew/bin:/usr/local/sbin:/usr/local/bin:/sbin:/usr/sbin:/bin:/usr/bin brew"
  export PATH_TO_FX="/Library/Java/JavaVirtualMachines/javafx-sdk/lib"
  ;;
Linux)
  alias ls='ls --color=auto'
  alias ll='ls -alF'
  alias la='ls -A'
  alias l='ls -CF'
  alias ffmpeg-qsv="sudo env PATH=$HOME/.local/bin:$PATH env LD_LIBRARY_PATH=$HOME/.local/lib:$LD_LIBRARY_PATH env LIBVA_DRIVERS_PATH=$HOME/.local/lib env LIBVA_DRIVER_NAME=iHD ffmpeg"
  export PATH_TO_FX="/usr/share/openjfx/lib"
  ;;
esac

alias rsync="rsync -azP"
alias conv-utf8='find . -type f -exec nkf --overwrite -w -Lu {} \;'

export EDITOR=nvim
export VISUAL=nvim
alias vi=nvim
alias vim=nvim
alias codex='AWS_PROFILE=cdx-pre-dev AWS_REGION=us-east-2 codex --profile bedrock'

# WSL 用の調整
if [[ "$(uname -r)" == *microsoft* ]]; then
  alias code="/mnt/c/Users/$(whoami)/AppData/Local/Programs/Microsoft\ VS\ Code/bin/code"
  unalias docker 2>/dev/null
  unalias docker-compose 2>/dev/null
fi
