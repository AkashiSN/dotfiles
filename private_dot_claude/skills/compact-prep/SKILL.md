---
name: compact-prep
description: |
  Claude Code の /compact 実行前に、現セッションの作業状態を一時 state file へ保存する。
  MANDATORY TRIGGERS: /compact-prep, compact-prep, 圧縮準備, compact 準備, コンパクト準備, 圧縮前状態保存。
  DO NOT TRIGGER: compact 後の復旧、通常の進捗報告、plan 作成、context 使用率の雑談。
argument-hint: "[復旧メモ]"
allowed-tools: Read, Write, Bash(printenv CLAUDE_CODE_SESSION_ID), Bash(id -u), Bash(mkdir *), Bash(date *), Bash(pwd)
---

# compact-prep

`/compact` の圧縮サマリーは会話履歴を自然文へ要約したもので、**作業指示と作業ログの区別**、
**却下した案とその理由**、**未検証であること**が落ちる。落ちると却下済みの案を再実装したり、
検証前にデプロイしたりする。それらを圧縮前に
`${TMPDIR:-/tmp}/claude-compact-<UID>/state/<SESSION_ID>.md` へ退避する。

## Strict procedure profile

- Strictness: strict-procedure。state file の内容と保存完了報告が成果そのもの。
- Hard gate: session_id が取得できない場合、**推測した名前で state file を作らない**。
  取得不能として停止する。別セッションの state を上書きすると復旧が壊れる。
- Forcing function: 保存先パスと見出しの順序を固定し、保存後に読み返して欠落を検知する。
- Completion receipt: state file パス、保存した主要項目、未確認項目、`/compact` の案内を報告する。

## 手順

1. `printenv CLAUDE_CODE_SESSION_ID` でセッション ID を取得する。
   空なら state file を作らず、session_id が取得できないため準備未完了と報告して停止する。
2. `id -u` で UID を取得し、保存先を
   `${TMPDIR:-/tmp}/claude-compact-<UID>/state/<SESSION_ID>.md` に決める。
   `mkdir -p -m 700 <base>` と `mkdir -p -m 700 <base>/state` を先に実行する
   (`<base>` は `${TMPDIR:-/tmp}/claude-compact-<UID>`)。
   パスに UID を含めるのは、共有マシンでは `TMPDIR` が `/tmp` で全員共通になり、固定名だと
   先に作ったユーザがディレクトリを所有して他ユーザが書けなくなるため。700 にするのは
   state file に作業判断が入るので他ユーザから読ませないため。
3. TaskList、作業中の plan / spec ファイル、agmsg の spawn 状態、編集中ファイルを確認する。
4. state file に次の見出しを**この順**で保存する。
   - `# Compact Prep State`
   - `## Active Plan`
   - `## Current Phase`
   - `## TaskList Summary`
   - `## Session Decisions`
   - `## Constraints and Blockers`
   - `## Worker Topology`
   - `## Editing Files`
   - `## Recovery Notes`
5. 保存後に state file を読み直し、上記の見出しがすべて存在することを確認する。
6. ユーザーに「準備完了。`/compact` を実行してください。」と伝える。

## 各見出しに書くこと

| 見出し | 内容 |
| --- | --- |
| `Active Plan` | 作業中の plan / spec ファイルの**絶対パス**。無ければ「無し」 |
| `Current Phase` | 現在のフェーズ／ステップ。**検証済みか未検証か**を必ず書く |
| `TaskList Summary` | in-progress と pending のタスク一覧と補足 |
| `Session Decisions` | ユーザーが選んだ案、**不採用にした案とその理由**。圧縮で最も落ちやすい |
| `Constraints and Blockers` | 制約、ブロッカー、未完了の検証。「実機確認まで配置しない」等の条件はここ |
| `Worker Topology` | agmsg で spawn 済みの相手（チーム / 自分 / レビュー役）。**despawn 未了なら明記**。未使用なら「未使用」 |
| `Editing Files` | 編集中のファイルと、未保存・未検証の注意点 |
| `Recovery Notes` | 圧縮後の自分への申し送り。引数で復旧メモを渡されたらここへ含める |

`Worker Topology` を落とすと、圧縮後に codex の bridge を片付け忘れる。生き残った bridge は
レビュー役宛のメッセージを黙って飲むため、事故が見えない形で起きる。

## Completion receipt

完了時は次を含める。

- state file パス
- 保存した主要項目
- 未確認項目と理由
- `準備完了。/compact を実行してください。`
