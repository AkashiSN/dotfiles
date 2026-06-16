# 70-keybindings.zsh — キーバインド。

# HOME, DELETE, END キーを有効にする
bindkey "^[[H"  beginning-of-line
bindkey "^[[3~" delete-char
bindkey "^[[F"  end-of-line

if [[ "$(uname)" != Darwin ]]; then
  if command -v xmodmap &> /dev/null ;then
    if [ -n "$DISPLAY" ]; then
      xmodmap $HOME/.Xmodmap
    fi
  fi
fi
