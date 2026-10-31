///|
extern "C" fn native_exit(code : Int32) -> Unit = "exit"

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
    { "apiVersion": String(api), .. } if @lib.version_at_least(
        api,
        @lib.minimum_sdk_api.to_string(),
      ) => ()
    _ =>
      raise Failure(
        "toolchain: HarmonyOS SDK API " +
        @lib.minimum_sdk_api.to_string() +
        " or newer is required; install it from DevEco Studio SDK Manager",
      )
  }
  doctor(@lib.parse_cli(["doctor"])) |> ignore
  let moon_version = command("toolchain", "moon", ["version"], base)
  let compiler_version = command("toolchain", "moonc", ["-v"], base)
  if !@lib.moonc_supported(compiler_version) {
    raise Failure(
      "toolchain: requires moonc >= " +
      @lib.minimum_moonc_version +
      ", found " +
      compiler_version.trim().to_owned() +
      "; run `moon upgrade`",
    )
  }
  let moon_home = moon_home()
  let os = host_os()
  let cmake = @lib.native_tool(os, native, "cmake")
  let ninja = @lib.native_tool(os, native, "ninja")
  let readelf = @lib.native_tool(os, native, "llvm-readelf")
  for
    tool in [
      cmake,
      ninja,
      @lib.native_tool(os, native, "clang"),
      readelf,
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
  let staged = stage_project(config, base, module_root, source_dir, work)
  let source = staged.source
  let bridge = source + "/moonohos_bridge"
  if @fs.exists(bridge) {
    raise Failure("stage: reserved package moonohos_bridge already exists")
  }
  // Resolve normal MoonBit dependencies in the disposable copy, then audit them.
  command("interface", "moon", ["info", "--target", "native"], staged.root)
  |> ignore
  let found : Array[NativePackage] = []
  discover_native(staged.root, found)
  let interface_text = read(
    source + "/" + package_relative + "/pkg.generated.mbti",
  )
  config.verify_interface(interface_text)
  let config = config.with_adapters(
    @lib.resolve_adapters(
      config,
      known_descriptors(found),
      @lib.interface_imports(interface_text),
    ),
  )
  let artifacts = config.generate()
  let cache_entry = if cache {
    let key = build_cache_key(
      staged.root,
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
      staged.bridge_path,
    ],
    staged.root,
  )
  // Do not persist dry-run environment dumps from unrelated host compiler steps.
  let commands = @lib.compiler_commands(plan, moon_home)
  let mut c_output = ""
  let compiler_log : Array[Json] = []
  for args in commands {
    let mut index = 0
    while index < args.length() {
      if args[index] == "-o" && index + 1 < args.length() {
        let output = resolve(staged.root, args[index + 1])
        ensure_dir(parent(output))
        if args[0] == "link-core" {
          c_output = output
        }
      }
      index += 1
    }
    compiler_log.push(Json(args))
    command("moonbit", "moonc", args, staged.root) |> ignore
  }
  write(
    work + "/compiler-commands.json",
    Json(compiler_log).stringify(indent=2),
  )
  let linked = linked_native(commands.last().unwrap(), staged.root, found, abis)
  let generated = work + "/native"
  let (native_build, native_manifest) = prepare_native(
    linked, generated, native, abis,
  )
  write(generated + "/core.c", read(c_output))
  write(generated + "/moonohos.h", artifacts.header)
  write(generated + "/embed.c", artifacts.embed)
  write(generated + "/napi_init.cpp", artifacts.native)
  write(
    generated + "/CMakeLists.txt",
    @lib.native_cmake(config.native_module, native_build),
  )
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
      readelf,
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
    "version": @lib.moonohos_version(),
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
    "schema": "moonohos-build-v2",
    "moonohosVersion": @lib.moonohos_version(),
    "module": config.native_module,
    "moon": moon_version.trim().to_owned(),
    "moonc": compiler_version.trim().to_owned(),
    "sdkApi": 26,
    "results": Json(results),
    "functions": Json(config.functions.map(f => f.signature())),
    "exports": Json(
      config.functions.map(f => {
        ({ "name": f.name, "async": f.is_async, "raises": f.raises } : Json)
      }),
    ),
    "handles": Json(config.handles),
    "nativeDependencies": Json(native_manifest),
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
  write(package_dir + "/README.md", @lib.package_readme(config.native_module))
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
          match options.help_topic {
            Some(topic) => @lib.command_help(topic)
            None => @lib.usage_text(@lib.moonohos_version())
          },
        )
        return
      }
      Version => {
        println("MoonOHOS " + @lib.moonohos_version())
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
      Init => init_project(options)
      Har => package_har(options)
    }
  } catch {
    error => {
      let diagnostic = @lib.failure_diagnostic(
        name,
        match error {
          Failure(message) => message
          @lib.Invalid(message) => message
          _ => error.to_string()
        },
      )
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
