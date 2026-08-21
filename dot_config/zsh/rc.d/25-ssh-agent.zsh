# 25-ssh-agent.zsh — 対話シェル起動時に ssh-agent を用意する。
# gitui/sheldon など libgit2 系は SSH 鍵を agent 経由でしか使えず（鍵ファイルを直読みしない）、
# agent が無いと push が "bad credentials" で、gitconfig の insteadOf で SSH へ書き換わる
# clone が Auth(-16) で失敗する。
#
# 1Password のエージェントがあるホスト（ローカル）はそれを使う。無いホスト（開発サーバ等）は
# 通常の ssh-agent を常駐させて既定鍵を登録する。socket 情報は保存して再利用し多重起動しない。
# 既に使える agent（forward された agent 等）がある場合は上書きしない。
#
# ファイル番号 25 は、プラグインを clone する 30-plugins より前に agent を用意するため。
if ! [ "$SSH_CONNECTION" ] && [ -S "${HOME}/.1password/agent.sock" ]; then
  export SSH_AUTH_SOCK="${HOME}/.1password/agent.sock"
elif ! ssh-add -l > /dev/null 2>&1; then
  _ssh_agent_env="${XDG_RUNTIME_DIR:-$HOME}/.ssh-agent.env"
  [ -f "$_ssh_agent_env" ] && . "$_ssh_agent_env" > /dev/null
  if ! ssh-add -l > /dev/null 2>&1; then
    ssh-agent -s > "$_ssh_agent_env"
    . "$_ssh_agent_env" > /dev/null
  fi
  ssh-add > /dev/null 2>&1
  unset _ssh_agent_env
fi
