---
name: codex-review
description: |
  agmsg 経由で codex にコードレビューを依頼し、結果を受け取って片付けるまでの手順。
  MANDATORY TRIGGERS: codex にレビュー, codex レビュー依頼, codex に見てもらう, 相互レビュー, agmsg でレビュー, /codex-review。
  DO NOT TRIGGER: 自分でレビューする, /code-review, PR のレビューコメント対応, agmsg で普通にメッセージを送るだけ。
argument-hint: "[レビュー対象と観点]"
allowed-tools: Bash, Read, Grep, Glob
---

# codex-review

codex を herdr のペインに立ち上げ、agmsg でレビューを依頼して、結果を受け取ったら片付ける。
**依頼のたびに spawn し、終わったら必ず片付ける。**

## Strict procedure profile

- Strictness: strict-procedure。起動フラグと片付けの順序が結果を決める。
- Hard gate: `despawn` に **`--force` 以外を打たない**。素の graceful を先に打つと二度と
  片付けられなくなる（下記）。
- Completion receipt: レビュー結果の要点、対応した指摘、片付け後の `delivery.sh status` の出力を報告する。

## 前提

端末は herdr。spawn は herdr のペインを分割してそこに codex を立てるので、**herdr のペインの
中から実行する**（`HERDR_PANE_ID` が要る）。

チーム名とエージェント名はプロジェクトごとに違う。以下では `<team>` がチーム、`<self>` が自分、
`<reviewer>` が codex のレビュー役。

```bash
S=~/.agents/skills/agmsg/scripts
$S/whoami.sh "$(pwd)"             # → agent=<self> teams=<team> ...
$S/identities.sh "$(pwd)" codex   # → <team> <reviewer>
```

`whoami.sh` が `suggest=` / `not_joined=` を返したら、このリポジトリはまだチームに参加していない。
`codex-bedrock-spawn` はその状態では止まる（別リポのチームへ join させないため）ので、先に
`/agmsg` でリポジトリ名のチームに join する。**チームはリポジトリごとに 1 つ**。git worktree は
メインチェックアウトへ解決されるので、worktree 内でも同じチーム・同じ `<self>` が返る。
新しいチームを作らない。

## 手順

```bash
S=~/.agents/skills/agmsg/scripts

codex-bedrock-spawn <reviewer> --fresh            # 起動。ペインが開く
$S/delivery.sh status codex "$(pwd)"              # → Codex bridge: ... alive を確認してから送る
$S/send.sh <team> <self> <reviewer> "<依頼>"
# 返信を待つ: $S/history.sh <team> に "<reviewer> → <self>" が現れる
$S/despawn.sh <team> <self> <reviewer> --force    # 片付け → status=forced
$S/delivery.sh status codex "$(pwd)"              # → no identities registered for this project
```

**Bedrock で動くかサブスク（OpenAI ログイン）で動くかは `~/.config/zsh/no-codex-bedrock` の
有無で決まる。** マーカーが無ければ Bedrock、あれば `codex-bedrock-spawn` が素の `spawn.sh` へ
委譲する。どちらでも手順は同じなので、レビューを頼む側が起動方法を選び分ける必要はない。

依頼文には**対象ファイル・変更の背景・見てほしい観点**を書く。背景が無いと、意図的な設計を
バグとして報告される。

## 起動フラグ

- **`--fresh` を付ける。** `spawn.sh` は resumable な過去セッションがあると既定で復帰するので、
  付けないと前の依頼の文脈が混ざる。
- **`spawn.sh` を直接使わない。`codex-bedrock-spawn` を使う。** codex の `--profile` は runtime
  コマンド専用で `codex app-server` が受け取らず、monitor モードでは TUI がその共有 app-server へ
  `--remote` で繋ぐため、素の spawn で起動した codex は Bedrock にならない。`codex-bedrock-spawn` は
  `CODEX_HOME` を Bedrock 用の一時 home へ向けたペインを作る（env なら app-server まで届く）。
  マーカーがあるときは中で素の `spawn.sh` へ委譲するので、こちらを入口にしておけば両方に効く。
- **`--force` を最初から付ける。素の graceful を先に打ってはいけない。** graceful な despawn は
  actas ロックだけを土台にしているが、codex は `actas-claim` を一度も走らせないのでロックが常に
  `free`。graceful は `status=ok note=no-live-lock` を返して**何も片付けない**うえ、離脱の直前に
  placement レコードを消す。そのため続けて `--force` を打っても `no placement record` で失敗し、
  **二度と force できなくなる**（順序は一方通行）。

## 送っても返信が来ないとき

spawn は codex の readiness を待たないので、送る前に bridge の生存を確認する。送信は成功して
いるのに `history.sh` の自分宛が増えないときは、受信経路を疑う。

```bash
$S/delivery.sh status codex "$(pwd)"
```

- `Codex bridge: ... alive` → bridge は生きている。ペインを見て、codex が承認待ちやエラーで
  止まっていないか確認する。
- `has no session recorded (N threads loaded, none identifiable as its session)` → agmsg が
  「どのスレッドがこのセッションか」を特定できていない。bridge は arm できず、送っても届かない。
- `not running` → bridge が落ちている。
- `mode: off` → 起動先に配信フック（`.codex/hooks.json`）が無い。`codex-bedrock-spawn` は起動前に
  `set monitor` するので通常は起きない。出たら `delivery.sh set monitor codex "$(pwd)"` を打って
  spawn し直す（worktree ごとに要る）。

**確実な代替は、依頼を起動時のプロンプトとして渡すこと。** 受信経路を使わないので、上のどれに
当たっても通る。返信は codex 側から送られるので受け取れる。

```bash
codex-bedrock-spawn <reviewer> --fresh --boot-prompt "<依頼。返信は
~/.agents/skills/agmsg/scripts/send.sh <team> <reviewer> <self> \"<結果>\" で送るよう書く>"
```

起動しっぱなしにすると、codex CLI が終わっても bridge だけが生き残り、`<reviewer>` 宛に送った
メッセージを黙って飲み込む。だから終わったら必ず片付ける。

## 気をつけること

- **サブスク版と Bedrock 版を同じプロジェクトで混ぜると（マーカーを付け外しした直後など）、
  開いていた側のセッションが切れる。**
  app-server はプロジェクトパスだけでキーされ設定を見ずに再利用されるので、`codex-bedrock-spawn`
  と zsh の `codex` 関数は起動前に `codex-appserver-evict` で食い違う app-server を畳む。
- Bedrock 用の一時 home を作り直した直後（`~/.codex/config.toml` かオーバレイを更新した後）は、
  ペインで `Hooks need review` が出る。`Trust all and continue` を選ぶ。codex が `hooks.state` を
  一時 home へ書くので、以後は聞かれない。対象は agmsg の配信フック。

## 関連

- 仕組みと落とし穴: `~/.local/share/chezmoi/docs/agmsg-cheatsheet.md`
- Bedrock 起動の経路: `~/.local/share/chezmoi/docs/zsh-cheatsheet.md`
