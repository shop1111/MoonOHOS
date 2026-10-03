///|
extern "C" fn native_exit(code : Int) -> Unit = "exit"

///|
fn usage() -> String {
  "MoonOHOS 0.3.0\nmoonohos build [--config moonohos.json] --sdk <SDK> [--abi arm64-v8a,x86_64] [--out <directory>] [--dry-run] [--cache] [--json]\n"
}

///|
async fn build(
  config_path : String,
  sdk_path : String,
  abi_text : String,
  out_path : String,
  dry_run : Bool,
  cache : Bool,
) -> Json {
  let config_path = normalized(@fs.realpath(config_path))
  let base = parent(config_path)
  let config = @lib.parse_project(read(config_path))
  config.validate()
  let module_root = normalized(@fs.realpath(resolve(base, config.module_dir)))
  let (module_name, source_dir) = module_metadata(module_root)
  if config.package_name != module_name &&
    !config.package_name.has_prefix(module_name + "/") {
    raise Failure("config: package must belong to selected module")
  }
  let package_relative = if config.package_name == module_name {
    ""
  } else {
    config.package_name[module_name.length() + 1:].to_owned()
  }
  let abis = abi_text.split(",").map(s => s.to_owned()).to_array()
  let seen : Map[String, Bool] = Map([])
  for abi in abis {
    if (abi != "arm64-v8a" && abi != "x86_64") || seen.contains(abi) {
      raise Failure("config: unsupported/duplicate ABI " + abi)
    }
    seen[abi] = true
  }
  let out = resolve(base, out_path)
  let sdk = normalized(@fs.realpath(resolve(base, sdk_path)))
  let candidates = [
    sdk + "/default/openharmony/native",
    sdk + "/openharmony/native",
    sdk + "/native",
    sdk,
  ]
  let mut native = ""
  for candidate in candidates {
    if @fs.exists(candidate + "/build/cmake/ohos.toolchain.cmake") {
      native = candidate
      break
    }
  }
  if native == "" {
    raise Failure("toolchain: OHOS Native SDK not found")
  }
  let metadata = @json.parse(read(native + "/oh-uni-package.json"))
  match metadata {
    { "apiVersion": "26", .. } => ()
    _ => raise Failure("toolchain: only SDK API 26 is verified")
  }
  doctor(@lib.parse_cli(["doctor"])) |> ignore
  let moon_version = command("toolchain", "moon", ["version"], base)
  let compiler_version = command("toolchain", "moonc", ["-v"], base)
  if !moon_version.contains("0.1.20260920") ||
    !compiler_version.contains("v0.10.14+7d59c7ec9") {
    raise Failure("toolchain: requires Moon 20260920 / moonc v0.10.14")
  }
  let moon_home = normalized(
    @env.get_env_var("MOON_HOME").unwrap_or(
      @env.get_env_var("USERPROFILE").unwrap_or("") + "/.moon",
    ),
  )
  let cmake = native + "/build-tools/cmake/bin/cmake.exe"
  let ninja = native + "/build-tools/cmake/bin/ninja.exe"
  for
    tool in [
      cmake,
      ninja,
      native + "/llvm/bin/clang.exe",
      native + "/llvm/bin/llvm-readelf.exe",
      native + "/NOTICE.txt",
      moon_home + "/lib/runtime/runtime.c",
      moon_home + "/include/moonbit.h",
    ] {
    if !@fs.exists(tool) {
      raise Failure("toolchain: missing " + tool)
    }
  }
  if dry_run {
    return { "dryRun": true, "output": out, "runtime": "not_run" }
  }
  if @fs.exists(out) {
    raise Failure(
      "publish: output already exists; choose a new --out directory",
    )
  }
  ensure_dir(base + "/_build/moonohos")
  let mut sequence = 1
  while @fs.exists(base + "/_build/moonohos/work-" + sequence.to_string()) {
    sequence += 1
  }
  let work = base + "/_build/moonohos/work-" + sequence.to_string()
  command_logs.val = Some(work + "/commands")
  let artifacts = config.generate()
  let staged = work + "/module"
  copy_tree(module_root, staged, module_tree=true)
  reject_stubs(staged)
  let source = staged + "/" + source_dir
  let bridge = source + "/moonohos_bridge"
  if @fs.exists(bridge) {
    raise Failure("stage: reserved package moonohos_bridge already exists")
  }
  // Resolve normal MoonBit dependencies in the disposable copy, then audit them.
  command("interface", "moon", ["info", "--target", "native"], staged) |> ignore
  reject_stubs(staged + "/.mooncakes") catch {
    error => if @fs.exists(staged + "/.mooncakes") { raise error }
  }
  config.verify_interface(
    read(source + "/" + package_relative + "/pkg.generated.mbti"),
  )
  let cache_entry = if cache {
    let key = build_cache_key(
      staged,
      native,
      moon_home,
      read(config_path),
      abis,
      artifacts,
    )
    Some(base + "/_build/moonohos/cache/" + key)
  } else {
    None
  }
  if cache_entry is Some(entry) && restore_cache(entry, work, out) {
    return {
      "output": out,
      "cache": "hit",
      "evidence": work,
      "runtime": "not_run",
    }
  }
  write(bridge + "/moon.pkg", artifacts.package_file)
  write(bridge + "/main.mbt", artifacts.wrapper)
  let plan = command(
    "plan",
    "moon",
    [
      "build",
      "--target",
      "native",
      "--release",
      "--dry-run",
      source_dir + "/moonohos_bridge",
    ],
    staged,
  )
  // Do not persist dry-run environment dumps from unrelated host compiler steps.
  let commands = @lib.compiler_commands(plan, moon_home)
  let mut c_output = ""
  let compiler_log : Array[Json] = []
  for args in commands {
    let mut index = 0
    while index < args.length() {
      if args[index] == "-o" && index + 1 < args.length() {
        let output = resolve(staged, args[index + 1])
        ensure_dir(parent(output))
        if args[0] == "link-core" {
          c_output = output
        }
      }
      index += 1
    }
    compiler_log.push(args.to_json())
    command("moonbit", "moonc", args, staged) |> ignore
  }
  write(
    work + "/compiler-commands.json",
    compiler_log.to_json().stringify(indent=2),
  )
  let generated = work + "/native"
  write(generated + "/core.c", read(c_output))
  write(generated + "/moonohos.h", artifacts.header)
  write(generated + "/embed.c", artifacts.embed)
  write(generated + "/napi_init.cpp", artifacts.native)
  write(generated + "/CMakeLists.txt", artifacts.cmake)
  let package_dir = work + "/dist"
  let results : Array[Json] = []
  for abi in abis {
    let build_dir = work + "/cmake-" + abi
    let configure = command(
      "cmake-configure/" + abi,
      cmake,
      [
        "-S",
        generated,
        "-B",
        build_dir,
        "-G",
        "Ninja",
        "-DCMAKE_MAKE_PROGRAM=" + ninja,
        "-DCMAKE_TOOLCHAIN_FILE=" + native + "/build/cmake/ohos.toolchain.cmake",
        "-DOHOS_ARCH=" + abi,
        "-DOHOS_COMPATIBLE_SDK_VERSION=26",
        "-DOHOS_STL=c++_static",
        "-DCMAKE_BUILD_TYPE=Release",
        "-DMOON_HOME=" + moon_home,
      ],
      base,
    )
    write(work + "/configure-" + abi + ".log", configure)
    let log = command("cmake-build/" + abi, cmake, ["--build", build_dir], base)
    write(work + "/build-" + abi + ".log", log)
    let library = build_dir + "/lib" + config.native_module + ".so"
    let elf = command(
      "elf/" + abi,
      native + "/llvm/bin/llvm-readelf.exe",
      ["-h", "-d", "--dyn-syms", library],
      base,
    )
    let machine = if abi == "arm64-v8a" {
      "AArch64"
    } else {
      "Advanced Micro Devices X86-64"
    }
    if !elf.contains(machine) || !elf.contains("libace_napi.z.so") {
      raise Failure("elf: wrong ABI or missing Node-API dependency")
    }
    if !elf.contains("napi_module_register") ||
      elf.contains("libc++_shared.so") ||
      elf.contains(".dll") {
      raise Failure(
        "elf: missing registration or unexpected runtime dependency",
      )
    }
    write(work + "/elf-" + abi + ".log", elf)
    let dest = package_dir + "/libs/" + abi
    ensure_dir(dest)
    @fs.write_file(
      dest + "/lib" + config.native_module + ".so",
      @fs.read_file(library),
    )
    results.push({
      "abi": abi,
      "elf": "verified",
      "build": "passed",
      "runtime": "not_run",
    })
  }
  let types = package_dir + "/types/lib" + config.native_module
  write(types + "/index.d.ts", artifacts.declarations)
  let type_manifest : Json = {
    "name": "lib" + config.native_module + ".so",
    "version": "0.3.0",
    "types": "./index.d.ts",
  }
  write(types + "/oh-package.json5", type_manifest.stringify(indent=2))
  let imported = "# Generated, relocatable import. This does not package the library into a HAP.\nadd_library(" +
    config.native_module +
    " SHARED IMPORTED)\nset_target_properties(" +
    config.native_module +
    " PROPERTIES IMPORTED_LOCATION \"${CMAKE_CURRENT_LIST_DIR}/../libs/${OHOS_ARCH}/lib" +
    config.native_module +
    ".so\")\n"
  write(package_dir + "/cmake/MoonOHOS.cmake", imported)
  let manifest : Json = {
    "schema": "moonohos-build-v1",
    "moonohosVersion": "0.3.0",
    "module": config.native_module,
    "moon": moon_version.trim().to_owned(),
    "moonc": compiler_version.trim().to_owned(),
    "sdkApi": 26,
    "results": results.to_json(),
    "functions": config.functions.map(f => f.signature()).to_json(),
  }
  write(package_dir + "/manifest.json", manifest.stringify(indent=2))
  write(package_dir + "/NOTICE.NativeSDK.txt", read(native + "/NOTICE.txt"))
  let runtime_source = read(moon_home + "/lib/runtime/runtime.c")
  let runtime_notice = runtime_source
    .split("*/")
    .head()
    .unwrap_or("")
    .to_owned() +
    "*/\n"
  write(package_dir + "/NOTICE.MoonBit.txt", runtime_notice)
  write(
    package_dir + "/README.md",
    "# MoonOHOS Native package\n\nCopy libs/<abi>/*.so into entry/libs/<abi>/. Copy types/lib" +
    config.native_module +
    " into entry/src/main/cpp/types/ and declare the local dependency in entry/oh-package.json5. Import lib" +
    config.native_module +
    ".so from ArkTS. The CMake import is optional and does not package the library into a HAP.\n\nSynchronous scalar, String, Bytes, Array and Struct functions. Arrays must be ordinary dense non-Sendable arrays. Records require own fields; extra fields are ignored. Containers are acyclic and bounded to depth 32, 1048576 nodes and 64 MiB copied data per conversion. All containers are copied. String uses length-delimited UTF-16 and preserves NUL and surrogate code units. Bytes accepts ordinary, attached Uint8Array views only. Input and output are copied; returned arrays are independent. ArrayBuffer, DataView, other typed arrays and shared buffers are unsupported.\n\nReference arguments are borrowed and reference results own one reference in the pinned compiler ABI. Buffers and references are released on failure. MoonBit panic or runtime allocation failure may terminate the process; typed MoonBit errors are unsupported. Runtime not verified by build.\n\nKeep NOTICE.NativeSDK.txt and NOTICE.MoonBit.txt with distributed libraries. Add the license of your own MoonBit code.\n",
  )
  if @fs.exists(out) {
    raise Failure(
      "publish: output already exists; choose a new --out directory",
    )
  }
  ensure_dir(parent(out))
  seal_package(package_dir)
  verify_package(package_dir) |> ignore
  @fs.rename(package_dir, out)
  if cache_entry is Some(entry) {
    save_cache(entry, out, work)
  }
  {
    "output": out,
    "cache": if cache {
      "miss"
    } else {
      "disabled"
    },
    "evidence": work,
    "runtime": "not_run",
  }
}

///|
async fn main {
  let args = @env.args()[1:].to_owned()
  let json = args.contains("--json")
  let options = @lib.parse_cli(args) catch {
    Invalid(message) => {
      let diagnostic : @lib.Diagnostic = {
        stage: "arguments",
        code: "invalid-option",
        message,
        context: [],
      }
      println(
        if json {
          @lib.failure_report(
            args.get(0).unwrap_or("help"),
            diagnostic,
            parameter=true,
          ).stringify(indent=2)
        } else {
          diagnostic.render()
        },
      )
      native_exit(2)
      return
    }
  }
  let name = @lib.command_name(options.command)
  let result : Json = try {
    match options.command {
      Help => {
        println(
          usage() +
          "Commands: doctor, check, inspect, plan, verify. Analysis commands support --json.",
        )
        return
      }
      Version => {
        println("MoonOHOS 0.3.0")
        return
      }
      Build =>
        build(
          options.config,
          options.sdk.unwrap(),
          options.abis.join(","),
          options.output,
          options.dry_run,
          options.cache,
        )
      Doctor => doctor(options)
      Check | Inspect | Plan => analyze(options)
      Verify => verify_package(options.output)
    }
  } catch {
    error => {
      let diagnostic : @lib.Diagnostic = {
        stage: name,
        code: "failed",
        message: match error {
          Failure(message) => message
          @lib.Invalid(message) => message
          _ => error.to_string()
        },
        context: [],
      }
      println(
        if options.json {
          @lib.failure_report(name, diagnostic).stringify(indent=2)
        } else {
          diagnostic.render()
        },
      )
      native_exit(3)
      return
    }
  }
  println(
    if options.json {
      @lib.success_report(name, result).stringify(indent=2)
    } else {
      result.stringify(indent=2)
    },
  )
}
