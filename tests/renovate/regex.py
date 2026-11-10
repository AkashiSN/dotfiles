"""renovate.json の customManagers の matchStrings を対象ファイルへ当て、拾われる依存を確かめる。

Renovate の正規表現は JS 風なので、Python の re へ渡す前に名前付きグループを
`(?<name>...)` から `(?P<name>...)` へ直す（`(?<=` / `(?<!` の後読みはそのまま）。
"""

import json
import re
import sys
from pathlib import Path

repo = Path(sys.argv[1])
conf = json.loads((repo / ".github/renovate.json").read_text())


def js_to_py(rx):
    return re.sub(r"\(\?<(?![=!])", "(?P<", rx)


def scan(desc_key):
    """description に desc_key を含む manager を適用し、{(depName, currentValue, digest)} を返す。"""
    mgrs = [m for m in conf["customManagers"] if desc_key in m.get("description", "")]
    assert len(mgrs) == 1, f"manager {desc_key!r} が {len(mgrs)} 個"
    m = mgrs[0]
    found = set()
    for f in sorted(repo.rglob("*")):
        rel = f.relative_to(repo).as_posix()
        if not f.is_file() or rel.startswith((".git/", ".superpowers/")):
            continue
        if not any(re.search(js_to_py(p.strip("/")), rel) for p in m["managerFilePatterns"]):
            continue
        text = f.read_text()
        for ms in m["matchStrings"]:
            for hit in re.finditer(js_to_py(ms), text):
                g = hit.groupdict()
                found.add(
                    (
                        g.get("depName") or m.get("depNameTemplate"),
                        g.get("currentValue"),
                        g.get("currentDigest"),
                    )
                )
    return found


def read_var(rel, var):
    return re.search(rf'^{var}="([^"]+)"', (repo / rel).read_text(), re.M).group(1)


def read_pin(rel, regex):
    return re.search(regex, (repo / rel).read_text(), re.M).group(1)


failed = 0


def check(name, got, want):
    global failed
    ok = want <= got and got
    print(("PASS" if ok else "FAIL") + f": {name}")
    if not ok:
        failed += 1
        print(f"  expected (subset): {sorted(want, key=str)}\n  actual: {sorted(got, key=str)}")


npm = scan("npm の CLI")
check(
    "NPM_GLOBALS: difit / cline",
    npm,
    {
        ("difit", read_pin("bootstrap/23-shared-npm.sh", r"difit@([^\s\"]+)"), None),
        ("cline", read_pin("bootstrap/23-shared-npm.sh", r"cline@([^\s\"]+)"), None),
    },
)
# NPM_GLOBALS="" の初期化行や版の無い行は拾わない
if {d for d, _, _ in npm} != {"difit", "cline"}:
    failed += 1
    print(f"FAIL: NPM_GLOBALS が余分な依存を拾った: {sorted(npm, key=str)}")
else:
    print("PASS: NPM_GLOBALS: 初期化行を拾わない")

uv = scan("uv の CLI")
check(
    "UV_TOOLS: ansible / graphifyy（extra は depName に入らない）",
    uv,
    {
        ("ansible", read_pin("bootstrap/24-shared-uv.sh", r"ansible==([^\s\"]+)"), None),
        ("graphifyy", read_pin("bootstrap/24-shared-uv.sh", r"graphifyy\[[^\]]*\]==([^\s\"]+)"), None),
    },
)

check(
    "RUST_VERSION",
    scan("Rust の toolchain"),
    {("rust-lang/rust", read_var("bootstrap/25-shared-rust.sh", "RUST_VERSION"), None)},
)

check(
    "AGMSG_VERSION / AGMSG_COMMIT",
    scan("agmsg"),
    {
        (
            "fujibee/agmsg",
            read_var("bootstrap/22-shared-agmsg.sh", "AGMSG_VERSION"),
            read_var("bootstrap/22-shared-agmsg.sh", "AGMSG_COMMIT"),
        )
    },
)

kiro = scan("Kiro CLI")
check(
    "Kiro: aqua.yaml の kiro.dev/kiro-cli",
    kiro,
    {("kiro.dev/kiro-cli", read_pin("dot_config/aquaproj-aqua/aqua.yaml", r"name: kiro\.dev/kiro-cli@(\S+)"), None)},
)

if failed:
    sys.exit(1)
