# 00-options.zsh — shell options / history / 表示
#
# ここに置いてよいのは「表示・補完・履歴」だけ。**コマンドの引数や意味を変える
# オプションは置かない**。zsh の既定から外すと、bash の書き方で書かれたコマンドが
# 黙って違う対象に対して成功する。実例:
#   NULL_GLOB        マッチ 0 件で引数ごと消える → `grep p *.md` が stdin でハングする
#   BRACE_CCL        `{json}` が `j n o s` の 4 引数に化ける
#   MARK_DIRS        glob 結果が `sub` → `sub/`（rsync は末尾の / で意味が変わる）
#   MAGIC_EQUAL_SUBST `--out=~/x` が `--out=/home/you/x` に展開される
#   NUMERIC_GLOB_SORT glob の並びが f1,f10,f2 → f1,f2,f10 に変わる
# いずれも zsh の既定は off。詳細は docs/zsh-cheatsheet.md の「既定から外さないオプション」。

export WORDCHARS="*?_-.[]~=&;!#$%^(){}<>" # 区切り文字

autoload -Uz colors && colors # 色を有効にして、実行する

LISTMAX=1000 # 補完リストが多いときに尋ねない
DIRSTACKSIZE=100 # ディレクトリスタックの最大サイズ

setopt AUTO_MENU # タブキーの連打で自動的にメニュー補完
setopt AUTO_LIST # 曖昧な補完で、自動的に選択肢をリストアップ
unsetopt LIST_AMBIGUOUS # 共通接頭辞を入れた Tab でも一覧を出す(2 回目の Tab から巡回に入る)
setopt AUTO_PARAM_KEYS # 変数名を補完する
setopt PROMPT_SUBST # プロンプト文字列で各種展開を行なう
setopt LIST_TYPES # 補完候補一覧でファイルの種別を識別マーク表示(ls -F の記号)
setopt NO_BEEP #BEEPを鳴らさない
setopt ALWAYS_LAST_PROMPT # 補完候補など表示する時はその場に表示し、終了時に画面から消す
setopt AUTO_PARAM_SLASH # ディレクトリ名を補完すると、末尾に / を付加
setopt LIST_PACKED # 補完候補を詰めて表示
unsetopt CORRECT # コマンドのスペルの訂正を使用しない
setopt NOTIFY # ジョブの状態をただちに知らせる
setopt MULTIOS # 複数のリダイレクトやパイプに対応
setopt PRINT_EIGHT_BIT # 補完候補リストの日本語を正しく表示
setopt HIST_IGNORE_SPACE # 余分な空白は詰めて記録
setopt APPEND_HISTORY # ヒストリファイルを上書きするのではなく、追加するようにする
setopt EXTENDED_HISTORY # ヒストリに時刻情報もつける
setopt HIST_EXPIRE_DUPS_FIRST # 履歴がいっぱいの時は最も古いものを先ず削除
setopt HIST_FIND_NO_DUPS #履歴検索中、重複を飛ばす
setopt HIST_NO_FUNCTIONS # ヒストリリストから関数定義を除く
setopt HIST_IGNORE_DUPS # 前のコマンドと同じならヒストリに入れない
setopt HIST_IGNORE_ALL_DUPS # 重複するヒストリを持たない
setopt INC_APPEND_HISTORY # 履歴をインクリメンタルに追加
setopt HIST_NO_STORE # history コマンドをヒストリに入れない
setopt HIST_REDUCE_BLANKS # 履歴から冗長な空白を除く
setopt SHARE_HISTORY # 履歴を共有
setopt HIST_SAVE_NO_DUPS # 古いコマンドと同じものは無視
setopt NO_PROMPTCR # 改行コードで終らない出力もちゃんと出力する
setopt INTERACTIVE_COMMENTS # コマンドラインでも # 以降をコメントと見なす
setopt COMPLETE_IN_WORD # 語の途中でもカーソル位置で補完

HISTFILE=$HOME/.zsh_history  # ヒストリーファイルの設定
HISTSIZE=1000000 # ヒストリーサイズ設定
SAVEHIST=1000000 # ヒストリーサイズ設定
