///|
/// Collects packages that ship stubs with a MoonOHOS native descriptor.
async fn descriptors(
  root : String,
  found : Array[(String, @lib.NativeDescriptor)],
) -> Unit {
  for name in @fs.readdir(root, include_hidden=false, sort=true) {
    let path = root + "/" + name
    if @fs.kind(path) == Directory {
      if name != "_build" && name != "testdata" {
        descriptors(path, found)
      }
    } else if name == @lib.native_descriptor_file() {
      let package_file = @fs.read_file(root + "/moon.pkg").text()
      let text = @fs.read_file(path).text()
      let declared = match @json.parse(text) {
        { "package": String(pkg), .. } => pkg
        _ => abort("descriptor without package: " + path)
      }
      found.push(
        (
          root,
          @lib.parse_native_descriptor(
            text,
            declared,
            @lib.native_stubs(package_file),
          ),
        ),
      )
    }
  }
}

///|
async fn main {
  let args = @env.args()
  let project = @lib.parse_project(@fs.read_file(args[1]).text())
  let module_dir = args[2]
  let native = args[3]
  @fs.mkdir(native, recursive=true)
  let (code, output, errors) = @process.collect_output(
    "moon",
    ["info", "--target", "native"],
    cwd=module_dir,
    no_console_window=true,
  )
  if code != 0 {
    abort(output.text() + errors.text())
  }
  let interface_text = @fs.read_file(module_dir + "/pkg.generated.mbti").text()
  project.verify_interface(interface_text)
  // Workspace members other than the module itself (e.g. ../ohos).
  let roots = [module_dir]
  if @fs.exists(module_dir + "/moon.work") {
    for
      entry in @lib.workspace_members(
        @fs.read_file(module_dir + "/moon.work").text(),
      ) {
      if entry != "." {
        roots.push(module_dir + "/" + entry)
      }
    }
  }
  let found : Array[(String, @lib.NativeDescriptor)] = []
  for root in roots {
    descriptors(root, found)
  }
  let project = project.with_adapters(
    @lib.resolve_adapters(
      project,
      found.map(f => f.1),
      @lib.interface_imports(interface_text),
    ),
  )
  let generated = project.generate_arrays()
  @fs.mkdir(module_dir + "/moonohos_bridge", recursive=true)
  @fs.write_file(
    module_dir + "/moonohos_bridge/moon.pkg",
    generated.package_file,
  )
  @fs.write_file(module_dir + "/moonohos_bridge/main.mbt", generated.wrapper)
  for
    (name, contents) in [
      ("moonohos.h", generated.header),
      ("embed.c", generated.embed),
      ("napi_init.cpp", generated.native),
      ("CMakeLists.txt", generated.cmake),
      ("index.d.ts", generated.declarations),
    ] {
    @fs.write_file(native + "/" + name, contents)
  }
  let (code, output, errors) = @process.collect_output(
    "moon",
    ["build", "--target", "native", "--release", "--dry-run", "moonohos_bridge"],
    cwd=module_dir,
    no_console_window=true,
  )
  if code != 0 {
    abort(output.text() + errors.text())
  }
  let home = @env.get_env_var("MOON_HOME")
    .unwrap_or(@env.get_env_var("USERPROFILE").unwrap() + "/.moon")
    .replace_all(old="\\", new="/")
  let mut c_output = ""
  for command in @lib.compiler_commands(output.text(), home) {
    let (code, output, errors) = @process.collect_output(
      "moonc",
      command,
      cwd=module_dir,
      no_console_window=true,
    )
    if code != 0 {
      abort(output.text() + errors.text())
    }
    for index, arg in command {
      if arg == "-o" && command[0] == "link-core" {
        c_output = command[index + 1]
      }
    }
  }
  @fs.write_file(native + "/core.c", @fs.read_file(module_dir + "/" + c_output))
  // Host checks compile every descriptor source with MOONOHOS_BRIDGE only.
  let deps : Array[Json] = found.map(f => {
    "dir": f.0,
    "sources": f.1.sources.to_json(),
    "includeDirs": f.1.include_dirs.to_json(),
  })
  @fs.write_file(native + "/deps.json", deps.to_json().stringify(indent=2))
}
