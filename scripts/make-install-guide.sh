#!/bin/sh
# Builds a single self-contained HTML install guide (images embedded) for the DMG.
# Usage: scripts/make-install-guide.sh [output.html]
set -eu
cd "$(dirname "$0")/.."
OUT="${1:-dist/How to open OpenMount.html}"
mkdir -p "$(dirname "$OUT")"
python3 -I - docs/install/guide.template.html "$OUT" <<'PY'
import base64, pathlib, re, sys
src, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
html = src.read_text()
def inline(m):
    name = m.group(1)
    p = src.parent / name
    return "data:image/png;base64," + base64.b64encode(p.read_bytes()).decode()
html = re.sub(r"\{\{img:([^}]+)\}\}", inline, html)
assert "{{" not in html, "unresolved placeholder"
out.write_text(html)
print(f"Wrote {out} ({out.stat().st_size // 1024} KB)")
PY
