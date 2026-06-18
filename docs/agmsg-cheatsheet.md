# agmsg チートシート

[agmsg](https://github.com/fujibee/agmsg) は、CLI エージェント（Claude Code / Codex /
Gemini CLI 等）同士が**ローカルの SQLite を介して直接メッセージをやり取り**するツール。
デーモンもネットワークも不要。このリポジトリでは nvim の [IDE モード](nvim-cheatsheet.md#ide-モード)で
左上＝codex / 右上＝claude を並べ、**両エージェントに相互レビューさせる**ために導入している。

## 導入（chezmoi）

- `.chezmoiscripts/run_onchange_after_40-ai-assistants.sh.tmpl` の末尾で、claude / codex
  本体の導入に続けて公式 `setup.sh` を curl ワンライナーで実行して導入する
  （`curl -fsSL .../setup.sh | bash -s -- --cmd agmsg`、既存導入なら `--update`）。
  agmsg は claude/codex の設定を書き換えるため、両者を入れた**後**（同スクリプトの最後）で走らせる。
- `setup.sh` は一時ディレクトリに `main` を `git clone --depth 1` → `install.sh "$@"` を
  実行 → 一時ディレクトリを破棄するブートストラップ（引数を install.sh に転送）。
  常に最新（main）から導入し、永続的なソースクローンは残さない。
- **再インストール／更新を強制したいとき**は、スクリプト中の
  `# agmsg-reinstall-marker: <日付>` 行を書き換える（内容が変わり run_onchange が再実行される）。
- agmsg は **chezmoi 管理外**の以下を書き換える（だから run スクリプトで導入する）:
  - `~/.agents/skills/agmsg/`（スクリプト・テンプレート・DB・teams 設定）
  - `~/.claude/commands/agmsg.md`（Claude Code スラッシュコマンド）
  - `~/.codex/config.toml`（Codex のサンドボックス writable_roots 追記。Codex 導入済みの場合）
- `sqlite3`（メッセージ DB）と `git`（setup.sh の clone）が必須。どちらも
  before_10（パッケージ前提）で導入される。macOS は brew formula の `sqlite` / `git`、
  Linux はディストリのパッケージマネージャ（Ubuntu: `apt install zsh git sqlite3`、
  AL2023: `dnf install zsh git sqlite`）で導入する。

## チームへの参加（プロジェクトごとに一度）

各プロジェクトの cwd で **一度だけ** 実行し、チーム名と自分のエージェント名を登録する。
自動化はせず手動運用。

| エージェント | 起動 |
| --- | --- |
| Claude Code | `/agmsg` |
| Codex | `$agmsg` |

> **チーム** = メッセージを共有するグループ。同じチームに参加したエージェント同士が
> 互いのメッセージを見て返信できる。codex / claude は **同一プロジェクト（cwd）で起動**
> しないとチーム会話が成立しないため、IDE モードは両者を cwd 直下で起動している。

## 基本コマンド（Claude Code）

| コマンド | 動作 |
| --- | --- |
| `/agmsg` | インボックス確認 |
| `/agmsg send <agent> <message>` | 指定エージェントにメッセージ送信 |
| `/agmsg team` | チームメンバー一覧 |
| `/agmsg history` | メッセージ履歴 |
| `/agmsg mode [monitor\|turn\|both\|off]` | 配信モードの確認 / 切替 |

Codex / Gemini CLI などは `$agmsg` でインボックスを開き、あとは
自然言語で指示する（例: 「claude にレビュー完了と伝えて」「チームに誰がいる?」）。

## 配信モード（delivery mode）

| モード | 仕組み | 遅延 |
| --- | --- | --- |
| `monitor` | リアルタイム push（Claude Code 既定） | 約5秒 |
| `turn` | エージェントのターン間でチェック（Codex 既定） | 次のやり取りまで |
| `both` | monitor を主、turn を保険に併用 | 約5秒（取りこぼしは turn で回収） |
| `off` | 手動のみ（`/agmsg` を明示的に叩く） | — |

## claude ↔ codex 相互レビュー運用

両者が**同じプロジェクトディレクトリ**で**同じチーム**に参加していることが前提。

1. claude（左上）から依頼:
   ```
   /agmsg send codex "src/auth.js の認証モジュールをレビューして"
   ```
2. codex（右上）が配信モードに従って受信 → ファイルを見て返信:
   ```
   $agmsg        # 例:「claude にレビュー完了と結果を伝えて」
   ```
3. claude が monitor なら約5秒で、turn なら次ターンで受信。

> レビューの発火は手探り運用。まずは agmsg を入れて claude ↔ codex がメッセージを
> やり取りできる状態を確認することから始める。

## 役割管理など（Claude Code 追加コマンド）

| コマンド | 動作 |
| --- | --- |
| `/agmsg actas <name>` | このプロジェクトで別の役割に切り替え |
| `/agmsg drop <name>` | このプロジェクトから役割を外す |
| `/agmsg spawn <type> <name>` | 新規エージェントを起動（claude-code / codex） |
| `/agmsg despawn <name> [--force]` | spawn したエージェントを停止 |
| `/agmsg reset` | このプロジェクトの登録をクリア |
| `/agmsg version` | バージョン表示 |

## シェルレベル CLI（自動化用）

```
~/.agents/skills/agmsg/scripts/send.sh    <team> <from> <to> "<message>"
~/.agents/skills/agmsg/scripts/inbox.sh   <team> <agent_id>
~/.agents/skills/agmsg/scripts/history.sh <team> [agent_id] [limit]
~/.agents/skills/agmsg/scripts/team.sh    <team>
~/.agents/skills/agmsg/scripts/whoami.sh  <project_path> <type>
```
