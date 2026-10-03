///|
async fn main {
  let args = @env.args()
  let project = @lib.parse_project(@fs.read_file(args[1]).text())
  let generated = project.generate_arrays()
  let module_dir = args[2]
  let native = args[3]
  @fs.mkdir(module_dir + "/moonohos_bridge", recursive=true)
  @fs.mkdir(native, recursive=true)
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
    ["info", "--target", "native"],
    cwd=module_dir,
    no_console_window=true,
  )
  if code != 0 {
    abort(output.text() + errors.text())
  }
  project.verify_interface(
    @fs.read_file(module_dir + "/pkg.generated.mbti").text(),
  )
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
  }
  @fs.write_file(
    native + "/core.c",
    @fs.read_file(
      module_dir +
      "/_build/native/release/build/moonohos_bridge/moonohos_bridge.c",
    ),
  )
}
