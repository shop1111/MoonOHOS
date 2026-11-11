"""Regenerate every system binding package from its moonohos.bindgen.json.

usage: python scripts/generate_bindings.py <DevEco sdk dir> [name ...]
"""
from pathlib import Path
import json
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
cli = root / "_build/native/release/build/cmd/moonohos/moonohos.exe"
names = sys.argv[2:]
summary = []
for spec in sorted((root / "ohos/sys").glob("*/moonohos.bindgen.json")):
    if names and spec.parent.name not in names:
        continue
    r = subprocess.run([str(cli), "bindgen", "--spec", str(spec), "--sdk", sys.argv[1], "--json"], capture_output=True, text=True, encoding="utf-8")
    report = json.loads(r.stdout)
    if not report["ok"]:
        raise SystemExit(f"{spec.parent.name}: {report['diagnostics']}")
    result = report["result"]
    summary.append((spec.parent.name, len(result["bound"]), len(result["skipped"])))
bound = sum(s[1] for s in summary)
skipped = sum(s[2] for s in summary)
for name, b, s in summary:
    print(f"  {name}: bound {b}, skipped {s}")
print(f"GENERATE_PASS packages={len(summary)} bound={bound} skipped={skipped}")
