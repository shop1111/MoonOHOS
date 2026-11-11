"""Compile and link generated system bindings against the real HarmonyOS SDK.

For every package directory (default: ohos/sys/*) and both ABIs, the generated
`*_stub.c` is compiled with the SDK's clang against the SDK headers with
-Wall -Wextra -Werror, then linked into a shared object against the declared
system libraries with --no-undefined, so a wrong type, cast or library fails.

usage: python scripts/verify_bindings.py <DevEco sdk dir> [package dir ...]
"""
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
sdk = Path(sys.argv[1])
native = next(p for p in [sdk / "default/openharmony/native", sdk / "openharmony/native", sdk / "native", sdk] if (p / "llvm").exists())
clang = native / "llvm/bin" / ("clang.exe" if os.name == "nt" else "clang")
sysroot = native / "sysroot"
packages = [Path(p) for p in sys.argv[2:]] or sorted(p for p in (root / "ohos/sys").iterdir() if (p / "moonohos.native.json").exists())
targets = {"arm64-v8a": "aarch64-linux-ohos", "x86_64": "x86_64-linux-ohos"}
results = []
work = Path(tempfile.mkdtemp(prefix="bindings-", dir=root / "_build" if (root / "_build").exists() else None))
for package in packages:
    descriptor = json.loads((package / "moonohos.native.json").read_text(encoding="utf-8"))
    for abi, triple in targets.items():
        out = work / package.name / abi
        out.mkdir(parents=True, exist_ok=True)
        objects = []
        for source in descriptor["sources"]:
            obj = out / (Path(source).stem + ".o")
            compile_cmd = [str(clang), f"--target={triple}", f"--sysroot={sysroot}", "-DMOONOHOS_TARGET_OHOS",
                           "-std=c11", "-fPIC", "-Wall", "-Wextra", "-Werror", "-c", str(package / source), "-o", str(obj)]
            r = subprocess.run(compile_cmd, capture_output=True, text=True)
            if r.returncode:
                print(r.stdout + r.stderr)
                raise SystemExit(f"compile failed: {package.name} {abi}")
            objects.append(str(obj))
        libs = [f"-l:{lib}" for lib in descriptor["systemLibraries"]]
        link_cmd = [str(clang), f"--target={triple}", f"--sysroot={sysroot}", "-shared", "-fPIC", "-o", str(out / "libcheck.so"),
                    *objects, *libs, "-Wl,--no-undefined"]
        r = subprocess.run(link_cmd, capture_output=True, text=True)
        if r.returncode:
            print(r.stdout + r.stderr)
            raise SystemExit(f"link failed: {package.name} {abi}")
    results.append(package.name)
print(f"BINDINGS_PASS packages={len(results)} abis=arm64-v8a,x86_64 werror=1 no_undefined=1 [{', '.join(results)}]")
