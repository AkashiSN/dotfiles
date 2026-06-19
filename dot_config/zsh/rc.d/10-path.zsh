# 10-path.zsh — PATH / FPATH / MANPATH 等。compinit(30) より前に fpath を確定させる。

export LOCAL_PREFIX=$HOME/.local
export MANPATH=$LOCAL_PREFIX/share/man:$MANPATH
export INFOPATH=$LOCAL_PREFIX/share/info:$INFOPATH
export LD_LIBRARY_PATH=$LOCAL_PREFIX/lib:$LD_LIBRARY_PATH
export LIBRARY_PATH=$LOCAL_PREFIX/lib:$LIBRARY_PATH
export PKG_CONFIG_PATH=$LOCAL_PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH
export C_INCLUDE_PATH=$LOCAL_PREFIX/include:$C_INCLUDE_PATH
export CPLUS_INCLUDE_PATH=$LOCAL_PREFIX/include:$CPLUS_INCLUDE_PATH
export PATH=$LOCAL_PREFIX/bin:$PATH
export FPATH=$LOCAL_PREFIX/share/zsh/site-functions:$FPATH

mkdir -p ${LOCAL_PREFIX}/{share,lib,include,bin,share/zsh/site-functions}

# agmsg: Codex monitor モードのシム（~/.agents/bin/codex）を本体 codex（~/.local/bin）
# より前に置く。delivery.sh set monitor codex 実行時に生成され、未生成でも実害なし。
# 詳細: docs/agmsg-cheatsheet.md の「Codex monitor モード」節。
export PATH=$HOME/.agents/bin:$PATH

# Golang (go 本体は aqua 管理)
export GOPATH=$HOME/Project
export GHQ_ROOT=$GOPATH/src
export PATH=$GOPATH/bin:$PATH

# Rancher Desktop
export PATH=$HOME/.rd/bin:$PATH

# NodeJS (Yarn)
export PATH=$HOME/.yarn/bin:$PATH

# /etc/profile.d
if [ -d /etc/profile.d ]; then
  for i in /etc/profile.d/*.sh ; do
    [ -r $i ] && source $i
  done
fi

# command not found handler
if [ -f /etc/zsh_command_not_found ]; then
  source /etc/zsh_command_not_found
fi
