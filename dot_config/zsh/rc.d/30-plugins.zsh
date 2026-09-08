# 30-plugins.zsh — sheldon / prompt / 各種 hook。
# sheldon の plugins.toml が fpath -> compinit の順で展開する。

if command -v sheldon &> /dev/null ;then
  eval "$(sheldon source)"
fi

# starship prompt（aqua 管理。初回起動は aqua proxy の解決で数秒待つことがある）
if command -v starship &> /dev/null ;then
  eval "$(starship init zsh)"
fi

# direnv
if command -v direnv &> /dev/null ;then
  eval "$(direnv hook zsh)"
fi

# fnm (node version manager, aqua 管理) — nvim/mason が node を見つけられるよう初期化
if command -v fnm &> /dev/null ;then
  eval "$(fnm env --use-on-cd)"
fi
