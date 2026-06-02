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
export GOPATH=$HOME/Project
export PATH=$PREFIX/bin:$GOPATH/bin:${HOMEBREW_PATH:-}/bin:$PATH
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
		chezmoi
		aqua
		ffmpeg
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

# chezmoi (dotfile manager). On macOS it is installed via Homebrew above;
# on other platforms install the prebuilt binary into $PREFIX/bin.
if ! [[ -x $(command -v chezmoi) ]]; then
	print -P "%F{33}▓▒░ %F{220}Installing %F{33}chezmoi%F{220} dotfile manager (%F{33}twpayne/chezmoi%F{220})…%f"
	command sh -c "$(curl -fsLS get.chezmoi.io)" -- -b $PREFIX/bin && \
		print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
		print -P "%F{160}▓▒░ The installation has failed.%f%b"
fi


#
# Install aqua (declarative CLI version manager)
#

# On macOS aqua is installed via Homebrew above; on other platforms download the
# prebuilt binary into $PREFIX/bin. The tools themselves are declared in
# ~/.config/aquaproj-aqua/aqua.yaml and installed by `aqua install` after chezmoi apply.
if ! [[ -x $(command -v aqua) ]]; then
	print -P "%F{33}▓▒░ %F{220}Installing %F{33}aqua%F{220} Declarative CLI Version Manager (%F{33}aquaproj/aqua%F{220})…%f"
	if [[ "$(uname)" == "Linux" ]]; then
		command curl -fsSL -o /tmp/aqua.tar.gz https://github.com/aquaproj/aqua/releases/latest/download/aqua_linux_amd64.tar.gz && \
			tar xf /tmp/aqua.tar.gz -C /tmp aqua && \
			mv /tmp/aqua $PREFIX/bin/aqua && \
			chmod +x $PREFIX/bin/aqua && \
			print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
			print -P "%F{160}▓▒░ The installation has failed.%f%b"
		command rm -f /tmp/aqua.tar.gz
	fi
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

print -P "%F{33}▓▒░ %F{220}Applying %F{33}dotfiles%F{220} with chezmoi%f"
# Point chezmoi at this repository (the .chezmoiroot file selects the home/ subdir).
# VS Code settings (macOS only) and ~/.ssh (skipped over SSH connections) are
# handled by home/.chezmoiignore.
command mkdir -p $HOME/.config/chezmoi
cat <<EOF > $HOME/.config/chezmoi/chezmoi.toml
sourceDir = "$GOPATH/src/github.com/AkashiSN/dotfiles"
EOF
command chezmoi apply

if [[ "$(uname)" == "Darwin" ]]; then
	command chmod 755 ${HOMEBREW_PATH}/share/zsh && \
		chmod 755 ${HOMEBREW_PATH}/share/zsh/site-functions && \
		defaults write com.apple.desktopservices DSDontWriteNetworkStores True && \
		killall Finder

	if [ -S "${HOME}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock" ]; then
		command mkdir -p ~/.1password && \
			ln -sf "${HOME}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock" "${HOME}/.1password/agent.sock"
	fi

	if [ -x "/Applications/1Password.app/Contents/MacOS/op-ssh-sign" ]; then
		command ln -sf "/Applications/1Password.app/Contents/MacOS/op-ssh-sign" "${PREFIX}/bin/op-ssh-sign"
	fi
fi


#
# Install tools with aqua
#

print -P "%F{33}▓▒░ %F{220}Installing tools with %F{33}aqua%F{220}%f"
command env \
	AQUA_GLOBAL_CONFIG="$HOME/.config/aquaproj-aqua/aqua.yaml" \
	AQUA_POLICY_CONFIG="$HOME/.config/aquaproj-aqua/aqua-policy.yaml" \
	aqua install --all

# ffmpeg (macOS: Homebrew above; Linux: BtbN static GPL build into $PREFIX/bin)
if [[ "$(uname)" == "Linux" ]] && ! [[ -x $(command -v ffmpeg) ]]; then
	print -P "%F{33}▓▒░ %F{220}Installing %F{33}ffmpeg%F{220} static build (%F{33}BtbN/FFmpeg-Builds%F{220})…%f"
	FFMPEG_ARCH="linux64"
	if [[ "$(uname -m)" == "aarch64" || "$(uname -m)" == "arm64" ]]; then
		FFMPEG_ARCH="linuxarm64"
	fi
	command curl -fsSL -o /tmp/ffmpeg.tar.xz "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-${FFMPEG_ARCH}-gpl.tar.xz" && \
		tar xf /tmp/ffmpeg.tar.xz -C /tmp && \
		find /tmp/ffmpeg-master-latest-${FFMPEG_ARCH}-gpl/bin -type f -exec mv {} $PREFIX/bin/ \; && \
		print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
		print -P "%F{160}▓▒░ The installation has failed.%f%b"
	command rm -rf /tmp/ffmpeg.tar.xz /tmp/ffmpeg-master-latest-${FFMPEG_ARCH}-gpl
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
