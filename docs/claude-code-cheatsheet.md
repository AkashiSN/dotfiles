# Claude Code の設定 チートシート

`~/.claude/settings.json` に chezmoi から配っている設定（plugin / compact 対策の hook / statusLine）の
リファレンス。

| 対象 | ソース |
| --- | --- |
| `settings.json` の `enabledPlugins` / `extraKnownMarketplaces` / `hooks` / `statusLine` | `private_dot_claude/modify_settings.json.tmpl`（`MANAGED`） |
| hook 本体 | `private_dot_claude/hooks/executable_*.sh`（`~/.claude/hooks/` へ展開） |
| `/compact-prep` スキル | `private_dot_claude/skills/compact-prep/SKILL.md`（`~/.claude/skills/compact-prep/` へ展開） |

> `~/.claude/settings.json` は Claude Code 自身が書き戻すため、chezmoi 側は
> `modify_settings.json.tmpl` で **`MANAGED` に書いたキーだけ**を所有する。ここにある設定を
> 変えるときはこのファイルを編集する（`/config` で変えても apply で戻る）。所有権の細かい規則は
> [knowledge-graph-cheatsheet.md](knowledge-graph-cheatsheet.md#書き込み先と-chezmoi-の分担)。

同じ `settings.json` で配っているもののうち、git / PR まわり（`pr-refresh-check.sh` /
`block-session-url.sh` / `attribution`）は [ai-git-cheatsheet.md](ai-git-cheatsheet.md)、
CodeGraph の MCP 権限と `prompt-hook` は [knowledge-graph-cheatsheet.md](knowledge-graph-cheatsheet.md)
にある。

---

## plugin

`enabledPlugins` / `extraKnownMarketplaces` で配る plugin について。

### 仕組み

`enabledPlugins` に書いた plugin は、`extraKnownMarketplaces` に marketplace が登録されていれば
Claude Code が起動時に自動で取得する（`~/.claude/plugins/cache/` に入り、`installed_plugins.json`
に記録される）。`claude-plugins-official` は組み込みなので登録は要らない。

| コマンド | 役割 |
| --- | --- |
| `claude plugin list` | 導入済み plugin と有効/無効 |
| `claude plugin marketplace list` | 登録済み marketplace |
| `claude plugin marketplace add <owner>/<repo>` | marketplace を取得（settings に宣言済みなら「declared in user settings」と出る） |
| `claude plugin install <plugin>@<marketplace>` | 取得を待たずその場で入れる |

### 配っているもの

| plugin | marketplace | 用途 | 前提 |
| --- | --- | --- | --- |
| `code-simplifier` | `claude-plugins-official`（組み込み） | 変更したコードの簡素化 | なし |
| `gopls-lsp` | `claude-plugins-official`（組み込み） | Go の LSP 連携 | なし |
| `superpowers` | `claude-plugins-official`（組み込み） / `superpowers-marketplace` | ブレインストーミング・TDD などの process skill 群 | なし |
| `natural-japanese` | `natural-japanese`（[coji/natural-japanese](https://github.com/coji/natural-japanese)） | 日本語文書の執筆・校正と AI 臭さの検出（`/natural-japanese`） | `uv` |

`natural-japanese` の検査スクリプト（`lint.py` / `outline.py` / `terms.py`）は PEP 723 の
インラインメタデータを持ち、`uv run` が実行時に sudachipy などを取ってくる。`uv` は aqua 管理
なので追加の手当ては要らない（[uv-cheatsheet.md](uv-cheatsheet.md)）。

### 追加・削除するとき

- plugin を足すときは `enabledPlugins` と `extraKnownMarketplaces` の**両方**を更新し、
  上の表にも行を足す。
- **登録の無い marketplace を `enabledPlugins` に書いても、エラーにはならず黙って取得されない。**
  組み込みの `claude-plugins-official` が登録不要なので気づきにくい。追加したら
  `claude plugin list` に出るところまで確認する。
- `modify_settings.json.tmpl` は現物へ**再帰マージ**する（`jq '. * $managed'`）ので、
  `enabledPlugins` から行を消しても現物からは消えない。宣言を落とすときは
  `~/.claude/settings.json` 側も手で消す:

  ```sh
  jq 'del(.enabledPlugins["<plugin>@<marketplace>"])' ~/.claude/settings.json > /tmp/s \
    && mv /tmp/s ~/.claude/settings.json
  ```

---

## コンテキスト圧縮（compact）対策と statusLine

`/compact` と自動 compact は、会話履歴を言語モデルに投げて**自然文へ要約**し、その要約で
コンテキストを組み直す。要約は「何をしたか」は残すが、**作業指示と作業ログの区別**、
**却下した案とその理由**、**まだ検証していないという事実**を落とす。落ちると、却下済みの案を
再実装する・未検証のまま次へ進む、といった事故が起きる。自動 compact は使用率 90〜95% で
勝手に発火するので、気づいたときには手遅れになりやすい。

対策は 3 つの部品でできている。

| 部品 | ソース | 役割 |
| --- | --- | --- |
| スキル | `private_dot_claude/skills/compact-prep/SKILL.md` | 圧縮前に作業状態を state file へ退避する（`/compact-prep`） |
| 復旧 hook | `hooks/executable_compact-recovery.sh`（PostCompact）+ `hooks/executable_userpromptsubmit-compact-recovery.sh` | 圧縮後の最初のプロンプトで state file を読み直させる |
| 予告 hook | `hooks/executable_statusline.sh` + `hooks/executable_userpromptsubmit-compact-prep-reminder.sh` | 自動 compact に先制される前に `/compact-prep` を促す |

登録はすべて `private_dot_claude/modify_settings.json.tmpl` の `MANAGED`（`hooks` と
`statusLine`）にある。

### 流れ

```
[使用率が閾値超]  statusline.sh              → warn/<session_id> を書く
[次のプロンプト]  ...compact-prep-reminder.sh → 「/compact-prep を提案せよ」を注入
                                               warn を消し warned/ を作る（cooldown）
[ユーザ]          /compact-prep              → state/<session_id>.md へ状態を保存
[ユーザ]          /compact
[圧縮直後]        compact-recovery.sh        → compacted/<session_id> を書く
                                               warned を消す（cooldown 解除）
[次のプロンプト]  ...compact-recovery.sh     → 「state file を読み直せ」を注入し marker を消す
```

置き場所は **`${TMPDIR:-/tmp}/claude-compact-<UID>/`**（mode 700）で、その下に
`state` / `compacted` / `warn` / `warned` が並ぶ。注入はどれも **one-shot**（読んだら消す）。

パスに UID を入れるのは、`TMPDIR` が未設定のマシン（= 全ユーザで `/tmp` が共通）で固定名に
すると、先に作ったユーザがディレクトリを所有して他ユーザの書き込みが黙って失敗するため
（hook は fail-open なのでエラーも出ない）。700 にしているのは、state file に作業判断や
未検証の情報が入るため。

`PostCompact` 自身は `additionalContext` を返せない（exit 2 でも stderr を見せるだけ）ので、
marker を挟む 2 段構成にしてある。どの hook も `jq` が無い・`session_id` が取れない・JSON が
壊れている場合は無出力で `exit 0` する（fail-open）。

### 閾値

context 使用率は **statusLine の JSON（`context_window.used_percentage`）でしか取れない**。
hook 側からは見えないので、`statusline.sh` が表示のついでに marker を書いている。

閾値は窓のサイズ（`context_window.context_window_size`）から決める。

| 窓 | 閾値 | 理由 |
| --- | --- | --- |
| 1M（拡張コンテキスト） | 60% | 自動 compact の 90〜95% まで 30% ≒ 300K の余力を残す |
| 200K（既定） | 80% | 同じ 60% だと早すぎて通知が邪魔になる。残り 40K あれば準備は足りる |

`CLAUDE_COMPACT_WARN_THRESHOLD` を export すると上書きできる。

### statusLine の表示

```
[Opus 5] chezmoi (main) ▓▓▓▓▓▓░░░░ 62%
```

モデル表示名 / カレントディレクトリ名 / git ブランチ / context 使用率のバー。バーの色は
閾値未満が緑、閾値以上が黄（`/compact-prep` を促す圏内）、閾値 +20% 以上が赤（自動 compact が
目前）。

AWS の認証が切れているときは、行の末尾に赤で `⚠ AWS 未認証: <profile>` が付く。

```
[Opus 5] chezmoi (main) ▓▓▓░░░░░░░ 31% ⚠ AWS 未認証: <profile>
```

marker（`~/.aws/.aws-login-<profile>.expired`）を置くのは `aws-login` で、statusLine は**有無を
見るだけ**。毎描画で走るので、こちらから STS を叩いて認証を確かめには行かない。別経路で入り
直して marker が取り残された場合は、creds キャッシュの期限を読んで自分で消す（`aws` は起動
しない）。仕組みは [aws-cheatsheet.md](aws-cheatsheet.md#走行中に認証が切れたとき)。

### `/compact-prep` が保存するもの

`${TMPDIR:-/tmp}/claude-compact-<UID>/state/<SESSION_ID>.md` に次の見出しで保存する。

| 見出し | 内容 |
| --- | --- |
| `Active Plan` | 作業中の plan / spec ファイルの絶対パス |
| `Current Phase` | 現在のフェーズ。**検証済みか未検証か**を必ず書く |
| `TaskList Summary` | in-progress と pending のタスク |
| `Session Decisions` | 採用した案と、**不採用にした案とその理由**（圧縮で最も落ちやすい） |
| `Constraints and Blockers` | 制約・ブロッカー・未完了の検証 |
| `Worker Topology` | agmsg で spawn 済みの相手。**despawn 未了なら明記** |
| `Editing Files` | 編集中のファイルと未保存・未検証の注意 |
| `Recovery Notes` | 圧縮後の自分への申し送り |

セッション ID は `CLAUDE_CODE_SESSION_ID` から取る。取得できないときは**推測した名前で state
file を作らず停止する**（別セッションの state を上書きすると復旧が壊れる）。

### 動作確認

```sh
# statusLine が JSON を受けて 1 行返すか（閾値の分岐込み）
echo '{"model":{"display_name":"Opus 5"},"workspace":{"current_dir":"'"$PWD"'"},
  "session_id":"test","context_window":{"used_percentage":65,"context_window_size":1000000}}' \
  | ~/.claude/hooks/statusline.sh

# marker が書かれたか
ls "${TMPDIR:-/tmp}/claude-compact-$(id -u)"/warn/

# 予告 hook が additionalContext を返すか（marker を消費する）
echo '{"session_id":"test"}' | ~/.claude/hooks/userpromptsubmit-compact-prep-reminder.sh
```

Claude Code 側の登録状況は `/hooks` と `/status` で確認できる。

### 注意

- `~/.claude/skills/` には `graphify install` が置く `graphify/` も同居するが、chezmoi は
  管理外のものを消さない（[knowledge-graph-cheatsheet.md](knowledge-graph-cheatsheet.md#graphify)）。
