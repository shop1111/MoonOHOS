"""CLI integration checks: clean builds, UTF-8 paths, contract errors, ELF/HAP contents."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from zipfile import ZipFile

root = Path(__file__).resolve().parents[1]
cli = root / "_build/native/release/build/cmd/moonohos/moonohos.exe"
sdk = Path(sys.argv[1]).resolve()
tests = root / "_build/integration"
tests.mkdir(parents=True, exist_ok=True)
run = Path(tempfile.mkdtemp(prefix="run-", dir=tests)) / "中文 项目"
run.mkdir()
shutil.copytree(root / "examples/core", run / "计算 库", ignore=shutil.ignore_patterns("_build", ".mooncakes"))
seed = json.loads((root / "moonohos.json").read_text(encoding="utf-8"))
seed["module"] = "计算 库"
config = run / "moonohos.json"
config.write_text(json.dumps(seed, ensure_ascii=False), encoding="utf-8")
results = []
source_hash = hashlib.sha256((run / "计算 库/core.mbt").read_bytes()).hexdigest()

def execute(label, extra=(), success=True):
    result = subprocess.run([str(cli), "build", "--config", str(config), "--sdk", str(sdk), *extra], capture_output=True, encoding="utf-8", timeout=120)
    (run / (label + ".log")).write_text(result.stdout + result.stderr, encoding="utf-8")
    assert (result.returncode == 0) == success, (label, result.stdout, result.stderr)
    results.append({"case": label, "passed": True, "exit": result.returncode})
    return result.stdout

execute("dry-run", ["--dry-run"])
assert not (run / "_build").exists(), "dry-run wrote build output"
execute("clean-dual-abi")
package = run / "_build/moonohos/dist"
manifest = json.loads((package / "manifest.json").read_text(encoding="utf-8"))
assert [r["abi"] for r in manifest["results"]] == ["arm64-v8a", "x86_64"]
assert all(r["runtime"] == "not_run" for r in manifest["results"])
assert manifest["moonohosVersion"] == "0.2.0"
assert "Uint8Array" in (package / "types/libmoonohos/index.d.ts").read_text(encoding="utf-8")
for abi, machine in [("arm64-v8a", 183), ("x86_64", 62)]:
    data = (package / "libs" / abi / "libmoonohos.so").read_bytes()
    assert data[:4] == b"\x7fELF" and int.from_bytes(data[18:20], "little") == machine
assert hashlib.sha256((run / "计算 库/core.mbt").read_bytes()).hexdigest() == source_hash
assert not (run / "计算 库/moonohos_bridge").exists()
for item in package.rglob("*"):
    if item.is_file():
        assert str(sdk).encode() not in item.read_bytes()
        assert sdk.as_posix().encode() not in item.read_bytes()
execute("existing-output", success=False)
execute("unknown-abi", ["--abi", "wasm"], success=False)
execute("duplicate-abi", ["--abi", "x86_64,x86_64"], success=False)
bad = json.loads(json.dumps(seed))
bad["functions"][0]["return"] = "Array[Int]"
config.write_text(json.dumps(bad), encoding="utf-8")
assert "unsupported type" in execute("unsupported-type", success=False)
bad = json.loads(json.dumps(seed))
bad["functions"][0]["params"][0]["type"] = "Double"
config.write_text(json.dumps(bad), encoding="utf-8")
output = execute("signature-mismatch", ["--out", "wrong-dist"], success=False)
assert "signature" in output
config.write_text(json.dumps(seed), encoding="utf-8")
(run / "计算 库/moon.pkg").write_text('options("native-stub": ["stub.c"])\n', encoding="utf-8")
output = execute("native-stub", ["--out", "stub-dist"], success=False)
assert "Native stubs" in output
shutil.copytree(root / "fixtures/reference_matrix", run / "混合 类型", ignore=shutil.ignore_patterns("_build", ".mooncakes"))
matrix = json.loads((run / "混合 类型/moonohos.json").read_text(encoding="utf-8"))
matrix["module"] = "混合 类型"
config.write_text(json.dumps(matrix, ensure_ascii=False), encoding="utf-8")
output = execute("reference-return-matrix", ["--abi", "x86_64", "--out", "matrix-dist"])
work = next(line.removeprefix("Evidence: ") for line in output.splitlines() if line.startswith("Evidence: "))
subprocess.run([sys.executable, str(root / "scripts/verify_host.py"), work, "matrix_bridge.cpp"], check=True)
results.append({"case": "reference-matrix-asan", "passed": True})
hap = root / "examples/harmony/entry/build/default/outputs/default/entry-default-unsigned.hap"
if hap.exists():
    names = ZipFile(hap).namelist()
    assert "libs/arm64-v8a/libmoonohos.so" in names
    assert "libs/x86_64/libmoonohos.so" in names
    results.append({"case": "hap-dual-abi", "passed": True})
(run.parent / "results.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
print(f"INTEGRATION_PASS cases={len(results)} evidence={run.parent}")
