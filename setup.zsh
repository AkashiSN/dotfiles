#!/bin/zsh
set -eu


#
# Setup env
#

ARCH="amd64"
if [[ "$(uname)" == "Darwin" ]]; then
	if [[ "$(uname -m)" == "amd64" || "$(uname -m)" == "x86_64" ]]; then
		HOMEBREW_PATH=/usr/local
		ARCH="amd64"
	elif [[ "$(uname -m)" == "arm64" ]]; then
		HOMEBREW_PATH=/opt/homebrew
		ARCH="arm64"
	fi
fi


#
# Setup PATH
#

cd $HOME
PREFIX=$HOME/.local
mkdir -p $PREFIX/bin
mkdir -p $PREFIX/lib
export PATH=$PREFIX/bin:${HOMEBREW_PATH:-}/bin:$PATH
export LD_LIBRARY_PATH=$PREFIX/lib:${LD_LIBRARY_PATH:-}
export TERM=xterm-256color
typeset -U PATH path

autoload -Uz colors && colors
autoload -Uz compinit && compinit
autoload -U +X bashcompinit && bashcompinit


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

get_latest_version_tag() {
	local repo_url=$1
	local prefix="${2:-""}"

	local version_pattern="^${prefix}\K[0-9]+(\.[0-9]+)+$"

	local latest_tag=$(git ls-remote --tags "$repo_url" | awk -F/ '{print $NF}' | \
		grep -oP "$version_pattern" | \
		sort -V | tail -n1)

	echo "$latest_tag"
}

get_latest_tag() {
	local repo_url=$1

	local latest_tag=$(git ls-remote --tags --sort='v:refname' "$repo_url" | \
		tail --line 1 | cut --delimiter='/' --fields=3)

	echo "$latest_tag"
}


#
# Check command exists
#

if [[ "$(uname)" == "Darwin" ]]; then
	command_exists "brew" || exit 1;

	brew update

	FORMULAS+=(
		coreutils
		diffutils
		ed
		findutils
		gawk
		git
		gnu-sed
		gnu-tar
		grep
		gzip
		pass
		stow
		unzip
		wget
		zsh
	)

	for formula in ${FORMULAS[@]}; do
		if brew ls --versions ${formula} ; then
			brew upgrade ${formula}
		else
			brew install ${formula}
		fi
	done

	path=(
		${HOMEBREW_PATH}/opt/coreutils/libexec/gnubin(N-/) # coreutils
		${HOMEBREW_PATH}/opt/ed/libexec/gnubin(N-/) # ed
		${HOMEBREW_PATH}/opt/findutils/libexec/gnubin(N-/) # findutils
		${HOMEBREW_PATH}/opt/gawk/libexec/gnubin(N-/) # gawk
		${HOMEBREW_PATH}/opt/gnu-sed/libexec/gnubin(N-/) # sed
		${HOMEBREW_PATH}/opt/gnu-tar/libexec/gnubin(N-/) # tar
		${HOMEBREW_PATH}/opt/grep/libexec/gnubin(N-/) # grep
		${HOMEBREW_PATH}/opt/unzip/bin(N-/) # unzip
		${HOMEBREW_PATH}/opt/curl/bin(N-/) # curl
		/usr/local/MacGPG2/bin(N-/) # MacGPG
		${path}
	)
fi

command_exists "curl" || exit 1;
command_exists "git" || exit 1;
command_exists "gpg" || exit 1;
command_exists "unzip" || exit 1;
command_exists "stow" || exit 1;


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
		command curl -L -o /tmp/ghq.zip https://github.com/x-motemen/ghq/releases/latest/download/ghq_darwin_${ARCH}.zip
	fi
	command unzip -qq /tmp/ghq.zip -d /tmp && \
		mv /tmp/ghq_*/ghq $PREFIX/bin/ && \
		print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
		print -P "%F{160}▓▒░ The installation has failed.%f%b"
	command rm -rf /tmp/ghq*
fi

# Peco
if ! [[ -x $(command -v peco) ]]; then
	print -P "%F{33}▓▒░ %F{220}Installing %F{33}peco%F{220} Simplistic interactive filtering tool (%F{33}peco/peco%F{220})…%f"
	if [[ "$(uname)" == "Linux" ]]; then
		command curl -L -o /tmp/peco.tar.gz https://github.com/peco/peco/releases/latest/download/peco_linux_amd64.tar.gz && \
			tar xvf /tmp/peco.tar.gz -C /tmp
	elif [[ "$(uname)" == "Darwin" ]]; then
		command curl -L -o /tmp/peco.zip https://github.com/peco/peco/releases/latest/download/peco_darwin_${ARCH}.zip && \
			unzip -qq /tmp/peco.zip -d /tmp
	fi
	command mv /tmp/peco_*/peco $PREFIX/bin/ && \
		print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
		print -P "%F{160}▓▒░ The installation has failed.%f%b"
	command rm -rf /tmp/peco*
fi

# tenv
if ! [[ -x $(command -v tenv) ]]; then
	print -P "%F{33}▓▒░ %F{220}Installing %F{33}tenv%F{220} OpenTofu, Terraform, Terragrunt, and Atmos version manager, written in Go. (%F{33}tofuutils/tenv%F{220})…%f"
	TENV_VERSION=$(get_latest_version_tag https://github.com/tofuutils/tenv.git v)
	if [[ "$(uname)" == "Linux" ]]; then
		command curl -L -o /tmp/tenv.tar.gz https://github.com/tofuutils/tenv/releases/download/v${TENV_VERSION}/tenv_v${TENV_VERSION}_Linux_x86_64.tar.gz && \
			tar xvf /tmp/tenv.tar.gz -C /tmp
	elif [[ "$(uname)" == "Darwin" ]]; then
		TENV_ARCH="x86_64"
		if [[ "${ARCH}" == "arm64" ]]; then
			TENV_ARCH="arm64"
		fi
		command curl -L -o /tmp/tenv.tar.gz https://github.com/tofuutils/tenv/releases/download/v${TENV_VERSION}/tenv_v${TENV_VERSION}_Darwin_${TENV_ARCH}.tar.gz && \
			tar xvf /tmp/tenv.tar.gz -C /tmp
	fi
	command mv /tmp/{tofu,tf,terragrunt,terraform,tenv,atmos} $PREFIX/bin/ && \
		print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
		print -P "%F{160}▓▒░ The installation has failed.%f%b"
fi

# terragrunt
if ! [[ -x $(command -v terragrunt) ]]; then
	if [[ "$(uname)" == "Linux" ]]; then
		command curl -L -o /tmp/terragrunt.tar.gz https://github.com/gruntwork-io/terragrunt/releases/latest/download/terragrunt_linux_amd64.tar.gz && \
			tar xvf /tmp/terragrunt.tar.gz -C /tmp
	elif [[ "$(uname)" == "Darwin" ]]; then
		command curl -L -o /tmp/terragrunt.tar.gz https://github.com/gruntwork-io/terragrunt/releases/latest/download/terragrunt_darwin_${ARCH}.tar.gz && \
			tar xvf /tmp/terragrunt.tar.gz -C /tmp
	fi
	command mv /tmp/terragrunt* $PREFIX/bin/terragrunt && \
		chmod +x $PREFIX/bin/terragrunt && \
		print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
		print -P "%F{160}▓▒░ The installation has failed.%f%b"
fi

# Nodenv
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

# Pyenv
export PYENV_ROOT=$ANYENV_ROOT/envs/pyenv
if [[ ! -f $ANYENV_ROOT/envs/pyenv/bin/pyenv ]]; then
	print -P "%F{33}▓▒░ %F{220}Installing %F{33}pyenv%F{220} Simple Python Version Management: pyenv (%F{33}pyenv/pyenv%F{220})…%f"
	command anyenv install pyenv && \
		print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
		print -P "%F{160}▓▒░ The clone has failed.%f%b"
fi

# direnv
if ! [[ -x $(command -v direnv) ]]; then
	if [[ "$(uname)" == "Linux" ]]; then
		command curl -L -o /tmp/direnv https://github.com/direnv/direnv/releases/latest/download/direnv.linux-amd64
	elif [[ "$(uname)" == "Darwin" ]]; then
		command curl -L -o /tmp/direnv https://github.com/direnv/direnv/releases/latest/download/direnv.darwin-${ARCh}
	fi
	command mv /tmp/direnv $PREFIX/bin/ && \
		chmod +x $PREFIX/bin/terragrunt && \
		print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
		print -P "%F{160}▓▒░ The installation has failed.%f%b"
fi


# AtomicParsley
if ! [[ -x $(command -v AtomicParsley) ]]; then
	print -P "%F{33}▓▒░ %F{220}Installing %F{33}AtomicParsley%F{220} AtomicParsley is a lightweight command line program for reading, parsing and setting metadata into MPEG-4 files, in particular, iTunes-style metadata. (%F{33}wez/atomicparsley%F{220})…%f"
	ATOMICPARSLEY_VERSION=$(get_latest_tag https://github.com/wez/atomicparsley.git)
	if [[ "$(uname)" == "Linux" ]]; then
		command curl -L -o /tmp/AtomicParsleyLinux.zip https://github.com/wez/atomicparsley/releases/download/${ATOMICPARSLEY_VERSION}/AtomicParsleyLinux.zip && \
			unzip -qq /tmp/AtomicParsleyLinux.zip -d /tmp
	elif [[ "$(uname)" == "Darwin" ]]; then
		command curl -L -o /tmp/AtomicParsleyMacOS.zip https://github.com/wez/atomicparsley/releases/download/${ATOMICPARSLEY_VERSION}/AtomicParsleyMacOS.zip && \
			unzip -qq /tmp/AtomicParsleyMacOS.zip -d /tmp
	fi
	command mv /tmp/AtomicParsley $PREFIX/bin/ && \
		print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
		print -P "%F{160}▓▒░ The installation has failed.%f%b"
fi

# ffmpeg
if [[ "$(uname)" == "Linux" ]]; then
	if ! [[ -x $(command -v ffmpeg) ]]; then
		print -P "%F{33}▓▒░ %F{220}Installing %F{33}ffmpeg%F{220} A complete, cross-platform solution to record, convert and stream audio and video. (%F{33}AkashiSN/ffmpeg-docker%F{220})…%f"
		FFMPEG_VERSION=$(get_latest_version_tag https://github.com/AkashiSN/ffmpeg-docker v)
		command curl -L -o /tmp/ffmpeg.tar.xz https://github.com/AkashiSN/ffmpeg-docker/releases/download/v${FFMPEG_VERSION}/ffmpeg-7.0.2-linux-amd64.tar.xz && \
			tar xvf /tmp/ffmpeg.tar.xz -C /tmp/
		command mv /tmp/ffmpeg-7.0.2-linux-amd64/bin/* $PREFIX/bin/ && \
			mv /tmp/ffmpeg-7.0.2-linux-amd64/lib/* $PREFIX/lib/ && \
			print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
			print -P "%F{160}▓▒░ The installation has failed.%f%b"
	fi
fi

# yt-dlp
if ! [[ -x $(command -v yt-dlp) ]]; then
	print -P "%F{33}▓▒░ %F{220}Installing %F{33}yt-dlp%F{220} yt-dlp is a feature-rich command-line audio/video downloader with support for thousands of sites. (%F{33}yt-dlp/yt-dlp%F{220})…%f"
	if [[ "$(uname)" == "Linux" ]]; then
		command curl -L -o /tmp/yt-dlp https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux
	elif [[ "$(uname)" == "Darwin" ]]; then
		if [[ "${ARCH}" == "arm64" ]]; then
			command curl -L -o /tmp/yt-dlp https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos
		else
			command curl -L -o /tmp/yt-dlp https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos_legacy
		fi
	fi
	command mv /tmp/yt-dlp $PREFIX/bin/ && \
		chmod +x $PREFIX/bin/yt-dlp && \
		print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
		print -P "%F{160}▓▒░ The installation has failed.%f%b"
fi


#
# Clone dotfiles
#

if [[ ! -d $GOPATH/src/github.com/AkashiSN/dotfiles ]]; then
	print -P "%F{33}▓▒░ %F{220}Installing %F{33}dotfiles%F{220} dotfiles (%F{33}AkashiSN/dotfiles%F{220})…%f"
	command mkdir -p $GOPATH/src/github.com/AkashiSN/dotfiles && \
		git clone https://github.com/AkashiSN/dotfiles.git $GOPATH/src/github.com/AkashiSN/dotfiles && \
		print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
		print -P "%F{160}▓▒░ The clone has failed.%f%b"
else
	print -P "%F{33}▓▒░ %F{220}Updating %F{33}dotfiles%F{220}%f"
	(cd $GOPATH/src/github.com/AkashiSN/dotfiles && git pull) && \
	print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
	print -P "%F{160}▓▒░ The clone has failed.%f%b"
fi

print -P "%F{33}▓▒░ %F{220}Linking %F{33}dotfiles%F{220}%f"
if [[ ! -L $HOME/.gitconfig ]]; then
  rm -f $HOME/.gitconfig
fi
command stow -v -d $GOPATH/src/github.com/AkashiSN/dotfiles -t $HOME others
command stow -v -d $GOPATH/src/github.com/AkashiSN/dotfiles -t $PREFIX/bin scripts

if [[ "$(uname)" == "Darwin" ]]; then
	command chmod 755 ${HOMEBREW_PATH}/share/zsh && \
		chmod 755 ${HOMEBREW_PATH}/share/zsh/site-functions && \
		defaults write com.apple.desktopservices DSDontWriteNetworkStores True && \
		killall Finder

	command stow --override='settings.json' -v -d $GOPATH/src/github.com/AkashiSN/dotfiles -t "$HOME/Library/Application Support/Code/User" vscode
fi

if ! [ "${SSH_CONNECTION:-}" ]; then
	print -P "%F{33}▓▒░ %F{220}Linking %F{33}.ssh%F{220}%f"
	command mkdir -p $HOME/.ssh && \
		stow -v -d $GOPATH/src/github.com/AkashiSN/dotfiles -t $HOME/.ssh ssh
fi


#
# Import gpgkey
#

if [[ ! $(gpg --list-keys nishi) ]]; then
	print -P "%F{33}▓▒░ %F{220}Import %F{33}gpg key%F{220}%f"
	gpg --import $GOPATH/src/github.com/AkashiSN/dotfiles/gpg/nishi.gpg
	echo -e "5\ny\n" | gpg --command-fd 0 --edit-key "nishi" trust
fi

if [[ ! -f $(gpgconf --list-dir homedir)/gpg-agent.conf ]]; then
	print -P "%F{33}▓▒░ %F{220}Setting to %F{33}gpg-agent.conf%F{220}%f"
	if [[ "$(uname -r)" == *microsoft* ]]; then
		cat <<EOF > $(gpgconf --list-dir homedir)/gpg-agent.conf
pinentry-program  /usr/bin/pinentry-curses
EOF
	elif [[ "$(uname)" == "Darwin" ]]; then
		cat <<EOF > $(gpgconf --list-dir homedir)/gpg-agent.conf
pinentry-program  /usr/local/MacGPG2/libexec/pinentry-mac.app/Contents/MacOS/pinentry-mac
EOF
	fi
	cat <<EOF >> $(gpgconf --list-dir homedir)/gpg-agent.conf

enable-ssh-support
default-cache-ttl-ssh    7200
max-cache-ttl-ssh       28800
EOF
fi


#
# Change default shell
#

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
	/bin/echo -n "Do you want to change default shell to zsh? [y/N]: ";
	if read -q; then;
		print -P "\n%F{33}▓▒░ %F{34}Change login shell to zsh%f%b"
		export user=$(whoami) && \
		sudo usermod -s $(which zsh) $user && \
		print -P "%F{33}▓▒░ %F{34}All complete, Restart your shell (exec zsh -l) .%f%b" || \
		print -P "%F{160}▓▒░ Changeing login shell has failed.%f%b"
	fi
fi
