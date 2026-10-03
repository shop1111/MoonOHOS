"""ASan checks generated C and bridge callbacks with a host Node-API test double."""
from pathlib import Path
import os
import subprocess
import sys
import shutil
import re

root = Path(__file__).resolve().parents[1]
if len(sys.argv) > 1:
    work = Path(sys.argv[1]).resolve()
else:
    candidates = [p for p in (root / "_build/moonohos").glob("work-*") if (p / "dist/manifest.json").exists() or (p / "build-x86_64.log").exists()]
    work = max(candidates, key=lambda p: int(p.name.split("-")[-1]))
generated = work / "native"
home = Path(os.environ.get("MOON_HOME", Path.home() / ".moon"))
test_source = root / "tests" / (sys.argv[2] if len(sys.argv) > 2 else "host_bridge.cpp")
build = root / "_build/host-asan-v0.3"
if test_source.name != "host_bridge.cpp":
    build = build / test_source.stem
build.mkdir(parents=True, exist_ok=True)
vswhere = Path(os.environ.get("ProgramFiles(x86)", "C:/Program Files (x86)")) / "Microsoft Visual Studio/Installer/vswhere.exe"
installation = subprocess.check_output([str(vswhere), "-latest", "-products", "*", "-requires", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64", "-property", "installationPath"], text=True).strip()
vcvars = Path(installation) / "VC/Auxiliary/Build/vcvars64.bat"
# Initialize compiler search paths only in this test subprocess environment.
env_script = build / "compiler-environment.cmd"
env_script.write_text(f'@echo off\ncall "{vcvars}" >nul\nif errorlevel 1 exit /b 1\nset\n', encoding="utf-8")
environment = subprocess.check_output(f'cmd.exe /d /s /c ""{env_script}""').decode("mbcs")
env = dict(os.environ)
for line in environment.splitlines():
    if "=" in line and not line.startswith("="):
        key, value = line.split("=", 1)
        env[key.upper()] = value
compiler = shutil.which("cl.exe", path=env["PATH"])
if not compiler:
    raise RuntimeError("MSVC C++ tools with AddressSanitizer required")
sources = [generated / "embed.c"] + [home / "lib/runtime" / name for name in ("runtime.c", "env.c", "backtrace.c", "sync_io.c", "utf.c")]
objects = []
flags = ["/nologo", "/fsanitize=address", "/O1", "/Zi", "/MT", "/utf-8", "/DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_SYSTEM", "/DMOONBIT_NATIVE_EXIT_ON_PANIC", "/D_CRT_SECURE_NO_WARNINGS", "/I" + str(home / "include"), "/I" + str(generated)]
exports = len(re.findall(r'\{"[^"\n]+", nullptr, Call_', (generated / "napi_init.cpp").read_text(encoding="utf-8")))
flags.append(f"/DMOONOHOS_EXPECTED_EXPORTS={exports}")
for source in sources:
    output = build / (source.stem + ".obj")
    subprocess.run([compiler, *flags, "/FI" + str(root / "tests/alloc_probe.h"), "/std:c11", "/c", str(source), "/Fo" + str(output)], check=True, env=env, cwd=build)
    objects.append(str(output))
exe = build / "host_bridge.exe"
subprocess.run([compiler, *flags, "/std:c++17", "/EHsc", "/UNDEBUG", "/I" + str(root / "tests/mock"), str(test_source), str(root / "tests/alloc_probe.cpp"), *objects, "/Fe" + str(exe)], check=True, env=env, cwd=build)
result = subprocess.run([str(exe)], capture_output=True, text=True, env=env)
(build / "result.log").write_text(result.stdout + result.stderr, encoding="utf-8")
print(result.stdout, end="")
print(result.stderr, end="")
result.check_returncode()
