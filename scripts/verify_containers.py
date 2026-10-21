"""Build actual compiler exports and run generated container callbacks under ASan."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
fixture = sys.argv[1] if len(sys.argv) > 1 else "array_core"
driver = sys.argv[2] if len(sys.argv) > 2 else "array_bridge.cpp"
work = Path(tempfile.mkdtemp(prefix="containers-", dir=root / "_build"))
shutil.copytree(root / "fixtures" / fixture, work / "module")
if (work / "module/moon.work").exists():
    # Workspace fixtures resolve the platform module from a sibling copy.
    shutil.copytree(root / "ohos", work / "ohos", ignore=shutil.ignore_patterns("_build", ".mooncakes"))
    (work / "module/moon.work").write_text('members = [\n  ".",\n  "../ohos",\n]\n', encoding="utf-8")
subprocess.run(["moon", "run", "--target", "native", "fixtures/emit", "--", str(work / "module/moonohos.json"), str(work / "module"), str(work / "native")], cwd=root, check=True)
subprocess.run([sys.executable, str(root / "scripts/verify_host.py"), str(work), driver], cwd=root, check=True)
print(f"CONTAINER_HOST_PASS fixture={fixture} evidence={work}")
