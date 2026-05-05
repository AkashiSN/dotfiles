#!/usr/bin/env bash
# dji_workflow.sh - DJI Osmo Pocket 4 → コピー → 結合 → Immichアップロード (immich-go版)
#
# 依存: bash >= 4.2 (printf '%(...)T' を使用), GNU coreutils, rsync, ffmpeg, ffprobe, immich-go
# インストール: brew install bash coreutils rsync ffmpeg immich-go
# 注: macOS 標準の /bin/bash は 3.2 で非対応のため、PATH に brew bash があることを前提
#     PATH に /opt/homebrew/opt/coreutils/libexec/gnubin が含まれている前提
#
# 出力レイアウト ($DEST_DIR 配下):
#   _originals/  rsync で SD から取り込んだそのままのファイル (LRF含む)
#   upload/      immich-go の入力ディレクトリ。結合済みMP4 + 単独動画/写真の hardlink
#
# 実行例:
#   # 1. Immich の接続情報を環境変数で渡す (~/.zshenv 等で永続化推奨)
#   export IMMICH_GO_SERVER="https://immich.example.com"
#   export IMMICH_GO_API_KEY="xxxxxxxxxxxxxxxxxxxx"
#
#   # 2. デフォルトはドライラン (immich-go --dry-run)。コピーと結合は実施され、
#   #    Immichへの実アップロードはスキップ。挙動確認に使う
#   ./scripts/dji_workflow.sh
#
#   # 3. 本番アップロード
#   DRY_RUN=0 ./scripts/dji_workflow.sh
#
#   # 4. 本番アップロード + 完了後に結合元 (_originals/) を削除して容量節約
#   DRY_RUN=0 DELETE_MERGED_SOURCES=1 ./scripts/dji_workflow.sh
#
#   # 5. ローカルへのコピーと結合のみ (Immich アクセス不要)
#   SKIP_UPLOAD=1 ./scripts/dji_workflow.sh
#
#   # 6. SD カードを別の場所にマウントしている場合
#   SD_MOUNT=/Volumes/Untitled DRY_RUN=0 ./scripts/dji_workflow.sh
#
#   # 7. 任意の DEST_DIR を指定 (デフォルトは SD 内最古撮影日 YYYYMMDD)。
#   #    同じ SD を再投入した場合、自動で同じ DEST_DIR が選ばれて
#   #    rsync が差分のみ転送する
#   DEST_DIR=~/Movies/OsmoPocket4/myproject ./scripts/dji_workflow.sh

set -euo pipefail

# ============================================================
# 設定 (環境に合わせて変更してください)
# ============================================================
SD_MOUNT="${SD_MOUNT:-/Volumes/SD_Card}"     # SDカードのマウントポイント
SRC_DCIM="${SD_MOUNT}/DCIM"                  # DJIファイルのDCIM
DEST_BASE="${DEST_BASE:-${HOME}/Movies/OsmoPocket4}"  # コピー先ベース
# DEST_DIR を環境変数で渡せば既存ディレクトリに差分追加できる。
# 未指定なら main 内で SD カードの最古撮影日 (YYYYMMDD) から自動生成し、
# 同じ SD を再投入したときに同じディレクトリに rsync 差分追加されるようにする
DEST_DIR="${DEST_DIR:-}"

# 結合判定: 前のファイル終端と次のファイル開始の許容誤差(秒)
# 実機計測: 連続録画ギャップ最大0.76秒、別録画最小10.95秒なので5秒で十分
SPLIT_TOLERANCE=5

# Immich設定 (環境変数 IMMICH_GO_SERVER / IMMICH_GO_API_KEY でも上書き可)
IMMICH_SERVER="${IMMICH_GO_SERVER:-}"
IMMICH_API_KEY="${IMMICH_GO_API_KEY:-}"
IMMICH_ALBUM_NAME="DJI Osmo Pocket 4"

# 写真として upload/ に hardlink する拡張子 (大文字小文字を問わず)
PHOTO_EXTS=(JPG)

# SD カードから _originals/ にコピーする拡張子 (大文字)。
# これ以外 (システムログ, 隠しファイル, サムネイルキャッシュ等) は rsync 時点で除外する
COPY_EXTS=(MP4 "${PHOTO_EXTS[@]}")

# 動作モード (デフォルトはドライランで安全側に倒す。本番は DRY_RUN=0)
DRY_RUN="${DRY_RUN:-1}"                     # 1にするとimmich-goを--dry-runで実行
SKIP_UPLOAD="${SKIP_UPLOAD:-0}"             # 1にするとアップロードをスキップ
EJECT_AFTER="${EJECT_AFTER:-1}"             # 1にすると完了後にSDをアンマウント
DELETE_MERGED_SOURCES="${DELETE_MERGED_SOURCES:-0}"  # 1にするとアップロード成功後に _originals/ を削除

# 内部パス (main で確定)
ORIGINALS_DIR=""
UPLOAD_DIR=""
GROUPS_FILE=""

# ============================================================
# ユーティリティ
# ============================================================
if [[ -t 1 ]]; then
  C_INFO=$'\033[1;34m'; C_WARN=$'\033[1;33m'; C_ERR=$'\033[1;31m'; C_RST=$'\033[0m'
else
  C_INFO=""; C_WARN=""; C_ERR=""; C_RST=""
fi

log()  { printf '%s[%(%H:%M:%S)T]%s %s\n' "$C_INFO" -1 "$C_RST" "$*"; }
warn() { printf '%s[%(%H:%M:%S)T] WARN:%s %s\n' "$C_WARN" -1 "$C_RST" "$*" >&2; }
err()  { printf '%s[%(%H:%M:%S)T] ERROR:%s %s\n' "$C_ERR" -1 "$C_RST" "$*" >&2; }
die()  { err "$*"; exit 1; }

confirm() {
  local prompt="${1:-続行しますか?}"
  read -r -p "${prompt} (y/N): " yn
  [[ "$yn" =~ ^[yY]$ ]]
}

check_deps() {
  # bash >= 4.2 が必要 (printf '%(...)T' を使うため)
  if (( BASH_VERSINFO[0] < 4 )) || { (( BASH_VERSINFO[0] == 4 )) && (( BASH_VERSINFO[1] < 2 )); }; then
    die "bash >= 4.2 が必要です (現在: ${BASH_VERSION})。brew install bash を実行してください"
  fi

  local missing=()
  for cmd in rsync ffmpeg ffprobe; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if [[ "$SKIP_UPLOAD" != "1" ]]; then
    command -v immich-go >/dev/null 2>&1 || missing+=("immich-go")
  fi
  # GNU date が必要 (BSD date は -d/--date 構文を解さない)
  if ! date --version 2>/dev/null | grep -q 'GNU coreutils'; then
    missing+=("GNU date (brew install coreutils)")
  fi
  if [[ ${#missing[@]} -gt 0 ]]; then
    die "以下のコマンドが見つかりません: ${missing[*]}
- immich-go: https://github.com/simulot/immich-go/releases から取得"
  fi
}

# 同一ファイルシステムなら hardlink、違うFSなら cp にフォールバック
# dst が既に存在する場合は何もしない (再実行時の冪等性のため)
hardlink_or_copy() {
  local src="$1" dst="$2"
  [[ -e "$dst" ]] && return 0
  ln "$src" "$dst" 2>/dev/null || cp "$src" "$dst"
}

# SDカード内の最古撮影日 (YYYYMMDD) を返す。DJIファイルが無ければ今日の日付
get_session_id() {
  local oldest
  oldest=$(find "$SRC_DCIM" -maxdepth 3 -name 'DJI_*_D.MP4' -type f -printf '%f\n' 2>/dev/null \
    | sed -E 's/^DJI_([0-9]{8}).*/\1/' \
    | sort -u | head -1)
  if [[ -z "$oldest" ]]; then
    oldest=$(date +%Y%m%d)
  fi
  echo "$oldest"
}

# ============================================================
# Step 1: SDカードから _originals/ へコピー
# ============================================================
copy_from_sd() {
  log "=== Step 1: SDカードから _originals/ へコピー ==="

  [[ -d "$SRC_DCIM" ]] || die "SDカードのDCIMが見つかりません: $SRC_DCIM"

  log "コピー元: $SRC_DCIM"
  log "コピー先: $ORIGINALS_DIR"

  log "転送元サイズ:"
  du -sh "$SRC_DCIM" | sed 's/^/  /'

  log "転送先空き容量:"
  df -h "$(dirname "$DEST_BASE")" | tail -1 | sed 's/^/  /'

  confirm "コピーを開始しますか?" || die "中断しました"

  mkdir -p "$ORIGINALS_DIR"

  # COPY_EXTS で指定された拡張子のファイルだけ転送する。
  # mtime + size 比較で差分転送 (SD は DJI 録画後の read-only 運用前提)。
  # (転送中の完全性は rsync の内部ロリングチェックサムで担保される)
  local include_args=(--include='*/')   # ディレクトリは降りる必要があるので include
  for ext in "${COPY_EXTS[@]}"; do
    include_args+=(--include="*.${ext}")
  done
  include_args+=(--exclude='*')         # マッチしない残りはすべて除外

  rsync -ah --progress --partial --stats \
    "${include_args[@]}" \
    "${SRC_DCIM}/" "$ORIGINALS_DIR/"

  log "コピー済みファイル種別:"
  find "$ORIGINALS_DIR" -type f | sed -E 's/.*\.([^.]+)$/\1/' | sort | uniq -c | sed 's/^/  /'
}

# ============================================================
# Step 2: 分割ファイル検出 → 結合
# ============================================================
filename_to_epoch() {
  local f="$1"
  local ts
  ts=$(basename "$f" | sed -E 's/DJI_([0-9]{14})_.*/\1/')
  # 14桁文字列を ISO 風に整形して GNU date に渡す
  date -d "${ts:0:4}-${ts:4:2}-${ts:6:2} ${ts:8:2}:${ts:10:2}:${ts:12:2}" +%s 2>/dev/null
}

get_duration() {
  ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "$1" 2>/dev/null \
    | awk '{printf "%d", $1}'
}

# 連続グループを検出: 1行=1グループ、ファイルパスをタブ区切り
detect_groups() {
  local target_dir="$1"
  local -a all_files

  while IFS= read -r f; do
    all_files+=("$f")
  done < <(find "$target_dir" -maxdepth 3 -name 'DJI_*_D.MP4' -type f | sort)

  [[ ${#all_files[@]} -eq 0 ]] && return 0

  local first=1
  local prev_end=0
  local -a current_group=()

  for f in "${all_files[@]}"; do
    local start dur end gap abs_gap
    start=$(filename_to_epoch "$f") || { warn "タイムスタンプ抽出失敗: $f"; continue; }
    dur=$(get_duration "$f")
    if [[ -z "$dur" ]]; then
      warn "duration取得失敗、グループ判定スキップ: $f"
      continue
    fi
    end=$((start + dur))

    if [[ $first -eq 1 ]]; then
      current_group=("$f")
      first=0
    else
      gap=$((start - prev_end))
      abs_gap=${gap#-}
      if [[ $abs_gap -le $SPLIT_TOLERANCE ]]; then
        current_group+=("$f")
      else
        printf '%s\n' "$(IFS=$'\t'; echo "${current_group[*]}")"
        current_group=("$f")
      fi
    fi

    prev_end=$end
  done

  if [[ ${#current_group[@]} -gt 0 ]]; then
    printf '%s\n' "$(IFS=$'\t'; echo "${current_group[*]}")"
  fi
}

cache_groups() {
  log "=== Step 2: 分割ファイル検出 ==="
  detect_groups "$ORIGINALS_DIR" > "$GROUPS_FILE"
  local count
  count=$(wc -l < "$GROUPS_FILE" | tr -d ' ')
  log "検出グループ数: ${count}"
}

merge_group() {
  local -a files=("$@")

  [[ ${#files[@]} -lt 2 ]] && return 0

  local first_name last_name first_seq last_seq first_ts out_name out_path list_file
  first_name=$(basename "${files[0]}" .MP4)
  last_name=$(basename "${files[-1]}" .MP4)
  first_seq=$(echo "$first_name" | sed -E 's/.*_([0-9]{4})_D/\1/')
  last_seq=$(echo "$last_name"  | sed -E 's/.*_([0-9]{4})_D/\1/')
  first_ts=$(echo "$first_name" | sed -E 's/DJI_([0-9]{14})_.*/\1/')
  out_name="DJI_${first_ts}_${first_seq}-${last_seq}_MERGED.MP4"
  out_path="${UPLOAD_DIR}/${out_name}"

  # 既に結合済みならスキップ (再実行時の冪等性)
  if [[ -e "$out_path" ]]; then
    log "結合済みのためスキップ: $(basename "$out_path")"
    return 0
  fi

  list_file=$(mktemp -t dji_concat.XXXXXX)

  for f in "${files[@]}"; do
    printf "file '%s'\n" "${f//\'/\'\\\'\'}" >> "$list_file"
  done

  log "結合: ${#files[@]}ファイル → $(basename "$out_path")"
  for f in "${files[@]}"; do log "  ← $(basename "$f")"; done

  if ! ffmpeg -nostdin -hide_banner -loglevel error -stats \
        -f concat -safe 0 -i "$list_file" \
        -c copy -fflags +genpts \
        "$out_path"; then
    warn "concat demuxer失敗。TS経由のフォールバックを試行..."
    rm -f "$out_path"
    merge_via_ts "$out_path" "${files[@]}" || {
      err "結合失敗: $out_name"
      rm -f "$list_file"
      return 1
    }
  fi

  rm -f "$list_file"
  log "✓ 結合完了: $(du -h "$out_path" | cut -f1) $(basename "$out_path")"
}

merge_via_ts() {
  local out_path="$1"; shift
  local -a files=("$@")
  local tsdir
  tsdir=$(mktemp -d -t dji_ts.XXXXXX)

  local codec
  codec=$(ffprobe -v error -select_streams v:0 \
    -show_entries stream=codec_name -of csv=p=0 "${files[0]}")
  local vbsf
  case "$codec" in
    h264) vbsf="h264_mp4toannexb" ;;
    hevc) vbsf="hevc_mp4toannexb" ;;
    *) warn "未知のコーデック: $codec"; vbsf="h264_mp4toannexb" ;;
  esac

  local concat_arg="" i=0
  for f in "${files[@]}"; do
    local ts="${tsdir}/part_$(printf '%03d' $i).ts"
    ffmpeg -nostdin -hide_banner -loglevel error \
      -i "$f" -c copy -bsf:v "$vbsf" -f mpegts "$ts" || { rm -rf "$tsdir"; return 1; }
    [[ -n "$concat_arg" ]] && concat_arg+="|"
    concat_arg+="$ts"
    i=$((i + 1))
  done

  ffmpeg -nostdin -hide_banner -loglevel error -stats \
    -i "concat:${concat_arg}" -c copy -bsf:a aac_adtstoasc \
    "$out_path" || { rm -rf "$tsdir"; return 1; }

  rm -rf "$tsdir"
}

merge_splits() {
  mkdir -p "$UPLOAD_DIR"
  local merge_count=0 single_count=0

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local -a files
    IFS=$'\t' read -r -a files <<< "$line"
    if [[ ${#files[@]} -ge 2 ]]; then
      merge_count=$((merge_count + 1))
      merge_group "${files[@]}" || warn "1グループ失敗"
    else
      single_count=$((single_count + 1))
    fi
  done < "$GROUPS_FILE"

  log "単独動画: ${single_count}本 / 結合グループ: ${merge_count}個"
}

# ============================================================
# Step 3: upload/ を構築 (単独動画と写真を hardlink)
# ============================================================
organize_for_upload() {
  log "=== Step 3: upload/ ディレクトリを構築 ==="
  mkdir -p "$UPLOAD_DIR"

  local linked_videos=0 linked_photos=0

  # 単独動画 (1ファイル1グループ) を hardlink
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local -a files
    IFS=$'\t' read -r -a files <<< "$line"
    if [[ ${#files[@]} -eq 1 ]]; then
      hardlink_or_copy "${files[0]}" "${UPLOAD_DIR}/$(basename "${files[0]}")"
      linked_videos=$((linked_videos + 1))
    fi
  done < "$GROUPS_FILE"

  # 写真を hardlink
  local find_args=()
  for ext in "${PHOTO_EXTS[@]}"; do
    [[ ${#find_args[@]} -gt 0 ]] && find_args+=(-o)
    find_args+=(-iname "*.${ext}")
  done
  while IFS= read -r f; do
    hardlink_or_copy "$f" "${UPLOAD_DIR}/$(basename "$f")"
    linked_photos=$((linked_photos + 1))
  done < <(find "$ORIGINALS_DIR" -maxdepth 3 -type f \( "${find_args[@]}" \))

  log "単独動画 ${linked_videos}本 / 写真 ${linked_photos}枚を upload/ に配置"
}

# ============================================================
# Step 4: Immich-Goでアップロード
# ============================================================
upload_to_immich() {
  log "=== Step 4: immich-goでアップロード ==="

  if [[ "$SKIP_UPLOAD" == "1" ]]; then
    log "SKIP_UPLOAD=1 のためスキップ"
    return 0
  fi

  [[ -z "$IMMICH_SERVER" ]] && die "IMMICH_GO_SERVER が設定されていません"
  [[ -z "$IMMICH_API_KEY" ]] && die "IMMICH_GO_API_KEY が設定されていません"

  log "アップロード対象ディレクトリ: $UPLOAD_DIR"
  log "アップロード先: $IMMICH_SERVER"
  log "アルバム: $IMMICH_ALBUM_NAME"

  local cmd_args=(
    upload from-folder
    --server "$IMMICH_SERVER"
    --api-key "$IMMICH_API_KEY"
    --album-name "$IMMICH_ALBUM_NAME"
    --exclude-extensions LRF
  )
  [[ "$DRY_RUN" == "1" ]] && cmd_args+=(--dry-run)
  cmd_args+=("$UPLOAD_DIR")

  immich-go "${cmd_args[@]}"

  log "✓ アップロード完了"
}

# ============================================================
# Step 5: ローカル整理
# ============================================================
cleanup_originals() {
  if [[ "$DELETE_MERGED_SOURCES" != "1" ]]; then return 0; fi
  log "=== Step 5: _originals/ を削除 ==="
  if confirm "アップロード元 (_originals/) を削除しますか? upload/ は保持されます"; then
    rm -rf "$ORIGINALS_DIR"
    log "✓ _originals/ 削除完了"
  fi
}

# ============================================================
# Step 6: アンマウント
# ============================================================
eject_sd() {
  if [[ "$EJECT_AFTER" != "1" ]]; then return 0; fi
  log "=== Step 6: SDカードをアンマウント ==="
  if confirm "SDカードを取り出しますか?"; then
    diskutil eject "$SD_MOUNT" && log "✓ アンマウント完了"
  fi
}

# ============================================================
# メイン
# ============================================================
main() {
  check_deps
  [[ -d "$SRC_DCIM" ]] || die "SDカードのDCIMが見つかりません: $SRC_DCIM"

  # DEST_DIR が未指定なら SD の最古撮影日から自動決定 (再投入時の差分追加を可能にする)
  DEST_DIR="${DEST_DIR:-${DEST_BASE}/$(get_session_id)}"
  ORIGINALS_DIR="${DEST_DIR}/_originals"
  UPLOAD_DIR="${DEST_DIR}/upload"
  GROUPS_FILE="${DEST_DIR}/.groups.tsv"

  mkdir -p "$DEST_DIR"

  log "DJI Osmo Pocket 4 ワークフロー開始"
  log "作業ディレクトリ: $DEST_DIR"
  [[ -d "$ORIGINALS_DIR" ]] && log "(既存ディレクトリに差分追加します)"

  copy_from_sd
  cache_groups
  merge_splits
  organize_for_upload
  upload_to_immich
  cleanup_originals
  rm -f "$GROUPS_FILE"
  eject_sd

  log "✓ 全工程完了: $DEST_DIR"
}

main "$@"
