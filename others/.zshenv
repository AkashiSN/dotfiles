export PATH
export MANPATH
export HOMEBREW_PATH

# -U: keep only the first occurrence of each duplicated value
# ref. http://zsh.sourceforge.net/Doc/Release/Shell-Builtin-Commands.html#index-typeset
typeset -U PATH path MANPATH manpath

# ignore /etc/zprofile, /etc/zshrc, /etc/zlogin, and /etc/zlogout
# ref. http://zsh.sourceforge.net/Doc/Release/Files.html
# ref. http://zsh.sourceforge.net/Doc/Release/Options.html#index-GLOBALRCS
unsetopt GLOBAL_RCS
# copied from /etc/zprofile
# system-wide environment settings for zsh(1)
if [ -x /usr/libexec/path_helper ]; then
  eval `/usr/libexec/path_helper -s`
fi

if [[ "$(uname -m)" == "amd64" ]]; then
  HOMEBREW_PATH=/usr/local
elif [[ "$(uname -m)" == "arm64" ]]; then
  HOMEBREW_PATH=/opt/homebrew
fi

path=(
  ${HOMEBREW_PATH}/bin(N-/) # homebrew
  ${HOMEBREW_PATH}/sbin(N-/) # homebrew
  ${path}
)
manpath=(
  ${HOMEBREW_PATH}/share/man(N-/) # homebrew
  ${manpath}
)

path=(
  ${HOMEBREW_PATH}/opt/coreutils/libexec/gnubin(N-/) # coreutils
  ${HOMEBREW_PATH}/opt/ed/libexec/gnubin(N-/) # ed
  ${HOMEBREW_PATH}/opt/findutils/libexec/gnubin(N-/) # findutils
  ${HOMEBREW_PATH}/opt/gnu-sed/libexec/gnubin(N-/) # sed
  ${HOMEBREW_PATH}/opt/gnu-tar/libexec/gnubin(N-/) # tar
  ${HOMEBREW_PATH}/opt/grep/libexec/gnubin(N-/) # grep
  ${HOMEBREW_PATH}/opt/node@20/bin(N-/) # node@20
  ${path}
)
manpath=(
  ${HOMEBREW_PATH}/opt/coreutils/libexec/gnuman(N-/) # coreutils
  ${HOMEBREW_PATH}/opt/ed/libexec/gnuman(N-/) # ed
  ${HOMEBREW_PATH}/opt/findutils/libexec/gnuman(N-/) # findutils
  ${HOMEBREW_PATH}/opt/gnu-sed/libexec/gnuman(N-/) # sed
  ${HOMEBREW_PATH}/opt/gnu-tar/libexec/gnuman(N-/) # tar
  ${HOMEBREW_PATH}/opt/grep/libexec/gnuman(N-/) # grep
  ${HOMEBREW_PATH}/opt/node@20/share/man(N-/) # node@20
  ${manpath}
)
