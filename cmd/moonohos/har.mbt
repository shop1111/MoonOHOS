///|
/// Nearest ancestor that is a Hvigor project (has build-profile.json5 with modules).
async fn hvigor_project(module_root : String) -> String {
  let mut dir = parent(module_root)
  for _ in 0..<8 {
    let profile = dir + "/build-profile.json5"
    if @fs.exists(profile) && read(profile).contains("\"modules\"") {
      return dir
    }
    dir = parent(dir)
  }
  raise Failure("har: no Hvigor project above " + module_root)
}

///|
/// `moonohos har`: places a verified package into a HAR module and optionally
/// assembles it with the DevEco Hvigor/ohpm toolchain.
async fn package_har(options : @lib.CliOptions) -> Json {
  let dist = normalized(@fs.realpath(options.dist.unwrap()))
  verify_package(dist) |> ignore
  let manifest_text = read(dist + "/manifest.json")
  let manifest = @lib.parse_package_manifest(manifest_text)
  let module_root = normalized(@fs.realpath(options.module_dir.unwrap()))
  @lib.validate_har_module(read(module_root + "/src/main/module.json5"))
  let module_name = manifest.module_name
  let package_file = module_root + "/oh-package.json5"
  let updated = @lib.har_package_manifest(read(package_file), module_name)
  for abi in manifest.abis {
    let library = "/libs/" + abi + "/lib" + module_name + ".so"
    ensure_dir(module_root + "/libs/" + abi)
    @fs.write_file(module_root + library, @fs.read_file(dist + library))
  }
  let types = "/types/lib" + module_name
  let declarations = read(dist + types + "/index.d.ts")
  write(
    module_root + "/src/main/cpp/types/lib" + module_name + "/index.d.ts",
    declarations,
  )
  write(
    module_root + "/src/main/cpp/types/lib" + module_name + "/oh-package.json5",
    read(dist + types + "/oh-package.json5"),
  )
  write(
    module_root + "/src/main/ets/generated/Native.ets",
    @lib.har_facade(module_name, declarations),
  )
  for notice in ["NOTICE.NativeSDK.txt", "NOTICE.MoonBit.txt"] {
    write(module_root + "/" + notice, read(dist + "/" + notice))
  }
  let provenance = @lib.har_provenance(
    manifest,
    @lib.sha256((manifest_text : &@io.Data).binary()),
  )
  write(module_root + "/moonohos-har.json", provenance.stringify(indent=2))
  write(package_file, updated)
  let module_dir_name = module_root.split("/").last().unwrap_or("").to_owned()
  if !options.assemble {
    return {
      "module": module_root,
      "prepared": true,
      "assembled": false,
      "abis": manifest.abis.to_json(),
    }
  }
  let deveco = normalized(@fs.realpath(options.deveco.unwrap()))
  let node = deveco + "/tools/node/node.exe"
  for
    tool in [
      node,
      deveco + "/tools/ohpm/bin/pm-cli.js",
      deveco + "/tools/hvigor/bin/hvigorw.js",
    ] {
    if !@fs.exists(tool) {
      raise Failure("har: DevEco tool missing: " + tool)
    }
  }
  let env : Map[String, String] = {
    "DEVECO_SDK_HOME": deveco + "/sdk",
    "NODE_HOME": deveco + "/tools/node",
    "OHPM_HOME": deveco + "/tools/ohpm",
    "JAVA_HOME": deveco + "/jbr",
  }
  let project = hvigor_project(module_root)
  command_logs.val = Some(module_root + "/build/moonohos-commands")
  command(
    "ohpm",
    node,
    [deveco + "/tools/ohpm/bin/pm-cli.js", "install"],
    project,
    timeout_ms=600000,
    env~,
  )
  |> ignore
  command(
    "hvigor",
    node,
    [
      deveco + "/tools/hvigor/bin/hvigorw.js",
      "--mode",
      "module",
      "-p",
      "module=" + module_dir_name + "@default",
      "-p",
      "product=default",
      "-p",
      "buildMode=release",
      "--no-daemon",
      "assembleHar",
    ],
    project,
    timeout_ms=600000,
    env~,
  )
  |> ignore
  let har = module_root +
    "/build/default/outputs/default/" +
    module_dir_name +
    ".har"
  if !@fs.exists(har) {
    raise Failure("har: hvigor finished without " + har)
  }
  let data = @fs.read_file(har).binary()
  {
    "module": module_root,
    "prepared": true,
    "assembled": true,
    "har": har,
    "size": data.length(),
    "sha256": @lib.sha256(data),
    "abis": manifest.abis.to_json(),
  }
}
