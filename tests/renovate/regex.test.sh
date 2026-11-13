#!/usr/bin/env bash
# .github/renovate.json の customManagers の正規表現が、対象ファイルから期待どおりの
# 依存（NPM_GLOBALS / UV_TOOLS / RUST_VERSION / AGMSG_* / Kiro）を拾うことを確かめる。
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
python3 -I "$here/regex.py" "$repo"
