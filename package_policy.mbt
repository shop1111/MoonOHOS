///|
pub fn validate_distribution_metadata(json : Json) -> Unit raise ConfigError {
  let fields = match json {
    Object(fields) => fields
    _ => raise Invalid("package: manifest is not an object")
  }
  let permitted = [
    "schema", "moonohosVersion", "module", "moon", "moonc", "sdkApi", "results",
    "functions", "files",
  ]
  for key, _ in fields {
    if !permitted.contains(key) {
      raise Invalid("package: unrecognized manifest field " + key)
    }
  }
  match json {
    {
      "moon": String(moon),
      "moonc": String(moonc),
      "functions": Array(functions),
      ..
    } => {
      if !moon.contains("0.1.20260920") || !moonc.contains("v0.10.14+7d59c7ec9") {
        raise Invalid("package: unverified compiler baseline")
      }
      let seen : Map[String, Bool] = Map([])
      for function in functions {
        let text = match function {
          String(text) => text
          _ => raise Invalid("package: function signature must be text")
        }
        let parsed = parse_package_interface(text)
        if parsed.functions.length() != 1 {
          raise Invalid("package: malformed function signature")
        }
        let signature = parsed.functions[0]
        if signature.unsupported is Some(_) || seen.contains(signature.name) {
          raise Invalid("package: invalid or duplicate exported function")
        }
        seen[signature.name] = true
      }
      if seen.is_empty() {
        raise Invalid("package: no exported functions")
      }
    }
    _ => raise Invalid("package: missing compiler or interface metadata")
  }
  match json {
    { "results": Array(results), .. } =>
      for result in results {
        match result {
          { "runtime": "not_run", .. } => ()
          _ =>
            raise Invalid(
              "package: build must not claim device runtime verification",
            )
        }
      }
    _ => raise Invalid("package: missing results")
  }
}

///|
pub fn verify_type_package(
  text : String,
  manifest : PackageManifest,
) -> Unit raise ConfigError {
  let json = @json.parse(text) catch {
    _ => raise Invalid("package: type package must be generated JSON")
  }
  match json {
    {
      "name": String(name),
      "version": String(version),
      "types": "./index.d.ts",
      ..
    } if name == "lib" + manifest.module_name + ".so" &&
      version == manifest.version => ()
    _ =>
      raise Invalid(
        "package: type package name, version or declarations path mismatch",
      )
  }
}

///|
pub fn verify_import_file(
  text : String,
  manifest : PackageManifest,
) -> Unit raise ConfigError {
  let module_name = manifest.module_name
  if !text.contains("add_library(" + module_name + " SHARED IMPORTED)") ||
    !text.contains(
      "${CMAKE_CURRENT_LIST_DIR}/../libs/${OHOS_ARCH}/lib" + module_name + ".so",
    ) {
    raise Invalid("package: CMake import does not match relocatable package")
  }
}

///|
pub fn verify_library(
  info : ElfInfo,
  manifest : PackageManifest,
  abi : String,
) -> Unit raise ConfigError {
  if info.abi != abi {
    raise Invalid("package: ELF architecture differs from manifest " + abi)
  }
  if info.soname is Some(name) && name != "lib" + manifest.module_name + ".so" {
    raise Invalid("package: wrong SONAME")
  }
  let allowed = [
    "libace_napi.z.so", "libc.so", "libm.so", "libdl.so", "libhilog_ndk.z.so", "libdeviceinfo_ndk.z.so",
  ]
  for dependency in info.dependencies {
    if !allowed.contains(dependency) {
      raise Invalid("package: unexpected dynamic dependency " + dependency)
    }
  }
}
