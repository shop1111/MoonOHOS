///|
async fn fingerprint_tree(
  root : String,
  domain : String,
  prefix : String,
  entries : Array[@lib.ContentFingerprint],
) -> Unit {
  for name in @fs.readdir(root, include_hidden=true, sort=true) {
    if @lib.ignored_cache_component(name) {
      continue
    }
    let path = root + "/" + name
    match @fs.kind(path, follow_symlink=false) {
      Directory => fingerprint_tree(path, domain, prefix + name + "/", entries)
      Regular =>
        entries.push(
          @lib.fingerprint(domain, prefix + name, @fs.read_file(path).binary()),
        )
      _ =>
        raise Failure(
          "cache: symbolic links and special files unsupported: " + path,
        )
    }
  }
}

///|
async fn build_cache_key(
  staged : String,
  sdk : String,
  home : String,
  config : String,
  abis : Array[String],
  artifacts : @lib.GeneratedArtifacts,
) -> String {
  let entries : Array[@lib.ContentFingerprint] = []
  fingerprint_tree(staged, "source-and-dependencies", "", entries)
  fingerprint_tree(home + "/lib/core", "core", "", entries)
  for file in @lib.runtime_files() {
    entries.push(
      @lib.fingerprint(
        "runtime",
        file,
        @fs.read_file(home + "/" + file).binary(),
      ),
    )
  }
  for file in ["bin/moon.exe", "bin/moonc.exe"] {
    entries.push(
      @lib.fingerprint(
        "compiler",
        file,
        @fs.read_file(home + "/" + file).binary(),
      ),
    )
  }
  for file in @lib.sdk_files() {
    entries.push(
      @lib.fingerprint("sdk", file, @fs.read_file(sdk + "/" + file).binary()),
    )
  }
  for abi in abis {
    let triple = if abi == "arm64-v8a" {
      "aarch64-linux-ohos"
    } else {
      "x86_64-linux-ohos"
    }
    let file = "sysroot/usr/lib/" + triple + "/libace_napi.z.so"
    entries.push(
      @lib.fingerprint("sdk", file, @fs.read_file(sdk + "/" + file).binary()),
    )
  }
  for
    (name, text) in [
      ("manifest", config),
      ("abis", abis.to_json().stringify()),
      ("generator-version", "0.3.0"),
      ("wrapper", artifacts.wrapper),
      ("wrapper-package", artifacts.package_file),
      ("native", artifacts.native),
      ("header", artifacts.header),
      ("embed", artifacts.embed),
      ("types", artifacts.declarations),
      ("cmake", artifacts.cmake),
    ] {
    entries.push(
      @lib.fingerprint("configuration", name, (text : &@io.Data).binary()),
    )
  }
  @lib.content_cache_key(entries)
}

///|
async fn restore_cache(entry : String, work : String, out : String) -> Bool {
  if !@fs.exists(entry) {
    return false
  }
  let valid = try verify_package(entry + "/dist") catch {
    _ => None
  } noraise {
    report => Some(report)
  }
  if valid is None {
    let mut sequence = 1
    while @fs.exists(entry + ".corrupt-" + sequence.to_string()) {
      sequence += 1
    }
    @fs.rename(entry, entry + ".corrupt-" + sequence.to_string())
    write(
      work + "/cache.json",
      ({ "status": "corrupt", "action": "rebuild" } : Json).stringify(),
    )
    return false
  }
  let pending = work + "/cached-dist"
  copy_tree(entry + "/dist", pending, module_tree=false)
  verify_package(pending) |> ignore
  if @fs.exists(out) {
    raise Failure("publish: output already exists")
  }
  ensure_dir(parent(out))
  @fs.rename(pending, out)
  write(work + "/cache.json", ({ "status": "hit" } : Json).stringify())
  true
}

///|
async fn save_cache(entry : String, out : String, work : String) -> Unit {
  if @fs.exists(entry) {
    return
  }
  let pending = work + "/cache-entry"
  copy_tree(out, pending + "/dist", module_tree=false)
  verify_package(pending + "/dist") |> ignore
  ensure_dir(parent(entry))
  if !@fs.exists(entry) {
    @fs.rename(pending, entry)
  }
  write(
    work + "/cache.json",
    ({ "status": "miss", "stored": true } : Json).stringify(),
  )
}
