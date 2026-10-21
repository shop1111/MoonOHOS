///|
/// `moonohos init <dir>`: creates a MoonBit library, its bridge manifest and a
/// Hvigor project with a HAR module. Refuses to touch a non-empty directory.
async fn init_project(options : @lib.CliOptions) -> Json {
  let target = normalized(options.target.unwrap())
  let root = if target.has_prefix("/") || target.contains(":") {
    target
  } else {
    normalized(@fs.realpath(".")) + "/" + target
  }
  if @fs.exists(root) && !@fs.readdir(root, include_hidden=true).is_empty() {
    raise Failure("init: directory is not empty: " + root)
  }
  let name = options.name.unwrap_or(
    root.split("/").last().unwrap_or("").to_owned(),
  )
  let ohos = match options.ohos {
    None => None
    Some(path) => {
      let resolved = normalized(@fs.realpath(path))
      if !@fs.exists(resolved + "/moon.mod") ||
        !read(resolved + "/moon.mod").contains("shop1111/moonohos_ohos") {
        raise Failure("init: --ohos must point to the MoonOHOS ohos module")
      }
      Some(@lib.relative_path(root, resolved))
    }
  }
  let files = @lib.init_files({
    name,
    package_name: options.package_name.unwrap_or("moonohos/" + name),
    ohos,
  })
  for file in files {
    write(root + "/" + file.0, file.1)
  }
  {
    "project": root,
    "name": name,
    "files": files.map(f => f.0).to_json(),
    "workspace": ohos.to_json(),
    "next": [
      "moonohos build --config " +
      target +
      "/moonohos.json --sdk <SDK> --out _build/dist",
      "moonohos har --dist " +
      target +
      "/_build/dist --module " +
      target +
      "/harmony/" +
      name +
      " --assemble --deveco <DevEco>",
    ].to_json(),
  }
}
