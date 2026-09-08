# 10-path.zsh — PATH / FPATH / MANPATH 等。compinit(30) より前に fpath を確定させる。

# LOCAL_PREFIX と PATH への $LOCAL_PREFIX/bin 追加は .zshenv 側(非対話シェルにも要るため)。
export MANPATH=$LOCAL_PREFIX/share/man:$MANPATH
export INFOPATH=$LOCAL_PREFIX/share/info:$INFOPATH
export LD_LIBRARY_PATH=$LOCAL_PREFIX/lib:$LD_LIBRARY_PATH
export LIBRARY_PATH=$LOCAL_PREFIX/lib:$LIBRARY_PATH
export PKG_CONFIG_PATH=$LOCAL_PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH
export C_INCLUDE_PATH=$LOCAL_PREFIX/include:$C_INCLUDE_PATH
export CPLUS_INCLUDE_PATH=$LOCAL_PREFIX/include:$CPLUS_INCLUDE_PATH
export FPATH=$LOCAL_PREFIX/share/zsh/site-functions:$FPATH

mkdir -p ${LOCAL_PREFIX}/{share,lib,include,bin,share/zsh/site-functions}

# agmsg: Codex monitor モードのシム（~/.agents/bin/codex）を本体 codex（~/.local/bin）
# より前に置く。delivery.sh set monitor codex 実行時に生成され、未生成でも実害なし。
# 詳細: docs/agmsg-cheatsheet.md の「Codex monitor モード」節。
export PATH=$HOME/.agents/bin:$PATH

# Golang (go 本体は aqua 管理)
export GOPATH=$HOME/Project
export GHQ_ROOT=$GOPATH/src
export PATH=$GOPATH/bin:$PATH

# Rancher Desktop
export PATH=$HOME/.rd/bin:$PATH

# NodeJS (Yarn)
export PATH=$HOME/.yarn/bin:$PATH

# /etc/profile.d — sh 向けに書かれたサードパーティのスクリプト群なので sh 意味論で
# source する(詳細は docs/zsh-cheatsheet.md の「/etc/profile.d の読み込み」)。
#
# emulate sh -c "source $i" は $i を文字列へ埋め込んでから sh -c に渡すため、
# ファイル名にスペースを含むと sh 側の単語分割で壊れる。関数にして "$1" のまま
# source へ渡せば、この結合を経由しないのでスペースを含むファイル名でも壊れない。
#
# emulate -L は関数内に閉じるのでグローバルのオプションを汚さない(実行後も
# nomatch=on / nullglob=off / shwordsplit=off が維持されることを確認済み)。
# サブシェル `( emulate -L sh; source $i )` にしてはいけない: profile.d が設定した
# 環境変数が親シェルへ伝播しなくなる。
_source_sh() {
  emulate -L sh
  source "$1"
}
if [ -d /etc/profile.d ]; then
  for i in /etc/profile.d/*.sh(N); do
    [ -r "$i" ] && _source_sh "$i"
  done
fi
unset -f _source_sh

# command not found handler
if [ -f /etc/zsh_command_not_found ]; then
  source /etc/zsh_command_not_found
fi
