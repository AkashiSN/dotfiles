#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["rich"]
# ///
"""Immich の DJI アセット撮影日時を、対応するローカルファイル名から修正する.

`dji_workflow.py` で TZ 未指定だった頃にアップロードしたアセットは、Immich 側で
撮影時刻が UTC として解釈されて表示時刻がずれている。本スクリプトでは:

  1. 指定タグ (既定 "DJI Osmo Pocket 4") が付いたアセットを Immich API で列挙
  2. originalFileName を --dest-base 配下のローカルファイルと突き合わせ
  3. DJI のファイル名 ``DJI_YYYYMMDDHHMMSS_...`` から撮影時刻を抽出
  4. --tz (既定 Asia/Tokyo) オフセット付き ISO 8601 で PUT /assets/{id}

API 認証は環境変数経由 (CLI に渡しても --help に値が露出するため):
  IMMICH_GO_SERVER   サーバ URL (--immich-server で上書き可)
  IMMICH_GO_API_KEY  API キー (CLI 引数では受け取らない)

実行フロー:
  プラン構築 → 件数サマリと例示 → 確認 → 適用

`--dry-run` で適用をスキップ、`--yes` で確認をスキップ。
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from rich.console import Console

console = Console()

DEFAULT_TAG = "DJI Osmo Pocket 4"
DEFAULT_TZ = "Asia/Tokyo"
DEFAULT_DEST_BASE = "~/Movies/OsmoPocket4"
TS_RE = re.compile(r"^DJI_(\d{14})")
PAGE_SIZE = 250


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
# Immich API (urllib で stdlib のみ)
# ============================================================
class ApiError(Exception):
    pass


def api_call(server: str, key: str, method: str, path: str,
             body: dict | None = None) -> object:
    """Immich REST API 呼び出し。失敗時は ``ApiError`` を送出する。

    呼び出し側で「失敗即死」と「失敗を集計して継続」を選べるように、
    ここでは ``die()`` せず例外で抜ける。
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
    """タグ名 (フルパス値) から id を解決する。

    Immich のタグは階層化可能で、``value`` がスラッシュ区切りのフルパス、
    ``name`` がリーフ名。``--tag`` には immich-go と同じ形式
    (例: "DJI Osmo Pocket 4" や "Camera/DJI Osmo Pocket 4") を渡すため、
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
    """ページ送りで全件 yield する。"""
    page = 1
    while True:
        resp = api_or_die(server, key, "POST", "/search/metadata", {
            "tagIds": [tag_id],
            "page": page,
            "size": PAGE_SIZE,
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


# ============================================================
# 日時抽出 / 整形
# ============================================================
def filename_to_datetime(name: str, tz: ZoneInfo) -> datetime | None:
    m = TS_RE.match(name)
    if not m:
        return None
    try:
        return datetime.strptime(m.group(1), "%Y%m%d%H%M%S").replace(tzinfo=tz)
    except ValueError:
        return None


def format_iso(dt: datetime) -> str:
    """Immich の PUT /assets/{id} が受け付ける形式に整形する。

    issue #18733 によれば ``+09:00`` のように分まで含むオフセット必須
    (``+09`` は黙って破棄される)。
    """
    base = dt.strftime("%Y-%m-%dT%H:%M:%S.000")
    offset = dt.strftime("%z")  # +0900
    return f"{base}{offset[:3]}:{offset[3:]}"


# ============================================================
# ローカル索引
# ============================================================
def build_local_index(dest_base: Path) -> dict[str, Path]:
    if not dest_base.is_dir():
        die(f"--dest-base が存在しません: {dest_base}")
    index: dict[str, Path] = {}
    for p in dest_base.rglob("*"):
        if p.is_file():
            # 同名は最初に見つけたものを残す (upload/ と originals/ の hardlink 等)
            index.setdefault(p.name, p)
    return index


# ============================================================
# プラン構築
# ============================================================
@dataclass
class Update:
    asset_id: str
    filename: str
    current: str | None
    new_iso: str
    local_path: Path


def build_plan(server: str, key: str, tag_id: str,
               local_index: dict[str, Path],
               tz: ZoneInfo) -> tuple[list[Update], int, list[str], list[str]]:
    updates: list[Update] = []
    no_local: list[str] = []
    unparsed: list[str] = []
    total = 0
    for asset in iter_assets_by_tag(server, key, tag_id):
        total += 1
        name = asset["originalFileName"]
        local = local_index.get(name)
        if local is None:
            no_local.append(name)
            continue
        dt = filename_to_datetime(local.name, tz)
        if dt is None:
            unparsed.append(local.name)
            continue
        updates.append(Update(
            asset_id=asset["id"],
            filename=name,
            current=asset.get("fileCreatedAt"),
            new_iso=format_iso(dt),
            local_path=local,
        ))
    return updates, total, no_local, unparsed


def print_plan(updates: list[Update], total: int,
               no_local: list[str], unparsed: list[str],
               sample: int = 10) -> None:
    log(f"対象タグのアセット総数: {total}")
    log(f"  更新候補: {len(updates)}")
    log(f"  ローカル未検出: {len(no_local)}")
    log(f"  ファイル名パース不能: {len(unparsed)}")

    if no_local:
        warn(f"ローカル未検出 (先頭 {min(sample, len(no_local))} 件):")
        for n in no_local[:sample]:
            console.print(f"  - {n}")

    if unparsed:
        warn(f"パース不能 (先頭 {min(sample, len(unparsed))} 件):")
        for n in unparsed[:sample]:
            console.print(f"  - {n}")

    if updates:
        log(f"更新内容プレビュー (先頭 {min(sample, len(updates))} 件):")
        for u in updates[:sample]:
            console.print(f"  {u.filename}")
            console.print(f"    {u.current}  →  {u.new_iso}")


# ============================================================
# main
# ============================================================
def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=__doc__.split("\n\n")[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--immich-server", default=None,
                        help="Immich サーバ URL (未指定時は環境変数 IMMICH_GO_SERVER)")
    parser.add_argument("--dest-base", default=DEFAULT_DEST_BASE,
                        help=f"ローカルファイル探索のベースディレクトリ "
                             f"(default: {DEFAULT_DEST_BASE})")
    parser.add_argument("--tag", default=DEFAULT_TAG,
                        help=f"対象タグ名 (value フルパス。default: {DEFAULT_TAG!r})")
    parser.add_argument("--tz", default=DEFAULT_TZ,
                        help=f"DJI ファイル名を解釈する TZ (IANA 名。"
                             f"default: {DEFAULT_TZ})")
    parser.add_argument("--dry-run", action="store_true",
                        help="プラン表示のみで更新 API を呼ばない")
    parser.add_argument("--yes", "-y", action="store_true",
                        help="確認プロンプトをスキップして適用")
    parser.add_argument("--sample", type=int, default=10,
                        help="プラン表示で先頭何件を例示するか (default: 10)")
    return parser


def main(argv: list[str]) -> int:
    ns = build_parser().parse_args(argv)

    server = ns.immich_server or os.environ.get("IMMICH_GO_SERVER")
    if not server:
        die("Immich サーバを --immich-server か IMMICH_GO_SERVER で指定してください")
    api_key = os.environ.get("IMMICH_GO_API_KEY")
    if not api_key:
        die("IMMICH_GO_API_KEY 環境変数を設定してください")

    tz = ZoneInfo(ns.tz)
    dest_base = Path(ns.dest_base).expanduser()

    log(f"Immich サーバ: {server}")
    log(f"タグ: {ns.tag}")
    log(f"ローカルベース: {dest_base}")
    log(f"TZ: {ns.tz}")

    tag_id = resolve_tag_id(server, api_key, ns.tag)
    log(f"タグ ID: {tag_id}")

    local_index = build_local_index(dest_base)
    log(f"ローカルファイル {len(local_index)} 件を索引化")

    log("アセット列挙とプラン構築中...")
    updates, total, no_local, unparsed = build_plan(
        server, api_key, tag_id, local_index, tz,
    )
    print_plan(updates, total, no_local, unparsed, sample=ns.sample)

    if not updates:
        log("適用すべき更新がありません")
        return 0

    if ns.dry_run:
        log("(dry-run) 更新 API を呼ばずに終了")
        return 0

    if not ns.yes:
        if not confirm(f"{len(updates)} 件のアセット撮影日時を更新しますか?"):
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
    log(f"✓ 完了: 成功 {n_ok} 件 / 失敗 {n_fail} 件")
    return 0 if n_fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
