///|
/// Native argument adapter declared by a platform package.
pub struct AdapterSpec {
  type_name : String
  ark_type : String
  ark_import : String
  acquire : String
  release : String
}

///|
/// Adapter bound to the package alias used in `moonohos.json`.
pub struct AdapterDef {
  pkg_alias : String
  type_name : String
  pkg : String
  ark_type : String
  ark_import : String
  acquire : String
  release : String
}

///|
/// Controlled description of a MoonBit package that ships C stubs.
pub struct NativeDescriptor {
  pkg : String
  sources : Array[String]
  include_dirs : Array[String]
  defines : Array[String]
  libraries : Array[String]
  abis : Array[String]
  adapters : Array[AdapterSpec]
}

///|
pub fn native_descriptor_file() -> String {
  "moonohos.native.json"
}

///|
/// HarmonyOS NDK libraries that platform packages may link.
pub fn system_library_allowlist() -> Array[String] {
  ["libhilog_ndk.z.so", "librawfile.z.so", "libdeviceinfo_ndk.z.so"]
}

///|
pub fn abi_triple(abi : String) -> String {
  if abi == "arm64-v8a" {
    "aarch64-linux-ohos"
  } else {
    "x86_64-linux-ohos"
  }
}

///|
fn quoted_strings(text : String) -> Array[String] {
  let result : Array[String] = []
  let mut current = ""
  let mut quoted = false
  let mut escaped = false
  for ch in text {
    if !quoted {
      if ch == '"' {
        quoted = true
        current = ""
      }
    } else if escaped {
      current += ch.to_string()
      escaped = false
    } else if ch == '\\' {
      escaped = true
    } else if ch == '"' {
      quoted = false
      result.push(current)
    } else {
      current += ch.to_string()
    }
  }
  result
}

///|
/// Extracts the `native-stub` list from `moon.pkg` or `moon.pkg.json`.
pub fn native_stubs(package_file : String) -> Array[String] {
  let marker = "\"native-stub\""
  let parts = package_file.split(marker).to_array()
  if parts.length() < 2 {
    return []
  }
  let rest = parts[1].to_owned()
  let open = rest.split("[").to_array()
  if open.length() < 2 {
    return []
  }
  let list = open[1].split("]").head().unwrap_or("").to_owned()
  quoted_strings(list)
}

///|
/// Build hooks and compiler flags that MoonOHOS cannot reproduce for OHOS.
pub fn forbidden_build_hook(package_file : String) -> String? {
  let compact = package_file
    .replace_all(old=" ", new="")
    .replace_all(old="\n", new="")
    .replace_all(old="\r", new="")
    .replace_all(old="\t", new="")
  for
    (needle, reason) in [
      ("pre-build", "pre-build hooks"),
      ("dev_build(", "pre-build hooks"),
      ("rule(", "custom build rules"),
      ("cc-flags", "C compiler flags"),
      ("cc-link-flags", "C linker flags"),
      ("stub-cc", "stub compiler overrides"),
      ("\"cc\":", "C compiler overrides"),
      ("native_stub", "legacy native stub fields"),
    ] {
    if compact.contains(needle) {
      return Some(reason)
    }
  }
  None
}

///|
fn relative_source(path : String, context : String) -> Unit raise ConfigError {
  if path == "" ||
    path.has_prefix("/") ||
    path.contains(":") ||
    path.contains("\\") ||
    path.split("/").any(p => p == ".." || p == "." || p == "") {
    raise Invalid(context + ": path must stay inside the package: " + path)
  }
}

///|
fn string_list(
  json : Json,
  key : String,
  context : String,
) -> Array[String] raise ConfigError {
  match json {
    Object(fields) =>
      match fields.get(key) {
        None => []
        Some(Array(values)) =>
          values.map(v => {
            match v {
              String(text) => text
              _ => raise Invalid(context + ": " + key + " must contain strings")
            }
          })
        _ => raise Invalid(context + ": " + key + " must be an array")
      }
    _ => raise Invalid(context + ": descriptor must be an object")
  }
}

///|
fn native_symbol(name : String) -> Bool {
  name.has_prefix("moonohos_") && identifier(name) && name.length() <= 96
}

///|
fn valid_define(text : String) -> Bool {
  let parts = text.split("=").map(s => s.to_owned()).to_array()
  if parts.length() > 2 || parts[0] == "" {
    return false
  }
  for index, ch in parts[0] {
    if !(ch >= 'A' && ch <= 'Z') &&
      ch != '_' &&
      !(index > 0 && ch >= '0' && ch <= '9') {
      return false
    }
  }
  parts[0] != "MOONOHOS_BRIDGE" &&
  parts[0] != "MOONOHOS_TARGET_OHOS" &&
  (
    parts.length() == 1 ||
    identifier(parts[1]) ||
    parts[1].iter().all(c => c >= '0' && c <= '9')
  )
}

///|
/// Accepts exactly `import { name } from '@kit.Kit';`.
fn valid_ark_import(text : String) -> Bool {
  guard text.has_prefix("import { ") && text.has_suffix("';") else {
    return false
  }
  let parts = text[9:text.length() - 2]
    .to_owned()
    .split(" } from '@kit.")
    .to_array()
  parts.length() == 2 &&
  identifier(parts[0].to_owned()) &&
  identifier(parts[1].to_owned())
}

///|
/// Parses and validates a descriptor against the package's declared stubs.
pub fn parse_native_descriptor(
  text : String,
  pkg : String,
  stubs : Array[String],
) -> NativeDescriptor raise ConfigError {
  let context = native_descriptor_file() + " for " + pkg
  let json = @json.parse(text) catch {
    _ => raise Invalid(context + ": invalid JSON")
  }
  match json {
    Object(fields) => {
      for key, _ in fields {
        if ![
            "schema", "package", "sources", "includeDirs", "defines", "systemLibraries",
            "abis", "adapters",
          ].contains(key) {
          raise Invalid(context + ": unknown field " + key)
        }
      }
      match fields.get("schema") {
        Some(String("moonohos-native-v1")) => ()
        _ => raise Invalid(context + ": schema must be moonohos-native-v1")
      }
      match fields.get("package") {
        Some(String(name)) if name == pkg => ()
        _ => raise Invalid(context + ": package field must be " + pkg)
      }
    }
    _ => raise Invalid(context + ": descriptor must be an object")
  }
  let sources = string_list(json, "sources", context)
  for source in sources {
    relative_source(source, context)
    if !source.has_suffix(".c") {
      raise Invalid(context + ": only C sources are supported: " + source)
    }
  }
  let declared = sources.copy()
  declared.sort()
  let expected = stubs.copy()
  expected.sort()
  if declared != expected {
    raise Invalid(
      context +
      ": sources must equal moon.pkg native-stub [" +
      stubs.join(", ") +
      "]",
    )
  }
  let include_dirs = string_list(json, "includeDirs", context)
  for dir in include_dirs {
    relative_source(dir, context)
  }
  let defines = string_list(json, "defines", context)
  for definition in defines {
    if !valid_define(definition) {
      raise Invalid(context + ": invalid define " + definition)
    }
  }
  let libraries = string_list(json, "systemLibraries", context)
  for library in libraries {
    if !system_library_allowlist().contains(library) {
      raise Invalid(
        context +
        ": system library " +
        library +
        " is not in the allowlist " +
        system_library_allowlist().join(", "),
      )
    }
  }
  let abis = string_list(json, "abis", context)
  parse_abis(abis.join(",")) |> ignore
  let adapters : Array[AdapterSpec] = []
  let entries = match json {
    Object(fields) =>
      match fields.get("adapters") {
        None => []
        Some(Array(entries)) => entries
        _ => raise Invalid(context + ": adapters must be an array")
      }
    _ => []
  }
  for entry in entries {
    let adapter : AdapterSpec = match entry {
      {
        "type": String(type_name),
        "arkType": String(ark_type),
        "arkImport": String(ark_import),
        "acquire": String(acquire),
        "release": String(release),
        ..
      } => { type_name, ark_type, ark_import, acquire, release, }
      _ => raise Invalid(context + ": malformed adapter")
    }
    let ark_parts = adapter.ark_type.split(".").to_array()
    if !identifier(adapter.type_name) ||
      !native_symbol(adapter.acquire) ||
      !native_symbol(adapter.release) ||
      ark_parts.length() > 2 ||
      !ark_parts.iter().all(p => identifier(p.to_owned())) ||
      !valid_ark_import(adapter.ark_import) {
      raise Invalid(context + ": invalid adapter " + adapter.type_name)
    }
    adapters.push(adapter)
  }
  { pkg, sources, include_dirs, defines, libraries, abis, adapters, }
}

///|
pub fn NativeDescriptor::to_json(self : NativeDescriptor) -> Json {
  {
    "package": self.pkg,
    "sources": self.sources.to_json(),
    "includeDirs": self.include_dirs.to_json(),
    "defines": self.defines.to_json(),
    "systemLibraries": self.libraries.to_json(),
    "abis": self.abis.to_json(),
    "adapters": self.adapters
    .map(a => {
      "type": a.type_name,
      "arkType": a.ark_type,
      "acquire": a.acquire,
      "release": a.release,
    })
    .to_json(),
  }
}

///|
/// Package directories linked by `link-core`, in the compiler's order.
pub fn linked_packages(link_core : Array[String]) -> Array[(String, String)] {
  let result : Array[(String, String)] = []
  let mut index = 0
  while index + 1 < link_core.length() {
    if link_core[index] == "-pkg-sources" {
      let value = link_core[index + 1]
      // Windows directories contain ':' after the drive letter; split once.
      let parts = value.split(":").to_array()
      if parts.length() >= 2 {
        let pkg = parts[0].to_owned()
        let dir = value[pkg.length() + 1:].to_owned()
        result.push((pkg, dir))
      }
      index += 2
    } else {
      index += 1
    }
  }
  result
}

///|
/// Binds `@alias.Type` parameters to adapters using the target's mbti imports.
pub fn resolve_adapters(
  project : Project,
  descriptors : Array[NativeDescriptor],
  imports : Map[String, String],
) -> Array[AdapterDef] raise ConfigError {
  let result : Array[AdapterDef] = []
  for function in project.functions {
    for param in function.params {
      guard param.kind is External(pkg_alias, type_name) else { continue }
      if result
        .iter()
        .any(a => a.pkg_alias == pkg_alias && a.type_name == type_name) {
        continue
      }
      if pkg_alias == "core" || pkg_alias.has_prefix("moonohos") {
        raise Invalid("adapter: reserved package alias @" + pkg_alias)
      }
      let pkg = imports
        .get(pkg_alias)
        .unwrap_or_else(() => {
          raise Invalid(
            "adapter: @" +
            pkg_alias +
            " is not imported by " +
            project.package_name,
          )
        })
      let descriptor = descriptors
        .search_by(d => d.pkg == pkg)
        .map(i => descriptors[i])
        .unwrap_or_else(() => {
          raise Invalid(
            "adapter: " + pkg + " has no " + native_descriptor_file(),
          )
        })
      let spec = descriptor.adapters
        .search_by(a => a.type_name == type_name)
        .map(i => descriptor.adapters[i])
        .unwrap_or_else(() => {
          raise Invalid(
            "adapter: " + pkg + " does not declare an adapter for " + type_name,
          )
        })
      result.push({
        pkg_alias,
        type_name,
        pkg,
        ark_type: spec.ark_type,
        ark_import: spec.ark_import,
        acquire: spec.acquire,
        release: spec.release,
      })
    }
  }
  result
}

///|
/// Additional CMake inputs contributed by native dependencies.
pub(all) struct NativeBuild {
  sources : Array[String]
  include_dirs : Array[String]
  defines : Array[String]
  libraries : Array[String]
}

///|
pub fn empty_native_build() -> NativeBuild {
  { sources: [], include_dirs: [], defines: [], libraries: [], }
}
