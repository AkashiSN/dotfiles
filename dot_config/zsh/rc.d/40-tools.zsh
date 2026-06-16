# 40-tools.zsh — compinit 後に必要なツール連携・補完。
# aqua 管理ツールのネイティブ補完は run_onchange スクリプトが site-functions へ生成し、
# compinit が自動ロードする。ここには fpath 化できないものだけを置く。

# fzf (aqua 管理): キーバインド(C-r/C-t/M-c) + ** 補完。--zsh をキャッシュして source。
if command -v fzf &> /dev/null ;then
  _load_completion fzf 'fzf --zsh' "$(command -v fzf)"
fi

# google cloud sdk（補完スクリプト同梱・source 専用）
if [ -f /usr/share/google-cloud-sdk/completion.zsh.inc ]; then
  source /usr/share/google-cloud-sdk/completion.zsh.inc
fi

if [ -f /opt/google-cloud-sdk/completion.zsh.inc ]; then
  export PATH=/opt/google-cloud-sdk/bin:$PATH
  source /opt/google-cloud-sdk/completion.zsh.inc
fi

# aws cli（bash 動的補完）
if command -v aws_completer &> /dev/null ;then
  complete -C "$(which aws_completer)" aws
fi

# tenv（補完は site-functions に事前生成。ここでは env のみ）
if command -v tenv &> /dev/null ;then
  export TENV_AUTO_INSTALL=true
  export TENV_VALIDATION=sha
fi

# terraform（bash 動的補完）
if command -v terraform &> /dev/null ;then
  complete -o nospace -C "$(which terraform)" terraform
  alias tf="terraform"
fi

# kubectl（非 aqua: ランタイム生成をキャッシュ）
if command -v kubectl > /dev/null 2>&1;then
  _load_completion kubectl 'kubectl completion zsh' "$(command -v kubectl)"
  alias k="kubectl"
fi

# ssh agent (1Password)
if ! [ "$SSH_CONNECTION" ]; then
  if [ -S "${HOME}/.1password/agent.sock" ]; then
    export SSH_AUTH_SOCK="${HOME}/.1password/agent.sock"
  fi
fi
