# herdr チートシート

複数の AI コーディングエージェント（codex / claude 等）を束ねる端末マルチプレクサ
[herdr](https://github.com/ogulcancelik/herdr) の起動・キーバインド・設定挙動のリファレンス。
単一の Rust バイナリで、tmux 級の永続セッション + エージェント状態検知 + socket API を提供する。

- **導入**: aqua で管理（`dot_config/aquaproj-aqua/aqua.yaml` の `ogulcancelik/herdr`）
- **設定ファイル**: `~/.config/herdr/config.toml`（chezmoi ソース = `dot_config/herdr/config.toml`）
- **prefix キー**: `Ctrl-b`（herdr デフォルト。tmux の `Ctrl-a` とは別キー。以下 `<prefix>` と表記）
- **テーマ**: Catppuccin（ghostty / nvim と統一）

> 表記: `<prefix>` = Ctrl-b。「prefix+X」は prefix を打ってから X。
> `prefix+alt+X` のような alt 併用は端末（ghostty）依存で効かない場合がある。

---

## 起動・セッション

| コマンド | 動作 |
| --- | --- |
| `herdr` | 永続セッションを起動 / アタッチ（サーバが無ければ起動） |
| `herdr --session <name>` | 名前付きセッションを起動 / アタッチ |
| `herdr session attach <name>` | 既存の名前付きセッションへ復帰 |
| `herdr --remote <ssh-target>` | リモートホストのセッションへ SSH 経由でアタッチ（切断耐性・接続多重化つき） |
| `herdr status` | ローカルクライアントと稼働中サーバの状態表示 |
| `herdr server reload-config` | 起動中サーバへ `config.toml` を再読込 |
| `herdr server stop` | サーバ停止（API ソケット経由） |
| `herdr update` | 最新版をダウンロードして更新 |
| `herdr completion zsh` | zsh 補完を生成 |
| `herdr config check` | `config.toml` を検証して診断を表示 |
| `herdr config reset-keys` | `config.toml` をバックアップしてカスタムキーを除去 |

---

## キーバインド（prefix モード）

いずれも `<prefix>` を打ってから続けて押す。主要な既定バインドを抜粋（全量は `herdr --default-config`）。

| キー | 動作 |
| --- | --- |
| `<prefix> ?` | ヘルプ |
| `<prefix> s` | 設定 |
| `<prefix> q` | デタッチ（セッションは生かしたまま抜ける） |
| `<prefix> shift+r` | config 再読込 |
| `<prefix> w` | ワークスペースピッカー |
| `<prefix> shift+n` | 新規ワークスペース |
| `<prefix> shift+g` | 新規 git worktree |
| `<prefix> c` | 新規タブ |
| `<prefix> p` / `<prefix> n` | 前 / 次のタブ |
| `<prefix> 1..9` | タブを番号で切替 |
| `<prefix> v` | ペインを縦分割 |
| `<prefix> -` | ペインを横分割 |
| `<prefix> x` | ペインを閉じる |
| `<prefix> z` | ペインをズーム（全画面トグル） |
| `<prefix> h/j/k/l` | 左/下/上/右のペインへフォーカス |
| `<prefix> tab` / `<prefix> shift+tab` | 次 / 前のペインへ巡回 |
| `<prefix> b` | サイドバーの表示トグル |
| `<prefix> e` | スクロールバックを編集 |
| `<prefix> r` | リサイズモード |

---

## 設定挙動（`config.toml` で有効化している項目）

デフォルトから変更 / 有効化しているのは以下。ファイル内では該当行に `# ← 設定` を付けている。

| 設定 | 値 | 目的 |
| --- | --- | --- |
| `[theme] name` | `catppuccin` | 端末(ghostty)・nvim と配色を統一。ghostty は固定ダークなので `auto_switch` は未使用 |
| `[ui.toast] delivery` | `system` | 背景エージェントの状態変化（要対応/完了）を macOS 通知センターへ。初回は OS の通知許可が必要 |
| `[experimental] switch_ascii_input_source_in_prefix` | `true` | prefix モード中だけ ASCII 配列へ一時切替し、抜けたら元へ戻す（日本語 IME 有効のまま prefix を取りこぼさない。macOS 専用） |
| `[experimental] reveal_hidden_cursor_for_cjk_ime` | `true` | claude/codex など自前カーソル描画の TUI でも IME 候補ウィンドウが追従する |
| `[experimental] cjk_ime_agents` | `["claude","codex","pi"]` | カーソル追従を実際に使うエージェントに限定 |

> 反映は `herdr server reload-config` または `<prefix> shift+r`。検証は `herdr config check`。
> `~/.config/herdr/` 内の `session.json` / `*.log` / `release-notes.json` は**実行時の状態ファイル**で、
> chezmoi ソースには含めない（管理対象は `config.toml` のみ）。

---

## エージェント状態 integration（claude / codex）

サイドバーの状態表示（作業中 / 要対応 / 完了）と `[ui.toast] delivery=system` の通知精度を上げるため、
各エージェントに herdr 公式フックを入れている。無くても端末出力ヒューリスティックで推定は効くが、
フックからの報告の方が正確で、codex⇄claude 相互レビューで片方が止まったのを取りこぼしにくい。

**chezmoi で自動導入**している（手動で `herdr integration install` を叩く必要はない）:

- `.chezmoiscripts/run_onchange_after_45-herdr-integration.sh.tmpl` が `chezmoi apply` 時に
  `herdr integration install claude` / `... codex` を実行する。install が書くのは以下（**chezmoi 管理外**・
  herdr がバージョン管理する実行時ファイル）:
  - claude: `~/.claude/hooks/herdr-agent-state.sh`（フック本体・マシン固有パスなしのポータブル）
  - codex : `~/.codex/herdr-agent-state.sh` + `~/.codex/hooks.json` + `config.toml` に `hooks = true`
- 例外は **claude の `~/.claude/settings.json` への `SessionStart` hook 追記**。これは chezmoi 管理ファイル
  （`private_dot_claude/settings.json.tmpl`）と衝突するため、hook エントリを**ソース側に焼き込んでいる**
  （パスは `{{ .chezmoi.homeDir }}` でテンプレート化）。ソースは herdr 出力と byte 一致（キー順そのまま・
  末尾改行なし）にしてあり、install は冪等に上書きするだけなのでドリフトしない。

| コマンド | 動作 |
| --- | --- |
| `herdr integration status` | 各エージェントのフック導入状況・バージョンを表示 |
| `herdr integration status --outdated-only` | herdr 更新でフック版が古くなったものだけ表示 |
| `herdr integration install <agent>` | フックを導入 / 最新版へ更新（claude/codex/pi/… 対応） |
| `herdr integration uninstall <agent>` | フックを除去 |

> herdr 本体を更新してフック版が上がったとき（`status --outdated-only` に出る）は、
> `run_onchange_after_45-herdr-integration.sh.tmpl` 内の `herdr-integration-marker:` の日付を書き換えると
> 既存マシンでも `chezmoi apply` で再導入されて最新版に揃う。

---

## 旧 `ide` 関数との関係

`ide`（`dot_config/zsh/rc.d/50-functions.zsh`）は nvim を土台に codex(左) + claude(右) + terminal(下)
を並べ、agmsg で相互レビューさせる「AI エージェントの実行土台」だった（エディタは主に差分確認用）。
その **多重化 + 永続化** の役割は herdr がネイティブに置き換えられる。

| ide での実現手段 | herdr での代替 |
| --- | --- |
| shpool による SSH 切断耐性ラッパー | herdr の永続セッション（サーバ常駐） + `herdr --remote` |
| `claude --remote-control`（モバイル操作） | `herdr --remote <ssh-target>` でリモートのセッションへアタッチ |
| ide.lua の codex/claude/terminal パネル配置 | `<prefix> v` / `<prefix> -` で分割し、各ペインで `codex` / `claude` を直接起動 |
| 非フォーカス端末の追従スクロール自作 | herdr のペイン管理・サイドバーで状態を把握 |
| nvim ide.lua の CJK IME 回避（SIGUSR1/Resync 等） | `[experimental]` の CJK IME オプション |
| 狭画面フォールバック（iPad/Termius） | `[ui] mobile_width_threshold` によるモバイル 1 カラムレイアウト |

エディタでの差分確認は herdr の範囲外。必要なときはペイン内で `nvim` / `git diff` / lazygit を開く
（`[[keys.command]]` に lazygit を割り当てる例が `config.toml` にコメントで残っている）。
