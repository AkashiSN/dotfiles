# 50-functions.zsh — カスタム関数。

# ghq 管理リポジトリを peco で選んで cd（キー: C-]）
function peco-src () {
  local selected_dir=$(ghq list -p | peco --query "$LBUFFER")
  if [ -n "$selected_dir" ]; then
    BUFFER="cd ${selected_dir}"
    zle accept-line
  fi
  zle clear-screen
}
zle -N peco-src
bindkey '^]' peco-src

# build latex in docker — https://hub.docker.com/r/akashisn/latexmk
function latex () {
  docker run --rm -it --name="latexmk" -v `pwd`:/workdir akashisn/latexmk:2023 latexmk-ext "$@"
}

function pdfcrop () {
  docker run --rm -it --name="pdfcrop" -v `pwd`:/workdir akashisn/latexmk:2023 pdfcrop "$@"
}

function convert-crlf-to-lf () {
  find . -type f | xargs file | grep CRLF \
    | awk -F: '{print $1}' | xargs nkf -Lu --overwrite
}

function search () {
  local result="$(find . -type f)"
  for arg in "$@"; do
    result="$(echo "$result" | grep -i "$arg")"
  done
  IFS=$'\n'
  local results=($(echo "$result" ))
  for r in "${results[@]}"; do
    printf %q "$r"
    echo
  done
}

# agmsg Codex monitor(beta): orphan codex-bridge.js の掃除（.meta ベース）。
# 各 bridge は run/ に codex-bridge.<team>.<name>.{pid,meta,appserver,thread,log}
# を残し、.meta に pid= / project= / team= / name= / type= を記録する。live な
# launcher の引数に project が現れない bridge = 孤児だけを安全に kill する
# （起動中の別 Codex セッションの bridge は launcher が生きているので残す）。
function agmsg-bridge-reap () {
  local run_dir="$HOME/.agents/skills/agmsg/run"
  [[ -d $run_dir ]] || return 0
  local launchers
  launchers=$(pgrep -fl 'codex-bridge-launcher\.sh' 2>/dev/null)
  local mf line bpid bproj bargs base killed=0
  local reap_files
  for mf in $run_dir/codex-bridge.*.meta(N); do
    bpid="" bproj=""
    # .meta を key=value で読む（値にスペースを含む project パスも1行なので安全）
    while IFS= read -r line; do
      case $line in
        pid=*)     bpid=${line#pid=} ;;
        project=*) bproj=${line#project=} ;;
      esac
    done < $mf

    base=${mf%.meta}                                   # run/codex-bridge.<team>.<name>
    reap_files=( $base.pid $base.meta $base.appserver $base.thread $base.log )

    # pid 不明 / 既に死んでいる → sidecar ごと掃除
    if [[ -z $bpid ]] || ! kill -0 $bpid 2>/dev/null; then
      rm -f $reap_files; continue
    fi
    # pid 再利用ガード: 実体が codex-bridge.js でなければ触らない
    bargs=$(ps -o args= -p $bpid 2>/dev/null)
    [[ $bargs == *codex-bridge.js* ]] || continue
    # launcher 生存（= その project の Codex セッションが生きている）→ 残す
    [[ -n $bproj && $launchers == *$bproj* ]] && continue
    # 孤児: bridge を止めて sidecar も一緒に掃除
    kill $bpid 2>/dev/null && (( killed++ ))
    rm -f $reap_files
  done
  (( killed )) && print -ru2 -- "agmsg-bridge-reap: 孤児 bridge ${killed} 件を停止しました"
  return 0
}

# claude.ai 障害時などに Claude Code を Amazon Bedrock(グローバル推論プロファイル)へ
# 切り替えるための共通 env を「現在のシェル」へ export する内部ヘルパー。claude-bedrock /
# ide-bedrock から サブシェル内で呼ぶので、呼び出し元の対話シェルは汚さない(per-invocation)。
# 使う AWS プロファイルは CLAUDE_CODE_BEDROCK_AWS_PROFILE(既定 cdx-pre-dev)で AWS_PROFILE を
# 常に上書きするので、対話中に aws-switch で選んでいるプロファイルには影響されない。認証は
# aws-login(credential_process)が担うため追加ログイン不要(トークン期限切れも自動更新)。
# Bedrock 側で対象モデルのアクセス権を有効化しておくこと。リージョン/モデルは
# CLAUDE_CODE_BEDROCK_* で上書き可能。AWS_REGION はグローバルプロファイルでも SigV4 署名用に
# 具体リージョンが必要(ルーティングはグローバルプロファイルが自動で行う)。
function _claude-bedrock-env () {
  export AWS_PROFILE="${CLAUDE_CODE_BEDROCK_AWS_PROFILE:-cdx-pre-dev}"
  export CLAUDE_CODE_USE_BEDROCK=1
  export CLAUDE_CODE_USE_MANTLE=1
  export CLAUDE_CODE_ENABLE_AUTO_MODE=1
  export AWS_REGION="${CLAUDE_CODE_BEDROCK_REGION:-us-east-1}"
  export ANTHROPIC_DEFAULT_OPUS_MODEL="${CLAUDE_CODE_BEDROCK_OPUS_MODEL:-global.anthropic.claude-opus-4-8[1m]}"
  export ANTHROPIC_DEFAULT_SONNET_MODEL="${CLAUDE_CODE_BEDROCK_SONNET_MODEL:-global.anthropic.claude-sonnet-5[1m]}"
  export ANTHROPIC_DEFAULT_HAIKU_MODEL="${CLAUDE_CODE_BEDROCK_HAIKU_MODEL:-global.anthropic.claude-haiku-4-5-20251001-v1:0}"
  export ANTHROPIC_MODEL="${ANTHROPIC_DEFAULT_OPUS_MODEL}"
}

# claude を Remote Control 付きで起動できるようラップする。SSH 接続先で「引数なしの素の起動」の
# ときだけ --remote-control を付け、claude.ai / モバイル等のリモートからそのインタラクティブ
# セッションを操作できるようにする。引数付き(プロンプト・-p/--print・mcp/update 等のサブコマンド・
# -c/--resume 等)は素通しする。Remote Control のセッション名プレフィックスは claude 既定でホスト名。
# 非対話シェル(スクリプト等)では rc.d が読まれず実バイナリのままなので影響しない。
function claude () {
  if [[ -n $SSH_CONNECTION && $# -eq 0 ]]; then
    command claude --remote-control
    return
  fi
  command claude "$@"
}

# Claude Code 単体を Bedrock で起動する。通常の `claude` は claude.ai のまま無変更。
# サブシェルで env を閉じ込めるので、呼び出し後のシェルには設定が残らない。claude(関数)経由で
# 呼ぶので、SSH 接続先で引数なし起動なら Remote Control も乗る。
# 詳細: ~/.local/share/chezmoi/docs/zsh-cheatsheet.md
function claude-bedrock () {
  ( _claude-bedrock-env && claude "$@" )
}

# codex 単体を Amazon Bedrock で起動する。通常の `codex` はサブスク(OpenAI ログイン)の
# まま無変更。Bedrock 用設定は ~/.codex/bedrock.config.toml(bedrock プロファイル)へ分離し、
# --profile でベース設定の上にレイヤする。使う AWS プロファイルは CODEX_BEDROCK_AWS_PROFILE
# (既定 cdx-pre-dev)で AWS_PROFILE に渡し、その credential_process = aws-login が認証を担う。
# サブシェルで閉じ込めるので呼び出し元の対話シェルの AWS_PROFILE は汚さない。
# 詳細: ~/.local/share/chezmoi/docs/zsh-cheatsheet.md
function codex-bedrock () {
  ( export AWS_PROFILE="${CODEX_BEDROCK_AWS_PROFILE:-cdx-pre-dev}" && command codex --profile bedrock "$@" )
}

# ログイン(対話)シェル起動時に一度だけ、非ブロッキングで孤児 bridge を回収する。
[[ -d $HOME/.agents/skills/agmsg/run ]] && ( agmsg-bridge-reap & ) 2>/dev/null
