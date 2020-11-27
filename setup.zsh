#!/bin/zsh

#
# Setup PATH
#

mkdir -p $HOME/bin
export PATH=$HOME/bin:$PATH
export TERM=xterm-256color
autoload -Uz colors && colors

#
# Functions
#

command_exists () {
	if ! [[ -x $(command -v "$1") ]]; then
		print -P "%F{160}▓▒░ %F{220}$1%F{160} not found in PATH.%f%b"
		return 1
	fi
	return 0
}

#
# Check command exists
#

command_exists "git" || exit 1;
command_exists "curl" || exit 1;

#
# ARC
#

if ! [[ -x $(command -v arc) ]]; then
	print -P "%F{33}▓▒░ %F{220}Installing %F{33}arc%F{220} A cross-platform, multi-format archive utility and Go library (%F{33}mholt/archiver%F{220})…%f"
	if [[ "$(uname)" == "Linux" ]]; then
		declare -a FILES=($(curl -sL https://github.com/mholt/archiver/releases/latest/download/checksums.txt | grep linux_amd64))
		command curl -L -o $HOME/bin/arc https://github.com/mholt/archiver/releases/latest/download/${FILES[2]}
	elif [[ "$(uname)" == "Darwin" ]]; then
		declare -a FILES=($(curl -sL https://github.com/mholt/archiver/releases/latest/download/checksums.txt | grep mac_amd64))
		command curl -L -o $HOME/bin/arc https://github.com/mholt/archiver/releases/latest/download/${FILES[2]}
	fi
	chmod +x $HOME/bin/arc
fi

#
# Anyenv
#

if [[ ! -f $HOME/.anyenv/bin/anyenv ]]; then
	print -P "%F{33}▓▒░ %F{220}Installing %F{33}anyenv%F{220} All in one for **env (%F{33}anyenv/anyenv%F{220})…%f"
	command git clone https://github.com/anyenv/anyenv "$HOME/.anyenv" && \
		print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
		print -P "%F{160}▓▒░ The clone has failed.%f%b"
	command mkdir -p $HOME/.anyenv/plugins
	command git clone https://github.com/znz/anyenv-update.git $HOME/.anyenv/plugins/anyenv-update && \
		print -P "%F{33}▓▒░ %F{34}Installation plugin anyenv-update successful.%f%b" || \
		print -P "%F{160}▓▒░ The clone has failed.%f%b"
	command git clone https://github.com/znz/anyenv-git.git $HOME/.anyenv/plugins/anyenv-git && \
		print -P "%F{33}▓▒░ %F{34}Installation plugin anyenv-git successful.%f%b" || \
		print -P "%F{160}▓▒░ The clone has failed.%f%b"
fi

# Initial setting of anyenv.
export PATH="$HOME/.anyenv/bin:$PATH"
export ANYENV_ROOT="$HOME/.anyenv"
eval "$(env PATH="$ANYENV_ROOT/libexec:$PATH" $ANYENV_ROOT/libexec/anyenv-init - --no-rehash)"

#
# Golang
#

# Add GOPATH
export GOENV_DISABLE_GOPATH=1
export GOPATH=$HOME/Project
export PATH=$GOPATH/bin:$PATH

# Goenv
if [[ ! -f $HOME/.anyenv/envs/goenv/bin/goenv ]]; then
	print -P "%F{33}▓▒░ %F{220}Installing %F{33}goenv%F{220} Go Version Management (%F{33}syndbg/goenv%F{220})…%f"
	command anyenv install goenv && \
		print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
		print -P "%F{160}▓▒░ The clone has failed.%f%b"
fi

# GHQ
if ! [[ -x $(command -v ghq) ]]; then
	print -P "%F{33}▓▒░ %F{220}Installing %F{33}ghq%F{220} Manage remote repository clones (%F{33}x-motemen/ghq%F{220})…%f"
	if [[ "$(uname)" == "Linux" ]]; then
		command curl -L -o /tmp/ghq.zip https://github.com/x-motemen/ghq/releases/latest/download/ghq_linux_amd64.zip
	elif [[ "$(uname)" == "Darwin" ]]; then
		command curl -L -o /tmp/ghq.zip https://github.com/x-motemen/ghq/releases/latest/download/ghq_darwin_amd64.zip
	fi
	command arc -strip-components 1 -overwrite unarchive /tmp/ghq.zip /tmp/ghq && \
		mv /tmp/ghq/ghq $HOME/bin/ && \
		print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
		print -P "%F{160}▓▒░ The installation has failed.%f%b"
	command rm -rf /tmp/ghq*
fi

# Peco
if ! [[ -x $(command -v peco) ]]; then
	print -P "%F{33}▓▒░ %F{220}Installing %F{33}peco%F{220} Simplistic interactive filtering tool (%F{33}peco/peco%F{220})…%f"
	if [[ "$(uname)" == "Linux" ]]; then
		command curl -L -o /tmp/peco.tar.gz https://github.com/peco/peco/releases/latest/download/peco_linux_amd64.tar.gz && \
			arc -strip-components 1 -overwrite unarchive /tmp/peco.tar.gz /tmp/peco
	elif [[ "$(uname)" == "Darwin" ]]; then
		command curl -L -o /tmp/peco.zip https://github.com/peco/peco/releases/latest/download/peco_darwin_amd64.zip && \
			arc -strip-components 1 -overwrite unarchive /tmp/peco.zip /tmp/peco
	fi
	command mv /tmp/peco/peco $HOME/bin/ && \
		print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
		print -P "%F{160}▓▒░ The installation has failed.%f%b"
	command rm -rf /tmp/peco*
fi

#
# Nodenv
#

if [[ ! -f $HOME/.anyenv/envs/nodenv/bin/nodenv ]]; then
	print -P "%F{33}▓▒░ %F{220}Installing %F{33}nodenv%F{220} Groom your app’s Node environment with nodenv. (%F{33}nodenv/nodenv%F{220})…%f"
	command anyenv install nodenv && \
		print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
		print -P "%F{160}▓▒░ The clone has failed.%f%b"
	command mkdir -p "$ANYENV_ROOT/envs/nodenv/plugins" && \
		git clone https://github.com/pine/nodenv-yarn-install.git "$ANYENV_ROOT/envs/nodenv/plugins/nodenv-yarn-install" && \
		print -P "%F{33}▓▒░ %F{34}Installation yarn plugin successful.%f%b" || \
		print -P "%F{160}▓▒░ The clone has failed.%f%b"
fi

#
# clone dotfiles
#

print -P "%F{33}▓▒░ %F{220}Installing %F{33}dotfiles%F{220} dotfiles (%F{33}AkashiSN/dotfiles%F{220})…%f"
command ghq get https://github.com/AkashiSN/dotfiles.git && \
	ln -snf $GOPATH/src/github.com/AkashiSN/dotfiles/.zshrc $HOME/.zshrc && \
	ln -snf $GOPATH/src/github.com/AkashiSN/dotfiles/.vimrc $HOME/.vimrc && \
	ln -snf $GOPATH/src/github.com/AkashiSN/dotfiles/.tmux.conf $HOME/.tmux.conf && \
	\cp -f $GOPATH/src/github.com/AkashiSN/dotfiles/.gitconfig $HOME/.gitconfig && \
	ln -snf $GOPATH/src/github.com/AkashiSN/dotfiles/.gitignore_global $HOME/.gitignore_global && \
	print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
	print -P "%F{160}▓▒░ The clone has failed.%f%b"

print -P "%F{33}▓▒░ %F{34}Change login shell to zsh%f%b"
export user=$(whoami) && \
sudo chsh -s $(which zsh) $user && \
print -P "%F{33}▓▒░ %F{34}All complete, Restart your shell (exec \$SHELL -l) .%f%b" || \
print -P "%F{160}▓▒░ Changeing login shell has failed.%f%b"
