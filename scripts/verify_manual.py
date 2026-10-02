"""One-off handwritten ABI/Node-API spike; the production builder is MoonBit."""
from pathlib import Path
import os
import shlex
import subprocess
import sys

root = Path(__file__).resolve().parents[1] / "fixtures/manual"
sdk = Path(sys.argv[1])
native = sdk / "default/openharmony/native"
home = Path(os.environ.get("MOON_HOME", Path.home() / ".moon"))
home_text = home.as_posix()
plan = subprocess.check_output(["moon", "build", "--target", "native", "--release", "--dry-run"], cwd=root, text=True, encoding="utf-8")
for line in plan.splitlines():
    if line.startswith("moonc "):
        args = [s.replace("$MOON_HOME", home.as_posix()) for s in shlex.split(line)]
        if "-all-pkgs" in args:
            i = args.index("-all-pkgs")
            del args[i:i + 2]
        output = root / args[args.index("-o") + 1]
        output.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(args, cwd=root, check=True)
cmake = native / "build-tools/cmake/bin/cmake.exe"
for abi in ("arm64-v8a", "x86_64"):
    build = root / "_build" / abi
    subprocess.run([str(cmake), "-S", str(root), "-B", str(build), "-G", "Ninja", f"-DCMAKE_MAKE_PROGRAM={native / 'build-tools/cmake/bin/ninja.exe'}", f"-DCMAKE_TOOLCHAIN_FILE={native / 'build/cmake/ohos.toolchain.cmake'}", f"-DOHOS_ARCH={abi}", "-DOHOS_COMPATIBLE_SDK_VERSION=26", "-DCMAKE_BUILD_TYPE=Release", f"-DMOON_HOME={home_text}"], check=True)
    subprocess.run([str(cmake), "--build", str(build)], check=True)
    subprocess.run([str(native / "llvm/bin/llvm-readelf.exe"), "-h", "-d", str(build / "libmoonohos.so")], check=True, stdout=subprocess.DEVNULL)
    print(f"manual bridge built: {abi}")
