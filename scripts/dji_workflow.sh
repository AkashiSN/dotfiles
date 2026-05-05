#!/bin/bash
# dji_workflow.sh - DJI Osmo Pocket 4 → コピー → 結合 → Immichアップロード (immich-go版)
#
# 依存: rsync, ffmpeg, ffprobe, immich-go (https://github.com/simulot/immich-go)
# インストール: brew install immich-go  (または GitHub releases からバイナリ)
# 使い方: ./dji_workflow.sh

set -euo pipefail

# ============================================================
# 設定 (環境に合わせて変更してください)
# ============================================================
SD_MOUNT="/Volumes/SD_Card"                 # SDカードのマウントポイント
SRC_DCIM="${SD_MOUNT}/DCIM"                 # DJIファイルのDCIM
DEST_BASE="${HOME}/Movies/OsmoPocket4"      # コピー先ベース
DEST_DIR="${DEST_BASE}/$(date +%Y%m%d_%H%M%S)"

# 結合判定: 前のファイル終端と次のファイル開始の許容誤差(秒)
SPLIT_TOLERANCE=5

# Immich設定 (環境変数 IMMICH_GO_SERVER / IMMICH_GO_API_KEY でも上書き可)
IMMICH_SERVER="${IMMICH_GO_SERVER:-}"
IMMICH_API_KEY="${IMMICH_GO_API_KEY:-}"
IMMICH_ALBUM_NAME="DJI Osmo Pocket 4"

# 動作モード
DRY_RUN="${DRY_RUN:-0}"                     # 1にするとimmich-goを--dry-runで実行
SKIP_UPLOAD="${SKIP_UPLOAD:-0}"             # 1にするとアップロードをスキップ
EJECT_AFTER="${EJECT_AFTER:-1}"             # 1にすると完了後にSDをアンマウント
DELETE_MERGED_SOURCES="${DELETE_MERGED_SOURCES:-0}"  # 1にすると結合元の分割MP4を削除

# ============================================================
# ユーティリティ
# ============================================================
log()  { printf '\033[1;34m[%(%H:%M:%S)T]\033[0m %s\n' -1 "$*"; }
warn() { printf '\033[1;33m[%(%H:%M:%S)T] WARN:\033[0m %s\n' -1 "$*" >&2; }
err()  { printf '\033[1;31m[%(%H:%M:%S)T] ERROR:\033[0m %s\n' -1 "$*" >&2; }
die()  { err "$*"; exit 1; }

confirm() {
  local prompt="${1:-続行しますか?}"
  read -r -p "${prompt} (y/N): " yn
  [[ "$yn" =~ ^[yY]$ ]]
}

# 依存コマンドチェック
check_deps() {
  local missing=()
  for cmd in rsync ffmpeg ffprobe; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if [[ "$SKIP_UPLOAD" != "1" ]]; then
    command -v immich-go >/dev/null 2>&1 || missing+=("immich-go")
  fi
  if [[ ${#missing[@]} -gt 0 ]]; then
    die "以下のコマンドが見つかりません: ${missing[*]}
- immich-go: https://github.com/simulot/immich-go/releases から取得"
  fi
}

# ============================================================
# Step 1: SDカードからコピー
# ============================================================
copy_from_sd() {
  log "=== Step 1: SDカードからコピー ==="

  [[ -d "$SRC_DCIM" ]] || die "SDカードのDCIMが見つかりません: $SRC_DCIM"

  log "コピー元: $SRC_DCIM"
  log "コピー先: $DEST_DIR"

  log "転送元サイズ:"
  du -sh "$SRC_DCIM" | sed 's/^/  /'

  log "転送先空き容量:"
  df -h "$(dirname "$DEST_BASE")" | tail -1 | sed 's/^/  /'

  confirm "コピーを開始しますか?" || die "中断しました"

  mkdir -p "$DEST_DIR"

  rsync -ah --progress --partial \
    --exclude='.*' \
    "${SRC_DCIM}/" "$DEST_DIR/"

  log "チェックサム検証中..."
  local rsync_out
  rsync_out=$(rsync -ahc --stats \
    --exclude='.*' \
    "${SRC_DCIM}/" "$DEST_DIR/")
  if echo "$rsync_out" | grep -E '^Number of regular files transferred:' | grep -qv ': 0'; then
    warn "再転送が発生しました。SDカードのデータに問題がないか確認してください"
  else
    log "✓ 全ファイルのチェックサム一致"
  fi

  log "コピー済みファイル種別:"
  find "$DEST_DIR" -type f | sed -E 's/.*\.([^.]+)$/\1/' | sort | uniq -c | sed 's/^/  /'
}

# ============================================================
# Step 2: 分割ファイル検出 → 結合
# ============================================================
filename_to_epoch() {
  local f="$1"
  local ts
  ts=$(basename "$f" | sed -E 's/DJI_([0-9]{14})_.*/\1/')
  date -j -f "%Y%m%d%H%M%S" "$ts" "+%s" 2>/dev/null
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
  done < <(find "$target_dir" -maxdepth 2 -name 'DJI_*_D.MP4' -type f \
            ! -path '*/_merged/*' | sort)

  [[ ${#all_files[@]} -eq 0 ]] && return 0

  local prev_end=0
  local -a current_group=()

  for f in "${all_files[@]}"; do
    local start dur end gap abs_gap
    start=$(filename_to_epoch "$f") || { warn "タイムスタンプ抽出失敗: $f"; continue; }
    dur=$(get_duration "$f")
    end=$((start + dur))

    if [[ $prev_end -ne 0 ]]; then
      gap=$((start - prev_end))
      abs_gap=${gap#-}
      if [[ $abs_gap -le $SPLIT_TOLERANCE ]]; then
        current_group+=("$f")
      else
        printf '%s\n' "$(IFS=$'\t'; echo "${current_group[*]}")"
        current_group=("$f")
      fi
    else
      current_group=("$f")
    fi

    prev_end=$end
  done

  if [[ ${#current_group[@]} -gt 0 ]]; then
    printf '%s\n' "$(IFS=$'\t'; echo "${current_group[*]}")"
  fi
}

merge_group() {
  local merged_dir="$1"; shift
  local -a files=("$@")

  [[ ${#files[@]} -lt 2 ]] && return 0

  local first_name last_name first_seq last_seq first_ts out_name out_path list_file
  first_name=$(basename "${files[0]}" .MP4)
  last_name=$(basename "${files[-1]}" .MP4)
  first_seq=$(echo "$first_name" | sed -E 's/.*_([0-9]{4})_D/\1/')
  last_seq=$(echo "$last_name"  | sed -E 's/.*_([0-9]{4})_D/\1/')
  first_ts=$(echo "$first_name" | sed -E 's/DJI_([0-9]{14})_.*/\1/')
  out_name="DJI_${first_ts}_${first_seq}-${last_seq}_MERGED.MP4"
  out_path="${merged_dir}/${out_name}"
  list_file=$(mktemp -t dji_concat.XXXXXX)

  for f in "${files[@]}"; do
    printf "file '%s'\n" "${f//\'/\'\\\'\'}" >> "$list_file"
  done

  log "結合: ${#files[@]}ファイル → $(basename "$out_path")"
  for f in "${files[@]}"; do log "  ← $(basename "$f")"; done

  if ! ffmpeg -hide_banner -loglevel error -stats \
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

  # 元ファイル削除オプション
  if [[ "$DELETE_MERGED_SOURCES" == "1" ]]; then
    for f in "${files[@]}"; do
      rm -f "$f"
      # 対応するLRFも削除
      local lrf="${f%.MP4}.LRF"
      [[ -f "$lrf" ]] && rm -f "$lrf"
    done
    log "  結合元ファイルを削除しました"
  fi
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
    ffmpeg -hide_banner -loglevel error \
      -i "$f" -c copy -bsf:v "$vbsf" -f mpegts "$ts" || { rm -rf "$tsdir"; return 1; }
    [[ -n "$concat_arg" ]] && concat_arg+="|"
    concat_arg+="$ts"
    ((i++))
  done

  ffmpeg -hide_banner -loglevel error -stats \
    -i "concat:${concat_arg}" -c copy -bsf:a aac_adtstoasc \
    "$out_path" || { rm -rf "$tsdir"; return 1; }

  rm -rf "$tsdir"
}

# 結合元ファイルのbasename一覧を返す(アップロード除外用)
list_merged_source_basenames() {
  local target_dir="$1"
  detect_groups "$target_dir" | while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # タブ区切りで分解
    local IFS=$'\t'
    local -a files=($line)
    if [[ ${#files[@]} -ge 2 ]]; then
      for f in "${files[@]}"; do
        basename "$f"
      done
    fi
  done
}

merge_splits() {
  log "=== Step 2: 分割ファイルの検出と結合 ==="

  local merged_dir="${DEST_DIR}/_merged"
  mkdir -p "$merged_dir"

  local groups_file
  groups_file=$(mktemp -t dji_groups.XXXXXX)
  detect_groups "$DEST_DIR" > "$groups_file"

  local group_count merge_count=0 single_count=0
  group_count=$(wc -l < "$groups_file" | tr -d ' ')
  log "検出グループ数: ${group_count}"

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local IFS=$'\t'
    local -a files=($line)
    if [[ ${#files[@]} -ge 2 ]]; then
      ((merge_count++)) || true
      merge_group "$merged_dir" "${files[@]}" || warn "1グループ失敗"
    else
      ((single_count++)) || true
    fi
  done < "$groups_file"

  rm -f "$groups_file"

  log "単独動画: ${single_count}本 / 結合グループ: ${merge_count}個"

  if [[ $merge_count -eq 0 ]]; then
    rmdir "$merged_dir" 2>/dev/null || true
    log "結合対象なし"
  fi
}

# ============================================================
# Step 3: Immich-Goでアップロード
# ============================================================
upload_to_immich() {
  log "=== Step 3: immich-goでアップロード ==="

  if [[ "$SKIP_UPLOAD" == "1" ]]; then
    log "SKIP_UPLOAD=1 のためスキップ"
    return 0
  fi

  [[ -z "$IMMICH_API_KEY" ]] && die "IMMICH_API_KEY が設定されていません"

  # 結合元になったMP4をban-fileに記録(重複アップロード防止)
  local ban_file_args=()
  local merged_sources_file
  merged_sources_file=$(mktemp -t dji_merged_src.XXXXXX)
  list_merged_source_basenames "$DEST_DIR" > "$merged_sources_file"

  local source_count
  source_count=$(wc -l < "$merged_sources_file" | tr -d ' ')

  if [[ $source_count -gt 0 ]]; then
    log "結合元になった ${source_count} 個の分割MP4をban-fileで除外します"
    while IFS= read -r bn; do
      [[ -z "$bn" ]] && continue
      ban_file_args+=(--ban-file "$bn")
    done < "$merged_sources_file"
  fi

  rm -f "$merged_sources_file"

  # LRFは編集用プロキシなのでアップロード対象外
  ban_file_args+=(--ban-file "*.LRF")
  ban_file_args+=(--ban-file "*.lrf")

  log "アップロード対象ディレクトリ: $DEST_DIR"
  log "アップロード先: $IMMICH_SERVER"
  log "アルバム: $IMMICH_ALBUM_NAME"

  local cmd_args=(
    upload from-folder
    --server "$IMMICH_SERVER"
    --api-key "$IMMICH_API_KEY"
    --album-name "$IMMICH_ALBUM_NAME"
  )
  [[ "$DRY_RUN" == "1" ]] && cmd_args+=(--dry-run)
  cmd_args+=("${ban_file_args[@]}")
  cmd_args+=("$DEST_DIR")

  immich-go "${cmd_args[@]}"

  log "✓ アップロード完了"
}

# ============================================================
# Step 4: アンマウント
# ============================================================
eject_sd() {
  if [[ "$EJECT_AFTER" != "1" ]]; then return 0; fi
  log "=== Step 4: SDカードをアンマウント ==="
  if confirm "SDカードを取り出しますか?"; then
    diskutil eject "$SD_MOUNT" && log "✓ アンマウント完了"
  fi
}

# ============================================================
# メイン
# ============================================================
main() {
  log "DJI Osmo Pocket 4 ワークフロー開始"
  check_deps
  copy_from_sd
  merge_splits
  upload_to_immich
  eject_sd
  log "✓ 全工程完了: $DEST_DIR"
}

main "$@"
