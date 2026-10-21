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
    import struct
    program_start = struct.unpack_from('<Q', original, 32)[0]
    program_size, program_count = struct.unpack_from('<HH', original, 54)
    dynamic_start = next(program_start + index * program_size for index in range(program_count)
                         if struct.unpack_from('<I', original, program_start + index * program_size)[0] == 2)
    for relative, replacement in [(32, 0), (16, struct.unpack_from('<Q', original, dynamic_start + 16)[0] + 1)]:
        data = bytearray(original)
        struct.pack_into('<Q', data, dynamic_start + relative, replacement)
        library.write_bytes(data)
        file_entry['sha256'] = hashlib.sha256(data).hexdigest()
        manifest_path.write_text(json.dumps(manifest), encoding='utf-8')
        report = run('verify', '--out', work / 'recovered', '--json', code=3)
        assert 'dynamic program segment' in json.dumps(report)
    library.write_bytes(original)
    file_entry["sha256"] = hashlib.sha256(original).hexdigest()
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    library = work / "recovered/libs/x86_64/librecords.so"
    data = bytearray(library.read_bytes())
    data[-1] ^= 1
    library.write_bytes(data)
    run("verify", "--out", work / "recovered", "--json", code=3)
    run("build", "--config", config, "--sdk", args.sdk, "--out", work / "first", "--json", code=3)
    framework_cases(run, work, args.sdk)
    (work / "results.json").write_text(json.dumps(calls, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"CLI_PASS cases={len(calls)} unicode/cache/recovery/corruption/init/native/har evidence={work}")


def stub_module(root: Path, package_file: str, descriptor: str | None, stub_name="x.c"):
    """Single-module project whose core package imports a package with C stubs."""
    (root / "native").mkdir(parents=True)
    (root / "moon.mod").write_text('name = "demo/stubs"\n\npreferred_target = "native"\n', encoding="utf-8")
    (root / "moon.pkg").write_text('import {\n  "demo/stubs/native",\n}\n', encoding="utf-8")
    (root / "core.mbt").write_text("///|\npub fn twice(x : Int) -> Int {\n  @native.id(x) * 2\n}\n", encoding="utf-8")
    (root / "native/moon.pkg").write_text(package_file, encoding="utf-8")
    (root / "native/native.mbt").write_text('///|\nextern "C" fn raw(x : Int) -> Int = "moonohos_demo_id"\n\n///|\npub fn id(x : Int) -> Int {\n  raw(x)\n}\n', encoding="utf-8")
    (root / "native" / stub_name).write_text("#include <stdint.h>\nint32_t moonohos_demo_id(int32_t x) { return x; }\n", encoding="utf-8")
    if descriptor is not None:
        (root / "native/moonohos.native.json").write_text(descriptor, encoding="utf-8")
    (root / "moonohos.json").write_text(json.dumps({"version": 1, "module": ".", "package": "demo/stubs", "nativeModule": "stubs",
        "functions": [{"name": "twice", "params": [{"name": "x", "type": "Int"}], "return": "Int"}]}), encoding="utf-8")
    return root / "moonohos.json"


def framework_cases(run, work: Path, sdk: str):
    # init: creates a workspace project once and refuses non-empty directories.
    created = run("init", work / "新建 项目", "--name", "demo", "--package", "alice/demo", "--ohos", ROOT / "ohos", "--json")["result"]
    assert "harmony/demo/src/main/module.json5" in created["files"]
    run("init", work / "新建 项目", "--name", "demo", "--json", code=3)
    run("init", "--name", "demo", "--json", code=2)
    run("init", work / "bad", "--name", "Bad-Name", "--json", code=3)

    # Workspace build with platform packages: NDK libraries linked and recorded.
    async_config = ROOT / "fixtures/async_core/moonohos.json"
    run("check", "--config", async_config, "--json")
    platform = run("build", "--config", async_config, "--sdk", sdk, "--abi", "x86_64", "--out", work / "platform", "--json")["result"]
    manifest = json.loads((work / "platform/manifest.json").read_text(encoding="utf-8"))
    assert manifest["schema"] == "moonohos-build-v2" and manifest["handles"] == ["Counter"]
    assert {d["package"] for d in manifest["nativeDependencies"]} == {"shop1111/moonohos_ohos/hilog", "shop1111/moonohos_ohos/rawfile", "shop1111/moonohos_ohos/task"}
    verified = run("verify", "--out", work / "platform", "--json")["result"]
    assert "librawfile.z.so" in json.dumps(verified) and platform["runtime"] == "not_run"

    # Native dependency policy: each rejection names its cause.
    stub_pkg = 'options(\n  "native-stub": [ "x.c" ],\n)\n'
    good = {"schema": "moonohos-native-v1", "package": "demo/stubs/native", "sources": ["x.c"], "abis": ["arm64-v8a", "x86_64"]}
    cases = [
        ("missing", stub_pkg, None, "x.c", "no moonohos.native.json"),
        ("library", stub_pkg, json.dumps(dict(good, systemLibraries=["libssl.so"])), "x.c", "allowlist"),
        ("mismatch", stub_pkg, json.dumps(dict(good, sources=["y.c"])), "x.c", "sources must equal"),
        ("escape", 'options(\n  "native-stub": [ "../x.c" ],\n)\n', json.dumps(dict(good, sources=["../x.c"])), "x.c", "parent directory|inside the package"),
        ("hook", 'options(\n  "native-stub": [ "x.c" ],\n  "pre-build": [],\n)\n', json.dumps(good), "x.c", "pre-build"),
    ]
    for name, package_file, descriptor, stub, expected in cases:
        stub_config = stub_module(work / "stubs" / name, package_file, descriptor, stub)
        report = run("build", "--config", stub_config, "--sdk", sdk, "--abi", "x86_64", "--out", work / "stubs" / (name + "-out"), "--json", code=3)
        assert any(e in report["diagnostics"][0]["message"] for e in expected.split("|")), (name, report)
    accepted = stub_module(work / "stubs/accepted", stub_pkg, json.dumps(good))
    run("build", "--config", accepted, "--sdk", sdk, "--abi", "x86_64", "--out", work / "stubs/accepted-out", "--json")

    # 0.3 (schema v1) packages remain verifiable.
    legacy = work / "legacy"
    shutil.copytree(work / "first", legacy)
    legacy_manifest = json.loads((legacy / "manifest.json").read_text(encoding="utf-8"))
    legacy_manifest.update({"schema": "moonohos-build-v1", "moonohosVersion": "0.3.0"})
    for key in ("exports", "handles", "nativeDependencies"):
        legacy_manifest.pop(key, None)
    types = next(legacy.glob("types/*/oh-package.json5"))
    types_json = json.loads(types.read_text(encoding="utf-8"))
    types_json["version"] = "0.3.0"
    types.write_bytes(json.dumps(types_json, indent=2).encode("utf-8"))
    entry = next(f for f in legacy_manifest["files"] if f["path"] == types.relative_to(legacy).as_posix())
    entry["size"], entry["sha256"] = types.stat().st_size, hashlib.sha256(types.read_bytes()).hexdigest()
    (legacy / "manifest.json").write_text(json.dumps(legacy_manifest), encoding="utf-8")
    assert run("verify", "--out", legacy, "--json")["result"]["moonohosVersion"] == "0.3.0"

    # har: prepare a HAR module from the init project without DevEco.
    project = work / "新建 项目"
    run("build", "--config", project / "moonohos.json", "--sdk", sdk, "--abi", "x86_64", "--out", project / "_build/dist", "--json")
    module = project / "harmony/demo"
    run("har", "--dist", project / "_build/dist", "--module", module, "--json")
    assert (module / "libs/x86_64/libdemo.so").exists()
    assert "export default native" in (module / "src/main/ets/generated/Native.ets").read_text(encoding="utf-8")
    assert json.loads((module / "moonohos-har.json").read_text(encoding="utf-8"))["module"] == "demo"
    run("har", "--dist", project / "_build/dist", "--module", module, "--assemble", "--json", code=2)
    run("har", "--dist", project / "_build/dist", "--module", project / "core", "--json", code=3)

if __name__ == "__main__":
    main()
