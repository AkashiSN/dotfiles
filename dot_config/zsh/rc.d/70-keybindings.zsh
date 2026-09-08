# 70-keybindings.zsh — キーバインド。

# HOME, DELETE, END キーを有効にする
bindkey "^[[H"  beginning-of-line
bindkey "^[[3~" delete-char
bindkey "^[[F"  end-of-line

# Tab は既定のまま（^I）。fzf(40) が ^I を fzf-completion で握り、`**` トリガが無ければ
# 素の補完へ落ちる。そこから先は 20-completion.zsh の menu select が受け持つ。

if [[ "$(uname)" != Darwin ]]; then
  if command -v xmodmap &> /dev/null ;then
    if [ -n "$DISPLAY" ]; then
      xmodmap $HOME/.Xmodmap
    fi
  fi
fi
