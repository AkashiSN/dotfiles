# sd-archive チートシート

古い SD カードを 1 ビットも変えずにセクタイメージとして保存し、写真・動画を撮影日別に
整理コピーするツール一式。macOS（Apple Silicon の MacBook Pro）で使う。

| コマンド / ファイル | ソース | 役割 |
| --- | --- | --- |
| `sd-archive` | `dot_local/bin/executable_sd-archive` | カード 1 枚ずつ: 検出 → イメージ化 → 照合 → 取り出し → 保存（root で動く） |
| `~/.local/libexec/sd-archive/block-automount` | `dot_local/libexec/sd-archive/block-automount.swift` | 実行中、外付け / リムーバブルディスクの自動マウントを拒否する常駐ツール |
| `organize-media` | `dot_local/bin/executable_organize-media` | 取り出したファイルから写真・動画を撮影日別フォルダへ整理コピー（sudo 不要） |

- 依存: `ddrescue` / `exiftool`（`run_onchange_before_10-install-packages` の「SD カードの
  アーカイブ」グループで Homebrew / MacPorts から導入）、Xcode Command Line Tools（`swiftc`）。
- `block-automount` は `chezmoi apply` 時に `run_onchange_after_51-sd-archive-build` が
  `swiftc -O` でビルドする。Swift ソースが変わると再ビルドされる。`swiftc` が無ければ
  ビルドを飛ばし、`sd-archive` は「自動マウントは防げません」と警告して動く。
- `sd-archive` と `block-automount` は macOS 専用なので、他 OS では `.chezmoiignore` で
  展開しない。`organize-media` は標準ライブラリ + exiftool だけなので OS を問わない。
- 最終保存先は TrueNAS（SMB でマウント）を想定。ZFS データセットの圧縮（lz4 / zstd）を
  有効にして置く。

## 基本原則（変更しないこと）

1. **カードには絶対に書き込まない。** macOS は自動マウント時に `.fseventsd` /
   `.Spotlight-V100` / `._*` 等を書くので、マウント自体を阻止する。
2. **ファイルコピーではなく、カード全体のセクタイメージを先に取る。** 削除済みデータ・
   隠しファイル・FAT の状態も含めて保存し、古いカードの読み込み回数も最小化する。
3. **ハッシュで検証する。** イメージとカード本体を SHA-256 で照合。転送後も照合。
4. **アーカイブ（`cardNNN/`）は不変。** 整理・リネームはすべて別ディレクトリへの「コピー」で行う。
5. 読めないセクタがあっても止まらない（ddrescue）。どこが読めなかったかを map として残す。

## 全体の流れ

```
SDカード ──(block-automount でマウント阻止)──▶ /dev/rdiskN を生読み
   │ ddrescue -n → (未読があれば) ddrescue -r3
   ▼
[作業dir]/cardNNN/card.img + card.map
   │ shasum(img) と shasum(/dev/rdiskN) を照合
   │   (食い違えば) 64MiB ずつ読み直して違う範囲を探し、カードの値が安定していればイメージを直す
   │ カードをイジェクト
   │ hdiutil attach -readonly でイメージをマウント → rsync -rt で files/ へ
   │ files.sha256 作成
   ▼ (作業dir指定時) rsync で保存先へ転送 → card.sha256 / files.sha256 で検証 → 作業dir削除
[保存先]/cardNNN/
   ▼
organize-media → [ライブラリ]/YYYY/YYYY-MM-DD/… （重複除去・ログ付き）
```

## sd-archive

```sh
sd-archive <保存先> [作業ディレクトリ]
sd-archive ~/sd-archive
sd-archive /Volumes/nas/sd-archive ~/sd-work   # 保存先が NAS など遅い / 切れやすいとき
VERIFY=0 sd-archive ~/sd-archive               # カード本体との照合（2 回目の全読み込み）を省略
```

- 一般ユーザで起動すると `sudo` で自分を起動し直す（`VERIFY` は引き継ぐ）。sudo の
  `secure_path` に `~/.local/bin` が無いので、`sudo sd-archive` では見つからない。
- カードを挿すよう促され、`yes` と入力したディスクだけを処理する。1 枚終わるたびに
  次のカードへ進むか聞かれる。

### 読めない箇所が残ったカードを続きから読み直す（`--resume`）

```sh
sd-archive --resume card002 ~/sd-archive            # 保存先の card002 を読み直す
sd-archive --resume card002 ~/sd-archive ~/sd-work  # 作業 dir に残っていればそちらを読み直す
```

- 結果が「不完全」だったカードや、途中で止めたカードに使う。別のカードリーダーに挿して再挑戦すると、
  読めなかった箇所が読めることがある。
- 起動後にカードを挿すと、容量が `info.txt` に最初に記録した `Disk Size` と同じか（途中で止めた
  `card.img` は書いたところまでの大きさしかないので、`card.img` とは比べない）、mapfile で読めている範囲の先頭（最大 1MiB）が
  カードとイメージで一致するかを確かめる。合わなければ別のカードとして何もせずに止める。
- 同じ mapfile で ddrescue を `-n`（未着手の範囲）→ 読み残しがあれば `-r3` の順に動かす。ddrescue は
  読めた範囲には書かないので、すでに読めた部分は変わらない。
- 更新するもの: `card.img`（読めた箇所の穴埋め）・`card.map`・`card.sha256`・`files/` と `files.sha256`
  （イメージから取り出し直す）。`info.txt` には `---- resume <日時> ----` と新しい結果を、`log.txt` には
  ログを追記する。**アーカイブは不変、の唯一の例外**なので、`--resume` を指定したときだけ行う。
- 1 枚処理したら終了する。同じ `cardNNN` を 2 つのプロセスで同時に読み直すことはできない。
- ddrescue が異常終了したとき（カードリーダーがエラーで切れたなど）は、`--resume` のコマンドを案内して
  そのカードの処理を終える。Ctrl+C で止めたときも含め、`cardNNN/` の持ち主は `$SUDO_USER` に戻す。

### 劣化したカードは内蔵スロットで読む

読めない箇所が多いカードは、**USB リーダーより内蔵スロットの方が速く進む**。USB リーダーでは macOS の
USB ストレージのドライバが読めないセクタを 1 回約 7 秒で何十回も読み直し（`log show` に
`IOSCSIBlockCommandsDevice … I/O error … retry N` が並ぶ）、ddrescue はその間カーネル待ち（状態 `U`）に
なって進まない。最後はデバイスが `Resource busy` で切れることもある。内蔵リーダーは早く諦めて次へ進む。
正常なカードは USB リーダーの方が速い（約 88MB/s。内蔵は約 57MB/s）。
- 読み直しで新しく読めた箇所があっても、読めない箇所が残っていれば結果は「不完全」のまま。読み残しが
  0 になれば、通常どおりカード本体との照合まで行う。

### 2 台同時に使う（内蔵スロット + USB リーダーなど）

ペインを 2 つ開き、**同じ保存先（作業ディレクトリを使うならそれも同じ）**でそれぞれ起動する。

```sh
sd-archive ~/sd-archive   # ペイン A
sd-archive ~/sd-archive   # ペイン B
```

- 両方が待っているところにカードを挿すと、先に予約できた方だけが「検出:」を表示する。
  **「検出:」が出たペインで `yes` を入力する。** もう片方は何も表示せず待ち続ける。
- 番号 `cardNNN` は保存先に `mkdir` で作れたものだけを使うので、同時に動いても重ならない。

1 枚ごとの出力 `cardNNN/`:

| ファイル | 内容 |
|---|---|
| `card.img` | カード全体の raw イメージ（カード容量と同サイズ） |
| `card.map` | ddrescue の mapfile |
| `card.sha256` | `shasum -c` 形式のイメージのハッシュ |
| `info.txt` | メモ・日時・`diskutil info` 全文・照合結果 |
| `files/<ボリューム名>/` | イメージから取り出したファイル |
| `files.sha256` | 取り出したファイル個別のハッシュ |
| `log.txt` | 処理ログ |

実装上のポイント:

- 起動時に `<スクリプトの場所>/../libexec/sd-archive/block-automount` があれば
  バックグラウンドで起動し、終了時に kill。ログは `<保存先>/block-automount.log`。
  sudo 下では HOME が root のものになりうるので、HOME ではなくスクリプトの場所から辿る。
- 起動後に**新しく現れた物理ディスク**（`diskutil list physical` の差分）だけを対象にする。内蔵 SSD 誤選択防止。
- 2 枚目以降の差分の基準は、前のカードを取り出した直後の一覧（取り出したディスクは除く）。
  取り出し後のファイル取り出し中や「次のカードを処理しますか？」の間に挿したカードも検出できる。
- 基準に入っていたディスクも、一度一覧から消えたら対象に戻す。macOS は抜いたカードの `diskN` を
  次のカードに使い回すため、挿し直したカードも同じ名前で現れる。
- 容量・名前・Protocol・Read-Only を表示し、`yes` 入力でのみ続行。
- マウント済み / 書き込み可能なら警告（ブロッカー稼働中でマウントされていなければ情報表示のみ）。
- 作業先の空き容量がカード容量 ×1.1 未満なら中止。
- 番号 `cardNNN` は、作業 dir に無く、保存先に `mkdir`（`-p` なし）で作れたものを使う（予約）。
  作業 dir を使うときも保存先に空の `cardNNN/` を先に作り、転送でそこを埋める。
- `--resume` では、読み直す `cardNNN` も `/var/run/sd-archive/` に予約する。作業 dir を指定していても、
  読み直したのが保存先のものなら転送しない（転送後に元を消す処理が、保存先そのものを消すため）。
- 検出したディスクは `/var/run/sd-archive/diskN/`（中に PID）を `mkdir` で作れたときだけ処理する。
  予約はスキップ時・容量不足時・カードの取り出し直後・終了時に外す。落ちたプロセスが残した予約は、
  PID が生きていなければ取り直す。`/var/run` は再起動で消える。
- 生デバイスは `/dev/rdiskN`（バッファなしで高速）。
- 読み取り専用かどうかは `diskutil info` の `Media Read-Only`（古い名前の `Read-Only Media` も見る）で判定。
- ddrescue には `diskutil` の容量を `-s` で渡す。macOS では ddrescue が `/dev/rdiskN` の大きさを
  取れず、渡さないと進捗が `non-tried: 9223 PB` / `pct rescued: 0.00%` になり残り時間も出ない。
- カード本体の照合は `/bin/dd bs=4194304 | shasum`。`shasum` に生デバイスを直接読ませると 8KB 単位の
  読み込みになり約 18MB/s しか出ない。GNU coreutils の `dd` は `bs=4m` を受け付けないので、`/bin/dd` に
  数値で渡す。読み切れなければ「照合失敗」として記録する。
- 照合でハッシュが食い違ったら、カードを取り出す前に `repair_image` が違う箇所を探す。カードを 64MiB ずつ
  読み直してイメージと比べ、違うチャンクはさらに 2 回読む。読み直した 3 回が一致し、そのデータで直した
  イメージのハッシュが照合時のハッシュとも一致したとき（カードが同じ値を 4 回返したとき）だけ `card.img` を直し、
  `card.sha256` を書き直す。結果は「OK（カード本体と完全一致。イメージの N セクタ…を直した（LBA: …））」。
  違うチャンクが無ければ照合時の読み込みだけが食い違ったとみなし、イメージはそのままで OK とする。
  読むたびに値が変わる・違うチャンクが 8 個（512MiB）を超える・直しても照合時のハッシュと合わないときは
  直さず（直しかけたものは元に戻す）、「不一致！」に理由を添えて記録する。読み直しでカード全体をもう 1 回
  読むので、食い違ったときだけ数分余計にかかる。ファイルの取り出しは直したイメージから行う。
- 取り出しの rsync はボリューム直下の `.Spotlight-V100` を除く。macOS が保護していて root でも読めない
  （中身は `card.img` に残る）。
- 保存先を新しく作ったときと `block-automount.log` は、持ち主を `$SUDO_USER` に戻す。
- macOS 標準 bash 3.2 で動くように書いている（連想配列・mapfile 不使用）。
- sudo 下では Homebrew の PATH が落ちるので `/opt/homebrew/bin` を先頭に追加。出力は最後に `$SUDO_USER` へ chown。

## block-automount

- Disk Arbitration の `DARegisterDiskMountApprovalCallback` に登録し、対象ディスクに
  `kDAReturnNotPermitted` の dissenter を返してマウントを拒否する。
- 許可するもの: Protocol が `Disk Image` / `Virtual Interface`（＝ hdiutil でのイメージ attach）、
  内蔵かつ非リムーバブル（Mac 本体の SSD）。
- それ以外（外付け or リムーバブル）は拒否。→ **稼働中は外付け HDD・USB メモリもマウントされない**
  （保存先の外付けディスクは事前に接続しておく運用）。

## organize-media

```sh
organize-media <アーカイブ> <ライブラリ> [--dry-run] [--cards card001 ...] [--min-year 1995] [--quicktime-utc]
organize-media ~/sd-archive ~/Pictures/SD-Library --dry-run
```

- exiftool をカード 1 枚につき 1 回 `-json -a -G0 -r` で呼び、日付タグを一括取得。
- 撮影日の優先順位: `EXIF:DateTimeOriginal` → `QuickTime:CreationDate`(Apple Keys) →
  `H264:DateTimeOriginal`(AVCHD) → `XMP:DateTimeOriginal` → `EXIF:CreateDate` →
  `QuickTime:CreateDate` → `QuickTime:MediaCreateDate` → `RIFF:DateTimeOriginal`(AVI) →
  `XMP:DateCreated` → `File:FileModifyDate`
- `--min-year` より前・未来の日付は無効扱い（時計電池切れカメラの 1980 年等対策）。
  全部無効なら `_unknown-date/<card>/<元の相対パス>`。
- SHA-256 で重複除去（カードをまたいでも 1 回だけコピー）。同名衝突は `_1`, `_2` を付与。
- `shutil.copy2` で mtime 保持、コピー後にハッシュ照合。
- `.organize-log.csv`（card, source, dest, date, date_tag, sha256, status）に記録。
  再実行時は (card, source) が既出なら処理しない＝冪等。
- 動画の QuickTime:CreateDate は既定で**現地時刻扱い**（古いデジカメの実態に合わせた）。
  iPhone 等 UTC で書く機器は `--quicktime-utc`。
- 対象外: `.THM` 等の付属ファイル、`.` / `._` で始まるファイル。

## 検証状況

| 対象 | 状況 |
|---|---|
| sd-archive | MBP 14" 内蔵 SDXC リーダー + 16GB FAT32 カード（ロック有り）で 1 枚通した（2026-11-07, macOS 27.2）。イメージ化 57MB/s・4 分 36 秒、読めないセクタ 0、カード本体と完全一致、取り出し・`files.sha256` 検証 OK。この後に入れた修正（`-s`・`dd` 照合・`.Spotlight-V100` 除外・持ち主）は単体での確認のみ |
| block-automount | macOS 27.2 / Swift 6.4.2 で警告なしにビルド。内蔵リーダーのカード（`Internal` だが `Removable`）を `BLOCK`、hdiutil attach したイメージ（`Virtual Interface`）を `allow` することを確認 |
| organize-media | Linux + exiftool 13.61 で合成 JPEG を使い動作確認済み（EXIF 日付振り分け、1980 年 mtime の無効判定 → `_unknown-date`、カード間重複スキップ、再実行時スキップ、`--dry-run`）。実カメラの動画ファイルでは未確認 |

## 実機で確認できたこと（2026-11-07, MBP 14" / macOS 27.2）

- 内蔵 SDXC リーダーのカードは `Device Location: Internal` / `Removable Media: Removable` /
  `Protocol: Secure Digital` と報告され、block-automount の拒否対象に入る。
- カードを挿すと、まず「アクセサリの接続を許可しますか」が出る（リーダーの接続許可。［許可］を押す）。
  マウント拒否時に「初期化」ダイアログは出なかった。
- `diskutil list physical` の差分で内蔵リーダーのカードを新規ディスクとして検出できる。
- `diskutil info` の `Disk Size` / `Device / Media Name` / `Protocol` は想定どおり。読み取り専用は
  `Media Read-Only`（ロック時 `Yes`）。
- `ddrescue` は `/dev/rdiskN` を読める。mapfile の解析（`bad_blocks`）も正しく 0。
- `hdiutil attach -readonly -nobrowse …` は block-automount 稼働中でも通り、出力のパースも正しい。
  ただし `hdiutil attach` は非推奨の警告（`diskutil image attach` を使え）を出す。
- openrsync（`/usr/bin/rsync`）の `-rt` で FAT32 の `.Trashes` / `.fseventsd` / `._*` は問題なくコピーできる。
- USB-C カードリーダーのカードは `Protocol: USB` / `Device / Media Name: MassStorageClass` と報告され、
  block-automount の拒否対象に入る。イメージ化は約 88MB/s。
- 内蔵スロットと USB リーダーで 2 台同時に動かすと、2 つのプロセスが別々のディスクを予約し、
  番号も重ならない。block-automount は 2 つとも動き、どちらもカードを拒否する（ログには 2 行ずつ出る）。
- 同じ 16GB カードを内蔵スロットと USB リーダーで読んだイメージの SHA-256 は一致した。
- 2026-11-08 に内蔵スロットと USB リーダーの 2 台同時で 11 枚（card001〜011）を、照合・取り出しまで最後まで通した
  （1 枚は照合が不一致。下の「経緯」）。
- 先頭付近に読めない箇所がある 4GB カードでは、ddrescue が読めない箇所を飛ばして先へ進む
  （読めない箇所ごとに応答待ちが入り、残り時間の表示は数十分〜1 日と大きく揺れる）。

## 未検証事項

1. 照合の食い違いを `repair_image` が実機で直すこと（合成データのテストと、card009 を同じ手順で手作業で
   直したことのみ）。2 枚目以降のカード検出の修正（取り出し直後の一覧を基準にする）も実機で未確認。
2. 読めないセクタがあるカードでの `ddrescue -r3` の所要時間と「不完全」判定、`--resume` で最後まで
   読み切ること（2026-11-08 に 4GB の劣化カードで試したが、1 回目の読み込みの 66% で止めた）。
3. 保存先が SMB の場合の `df -k` パース、rsync 転送と `shasum -c` の速度（作業ディレクトリ指定時の転送経路）。
4. exFAT（SDXC）や FAT16 の古いカード、パーティションの無いカード。
5. organize-media の `-a -G0` 付き JSON で同名タグ重複時の挙動、AVCHD(.MTS)・AVI・3GP・MOV の
   日付取得が期待どおりか。

## 未決定・今後の候補

- **ddrescue の `-S`（スパース書き込み）**: 空き領域が 0 埋めのカードならディスク使用量が減る。
  入れる場合は `VERIFY` と同様に環境変数でオプション化する。SMB / Finder コピーでスパースが
  展開される点に注意。
- 日本語 8.3 ファイル名（古い国産機の CP932）の文字化け対策。イメージは無傷なので後処理で可。
- 削除済み写真の復元（`photorec` をイメージに対して実行）を一括処理するスクリプト。
- 途中中断時の再開（現状はフォルダを消してやり直し。手動なら同じ map を渡して ddrescue 再開可）。

## AI エージェントに触らせるときのルール

- **書き込み系のディスク操作は絶対に実行しない / 提案しない**: `dd of=/dev/…`、
  `diskutil eraseDisk|eraseVolume|partitionDisk|repairDisk|repairVolume`、ディスクユーティリティの
  First Aid、`newfs_*`、`fsck` の修復モード。
- カード（`/dev/diskN`）に対する操作は読み取りのみ。デバイス番号は毎回 `diskutil list` の容量で確認してから。
- 既存の `cardNNN/` 配下のファイルを変更・削除しない。
- `sudo` が必要なコマンドを実行する前は、何をするかをユーザーに示して確認を取る。
- スクリプトは macOS 標準の bash 3.2 互換を保つ（`/bin/bash`）。Python は標準ライブラリのみ
  （外部依存は exiftool バイナリだけ）。
- 変更したら `bash -n` / `python3 -m py_compile` を通し、可能なら `hdiutil create` で作った
  FAT32 のテスト用イメージで organize 系を確認する。

## 経緯

claude.ai のチャットで設計・実装し、`~/src/sd-archive/`（`sd-archive.sh` /
`block-automount.swift` / `organize-media.py` と引き継ぎ用 CLAUDE.md）として受け取ったものを
chezmoi 管理へ移した。移すときに、コマンド名から拡張子を外し、block-automount の置き場所を
スクリプトと同じフォルダから `~/.local/libexec/sd-archive/` へ変え（ビルドは chezmoi apply 時）、
`sudo` の自己再起動を加えた。

同日に実機で 1 枚通したところ、`diskutil info` の項目名が `Media Read-Only` に変わっていて読み取り
専用を判定できない、照合が 8KB 読みで遅い（16GB で約 15 分）、ddrescue の進捗が出ない、
`.Spotlight-V100` のコピー失敗で毎回警告が出る、保存先フォルダが root の持ち主になる、の 5 点が
見つかり直した。

続けて 2 台同時に動かせるよう、番号とカードの予約を加えた。内蔵スロット + USB リーダーで試したところ、
予約は想定どおり動いたが、次の 2 つのバグでイメージ化の直後にプロセスが落ちた。

- ddrescue に `-s` で容量を渡すと、mapfile に容量より先の範囲が `?` として残る。読み残しを数える
  `bad_blocks` がこれを数え、正常なカードを「不完全」と判定していた。容量より先の行は数えないようにした。
- `"…ブロック: $bad。…"` のように変数の直後に全角文字があると、UTF-8 ロケールの bash 3.2 は
  全角文字の先頭バイトまで変数名として読み、`set -u` で `bad�: unbound variable` になって落ちる
  （C ロケールでは起きない。sudo は利用者の `LANG` を引き継ぐ）。引き継ぎ時からあった書き方で、
  読めないブロックがあるとき・照合が合わないときだけ通る行だった。`${bad}` のように囲んだ。

同じ 2 台同時テストで、先頭付近から読めない箇所が続く 4GB カードが内蔵スロットで約 1.5MB/s しか
進まなかったため、`--resume`（同じ mapfile で続きから読み直す）を加えた。USB リーダーで読み直すと、
内蔵スロットで詰まっていたのと同じ位置（LBA `0x500280`）でカーネルの再試行が続き、2 分半後にデバイスが
`Resource busy` で切れた。カード自体の劣化で、読めない箇所では USB リーダーの方が遅いと分かった。
このとき ddrescue の異常終了で `sd-archive` が何も表示せずに終わり持ち主も root のまま残ったので、
`--resume` を案内して持ち主を戻すようにした。

2026-11-08 に USB リーダーで 2 枚目を処理したあと「次のカードを処理しますか？」で `Y` を押して
カードを差し替えても、検出されずに待ち続けた。起動し直すと検出できた。差分の基準を `Y` を押した時点で
取っていたため、それより前に挿したカードは基準に入り、挿し直しても macOS が同じ `disk5` を使い回すので
差分に出なかった（取り出した `disk5` 自体はすぐ一覧から消えることを確認した）。基準を取り出し直後に取り、
一度消えたディスクは基準から外すようにした。

同じ日に 16GB カード（card009）の照合が「不一致」になった。ddrescue も照合の `dd` も読み込みエラーなしで
最後まで読んでいた。カードを挿し直して 64MiB ずつ比べると、違うのは 1 チャンクの 4 セクタ（121 バイト、
ほとんどが 1 ビット反転）だけで、カードは読み直すたびに同じ値を返し、その値で直したイメージのハッシュは
照合時のカードのハッシュと一致した。ddrescue の 1 回目の読み込みだけが一時的に化けていた
（該当ファイルは動画 1 本）。手作業でイメージと取り出したファイルを直したうえで、同じ手順を
照合の食い違い時に自動で行う `repair_image` を加えた。
