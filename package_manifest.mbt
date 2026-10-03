///|
pub struct PackageFile {
  path : String
  size : Int
  checksum : String
}

///|
pub struct PackageManifest {
  module_name : String
  version : String
  abis : Array[String]
  files : Array[PackageFile]
}

///|
pub fn package_file(
  path : String,
  data : Bytes,
) -> PackageFile raise ConfigError {
  validate_package_path(path)
  { path, size: data.length(), checksum: sha256(data), }
}

///|
pub fn validate_package_path(path : String) -> Unit raise ConfigError {
  if path == "" ||
    path.has_prefix("/") ||
    path.contains(":") ||
    path.contains("\\") {
    raise Invalid("package: path must be relative: " + path)
  }
  for part in path.split("/") {
    if part == "" || part == "." || part == ".." {
      raise Invalid("package: unsafe path: " + path)
    }
  }
}

///|
pub fn PackageFile::to_json(self : PackageFile) -> Json {
  { "path": self.path, "size": self.size, "sha256": self.checksum }
}

///|
fn valid_checksum(text : String) -> Bool {
  if text.length() != 64 {
    return false
  }
  for char in text {
    if !(char >= '0' && char <= '9') && !(char >= 'a' && char <= 'f') {
      return false
    }
  }
  true
}

///|
pub fn package_requirements(
  module_name : String,
  abis : Array[String],
) -> Array[String] {
  let required = [
    "README.md",
    "NOTICE.NativeSDK.txt",
    "NOTICE.MoonBit.txt",
    "cmake/MoonOHOS.cmake",
    "types/lib" + module_name + "/index.d.ts",
    "types/lib" + module_name + "/oh-package.json5",
  ]
  for abi in abis {
    required.push("libs/" + abi + "/lib" + module_name + ".so")
  }
  required
}

///|
pub fn parse_package_manifest(
  text : String,
) -> PackageManifest raise ConfigError {
  let json = @json.parse(text) catch {
    _ => raise Invalid("package: invalid manifest JSON")
  }
  validate_distribution_metadata(json)
  let (module_name, version, results, entries) = match json {
    {
      "schema": "moonohos-build-v1",
      "module": String(module_name),
      "moonohosVersion": String(version),
      "sdkApi": Number(26, ..),
      "results": Array(results),
      "files": Array(entries),
      ..
    } => (module_name, version, results, entries)
    _ =>
      raise Invalid(
        "package: unsupported or incomplete manifest; checksums are required",
      )
  }
  if !identifier(module_name) {
    raise Invalid("package: invalid native module name")
  }
  if version != "0.2.0" && version != "0.3.0" {
    raise Invalid("package: unsupported generator version " + version)
  }
  let abis : Array[String] = []
  for result in results {
    match result {
      { "abi": String(abi), "build": "passed", "elf": "verified", .. } =>
        abis.push(abi)
      _ => raise Invalid("package: incomplete ABI build result")
    }
  }
  parse_abis(abis.join(",")) |> ignore
  let files : Array[PackageFile] = []
  let seen : Map[String, Bool] = Map([])
  for entry in entries {
    let file : PackageFile = match entry {
      {
        "path": String(path),
        "size": Number(size, ..),
        "sha256": String(checksum),
        ..
      } => {
        if size < 0 || size > 2147483647 || size != size.trunc() {
          raise Invalid("package: invalid file size")
        }
        { path, size: size.to_int(), checksum, }
      }
      _ => raise Invalid("package: malformed file record")
    }
    validate_package_path(file.path)
    if file.path == "manifest.json" || seen.contains(file.path) {
      raise Invalid("package: duplicate or recursive checksum entry")
    }
    if !valid_checksum(file.checksum) {
      raise Invalid("package: invalid SHA256 for " + file.path)
    }
    seen[file.path] = true
    files.push(file)
  }
  for required in package_requirements(module_name, abis) {
    if !seen.contains(required) {
      raise Invalid("package: manifest omits required file " + required)
    }
  }
  { module_name, version, abis, files, }
}

///|
pub fn PackageFile::verify(
  self : PackageFile,
  data : Bytes,
) -> Unit raise ConfigError {
  if data.length() != self.size {
    raise Invalid("package: size mismatch for " + self.path)
  }
  if sha256(data) != self.checksum {
    raise Invalid("package: SHA256 mismatch for " + self.path)
  }
}

///|
pub fn seal_manifest(
  manifest : Json,
  files : Array[PackageFile],
) -> Json raise ConfigError {
  match manifest {
    Object(fields) => {
      let result = fields.copy()
      result["files"] = files.map(f => f.to_json()).to_json()
      result.to_json()
    }
    _ => raise Invalid("package: manifest must be an object")
  }
}
