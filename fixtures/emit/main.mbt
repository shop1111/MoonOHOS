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
  let commands = @lib.compiler_commands(output.text(), home)
  write_all_pkgs(commands, home, module_dir)
  for command in commands {
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
    "sources": Json(f.1.sources),
    "includeDirs": Json(f.1.include_dirs),
  })
  @fs.write_file(native + "/deps.json", Json(deps).stringify(indent=2))
}

///|
async fn core_packages(dir : String, rel : String, out : Array[Json]) -> Unit {
  for name in @fs.readdir(dir, include_hidden=false, sort=true) {
    let path = dir + "/" + name
    if @fs.kind(path) == Directory {
      core_packages(path, if rel == "" { name } else { rel + "/" + name }, out)
    } else if rel != "" && name.has_suffix(".mi") {
      out.push(
        @lib.all_pkgs_entry("moonbitlang/core", "moonbitlang/core/" + rel, path),
      )
    }
  }
}

///|
/// Same table the CLI writes before running the moonc steps of a plan.
async fn write_all_pkgs(
  commands : Array[Array[String]],
  home : String,
  root : String,
) -> Unit {
  guard @lib.all_pkgs_path(commands) is Some(path) else { return }
  let entries : Array[Json] = []
  let bundle = home + "/lib/core/_build/native/release/bundle"
  if @fs.exists(bundle) {
    core_packages(bundle, "", entries)
  }
  for planned in @lib.planned_packages(commands) {
    let (pkg, workspace, artifact) = planned
    let module_text = @fs.read_file(under(root, workspace) + "/moon.mod").text()
    let mut module_name = ""
    for line in module_text.split("\n") {
      let tokens = @lib.tokenize(line.trim().to_owned())
      if tokens.length() == 3 && tokens[0] == "name" {
        module_name = tokens[2]
      }
    }
    entries.push(@lib.all_pkgs_entry(module_name, pkg, under(root, artifact)))
  }
  let target = under(root, path)
  let parts = target.replace_all(old="\\", new="/").split("/").to_array()
  @fs.mkdir(parts[:parts.length() - 1].to_owned().join("/"), recursive=true)
  @fs.write_file(target, ({ "packages": Json(entries) } : Json).stringify())
}

///|
/// `path` relative to `root` unless it is already absolute.
fn under(root : String, path : String) -> String {
  if path.has_prefix("/") || path.contains(":") {
    path
  } else {
    root + "/" + path
  }
}
