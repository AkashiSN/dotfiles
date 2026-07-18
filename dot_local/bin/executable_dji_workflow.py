#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["rich"]
# ///
"""SD カード → コピー → 動画結合 → upload/ 構築 → immich-go コマンド表示のワークフロー.

実際の Immich アップロードはこのスクリプトでは実行せず、最後に immich-go コマンドを
表示するだけにとどめる。アップロードは時間がかかり失敗もするため、表示されたコマンドを
コピペして別途手動で実行する想定。

DJI Osmo Pocket 4 を主対象としているが、`--device-tag` と `--ext` で
他デバイスにも流用できる構成。

依存:
  - uv (`brew install uv`)         # PEP 723 を解釈し依存を裏で解決する
  - rsync, ffmpeg, ffprobe
  - macOS の `diskutil` (アンマウント用)
  - immich-go (このスクリプトからは起動しないが、表示コマンドの実行側で必要)

設定:
  - 通常設定値は CLI 引数のみで指定する
  - 機密情報のみ環境変数フォールバックを許可:
      IMMICH_SERVER  → --immich-server の既定値
  - API キーは表示コマンド中で常に "$IMMICH_API_KEY" 参照になるため、
    実行時に環境変数を export しておくこと

タイムゾーン:
  - DJI の MP4 メタデータ creation_time は UTC (末尾 Z) で正しく記録される
    が、DJI はタイムゾーンのオフセットも GPS も書かないため、Immich は撮影地
    の TZ を判定できず localDateTime を UTC の壁時計のまま採用してしまい、表示
    時刻がずれる。immich-go の --time-zone は「TZ を持たない時刻」の解釈用で、
    Z 付きの creation_time には効かない (localDateTime はサーバが埋め込み
    メタデータから再計算するため、アップロード時フラグでは上書きもできない)。
  - そこでアップロード後に --fix-timezone を実行し、ファイル名
    (DJI_YYYYMMDDHHMMSS_...) の壁時計を --tz (既定 Asia/Tokyo) のオフセット
    付き ISO 8601 にして Immich API (PUT /assets/{id} の dateTimeOriginal)
    へ書き戻すことで localDateTime を正す。
  - --tz は (1) 結合後 MP4 の mtime 計算 (filename_to_epoch)、
    (2) --fix-timezone の書き戻しオフセット、の両方で同じ値を使う。

出力レイアウト ($DEST_DIR 配下):
  originals/      rsync で SD から取り込んだファイル (`--ext` でフィルタ)
  upload/         immich-go の入力ディレクトリ。結合済みMP4 + 単独動画/写真の hardlink
  failed_merges/  結合に失敗した分割動画グループ (再実行や手動結合の判断はユーザに委ねる)

実行例:
  # IMMICH_API_KEY は ~/.zshenv 等で永続化推奨
  export IMMICH_API_KEY=XXXX

  # 取り込み + 結合 + upload/ 構築 + immich-go コマンド表示
  ./scripts/dji_workflow.py --immich-server https://immich.example.com

  # (immich-go でのアップロード完了後) 撮影日時のずれを Immich API で修正
  ./scripts/dji_workflow.py --fix-timezone \
      --immich-server https://immich.example.com

  # 全工程ドライラン (rsync -n、結合・hardlink・eject 全てスキップ、
  # 表示 immich-go コマンドにも --dry-run が付く)
  ./scripts/dji_workflow.py --dry-run

  # SD を抜いた状態で結合からやり直す (SD 未マウントなら自動でコピーをスキップ)
  ./scripts/dji_workflow.py
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from rich.console import Console

console = Console()

# 内部で「動画 (=結合対象候補)」と判断する拡張子。それ以外は写真扱い。
VIDEO_EXTS = {"MP4", "MOV"}
DEFAULT_DEVICE_TAG = "DJI Osmo Pocket 4"
DEFAULT_EXTS = ["MP4", "JPG"]
DEFAULT_TZ = "Asia/Tokyo"


# ============================================================
# ログ
# ============================================================
def log(msg: str) -> None:
    console.log(f"[bold blue]{msg}[/bold blue]")


def warn(msg: str) -> None:
    console.log(f"[bold yellow]WARN:[/bold yellow] {msg}")


def err(msg: str) -> None:
    console.log(f"[bold red]ERROR:[/bold red] {msg}")


def die(msg: str) -> None:
    err(msg)
    sys.exit(1)


def confirm(prompt: str) -> bool:
    try:
        ans = input(f"{prompt} (y/N): ")
    except EOFError:
        return False
    return ans.strip().lower() in ("y", "yes")


# ============================================================
# Config
# ============================================================
@dataclass
class Config:
    sd_mount: Path
    dest_base: Path
    dest_dir: Path | None
    immich_server: str
    immich_client_timeout: str
    immich_concurrency: int
    device_tag: str
    extra_tags: list[str]
    split_tolerance: int
    split_min_size_bytes: int
    exts: list[str]
    tz_name: str
    tz: ZoneInfo
    dry_run: bool
    skip_copy: bool
    eject_after: bool
    fix_timezone: bool
    assume_yes: bool

    @property
    def src_dcim(self) -> Path:
        return self.sd_mount / "DCIM"

    @property
    def video_exts(self) -> list[str]:
        return [e for e in self.exts if e in VIDEO_EXTS]

    @property
    def photo_exts(self) -> list[str]:
        return [e for e in self.exts if e not in VIDEO_EXTS]

    @property
    def all_tags(self) -> list[str]:
        return [self.device_tag, *self.extra_tags]

    @classmethod
    def from_args(cls, ns: argparse.Namespace) -> Config:
        exts = [e.upper().lstrip(".") for e in (ns.ext or DEFAULT_EXTS)]
        # IMMICH_SERVER は機密ではないが、--help に値を露出させたくないので
        # parser default ではなくここで環境変数フォールバックする
        immich_server = ns.immich_server or os.environ.get("IMMICH_SERVER", "")
        return cls(
            sd_mount=Path(ns.sd_mount),
            dest_base=Path(ns.dest_base).expanduser(),
            dest_dir=Path(ns.dest_dir).expanduser() if ns.dest_dir else None,
            immich_server=immich_server,
            immich_client_timeout=ns.immich_client_timeout,
            immich_concurrency=ns.immich_concurrency,
            device_tag=ns.device_tag,
            extra_tags=ns.tag or [],
            split_tolerance=ns.split_tolerance,
            split_min_size_bytes=int(ns.split_min_size_gib * 1024**3),
            exts=exts,
            tz_name=ns.tz,
            tz=ZoneInfo(ns.tz),
            dry_run=ns.dry_run,
            skip_copy=ns.skip_copy,
            eject_after=ns.eject,
            fix_timezone=ns.fix_timezone,
            assume_yes=ns.yes,
        )


class _NonEmptyDefaultsFormatter(argparse.ArgumentDefaultsHelpFormatter):
    """既定値が None / 空文字 / 空リストのときは ``(default: ...)`` を出さない。

    機密情報を `default=os.environ.get(...)` で渡すと help に値が露出するので、
    parser 側ではデフォルトを設定せず help にも default 行を出さないようにする。
    """

    def _get_help_string(self, action: argparse.Action) -> str | None:
        if action.default in (None, "", [], argparse.SUPPRESS):
            return action.help
        return super()._get_help_string(action)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=__doc__.split("\n\n")[0],
        formatter_class=_NonEmptyDefaultsFormatter,
    )
    parser.add_argument("--sd-mount", default="/Volumes/SD_Card",
                        help="SD カードのマウントポイント")
    parser.add_argument("--dest-base", default="/Volumes/SanDisk 2TB/OsmoPocket4",
                        help="コピー先ベースディレクトリ")
    parser.add_argument("--dest-dir", default=None,
                        help="既存ディレクトリ再利用時に指定。未指定なら自動決定")
    parser.add_argument("--immich-server", default=None,
                        help="表示コマンドに埋め込む Immich サーバー URL "
                             "(未指定時は環境変数 IMMICH_SERVER)")
    parser.add_argument("--immich-client-timeout", default="24h",
                        help="表示コマンドに埋め込む immich-go の HTTP クライアントタイムアウト "
                             "(Go duration 形式。巨大動画想定で既定は 24h)")
    parser.add_argument("--immich-concurrency", type=int, default=2,
                        help="表示コマンドに埋め込む immich-go の並列アップロード数 (1-20)。"
                             "巨大ファイル時はサーバ負荷を抑えるため 1〜2 推奨")
    parser.add_argument("--device-tag", default=DEFAULT_DEVICE_TAG,
                        help="常に付与されるデバイス識別タグ")
    parser.add_argument("--tag", action="append",
                        help="--device-tag に追加で付与する Immich タグ "
                             "(`/` で階層化可、複数指定可)")
    parser.add_argument("--split-tolerance", type=int, default=5,
                        help="連続録画と判定するギャップ許容秒")
    parser.add_argument("--split-min-size-gib", type=float, default=15.0,
                        help="分割と判定する直前ファイルの最小サイズ (GiB)。"
                             "DJI は ~16GiB でファイルを自動分割するので、"
                             "これを下回るサイズのファイルの直後は "
                             "別グループ (連続録画ではない) として扱う")
    parser.add_argument("--ext", action="append",
                        help=f"取り込む拡張子 (動画/写真両方を一括指定)。"
                             f"動画 ({', '.join(sorted(VIDEO_EXTS))}) は内部で結合対象として扱う。"
                             f"未指定時は {', '.join(DEFAULT_EXTS)}")
    parser.add_argument("--tz", default=DEFAULT_TZ,
                        help="DJI ファイル名のタイムスタンプを解釈する TZ "
                             "(IANA 名)。mtime 計算と immich-go の --time-zone "
                             "の両方に使う。DJI のメタデータには TZ が無く "
                             "Immich 側で UTC 扱いされて時刻がずれるのを防ぐため "
                             "明示固定する")
    parser.add_argument("--dry-run", action=argparse.BooleanOptionalAction,
                        default=False,
                        help="全工程ドライラン: rsync は -n、ffmpeg 結合・hardlink "
                             "作成・eject を全てスキップし、表示 immich-go コマンドにも "
                             "--dry-run を付与")
    parser.add_argument("--skip-copy", action="store_true",
                        help="SD があってもコピーをスキップして結合以降のみ実行")
    parser.add_argument("--eject", action=argparse.BooleanOptionalAction,
                        default=True,
                        help="完了後に SD をアンマウント")
    parser.add_argument("--fix-timezone", action="store_true",
                        help="コピー/結合/アップロード表示は行わず、アップロード済み "
                             "Immich アセットの撮影日時をファイル名 (壁時計) から "
                             "--tz オフセット付きで書き戻して時刻ずれを修正する "
                             "(要 IMMICH_API_KEY / --immich-server)")
    parser.add_argument("--yes", "-y", action="store_true",
                        help="--fix-timezone の適用確認プロンプトをスキップ")
    return parser


# ============================================================
# 依存チェック
# ============================================================
def check_deps(cfg: Config) -> None:
    missing: list[str] = []
    for cmd in ("rsync", "ffmpeg", "ffprobe"):
        if shutil.which(cmd) is None:
            missing.append(cmd)
    if missing:
        die(f"以下のコマンドが見つかりません: {' '.join(missing)}")
    if shutil.which("immich-go") is None:
        warn("immich-go が見つかりません。"
             "表示されるコマンドを実行する側で別途インストールしてください")


# ============================================================
# DEST_DIR 解決
# ============================================================
SESSION_RE = re.compile(r"^DJI_(\d{8})")
TS_RE = re.compile(r"^DJI_(\d{14})_")
SEQ_RE = re.compile(r"_(\d{4})_D$")
DATE_DIR_RE = re.compile(r"^\d{8}$")


def get_session_id_from_sd(src_dcim: Path) -> str | None:
    """SD 内の最古撮影日 (YYYYMMDD) を返す。見つからなければ None"""
    days = sorted({
        m.group(1)
        for p in src_dcim.rglob("DJI_*_D.MP4")
        if (m := SESSION_RE.match(p.name))
    })
    return days[0] if days else None


def find_latest_existing_dest(dest_base: Path) -> Path | None:
    """dest_base 配下で YYYYMMDD 形式かつ originals/ にデータがあるディレクトリのうち、
    名前順最新を返す。手動で作った非日付ディレクトリは候補外。"""
    if not dest_base.is_dir():
        return None
    candidates: list[Path] = []
    for child in dest_base.iterdir():
        if not child.is_dir() or not DATE_DIR_RE.match(child.name):
            continue
        originals = child / "originals"
        if originals.is_dir() and any(originals.rglob("DJI_*_D.MP4")):
            candidates.append(child)
    if not candidates:
        return None
    return sorted(candidates, key=lambda p: p.name)[-1]


def resolve_dest_dir(cfg: Config, sd_mounted: bool) -> Path:
    if cfg.dest_dir is not None:
        return cfg.dest_dir
    if sd_mounted:
        session_id = (get_session_id_from_sd(cfg.src_dcim)
                      or datetime.now(cfg.tz).strftime("%Y%m%d"))
        return cfg.dest_base / session_id
    latest = find_latest_existing_dest(cfg.dest_base)
    if latest is None:
        die(f"SD カード ({cfg.sd_mount}) もマウントされておらず、"
            f"{cfg.dest_base} 配下に YYYYMMDD 形式の既存ディレクトリ "
            f"(originals/ を含む) もありません")
    log(f"SD 未マウント。YYYYMMDD 形式で最新の既存ディレクトリを採用: {latest}")
    return latest  # type: ignore[unreachable]


# ============================================================
# Step 1: SD からコピー
# ============================================================
def get_dir_size_bytes(path: Path) -> int:
    """`du -sk` でディレクトリサイズをバイト単位で返す。"""
    out = subprocess.run(
        ["du", "-sk", str(path)],
        check=True, capture_output=True, text=True,
    ).stdout
    return int(out.split()[0]) * 1024


def fmt_gib(b: int) -> str:
    return f"{b / 1024**3:.2f} GiB"


def copy_from_sd(cfg: Config, originals_dir: Path) -> None:
    log("=== Step 1: SDカードから originals/ へコピー ===")
    if cfg.dry_run:
        log("(dry-run) rsync は -n でプレビューのみ、ディレクトリも作成しない")

    src = cfg.src_dcim
    if not src.is_dir():
        die(f"SD カードの DCIM が見つかりません: {src}")

    log(f"コピー元: {src}")
    log(f"コピー先: {originals_dir}")

    src_size = get_dir_size_bytes(src)
    df_target = cfg.dest_base if cfg.dest_base.exists() else cfg.dest_base.parent
    free_space = shutil.disk_usage(df_target).free
    log(f"転送元サイズ: {fmt_gib(src_size)} (フィルタ前の SD 全体)")
    log(f"転送先空き容量: {fmt_gib(free_space)}")

    # rsync の差分転送・拡張子フィルタで実際の転送量はもっと少ないが、
    # フィルタ前の総量で比較しておく方が安全側
    if src_size > free_space:
        die(f"転送先の空き容量が不足しています "
            f"(SD 全体: {fmt_gib(src_size)}, 空き: {fmt_gib(free_space)})")

    if not cfg.dry_run:
        originals_dir.mkdir(parents=True, exist_ok=True)

    # mtime + size 比較で差分転送 (SD は read-only 運用前提)
    cmd = [
        "rsync", "-ah", "--progress", "--partial", "--stats",
        *(["-n"] if cfg.dry_run else []),
        "--include=*/",
        *[f"--include=*.{ext}" for ext in cfg.exts],
        "--exclude=*",
        f"{src}/", f"{originals_dir}/",
    ]
    subprocess.run(cmd, check=True)

    if cfg.dry_run:
        return

    log("コピー済みファイル種別:")
    counts: dict[str, int] = {}
    for p in originals_dir.rglob("*"):
        if p.is_file():
            ext = p.suffix.lstrip(".") or "(none)"
            counts[ext] = counts.get(ext, 0) + 1
    for ext, n in sorted(counts.items()):
        console.print(f"  {n:5d} {ext}")


# ============================================================
# Step 2: 分割検出 + 結合
# ============================================================
def filename_to_epoch(p: Path, tz: ZoneInfo) -> int | None:
    """DJI ファイル名 ``DJI_YYYYMMDDHHMMSS_...`` を epoch 秒に変換する。

    DJI 側の壁時計 (TZ 情報なし) を ``tz`` で解釈してから epoch に落とす。
    naive datetime の ``.timestamp()`` は実行マシンの TZ 依存になるので、
    ZoneInfo を付与してから変換することで TZ 設定に左右されない結果にする。
    """
    m = TS_RE.match(p.name)
    if not m:
        return None
    try:
        dt = datetime.strptime(m.group(1), "%Y%m%d%H%M%S").replace(tzinfo=tz)
        return int(dt.timestamp())
    except ValueError:
        return None


def get_duration(p: Path) -> float | None:
    try:
        out = subprocess.run(
            ["ffprobe", "-v", "error",
             "-show_entries", "format=duration",
             "-of", "default=noprint_wrappers=1:nokey=1",
             str(p)],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
        return float(out) if out else None
    except (subprocess.CalledProcessError, ValueError):
        return None


def detect_groups(originals_dir: Path, tolerance: int,
                  min_split_size: int, tz: ZoneInfo) -> list[list[Path]]:
    """連続録画グループを検出する。

    同一録画と判定する条件 (全て満たす必要あり):
      - 直前ファイル終端と次ファイル開始時刻の差が ``tolerance`` 秒以内
      - 直前ファイルサイズが ``min_split_size`` バイト以上
        (DJI は ~16GiB で自動分割するため、これ未満なら分割ではなく
        ユーザ操作などで終了した別録画とみなす)
    """
    files = sorted(originals_dir.rglob("DJI_*_D.MP4"))
    if not files:
        return []

    groups: list[list[Path]] = []
    current: list[Path] = []
    prev_end: int | None = None
    prev_size: int | None = None

    def flush_current() -> None:
        nonlocal current, prev_end, prev_size
        if current:
            groups.append(current)
            current = []
        prev_end = None
        prev_size = None

    for f in files:
        start = filename_to_epoch(f, tz)
        if start is None:
            warn(f"タイムスタンプ抽出失敗、グループ区切り: {f.name}")
            flush_current()
            continue
        dur = get_duration(f)
        if dur is None:
            warn(f"duration 取得失敗、グループ区切り: {f.name}")
            flush_current()
            continue
        size = f.stat().st_size
        end = int(start + dur)

        if prev_end is None:
            current = [f]
        else:
            gap = start - prev_end
            prev_at_limit = (prev_size or 0) >= min_split_size
            if gap < 0:
                # オーバーラップしている=連続録画ではない
                warn(f"前ファイル終端より {-gap}s 前に開始、別グループ扱い: {f.name}")
                groups.append(current)
                current = [f]
            elif gap <= tolerance and prev_at_limit:
                current.append(f)
            else:
                if gap <= tolerance and not prev_at_limit:
                    log(f"前ファイル {fmt_gib(prev_size or 0)} < 分割閾値 "
                        f"{fmt_gib(min_split_size)}、別グループ扱い: {f.name}")
                groups.append(current)
                current = [f]
        prev_end = end
        prev_size = size

    if current:
        groups.append(current)
    return groups


def _detect_codec(path: Path) -> str:
    return subprocess.run(
        ["ffprobe", "-v", "error",
         "-select_streams", "v:0",
         "-show_entries", "stream=codec_name",
         "-of", "csv=p=0", str(path)],
        check=True, capture_output=True, text=True,
    ).stdout.strip()


def merge_via_ts(out_path: Path, files: list[Path]) -> bool:
    """TS 経由で再結合する concat demuxer のフォールバック."""
    with tempfile.TemporaryDirectory(prefix="dji_ts_") as tsdir_str:
        tsdir = Path(tsdir_str)
        codec = _detect_codec(files[0])
        if codec == "h264":
            vbsf = "h264_mp4toannexb"
        elif codec == "hevc":
            vbsf = "hevc_mp4toannexb"
        else:
            warn(f"未知のコーデック: {codec}")
            vbsf = "h264_mp4toannexb"

        ts_paths: list[Path] = []
        for i, f in enumerate(files):
            ts_path = tsdir / f"part_{i:03d}.ts"
            r = subprocess.run(
                ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error",
                 "-i", str(f), "-c", "copy", "-bsf:v", vbsf,
                 "-f", "mpegts", str(ts_path)])
            if r.returncode != 0:
                return False
            ts_paths.append(ts_path)

        concat_arg = "concat:" + "|".join(str(p) for p in ts_paths)
        r = subprocess.run(
            ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-stats",
             "-i", concat_arg, "-c", "copy", "-bsf:a", "aac_adtstoasc",
             str(out_path)])
        return r.returncode == 0


def compute_recording_end_epoch(files: list[Path], tz: ZoneInfo) -> int | None:
    """連続録画グループの録画終了時刻 (epoch 秒) を返す。

    ファイル名の DJI_YYYYMMDDHHMMSS は録画開始時刻なので、
    最後の分割ファイルの開始時刻 + その duration が全体の録画終了時刻。
    """
    last = files[-1]
    start = filename_to_epoch(last, tz)
    if start is None:
        return None
    dur = get_duration(last)
    if dur is None:
        return None
    return int(start + dur)


def set_mtime_to_recording_end(out_path: Path, files: list[Path],
                               tz: ZoneInfo) -> None:
    """結合後ファイルの mtime/atime を録画終了時刻に揃える。

    macOS APFS では mtime を現在より過去に下げると birthtime もそれに
    追従するため、結果として birthtime=mtime=録画終了時刻 となり、
    分割前のオリジナルファイルと同じタイムスタンプ規約に揃う。
    """
    end = compute_recording_end_epoch(files, tz)
    if end is None:
        warn(f"録画終了時刻を算出できず、mtime を更新せず: {out_path.name}")
        return
    os.utime(out_path, (end, end))


def merge_group(files: list[Path], upload_dir: Path, tz: ZoneInfo) -> bool:
    """結合に成功したら True、失敗 (or パース不能) なら False を返す。"""
    if len(files) < 2:
        return True

    first_stem = files[0].stem
    last_stem = files[-1].stem
    first_seq_m = SEQ_RE.search(first_stem)
    last_seq_m = SEQ_RE.search(last_stem)
    first_ts_m = TS_RE.match(first_stem)
    if not (first_seq_m and last_seq_m and first_ts_m):
        warn(f"ファイル名パース失敗、スキップ: {first_stem}")
        return False

    out_name = (f"DJI_{first_ts_m.group(1)}"
                f"_{first_seq_m.group(1)}-{last_seq_m.group(1)}_MERGED.MP4")
    out_path = upload_dir / out_name

    if out_path.exists():
        log(f"結合済みのためスキップ: {out_name}")
        set_mtime_to_recording_end(out_path, files, tz)
        return True

    log(f"結合: {len(files)} ファイル → {out_name}")
    for f in files:
        log(f"  ← {f.name}")

    # ffmpeg concat の ' エスケープ規則: ' → '\''
    list_lines = [
        "file '" + str(f).replace("'", r"'\''") + "'\n"
        for f in files
    ]
    with tempfile.NamedTemporaryFile("w", prefix="dji_concat_",
                                     suffix=".txt", delete=False,
                                     encoding="utf-8") as lf:
        list_file = Path(lf.name)
        lf.writelines(list_lines)

    try:
        r = subprocess.run(
            ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-stats",
             "-f", "concat", "-safe", "0",
             "-i", str(list_file),
             "-c", "copy", "-fflags", "+genpts",
             str(out_path)])
        if r.returncode != 0:
            warn("concat demuxer 失敗。TS フォールバックを試行...")
            out_path.unlink(missing_ok=True)
            if not merge_via_ts(out_path, files):
                err(f"結合失敗: {out_name}")
                out_path.unlink(missing_ok=True)
                return False
        size_mb = out_path.stat().st_size / (1024 * 1024)
        log(f"✓ 結合完了: {size_mb:.1f}MB {out_name}")
        set_mtime_to_recording_end(out_path, files, tz)
        return True
    finally:
        list_file.unlink(missing_ok=True)


def stage_failed_group(group: list[Path], failed_dir: Path) -> Path:
    """失敗グループを failed_merges/<group_id>/ にハードリンクで配置."""
    group_id = group[0].stem
    target = failed_dir / group_id
    target.mkdir(parents=True, exist_ok=True)
    for f in group:
        dst = target / f.name
        if dst.exists():
            continue
        try:
            os.link(f, dst)
        except OSError:
            shutil.copy2(f, dst)
    return target


def merge_splits(groups: list[list[Path]],
                 upload_dir: Path,
                 failed_dir: Path,
                 dry_run: bool,
                 tz: ZoneInfo) -> list[tuple[list[Path], Path]]:
    """結合に失敗したグループ (元ファイル群, ステージング先) のリストを返す。

    dry_run=True なら ffmpeg を起動せず、結合候補の一覧と件数だけ表示する。
    """
    if not dry_run:
        upload_dir.mkdir(parents=True, exist_ok=True)
    merge_count = 0
    single_count = 0
    failed: list[tuple[list[Path], Path]] = []
    for g in groups:
        if len(g) >= 2:
            merge_count += 1
            if dry_run:
                log(f"(dry-run) 結合対象 {len(g)} ファイル: "
                    f"{g[0].name} 〜 {g[-1].name}")
                continue
            try:
                ok = merge_group(g, upload_dir, tz)
            except Exception as e:
                warn(f"結合中エラー: {e}")
                ok = False
            if not ok:
                staged = stage_failed_group(g, failed_dir)
                failed.append((g, staged))
        else:
            single_count += 1
    prefix = "(dry-run) " if dry_run else ""
    log(f"{prefix}単独動画: {single_count} 本 / 結合グループ: {merge_count} 個 "
        f"(うち失敗: {len(failed)} 個)")
    return failed


# ============================================================
# Step 3: upload/ 構築
# ============================================================
def hardlink_or_copy(src: Path, dst: Path) -> None:
    if dst.exists():
        return
    try:
        os.link(src, dst)
    except OSError:
        shutil.copy2(src, dst)


def organize_for_upload(groups: list[list[Path]],
                        originals_dir: Path,
                        upload_dir: Path,
                        photo_exts: list[str],
                        dry_run: bool) -> None:
    log("=== Step 3: upload/ ディレクトリを構築 ===")
    if not dry_run:
        upload_dir.mkdir(parents=True, exist_ok=True)

    linked_videos = 0
    for g in groups:
        if len(g) == 1:
            src = g[0]
            if not dry_run:
                hardlink_or_copy(src, upload_dir / src.name)
            linked_videos += 1

    photo_exts_lower = {e.lower() for e in photo_exts}
    linked_photos = 0
    for p in originals_dir.rglob("*"):
        if p.is_file() and p.suffix.lstrip(".").lower() in photo_exts_lower:
            if not dry_run:
                hardlink_or_copy(p, upload_dir / p.name)
            linked_photos += 1

    prefix = "(dry-run) " if dry_run else ""
    log(f"{prefix}単独動画 {linked_videos} 本 / 写真 {linked_photos} 枚を upload/ に配置")


# ============================================================
# Step 4: Immich アップロードコマンド表示
# ============================================================
def print_upload_command(cfg: Config, upload_dir: Path) -> None:
    """immich-go コマンドを構築し、コピペ実行できる形で表示する。

    実アップロードは時間がかかり失敗もあるため、本スクリプトでは実行しない。
    API キーは表示コマンド中で常に "$IMMICH_API_KEY" 参照とし、
    端末スクロールバックに生のキーを残さない。
    """
    log("=== Step 4: Immich アップロードコマンドを表示 ===")

    if cfg.immich_server:
        server_arg = shlex.quote(cfg.immich_server)
    else:
        warn("--immich-server / IMMICH_SERVER 未設定。"
             '表示コマンドでは "$IMMICH_SERVER" のまま、実行時に補ってください')
        server_arg = '"$IMMICH_SERVER"'

    lines: list[str] = [
        "immich-go upload",
        f"  --client-timeout {shlex.quote(cfg.immich_client_timeout)}",
        f"  --concurrent-tasks {cfg.immich_concurrency}",
        "  from-folder",
        f"  --server {server_arg}",
        '  --api-key "$IMMICH_API_KEY"',
        f"  --time-zone {shlex.quote(cfg.tz_name)}",
    ]
    for tag in cfg.all_tags:
        lines.append(f"  --tag {shlex.quote(tag)}")
    if cfg.dry_run:
        lines.append("  --dry-run")
    lines.append(f"  {shlex.quote(str(upload_dir))}")

    log("以下のコマンドをコピーして実行してください "
        "(IMMICH_API_KEY を export 済みであること):")
    console.print()
    console.print(" \\\n".join(lines))
    console.print()

    # DJI は creation_time を UTC で埋め込むが TZ オフセットを書かないため、
    # アップロードしただけでは Immich が撮影時刻を UTC 表示してしまう。
    # 上のアップロード完了後に --fix-timezone で撮影日時を書き戻して直す。
    log("アップロード完了後、撮影時刻のずれを直すため続けて以下も実行してください:")
    console.print()
    fix_lines = [
        f"{shlex.quote(sys.argv[0])} --fix-timezone",
        f"  --immich-server {server_arg}",
        f"  --device-tag {shlex.quote(cfg.device_tag)}",
        f"  --tz {shlex.quote(cfg.tz_name)}",
        f"  --dest-dir {shlex.quote(str(upload_dir.parent))}",
    ]
    if cfg.dry_run:
        fix_lines.append("  --dry-run")
    console.print(" \\\n".join(fix_lines))
    console.print()


# ============================================================
# Step 5: アンマウント
# ============================================================
def eject_sd(cfg: Config) -> None:
    if not cfg.eject_after:
        return
    log("=== Step 5: SD カードをアンマウント ===")
    if cfg.dry_run:
        log("(dry-run) アンマウントしない")
        return
    if not confirm("SD カードを取り出しますか?"):
        log("アンマウントせず終了します")
        return
    r = subprocess.run(["diskutil", "eject", str(cfg.sd_mount)])
    if r.returncode == 0:
        log("✓ アンマウント完了")


# ============================================================
# --fix-timezone: アップロード後の撮影日時修正 (Immich API)
# ============================================================
class ApiError(Exception):
    pass


def api_call(server: str, key: str, method: str, path: str,
             body: dict | None = None) -> object:
    """Immich REST API 呼び出し。失敗時は ``ApiError`` を送出する。

    呼び出し側で「失敗即死」と「失敗を集計して継続」を選べるように、
    ここでは die() せず例外で抜ける。
    """
    url = server.rstrip("/") + "/api" + path
    data = json.dumps(body).encode() if body is not None else None
    headers = {"x-api-key": key, "Accept": "application/json"}
    if data is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        body_text = e.read().decode(errors="replace")
        raise ApiError(f"{method} {path} 失敗: {e.code} {e.reason}\n{body_text}") from e
    except urllib.error.URLError as e:
        raise ApiError(f"{method} {path} 接続失敗: {e.reason}") from e


def api_or_die(server: str, key: str, method: str, path: str,
               body: dict | None = None) -> object:
    try:
        return api_call(server, key, method, path, body)
    except ApiError as e:
        die(str(e))


def resolve_tag_id(server: str, key: str, tag_name: str) -> str:
    """タグ名から id を解決する。

    Immich のタグは階層化可能で、value がスラッシュ区切りのフルパス、
    name がリーフ名。--device-tag には immich-go と同じ形式を渡すため、
    value 優先、フォールバックで name 一致を許す。
    """
    tags = api_or_die(server, key, "GET", "/tags")
    if not isinstance(tags, list):
        die(f"GET /tags の応答が想定外: {tags!r}")
    for t in tags:
        if t.get("value") == tag_name:
            return t["id"]
    for t in tags:
        if t.get("name") == tag_name:
            return t["id"]
    die(f"タグが見つかりません: {tag_name!r}")


def iter_assets_by_tag(server: str, key: str, tag_id: str):
    """指定タグのアセットをページ送りで全件 yield する。"""
    page = 1
    while True:
        resp = api_or_die(server, key, "POST", "/search/metadata", {
            "tagIds": [tag_id],
            "page": page,
            "size": 250,
        })
        assets = resp["assets"]
        for item in assets.get("items", []):
            yield item
        next_page = assets.get("nextPage")
        if not next_page:
            break
        try:
            page = int(next_page)
        except (TypeError, ValueError):
            break


def filename_to_datetime(name: str, tz: ZoneInfo) -> datetime | None:
    """DJI ファイル名の壁時計を ``tz`` 付き aware datetime にする。

    結合後の ``DJI_..._MERGED.MP4`` も先頭タイムスタンプ (録画開始時刻) で
    マッチする。
    """
    m = TS_RE.match(name)
    if not m:
        return None
    try:
        return datetime.strptime(m.group(1), "%Y%m%d%H%M%S").replace(tzinfo=tz)
    except ValueError:
        return None


def format_dt_iso(dt: datetime) -> str:
    """Immich の PUT /assets/{id} が受け付ける形式に整形する。

    dateTimeOriginal のオフセットは分まで必須 (``+09`` は黙って破棄され、
    ``+09:00`` は受理される)。
    """
    base = dt.strftime("%Y-%m-%dT%H:%M:%S.000")
    offset = dt.strftime("%z")  # +0900
    return f"{base}{offset[:3]}:{offset[3:]}"


@dataclass
class TzUpdate:
    asset_id: str
    filename: str
    current: str | None
    new_iso: str


def build_local_name_set(dest_dir: Path) -> set[str]:
    """dest_dir 配下のファイル名集合。

    タグには他セッションのアセットも含まれ得るので、本セッションで取り込んだ
    ファイル名と一致するものだけに更新対象を絞る安全網。
    """
    return {p.name for p in dest_dir.rglob("*") if p.is_file()}


def build_tz_plan(server: str, key: str, tag_id: str,
                  local_names: set[str], tz: ZoneInfo,
                  ) -> tuple[list[TzUpdate], int, list[str], list[str]]:
    updates: list[TzUpdate] = []
    no_local: list[str] = []
    unparsed: list[str] = []
    total = 0
    for asset in iter_assets_by_tag(server, key, tag_id):
        total += 1
        name = asset["originalFileName"]
        if name not in local_names:
            no_local.append(name)
            continue
        dt = filename_to_datetime(name, tz)
        if dt is None:
            unparsed.append(name)
            continue
        updates.append(TzUpdate(
            asset_id=asset["id"],
            filename=name,
            current=asset.get("fileCreatedAt"),
            new_iso=format_dt_iso(dt),
        ))
    return updates, total, no_local, unparsed


def fix_timezone(cfg: Config, dest_dir: Path) -> int:
    """アップロード済み Immich アセットの撮影日時をファイル名から書き戻す。"""
    log("=== --fix-timezone: Immich アセット撮影日時を修正 ===")
    if not cfg.immich_server:
        die("--immich-server / IMMICH_SERVER を指定してください")
    api_key = os.environ.get("IMMICH_API_KEY")
    if not api_key:
        die("IMMICH_API_KEY 環境変数を設定してください")

    server = cfg.immich_server
    log(f"Immich サーバ: {server}")
    log(f"対象タグ: {cfg.device_tag}")
    log(f"ローカル照合ベース: {dest_dir}")
    log(f"TZ: {cfg.tz_name}")

    tag_id = resolve_tag_id(server, api_key, cfg.device_tag)
    local_names = build_local_name_set(dest_dir)
    log(f"ローカルファイル {len(local_names)} 件で照合")

    updates, total, no_local, unparsed = build_tz_plan(
        server, api_key, tag_id, local_names, cfg.tz)

    log(f"タグ内アセット総数: {total} / 更新候補: {len(updates)} / "
        f"ローカル未検出: {len(no_local)} / パース不能: {len(unparsed)}")
    for u in updates[:10]:
        console.print(f"  {u.filename}: {u.current}  →  {u.new_iso}")
    if len(updates) > 10:
        console.print(f"  ... 他 {len(updates) - 10} 件")

    if not updates:
        log("更新すべきアセットがありません")
        return 0
    if cfg.dry_run:
        log("(dry-run) 更新 API を呼ばずに終了")
        return 0
    if not cfg.assume_yes and not confirm(f"{len(updates)} 件を更新しますか?"):
        log("中止しました")
        return 1

    n_ok = 0
    n_fail = 0
    for u in updates:
        try:
            api_call(server, api_key, "PUT", f"/assets/{u.asset_id}",
                     {"dateTimeOriginal": u.new_iso})
            n_ok += 1
        except ApiError as e:
            n_fail += 1
            warn(f"更新失敗: {u.filename}: {e}")
        if (n_ok + n_fail) % 50 == 0:
            log(f"進捗: {n_ok + n_fail}/{len(updates)}")
    log(f"✓ 完了: 成功 {n_ok} 件 / 失敗 {n_fail} 件 "
        f"(localDateTime への反映はサーバのメタデータジョブ後)")
    return 0 if n_fail == 0 else 1


# ============================================================
# main
# ============================================================
def main(argv: list[str]) -> int:
    parser = build_parser()
    ns = parser.parse_args(argv)
    cfg = Config.from_args(ns)

    check_deps(cfg)

    sd_mounted = cfg.src_dcim.is_dir()
    dest_dir = resolve_dest_dir(cfg, sd_mounted)
    originals_dir = dest_dir / "originals"
    upload_dir = dest_dir / "upload"
    failed_dir = dest_dir / "failed_merges"

    if cfg.fix_timezone:
        log(f"作業ディレクトリ: {dest_dir}")
        return fix_timezone(cfg, dest_dir)

    if not cfg.dry_run:
        dest_dir.mkdir(parents=True, exist_ok=True)
    log("ワークフロー開始")
    if cfg.dry_run:
        log("(dry-run) 全工程プレビュー: 実 I/O は行わない")
    log(f"作業ディレクトリ: {dest_dir}")
    log(f"撮影タイムゾーン: {cfg.tz_name}")
    if originals_dir.is_dir() and any(originals_dir.iterdir()):
        log("(既存ディレクトリに差分追加します)")

    has_originals = (originals_dir.is_dir()
                     and any(originals_dir.rglob("DJI_*_D.MP4")))
    if cfg.skip_copy:
        log("--skip-copy 指定のためコピーをスキップ")
    elif sd_mounted:
        copy_from_sd(cfg, originals_dir)
    elif has_originals:
        log("SD 未マウント、originals/ に既存データを検出 → コピーをスキップ")
    else:
        die("SD カードがマウントされておらず、originals/ にもデータがありません")

    log("=== Step 2: 分割ファイル検出 ===")
    groups = detect_groups(originals_dir, cfg.split_tolerance,
                           cfg.split_min_size_bytes, cfg.tz)
    log(f"検出グループ数: {len(groups)} "
        f"(分割閾値: {fmt_gib(cfg.split_min_size_bytes)} 以上で連続録画と判定)")

    failed = merge_splits(groups, upload_dir, failed_dir, cfg.dry_run, cfg.tz)
    organize_for_upload(groups, originals_dir, upload_dir, cfg.photo_exts,
                        cfg.dry_run)
    print_upload_command(cfg, upload_dir)
    if sd_mounted:
        eject_sd(cfg)

    if failed:
        warn(f"結合失敗グループが {len(failed)} 件あります "
             f"(upload/ には含めていません)")
        for g, staged in failed:
            warn(f"  - {staged}  ({g[0].name} 〜 {g[-1].name}, {len(g)} ファイル)")
        warn("再実行や手動結合は failed_merges/ を確認してユーザ側で判断してください")

    log(f"✓ 全工程完了: {dest_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
