///|
/// Relative import specifier from `from` to `to` (both absolute, `/`).
async fn import_path(from : String, to : String) -> String {
  let relative = @lib.relative_path(
    from,
    to,
    case_sensitive=!host_os().case_insensitive_paths(),
  )
  if relative.has_prefix("../") {
    relative
  } else {
    "./" + relative
  }
}

///|
/// `moonohos hvigor`: writes the MoonOHOS Hvigor plugin into the project's
/// `hvigor/` directory and applies it to a HAR module, so DevEco Studio's
/// Build and Run compile the MoonBit module before the HAR.
async fn add_hvigor_plugin(options : @lib.CliOptions) -> Json {
  let module_root = normalized(@fs.realpath(options.module_dir.unwrap()))
  @lib.validate_har_module(read(module_root + "/src/main/module.json5"))
  let config_path = normalized(@fs.realpath(options.config))
  let config = @lib.parse_project(read(config_path))
  if @lib.path_root(module_root) != @lib.path_root(config_path) {
    raise Failure(
      "hvigor: moonohos.json and the HAR module must be on the same drive: " +
      config_path,
    )
  }
  let project = hvigor_project(module_root)
  let plugin = project + "/hvigor/" + @lib.hvigor_plugin_file
  write(plugin, @lib.hvigor_plugin_source())
  let plugin_import = import_path(
    module_root,
    plugin[:plugin.length() - 3].to_owned(),
  )
  let config_relative = import_path(module_root, config_path)
  let hvigorfile = module_root + "/hvigorfile.ts"
  let existing = if @fs.exists(hvigorfile) { read(hvigorfile) } else { "" }
  let (status, manual) = match
    @lib.hvigorfile_update(existing, plugin_import, config_relative) {
    Present => ("present", None)
    Replace(text) => {
      write(hvigorfile, text)
      ("applied", None)
    }
    Manual(lines) => ("manual", Some(lines))
  }
  // ohpm resolves the type package during sync, before the first build.
  let native = config.native_module
  let types = module_root + "/src/main/cpp/types/lib" + native
  if !@fs.exists(types + "/oh-package.json5") {
    write(types + "/oh-package.json5", @lib.type_package_manifest(native))
  }
  let package_file = module_root + "/oh-package.json5"
  write(package_file, @lib.har_package_manifest(read(package_file), native))
  let result : Map[String, Json] = {
    "module": module_root,
    "plugin": plugin,
    "config": config_relative,
    "hvigorfile": status,
  }
  if manual is Some(lines) {
    result["manual"] = Json(lines)
  }
  Json::object(result)
}
