# dotfiles

Managed with [chezmoi](https://www.chezmoi.io/). CLI tools are installed
declaratively with [aqua](https://aquaproj.github.io/); zsh plugins with
[sheldon](https://sheldon.cli.rs/) and the prompt with
[starship](https://starship.rs/).

## Setup

On a fresh machine (macOS: install [Homebrew](https://brew.sh/) first):

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply AkashiSN
chsh -s "$(command -v zsh)"   # change the login shell (one-time, manual)
```

`chezmoi init --apply` clones this repo into `~/.local/share/chezmoi`,
generates the config, applies the dotfiles, then runs the provisioning
scripts in `home/.chezmoiscripts/` (install packages → `aqua install` →
import GPG key → macOS tweaks).

## Day-to-day

```sh
chezmoi edit ~/.zshrc     # edit a managed file
chezmoi apply             # apply changes (re-runs scripts only when needed)
chezmoi cd                # open a shell in the source repo
```
