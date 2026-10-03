///|
async fn list_files(root : String, prefix? : String = "") -> Array[String] {
  let result : Array[String] = []
  for name in @fs.readdir(root, include_hidden=true, sort=true) {
    let path = root + "/" + name
    match @fs.kind(path, follow_symlink=false) {
      Directory => result.append(list_files(path, prefix=prefix + name + "/"))
      Regular => result.push(prefix + name)
      _ =>
        raise Failure(
          "package: symbolic links and special files are unsupported: " + path,
        )
    }
  }
  result
}

///|
async fn seal_package(root : String) -> Unit {
  let entries : Array[@lib.PackageFile] = []
  for path in list_files(root) {
    if path != "manifest.json" {
      entries.push(
        @lib.package_file(path, @fs.read_file(root + "/" + path).binary()),
      )
    }
  }
  let manifest = @lib.seal_manifest(
    @json.parse(read(root + "/manifest.json")),
    entries,
  )
  write(root + "/manifest.json", manifest.stringify(indent=2))
}

///|
async fn verify_package(root : String) -> Json {
  let root = normalized(@fs.realpath(root))
  let manifest = @lib.parse_package_manifest(read(root + "/manifest.json"))
  let actual = list_files(root)
  let declared = manifest.files.map(f => f.path)
  for path in actual {
    if path != "manifest.json" && !declared.contains(path) {
      raise Failure("package: unlisted file " + path)
    }
  }
  for file in manifest.files {
    if !actual.contains(file.path) {
      raise Failure("package: missing file " + file.path)
    }
    file.verify(@fs.read_file(root + "/" + file.path).binary())
  }
  @lib.verify_type_package(
    read(root + "/types/lib" + manifest.module_name + "/oh-package.json5"),
    manifest,
  )
  @lib.verify_import_file(read(root + "/cmake/MoonOHOS.cmake"), manifest)
  let libraries : Array[Json] = []
  for abi in manifest.abis {
    let library = root + "/libs/" + abi + "/lib" + manifest.module_name + ".so"
    let info = @lib.inspect_elf(@fs.read_file(library).binary())
    @lib.verify_library(info, manifest, abi)
    libraries.push(info.to_json())
  }
  {
    "verified": true,
    "module": manifest.module_name,
    "moonohosVersion": manifest.version,
    "files": manifest.files.length(),
    "libraries": libraries.to_json(),
    "runtime": "not_run",
  }
}
