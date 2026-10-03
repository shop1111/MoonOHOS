"""Exercise the actual MoonBit CLI, including cache recovery and Unicode paths."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import hashlib

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sdk", required=True)
    parser.add_argument("--cli", default=str(ROOT / "_build/native/release/build/cmd/moonohos/moonohos.exe"))
    args = parser.parse_args()
    cli = str(Path(args.cli).resolve())
    work = Path(tempfile.mkdtemp(prefix="CLI 中文 空格-", dir=ROOT / "_build"))
    project = work / "项目 核心"
    shutil.copytree(ROOT / "fixtures/record_core", project, ignore=shutil.ignore_patterns("_build"))
    config = project / "moonohos.json"
    calls = []

    def run(*arguments, code=0, structured=True):
        result = subprocess.run([cli, *map(str, arguments)], cwd=work, capture_output=True,
                                encoding="utf-8", timeout=600)
        assert result.returncode == code, (arguments, result.returncode, result.stdout, result.stderr)
        report = json.loads(result.stdout) if structured else result.stdout
        if structured:
            assert report["exitCode"] == code
            assert report["ok"] == (code == 0)
        calls.append({"args": list(map(str, arguments)), "exitCode": code, "report": report})
        return report

    run("check", "--unknown", "--json", code=2)
    run("build", "--sdk", "--json", code=2)
    run("check", "--config", work / "absent.json", "--json", code=3)
    run("check", "--config", config, "--json")
    run("inspect", "--config", config, "--json")
    run("plan", "--config", config, "--abi", "x86_64", "--json")
    run("doctor", "--sdk", args.sdk, "--json")
    before = set((project / "_build/moonohos").iterdir())
    run("build", "--config", config, "--sdk", args.sdk, "--dry-run", "--json")
    assert set((project / "_build/moonohos").iterdir()) == before

    def build(name):
        return run("build", "--config", config, "--sdk", args.sdk, "--abi", "x86_64",
                   "--out", str(work / name), "--cache", "--json")["result"]

    assert build("first")["cache"] == "miss"
    assert build("second")["cache"] == "hit"
    source = project / "core.mbt"
    source.write_text(source.read_text(encoding="utf-8") + "\n// Cache invalidation probe\n", encoding="utf-8")
    assert build("changed")["cache"] == "miss"
    entries = list((project / "_build/moonohos/cache").glob("*/dist/libs/x86_64/librecords.so"))
    for library in entries:
        library.write_bytes(b"corrupted")
    assert build("recovered")["cache"] == "miss"
    assert list((project / "_build/moonohos/cache").glob("*.corrupt-*"))
    run("verify", "--out", work / "recovered", "--json")
    # Recompute file checksums after corrupting ELF metadata so these cases reach
    # the binary parser rather than failing at the checksum gate.
    library = work / "recovered/libs/x86_64/librecords.so"
    original = library.read_bytes()
    manifest_path = work / "recovered/manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    file_entry = next(f for f in manifest["files"] if f["path"].endswith("librecords.so"))
    for offset, value, label in [(0, 0, "magic"), (4, 1, "class"), (5, 2, "endian"),
                                  (16, 2, "executable"), (18, 183, "machine"), (47, 255, "section-offset")]:
        data = bytearray(original)
        data[offset] = value
        library.write_bytes(data)
        file_entry["sha256"] = hashlib.sha256(data).hexdigest()
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        report = run("verify", "--out", work / "recovered", "--json", code=3)
        assert "elf:" in report["diagnostics"][0]["message"] or "architecture" in report["diagnostics"][0]["message"], label
    library.write_bytes(original)
    file_entry["sha256"] = hashlib.sha256(original).hexdigest()
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    library = work / "recovered/libs/x86_64/librecords.so"
    data = bytearray(library.read_bytes())
    data[-1] ^= 1
    library.write_bytes(data)
    run("verify", "--out", work / "recovered", "--json", code=3)
    run("build", "--config", config, "--sdk", args.sdk, "--out", work / "first", "--json", code=3)
    (work / "results.json").write_text(json.dumps(calls, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"CLI_PASS cases={len(calls)} unicode/cache/recovery/corruption evidence={work}")

if __name__ == "__main__":
    main()
