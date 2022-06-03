#!/bin/zsh

#
# Setup PATH
#

cd $HOME
PREFIX=$HOME/.local
mkdir -p $PREFIX/bin
mkdir -p $PREFIX/lib
export PATH=$PREFIX/bin:$PATH
export LD_LIBRARY_PATH=$PREFIX/lib:$LD_LIBRARY_PATH
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
# arc
#

if ! [[ -x $(command -v arc) ]]; then
	print -P "%F{33}▓▒░ %F{220}Installing %F{33}arc%F{220} A cross-platform, multi-format archive utility and Go library (%F{33}mholt/archiver%F{220})…%f"
	if [[ "$(uname)" == "Linux" ]]; then
		command curl -L -o $PREFIX/bin/arc https://github.com/mholt/archiver/releases/download/v3.5.0/arc_3.5.0_linux_amd64 && \
        chmod +x $PREFIX/bin/arc

	elif [[ "$(uname)" == "Darwin" ]]; then
		command curl -L -o $PREFIX/bin/arc https://github.com/mholt/archiver/releases/download/v3.5.0/arc_3.5.0_mac_amd64 && \
        chmod +x $PREFIX/bin/arc
	fi
fi

#
# Anyenv
#

export ANYENV_ROOT="$HOME/.anyenv"

if [[ ! -f $ANYENV_ROOT/bin/anyenv ]]; then
	print -P "%F{33}▓▒░ %F{220}Installing %F{33}anyenv%F{220} All in one for **env (%F{33}anyenv/anyenv%F{220})…%f"
	command git clone https://github.com/anyenv/anyenv "$ANYENV_ROOT" && \
		print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
		print -P "%F{160}▓▒░ The clone has failed.%f%b"
	command mkdir -p $ANYENV_ROOT/plugins
	command git clone https://github.com/znz/anyenv-update.git $ANYENV_ROOT/plugins/anyenv-update && \
		print -P "%F{33}▓▒░ %F{34}Installation plugin anyenv-update successful.%f%b" || \
		print -P "%F{160}▓▒░ The clone has failed.%f%b"
	command git clone https://github.com/znz/anyenv-git.git $ANYENV_ROOT/plugins/anyenv-git && \
		print -P "%F{33}▓▒░ %F{34}Installation plugin anyenv-git successful.%f%b" || \
		print -P "%F{160}▓▒░ The clone has failed.%f%b"
	export PATH="$ANYENV_ROOT/bin:$PATH"
	command yes | anyenv install --init
fi

# Initial setting of anyenv.
export PATH="$ANYENV_ROOT/bin:$PATH"
eval "$(env PATH="$ANYENV_ROOT/libexec:$PATH" $ANYENV_ROOT/libexec/anyenv-init - --no-rehash)"

#
# Golang
#

# Add GOPATH
export GOENV_DISABLE_GOPATH=1
export GOPATH=$HOME/Project
export PATH=$GOPATH/bin:$PATH
git config --global ghq.root $GOPATH/src

# Goenv
if [[ ! -f $ANYENV_ROOT/envs/goenv/bin/goenv ]]; then
	print -P "%F{33}▓▒░ %F{220}Installing %F{33}goenv%F{220} Go Version Management (%F{33}syndbg/goenv%F{220})…%f"
	command anyenv install goenv && \
		print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
		print -P "%F{160}▓▒░ The clone has failed.%f%b"
fi

# ghq
if ! [[ -x $(command -v ghq) ]]; then
	print -P "%F{33}▓▒░ %F{220}Installing %F{33}ghq%F{220} Manage remote repository clones (%F{33}x-motemen/ghq%F{220})…%f"
	if [[ "$(uname)" == "Linux" ]]; then
		command curl -L -o /tmp/ghq.zip https://github.com/x-motemen/ghq/releases/latest/download/ghq_linux_amd64.zip
	elif [[ "$(uname)" == "Darwin" ]]; then
		command curl -L -o /tmp/ghq.zip https://github.com/x-motemen/ghq/releases/latest/download/ghq_darwin_amd64.zip
	fi
	command arc -strip-components 1 -overwrite unarchive /tmp/ghq.zip /tmp/ghq && \
		mv /tmp/ghq/ghq $PREFIX/bin/ && \
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
	command mv /tmp/peco/peco $PREFIX/bin/ && \
		print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
		print -P "%F{160}▓▒░ The installation has failed.%f%b"
	command rm -rf /tmp/peco*
fi

#
# Nodenv
#

if [[ ! -f $ANYENV_ROOT/envs/nodenv/bin/nodenv ]]; then
	print -P "%F{33}▓▒░ %F{220}Installing %F{33}nodenv%F{220} Groom your app's Node environment with nodenv. (%F{33}nodenv/nodenv%F{220})…%f"
	command anyenv install nodenv && \
		print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
		print -P "%F{160}▓▒░ The clone has failed.%f%b"
	command mkdir -p "$ANYENV_ROOT/envs/nodenv/plugins" && \
		git clone https://github.com/pine/nodenv-yarn-install.git "$ANYENV_ROOT/envs/nodenv/plugins/nodenv-yarn-install" && \
		print -P "%F{33}▓▒░ %F{34}Installation yarn plugin successful.%f%b" || \
		print -P "%F{160}▓▒░ The clone has failed.%f%b"
fi

#
# Pyenv
#

export PYENV_ROOT=$ANYENV_ROOT/envs/pyenv

if [[ ! -f $ANYENV_ROOT/envs/pyenv/bin/pyenv ]]; then
	print -P "%F{33}▓▒░ %F{220}Installing %F{33}pyenv%F{220} Simple Python Version Management: pyenv (%F{33}pyenv/pyenv%F{220})…%f"
	command anyenv install pyenv && \
		print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
		print -P "%F{160}▓▒░ The clone has failed.%f%b"
	print -P "%F{33}▓▒░ %F{220}Installing %F{33}miniconda3%F{220} Miniconda is a free minimal installer for conda."
	command $PYENV_ROOT/bin/pyenv install miniconda3-latest && \
		$PYENV_ROOT/bin/pyenv global miniconda3-latest && \
		print -P "%F{33}▓▒░ %F{34}Installation miniconda3 successful.%f%b" || \
		print -P "%F{160}▓▒░ The clone has failed.%f%b"
fi

#
# Jenv
#

if [[ "$(uname)" == "Darwin" ]]; then
	if [[ ! -f $ANYENV_ROOT/envs/jenv/bin/jenv ]]; then
		print -P "%F{33}▓▒░ %F{220}Installing %F{33}jenv%F{220} Master your Java Environment with jenv (%F{33}jenv/jenv%F{220})…%f"
		command anyenv install jenv && \
			print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
			print -P "%F{160}▓▒░ The clone has failed.%f%b"
	fi
fi

#
# FFmpeg
#

if [[ "$(uname)" == "Linux" ]]; then
	if [[ ! -f $PREFIX/bin/ffmpeg ]]; then
		print -P "%F{33}▓▒░ %F{220}Installing %F{33}ffmpeg%F{220} ffmpeg with Intel QSV in docker (%F{33}AkashiSN/ffmpeg-docker%F{220})…%f"
		command curl -L -o /tmp/fffmpeg-5.0.1-linux-amd64.tar.xz https://github.com/AkashiSN/ffmpeg-docker/releases/latest/download/ffmpeg-5.0.1-linux-amd64.tar.xz && \
			arc -strip-components 1 -overwrite unarchive /tmp/ffmpeg-5.0.1-linux-amd64.tar.xz /tmp/ffmpeg && \
			mv /tmp/ffmpeg/bin/* ${PREFIX}/bin/ && \
			mv /tmp/ffmpeg/lib/* ${PREFIX}/lib/ && \
			print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
			print -P "%F{160}▓▒░ The download has failed.%f%b"
	fi
fi

#
# clone dotfiles
#

if [[ ! -d $GOPATH/src/github.com/AkashiSN/dotfiles ]]; then
	print -P "%F{33}▓▒░ %F{220}Installing %F{33}dotfiles%F{220} dotfiles (%F{33}AkashiSN/dotfiles%F{220})…%f"
	command ghq get git@github.com:AkashiSN/dotfiles.git && \
		print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
		(print -P "%F{160}▓▒░ The clone has failed.%f%b" && \
		print -P "%F{220}▓▒░ Retry to clone.%f%b" && \
		mkdir -p $GOPATH/src/github.com/AkashiSN/dotfiles && \
		git clone https://github.com/AkashiSN/dotfiles.git $GOPATH/src/github.com/AkashiSN/dotfiles && \
		print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
		print -P "%F{160}▓▒░ The clone has failed.%f%b")
else
	print -P "%F{33}▓▒░ %F{220}Updating %F{33}dotfiles%F{220}%f"
	(cd $GOPATH/src/github.com/AkashiSN/dotfiles && git pull) && \
	print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
	print -P "%F{160}▓▒░ The clone has failed.%f%b"
fi

print -P "%F{33}▓▒░ %F{220}Linking %F{33}dotfiles%F{220}%f"
command ln -snfv $GOPATH/src/github.com/AkashiSN/dotfiles/.zshrc $HOME/.zshrc && \
		ln -snfv $GOPATH/src/github.com/AkashiSN/dotfiles/.zlogout $HOME/.zlogout && \
		ln -snfv $GOPATH/src/github.com/AkashiSN/dotfiles/.vimrc $HOME/.vimrc && \
		ln -snfv $GOPATH/src/github.com/AkashiSN/dotfiles/.tmux.conf $HOME/.tmux.conf && \
		ln -snfv $GOPATH/src/github.com/AkashiSN/dotfiles/.gitconfig $HOME/.gitconfig && \
		ln -snfv $GOPATH/src/github.com/AkashiSN/dotfiles/.gitignore_global $HOME/.gitignore_global && \
		ln -snfv $GOPATH/src/github.com/AkashiSN/dotfiles/.Xmodmap $HOME/.Xmodmap

if [[ "$(uname)" == "Darwin" ]]; then
	command chmod 755 /usr/local/share/zsh && \
		chmod 755 /usr/local/share/zsh/site-functions
fi

if ! [ "$SSH_CONNECTION" ]; then
	print -P "%F{33}▓▒░ %F{220}Linking %F{33}.ssh%F{220}%f"
	command mkdir -p $HOME/.ssh && \
			ln -snfv $GOPATH/src/github.com/AkashiSN/dotfiles/.ssh/config $HOME/.ssh/config && \
			ln -snfv $GOPATH/src/github.com/AkashiSN/dotfiles/.ssh/gpg.pub $HOME/.ssh/gpg.pub
fi

/bin/echo -n "Do you want to change default shell to zsh? [y/N]: ";
if read -q; then;
	zsh=false
	if [[ "$(uname)" == "Linux" ]]; then
		if [[ $(cat /etc/passwd | grep $HOME) =~ "zsh" ]]; then
			zsh=true
		fi
	elif [[ "$(uname)" == "Darwin" ]]; then
		if [[ $(dscl . -read ~/ UserShell) =~ "zsh" ]]; then
			zsh=true
		fi
	fi

	if ! $zsh ; then
		print -P "%F{33}▓▒░ %F{34}Change login shell to zsh%f%b"
		export user=$(whoami) && \
		sudo chsh -s $(which zsh) $user && \
		print -P "%F{33}▓▒░ %F{34}All complete, Restart your shell (exec \$SHELL -l) .%f%b" || \
		print -P "%F{160}▓▒░ Changeing login shell has failed.%f%b"
	fi
fi
