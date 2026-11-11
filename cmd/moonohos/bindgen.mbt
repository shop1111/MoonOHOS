///|
/// Library directories of the two target ABIs inside the SDK sysroot.
let bindgen_triples : Array[(String, String)] = [
  ("arm64-v8a", "aarch64-linux-ohos"),
  ("x86_64", "x86_64-linux-ohos"),
]

///|
/// Maps each wanted function to the shared library that exports it under the
/// same name for both ABIs; functions missing from either ABI are left out.
async fn exporting_libraries(
  sysroot : String,
  wanted : Array[String],
) -> Map[String, String] {
  let per_abi : Array[Map[String, String]] = []
  for pair in bindgen_triples {
    let dir = sysroot + "/usr/lib/" + pair.1
    let found : Map[String, String] = Map([])
    for name in @fs.readdir(dir, include_hidden=false, sort=true) {
      if !name.has_suffix(".so") {
        continue
      }
      let path = dir + "/" + name
      if @fs.kind(path) != Regular {
        continue
      }
      // Linker scripts and non-ELF files are not libraries to bind against.
      let exports = @lib.elf_dynamic_exports(@fs.read_file(path).binary()) catch {
        _ => continue
      }
      for symbol in exports {
        if wanted.contains(symbol) && !found.contains(symbol) {
          found[symbol] = name
        }
      }
    }
    per_abi.push(found)
  }
  let result : Map[String, String] = Map([])
  for function in wanted {
    match (per_abi[0].get(function), per_abi[1].get(function)) {
      (Some(a), Some(b)) if a == b => result[function] = a
      _ => ()
    }
  }
  result
}

///|
async fn bindgen(options : @lib.CliOptions) -> Json {
  let base = @env.current_dir().unwrap_or(".")
  let spec_path = resolve(base, options.spec.unwrap_or("moonohos.bindgen.json"))
  let spec = @lib.parse_bindgen_spec(read(spec_path))
  let native = native_sdk(resolve(base, options.sdk.unwrap_or("")))
  let sysroot = native + "/sysroot"
  let os = host_os()
  let clang = @lib.native_tool(os, native, "clang")
  let out = resolve(base, options.output)
  // Scratch translation unit, removed after the AST is read.
  let work = out + "/.moonohos-bindgen"
  ensure_dir(work)
  let unit = work + "/headers.c"
  write(
    unit,
    "#include <stdbool.h>\n#include <stddef.h>\n#include <stdint.h>\n" +
    spec.headers.map(h => "#include <" + h + ">").join("\n") +
    "\n",
  )
  // The x86_64 view of the headers; both ABIs are LP64 and share them.
  let ast = command(
    "bindgen",
    clang,
    [
      "--target=x86_64-linux-ohos",
      "--sysroot=" + sysroot,
      "-fsyntax-only",
      "-Xclang",
      "-ast-dump=json",
      unit,
    ],
    work,
    timeout_ms=120000,
  )
  @fs.rmdir(work, recursive=true)
  let model = @lib.read_header_model(ast, spec.headers)
  let libraries = exporting_libraries(sysroot, model.functions.map(f => f.name))
  let output = @lib.generate_bindings(
    spec, model, libraries, @lib.minimum_sdk_api,
  )
  for file in output.files {
    write(out + "/" + file.0, file.1)
  }
  {
    "package": spec.package_name,
    "out": out,
    "headers": Json(spec.headers.map(h => Json::string(h))),
    "libraries": Json(output.libraries.map(l => Json::string(l))),
    "notAllowlisted": Json(
      output.libraries
      .filter(l => !@lib.system_library_allowlist().contains(l))
      .map(l => Json::string(l)),
    ),
    "bound": Json(output.bound.map(f => Json::string(f))),
    "skipped": Json(
      output.skipped.map(s => ({ "function": s.0, "reason": s.1 } : Json)),
    ),
  }
}
