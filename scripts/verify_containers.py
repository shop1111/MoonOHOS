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
subprocess.run(["moon", "run", "--target", "native", "fixtures/emit", "--", str(work / "module/moonohos.json"), str(work / "module"), str(work / "native")], cwd=root, check=True)
subprocess.run([sys.executable, str(root / "scripts/verify_host.py"), str(work), driver], cwd=root, check=True)
print(f"CONTAINER_HOST_PASS fixture={fixture} evidence={work}")
