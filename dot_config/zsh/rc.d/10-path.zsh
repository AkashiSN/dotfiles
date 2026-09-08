# 10-path.zsh — zsh 固有のパス設定。compinit(30) より前に fpath を確定させる。
#
# PATH / MANPATH / 開発系パス（LD_LIBRARY_PATH 等）と GOPATH は zsh・bash 共通の
# ~/.config/shell/env.sh にある。ここに残すのは zsh でしか意味を持たないものだけ。

export FPATH=$LOCAL_PREFIX/share/zsh/site-functions:$FPATH

mkdir -p ${LOCAL_PREFIX}/{share,lib,include,bin,share/zsh/site-functions}

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
