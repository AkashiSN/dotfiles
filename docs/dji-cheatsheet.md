# dji_workflow チートシート

DJI Osmo Pocket 4 の SD カードを SanDisk 2TB へ取り込み、分割動画を結合して
Immich へアップロードするまでのワークフロー。実体は
`dot_local/bin/executable_dji_workflow.py`（PEP 723 / `uv run --script`）。

依存: `uv` / `rsync` / `ffmpeg` / `ffprobe` / `diskutil` / `immich-go`
（immich-go はスクリプトからは起動せず、表示されたコマンドを手で実行する）。

## ディレクトリレイアウト

```
$DEST_BASE = /Volumes/SanDisk 2TB/OsmoPocket4
├── DJI_001/            ← SD の DCIM/DJI_001 と同構成。オリジナルの蓄積先
├── PANORAMA/001_XXXX/  ← 同上
├── merged/             ← 結合済み MP4 の実体。オリジナルと同じ相対パスを維持
│   └── DJI_001/DJI_20260603180513_0036-0037_MERGED.MP4
├── upload/             ← immich-go の入力。毎回作り直し、中身は全てハードリンク
│   ├── DJI_001/…
│   └── PANORAMA/001_0160/PANO_0001.JPG
└── failed_merges/      ← 結合に失敗したグループ
```

| ディレクトリ | 役割 | 消してよいか |
| --- | --- | --- |
| `DJI_001/` `PANORAMA/` など | オリジナルの蓄積先。SD の `DCIM/` と同構成 | ✗ 実体 |
| `merged/` | 結合済み MP4 の実体 | ✗ 消すと再結合が必要（16GiB 級） |
| `upload/` | immich-go の入力。全てハードリンク | ✓ 実行のたびに作り直される |
| `failed_merges/` | 結合に失敗したグループ | ✓ ハードリンク |

`merged` / `upload` / `failed_merges` は予約名で、オリジナル走査から除外される。
それ以外の `$DEST_BASE` 直下ディレクトリは全てオリジナルの置き場とみなされる。

## 典型的な手順

```bash
# IMMICH_API_KEY は ~/.zshenv 等で永続化しておく
export IMMICH_API_KEY=XXXX

# 1. SD を挿して取り込み + 結合 + upload/ 構築 + immich-go コマンド表示
#    (--since 未指定なら SD 内の最古撮影日が対象下限になる)
dji_workflow.py --immich-server https://immich.example.com

# 2. 表示された immich-go upload コマンドをコピペして実行

# 3. 撮影日時のずれを Immich API で修正
dji_workflow.py --fix-timezone --immich-server https://immich.example.com
```

アップロード自体をスクリプトが実行しないのは、時間がかかり失敗もするため。
コマンドを表示するだけにとどめて、実行はユーザーに委ねている。

### SD 無しで upload/ を組み直す

SD を挿していなくても、蓄積済みオリジナルから指定日以降を拾って `upload/` を
作り直せる。分割ファイルの結合も通常フローと同じように走る。

```bash
dji_workflow.py --since 20260718 --immich-server https://immich.example.com
```

SD が未マウントのとき `--since` は必須。省略すると `die` する。

### ドライラン

```bash
dji_workflow.py --dry-run
```

rsync は `-n`、ffmpeg 結合・ハードリンク作成・`upload/` 削除・eject を全てスキップし、
表示される immich-go コマンドにも `--dry-run` が付く。

## オプション一覧

| オプション | 既定値 | 説明 |
| --- | --- | --- |
| `--sd-mount` | `/Volumes/SD_Card` | SD カードのマウントポイント |
| `--dest-base` | `/Volumes/SanDisk 2TB/OsmoPocket4` | オリジナルの蓄積先 |
| `--since` | SD 内の最古撮影日 | `upload/` に入れる対象の下限日。`YYYYMMDD` / `YYYY-MM-DD`、指定日を含む。SD 未マウント時は必須 |
| `--immich-server` | `$IMMICH_SERVER` | 表示コマンドに埋め込む Immich サーバー URL |
| `--immich-client-timeout` | `24h` | immich-go の HTTP タイムアウト（Go duration 形式） |
| `--immich-concurrency` | `2` | immich-go の並列アップロード数。巨大ファイル時は 1〜2 推奨 |
| `--device-tag` | `DJI Osmo Pocket 4` | 常に付与されるデバイス識別タグ |
| `--tag` | — | 追加の Immich タグ（`/` で階層化可、複数指定可） |
| `--split-tolerance` | `5` | 連続録画と判定するギャップ許容秒 |
| `--split-min-size-gib` | `15.0` | 分割と判定する直前ファイルの最小サイズ |
| `--ext` | `MP4`, `JPG` | 取り込む拡張子。`MP4` / `MOV` は結合対象として扱われる |
| `--tz` | `Asia/Tokyo` | DJI ファイル名の壁時計を解釈する TZ |
| `--dry-run` | off | 全工程ドライラン |
| `--skip-copy` | off | SD があってもコピーをスキップ |
| `--eject` / `--no-eject` | on | 完了後に SD をアンマウント |
| `--fix-timezone` | off | アップロード済みアセットの撮影日時を修正するモード |
| `--yes` / `-y` | off | `upload/` 削除と `--fix-timezone` 適用の確認をスキップ |

## 処理の流れ

| Step | 内容 |
| --- | --- |
| 1 | SD の `DCIM/` を `$DEST_BASE` 直下へ rsync（SD 無し / `--skip-copy` ならスキップ） |
| 2 | `$DEST_BASE` 配下から `--since` 以降のメディアを収集 |
| 3 | 対象動画から分割グループを検出し `merged/` へ結合 |
| 4 | `upload/` を削除して作り直し、単独動画・写真・結合済み MP4 をハードリンク |
| 5 | immich-go コマンドを表示 |
| 6 | SD をアンマウント |

ffprobe は `--since` で絞った動画にしか走らない。`DJI_001/` には 300 本超の
MP4 が蓄積するので、毎回全件の duration を取ると実用にならないため。

## --since の日付判定

| ファイル | 判定 |
| --- | --- |
| `DJI_20260801100000_0001_D.MP4` | ファイル名の壁時計 → 2026-08-01 |
| `PANO_0001.JPG` | mtime を `--tz` で解釈 |

パノラマはファイル名にタイムスタンプを持たないので mtime に頼る。カメラが記録した
mtime は rsync `-a` が保存するので撮影日として使える。

## オリジナルの上書き防止と衝突リネーム

rsync は `--ignore-existing --partial-dir=.rsync-partial` で走るので、既存
オリジナルには一切書き込まない。`--partial-dir` を使うのは、中断した部分ファイルを
転送先に残すと `--ignore-existing` がそれを「既存」とみなして永久にスキップして
しまうため。

SD 側と同名で内容の違うファイル（size か mtime が相違）は、上書きせず
`<stem>_<YYYYMMDDHHMMSS>.<ext>` にリネームして退避する。タイムスタンプは SD 側
ファイルの mtime を `--tz` で解釈した壁時計。

```
PANO_0001.JPG  →  PANO_0001_20260509122400.JPG
```

- パノラマは `PANORAMA/001_XXXX/PANO_0001.JPG` のようにカメラ側の連番なので、
  SD をフォーマットすると番号が再利用されて衝突しうる。
- 退避先に同じ内容（size + mtime 一致）のファイルが既にあれば再コピーしない。
  SD を挿したまま繰り返し実行しても `_2` `_3` と増え続けることはない。
- 内容まで違う別ファイルなら `_2`, `_3` と連番が付く。

`._DJI_xxx.MP4` のような AppleDouble は本物と同じ拡張子を持つため、rsync の
`--exclude=._*` と走査側の両方で除外している。

## upload/ を作り直す挙動

`upload/` の中身はオリジナルと `merged/` へのハードリンクだけなので、削除しても
実データは失われない。実行のたびに確認プロンプトを出して削除・再構築する
（`--yes` でスキップ）。

`du -sk upload` がほぼ 0 なのに実ファイルの合計が数十 GiB になっていれば、
正しくハードリンクで構成されている。

## トラブルシューティング

| 症状 | 対処 |
| --- | --- |
| `--since で対象日を指定してください` | SD 未マウント時は `--since` が必須 |
| `upload/ がありません`（`--fix-timezone`） | 同じ `--since` で先に `upload/` を組み直す |
| `以降の対象ファイルがありません` | `--since` が新しすぎる。終了コードは 1 |
| 結合失敗 | `failed_merges/<group_id>/` を確認して手動結合を検討 |
| 不完全な動画が混ざる | `.rsync-partial/` に中断ファイルが残っていないか確認 |

## 撮影日時のずれと --fix-timezone

DJI は MP4 メタデータの `creation_time` を UTC で正しく書くが、TZ オフセットも
GPS も書かない。そのため Immich は撮影地の TZ を判定できず `localDateTime` を
UTC の壁時計のまま採用してしまい、表示時刻がずれる。immich-go の `--time-zone` は
「TZ を持たない時刻」の解釈用なので、`Z` 付きの `creation_time` には効かない。

`--fix-timezone` はアップロード後に走らせるモードで、ファイル名
（`DJI_YYYYMMDDHHMMSS_...`）の壁時計を `--tz` のオフセット付き ISO 8601 にして
Immich API（`PUT /assets/{id}` の `dateTimeOriginal`）へ書き戻す。

更新対象は `--device-tag` のタグが付いたアセットのうち、`upload/` 配下に同名の
ファイルがあるものだけ。タグには他セッションのアセットも含まれ得るための安全網。

## 経緯

以前は `$DEST_BASE/YYYYMMDD/{originals,upload}/` という日付ディレクトリ方式
だった。しかし実運用では SanDisk 側に SD と同構成でオリジナルを蓄積していたため、
`20260718/originals/DJI_001` と root の `DJI_001` に同じ動画が二重に存在する状態に
なっていた。

2026-08-01 に `$DEST_BASE` 直下へオリジナルを蓄積する方式へ移行し、`--dest-dir` を
廃止して `--since` を導入した。あわせて以下を変更した。

- 結合済み MP4 の実体を `merged/` に分離し、`upload/` を使い捨てにした
  （以前は `upload/` に実体があり、作り直すと再結合が必要だった）
- `upload/` 内でオリジナルの相対パスを維持するようにした。以前はフラット化して
  いたため、`PANORAMA/001_0160/PANO_0001.JPG` と `001_0161/PANO_0001.JPG` が
  衝突して片方が失われていた
- rsync を `--ignore-existing --partial-dir` にしてオリジナルを上書きしなくした

既存の `20260521/` `20260718/` は手動で `$DEST_BASE` 直下へ統合した。重複していた
34 ファイルはすべて同一 inode のハードリンクだったので、実データの損失なく統合できた。
`20260521/upload/` にあった MERGED の実体は `merged/DJI_001/` へ移した。
