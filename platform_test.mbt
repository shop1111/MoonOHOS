///|
test "host OS detection and executable names" {
  assert_eq(@moonohos.detect_host_os(Some("Windows_NT"), false), Windows)
  assert_eq(@moonohos.detect_host_os(None, true), MacOS)
  assert_eq(@moonohos.detect_host_os(None, false), Linux)
  assert_eq(@moonohos.HostOs::Windows.exe("cmake"), "cmake.exe")
  assert_eq(@moonohos.HostOs::Linux.exe("cmake"), "cmake")
  assert_true(@moonohos.HostOs::MacOS.case_insensitive_paths())
  assert_false(@moonohos.HostOs::Linux.case_insensitive_paths())
  assert_eq(
    @moonohos.native_tool(Linux, "/sdk/native", "ninja"),
    "/sdk/native/build-tools/cmake/bin/ninja",
  )
  assert_eq(
    @moonohos.native_tool(Windows, "D:/sdk/native", "llvm-readelf"),
    "D:/sdk/native/llvm/bin/llvm-readelf.exe",
  )
  assert_true(
    @moonohos.sdk_files(os=Linux).contains("build-tools/cmake/bin/cmake"),
  )
  assert_true(@moonohos.sdk_files().contains("llvm/bin/clang.exe"))
}

///|
test "Moon home falls back to the platform's home directory" {
  assert_eq(
    @moonohos.moon_home_dir(Windows, None, Some("C:\\Users\\a"), None),
    "C:/Users/a/.moon",
  )
  assert_eq(
    @moonohos.moon_home_dir(Linux, None, None, Some("/home/a")),
    "/home/a/.moon",
  )
  assert_eq(
    @moonohos.moon_home_dir(MacOS, Some("/opt/moon"), None, Some("/Users/a")),
    "/opt/moon",
  )
  assert_eq(
    @moonohos.moon_home_dir(Linux, Some(""), None, Some("/home/a")),
    "/home/a/.moon",
  )
}

///|
fn resolve(
  os : @moonohos.HostOs,
  deveco : String,
  existing : Array[String],
) -> @moonohos.DevEcoTools raise {
  for path in existing {
    assert_true(@moonohos.deveco_probe_paths(os, deveco).contains(path))
  }
  @moonohos.resolve_deveco(os, deveco, existing)
}

///|
test "DevEco layouts on Windows, macOS and command-line tools" {
  let win = resolve(Windows, "D:/apps/DevEco Studio", [
    "D:/apps/DevEco Studio/tools/node/node.exe", "D:/apps/DevEco Studio/tools/ohpm/bin/pm-cli.js",
    "D:/apps/DevEco Studio/tools/hvigor/bin/hvigorw.js", "D:/apps/DevEco Studio/sdk",
    "D:/apps/DevEco Studio/jbr",
  ])
  assert_eq(win.node_home, "D:/apps/DevEco Studio/tools/node")
  assert_eq(win.ohpm_home, "D:/apps/DevEco Studio/tools/ohpm")
  assert_eq(win.env().get("JAVA_HOME"), Some("D:/apps/DevEco Studio/jbr"))
  let app = "/Applications/DevEco-Studio.app"
  let mac = resolve(MacOS, app, [
    app + "/Contents/tools/node/bin/node",
    app + "/Contents/tools/ohpm/bin/pm-cli.js",
    app + "/Contents/tools/hvigor/bin/hvigorw.js",
    app + "/Contents/sdk",
    app + "/Contents/jbr/Contents/Home",
  ])
  assert_eq(mac.node_home, app + "/Contents/tools/node")
  assert_eq(mac.java_home, Some(app + "/Contents/jbr/Contents/Home"))
  assert_eq(mac.sdk, app + "/Contents/sdk")
  let cli = "/opt/command-line-tools"
  let linux = resolve(Linux, cli, [
    cli + "/tool/node/bin/node",
    cli + "/ohpm/bin/pm-cli.js",
    cli + "/hvigor/bin/hvigorw.js",
    cli + "/sdk",
  ])
  assert_eq(linux.node_home, cli + "/tool/node")
  assert_eq(linux.java_home, None)
  assert_eq(linux.env().get("JAVA_HOME"), None)
  let missing = try {
    @moonohos.resolve_deveco(Linux, cli, [cli + "/sdk"]) |> ignore
    ""
  } catch {
    Invalid(message) => message
  }
  assert_true(missing.has_prefix("har: DevEco tools not found"))
}

///|
test "relative paths respect case sensitivity" {
  assert_eq(@moonohos.relative_path("D:/A/proj", "d:/a/ohos"), "../ohos")
  assert_eq(
    @moonohos.relative_path("/home/A/proj", "/home/a/ohos", case_sensitive=true),
    "../../a/ohos",
  )
}

///|
test "path roots separate Windows drives" {
  assert_eq(@moonohos.path_root("d:/code/proj"), "D:")
  assert_eq(@moonohos.path_root("D:/apps"), "D:")
  assert_true(@moonohos.path_root("C:/Users") != @moonohos.path_root("D:/Code"))
  assert_eq(@moonohos.path_root("/home/a"), "/")
}
