# 00-options.zsh — shell options / history / 表示

export TERM=xterm-256color # 色空間
export WORDCHARS="*?_-.[]~=&;!#$%^(){}<>" # 区切り文字

autoload -Uz colors && colors # 色を有効にして、実行する

LISTMAX=1000 # 補完リストが多いときに尋ねない
DIRSTACKSIZE=100 # ディレクトリスタックの最大サイズ

setopt AUTO_MENU # タブキーの連打で自動的にメニュー補完
setopt AUTO_LIST # 曖昧な補完で、自動的に選択肢をリストアップ
setopt AUTO_PARAM_KEYS # 変数名を補完する
setopt PROMPT_SUBST # プロンプト文字列で各種展開を行なう
setopt AUTO_RESUME # サスペンド中のプロセスと同じコマンド名を実行した場合はリジュームする
setopt RM_STAR_SILENT # rm *で確認を求める機能を無効化する
setopt MARK_DIRS # ファイル名の展開でディレクトリにマッチした場合 末尾に / を付加
setopt list_types # 補完候補一覧でファイルの種別を識別マーク表示(ls -F の記号)
setopt NO_BEEP #BEEPを鳴らさない
setopt ALWAYS_LAST_PROMPT # 補完候補など表示する時はその場に表示し、終了時に画面から消す
setopt AUTO_PARAM_SLASH # ディレクトリ名を補完すると、末尾に / を付加
setopt AUTO_PUSHD # 普通のcdでもディレクトリスタックに入れる
setopt PUSHD_IGNORE_DUPS # ディレクトリスタックに、同じディレクトリを入れない
setopt LIST_PACKED # 補完候補を詰めて表示
unsetopt CORRECT # コマンドのスペルの訂正を使用しない
setopt NOTIFY # ジョブの状態をただちに知らせる
setopt MULTIOS # 複数のリダイレクトやパイプに対応
setopt NUMERIC_GLOB_SORT # ファイル名を数値的にソート
setopt MAGIC_EQUAL_SUBST # =以降でも補完できるようにする
setopt PRINT_EIGHT_BIT # 補完候補リストの日本語を正しく表示
setopt BRACE_CCL # echo {a-z}などを使えるようにする
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
setopt HIST_EXPAND # 補完時にヒストリを自動的に展開する
setopt NO_PROMPTCR # 改行コードで終らない出力もちゃんと出力する
setopt INTERACTIVE_COMMENTS # コマンドラインでも # 以降をコメントと見なす
setopt COMPLETE_IN_WORD # 語の途中でもカーソル位置で補完
setopt NULL_GLOB # ワイルドカードをゼロ個の文字列として展開

HISTFILE=$HOME/.zsh_history  # ヒストリーファイルの設定
HISTSIZE=1000000 # ヒストリーサイズ設定
SAVEHIST=1000000 # ヒストリーサイズ設定

HISTTIMEFORMAT="[%Y/%M/%D %H:%M:%S] " # ヒストリの一覧を読みやすい形に変更
