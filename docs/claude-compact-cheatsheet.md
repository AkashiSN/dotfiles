# Claude Code のコンテキスト圧縮（compact）対策

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

## 流れ

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

## 閾値

context 使用率は **statusLine の JSON（`context_window.used_percentage`）でしか取れない**。
hook 側からは見えないので、`statusline.sh` が表示のついでに marker を書いている。

閾値は窓のサイズ（`context_window.context_window_size`）から決める。

| 窓 | 閾値 | 理由 |
| --- | --- | --- |
| 1M（拡張コンテキスト） | 60% | 自動 compact の 90〜95% まで 30% ≒ 300K の余力を残す |
| 200K（既定） | 80% | 同じ 60% だと早すぎて通知が邪魔になる。残り 40K あれば準備は足りる |

`CLAUDE_COMPACT_WARN_THRESHOLD` を export すると上書きできる。

## statusLine の表示

```
[Opus 5] chezmoi (main) ▓▓▓▓▓▓░░░░ 62%
```

モデル表示名 / カレントディレクトリ名 / git ブランチ / context 使用率のバー。バーの色は
閾値未満が緑、閾値以上が黄（`/compact-prep` を促す圏内）、閾値 +20% 以上が赤（自動 compact が
目前）。

## `/compact-prep` が保存するもの

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

## 動作確認

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

## 注意

- `~/.claude/settings.json` は Claude Code 自身が書き戻すため、chezmoi 側は
  `modify_settings.json.tmpl` で **`MANAGED` に書いたキーだけ**を所有する。statusLine や
  compact 系 hook を変えるときはこのファイルを編集する（`/config` で変えても apply で戻る）。
- hook 本体は `private_dot_claude/hooks/executable_*.sh`。`~/.claude/hooks/` へ展開される。
- スキルは `~/.claude/skills/compact-prep/SKILL.md` へ展開される。同ディレクトリには
  `graphify install` が置く `graphify/` も同居するが、chezmoi は管理外のものを消さない。
