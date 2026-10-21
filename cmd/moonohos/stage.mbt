///|
priv struct StagedProject {
  /// Directory in which Moon and moonc commands run.
  root : String
  /// Staged source directory of the selected module.
  source : String
  /// Bridge package path relative to `root`.
  bridge_path : String
}

///|
/// Package with C stubs found in the staged tree.
priv struct NativePackage {
  dir : String
  stubs : Array[String]
  text : String?
  descriptor : @lib.NativeDescriptor?
}

///|
fn clean_path(path : String) -> String {
  let parts : Array[String] = []
  for part in normalized(path).split("/") {
    let part = part.to_owned()
    if part == "." || (part == "" && !parts.is_empty()) {
      continue
    }
    if part == ".." && !parts.is_empty() && parts.last() != Some("..") {
      parts.pop() |> ignore
    } else {
      parts.push(part)
    }
  }
  parts.join("/")
}

///|
fn join_source(prefix : String, source_dir : String, leaf : String) -> String {
  let parts = [prefix, source_dir, leaf].filter(p => p != "" && p != ".")
  parts.join("/")
}

///|
/// Copies the selected module, or every member of its workspace, for building.
async fn stage_project(
  project : @lib.Project,
  base : String,
  module_root : String,
  source_dir : String,
  work : String,
) -> StagedProject {
  match project.workspace {
    None => {
      let root = work + "/module"
      copy_tree(module_root, root, module_tree=true)
      {
        root,
        source: root + "/" + source_dir,
        bridge_path: join_source("", source_dir, "moonohos_bridge"),
      }
    }
    Some(file) => {
      let workspace = normalized(@fs.realpath(resolve(base, file)))
      let members = @lib.workspace_members(read(workspace))
      let root = work + "/ws"
      let mut selected = -1
      for index, entry in members {
        let member_root = normalized(
          @fs.realpath(resolve(parent(workspace), entry)),
        )
        copy_tree(
          member_root,
          root + "/m" + index.to_string(),
          module_tree=true,
        )
        if member_root == module_root {
          selected = index
        }
      }
      if selected < 0 {
        raise Failure(
          "stage: module " + module_root + " is not a member of " + file,
        )
      }
      write(root + "/moon.work", @lib.staged_workspace(members.length()))
      let prefix = "m" + selected.to_string()
      {
        root,
        source: root + "/" + prefix + "/" + source_dir,
        bridge_path: join_source(prefix, source_dir, "moonohos_bridge"),
      }
    }
  }
}

///|
/// Rejects unsupported build hooks and records every package with C stubs.
async fn discover_native(root : String, found : Array[NativePackage]) -> Unit {
  for name in @fs.readdir(root, include_hidden=true, sort=true) {
    let path = root + "/" + name
    match @fs.kind(path, follow_symlink=false) {
      Directory =>
        if name != "_build" &&
          name != ".git" &&
          name != "node_modules" &&
          name != "oh_modules" {
          discover_native(path, found)
        }
      Regular =>
        if name == "moon.pkg" ||
          name == "moon.pkg.json" ||
          name == "moon.mod" ||
          name == "moon.mod.json" {
          let text = read(path)
          if @lib.forbidden_build_hook(text) is Some(reason) {
            raise Failure("stage: " + reason + " are unsupported: " + path)
          }
          let stubs = if name.has_prefix("moon.pkg") {
            @lib.native_stubs(text)
          } else {
            []
          }
          if !stubs.is_empty() {
            let descriptor_path = root + "/" + @lib.native_descriptor_file()
            if @fs.exists(descriptor_path) {
              let descriptor_text = read(descriptor_path)
              let declared = match
                (@json.parse(descriptor_text) catch {
                  _ => raise Failure("native: invalid JSON " + descriptor_path)
                }) {
                { "package": String(name), .. } => name
                _ =>
                  raise Failure(
                    "native: descriptor has no package " + descriptor_path,
                  )
              }
              let descriptor = @lib.parse_native_descriptor(
                descriptor_text, declared, stubs,
              )
              for file in descriptor.sources {
                if !@fs.exists(root + "/" + file) {
                  raise Failure("native: missing source " + root + "/" + file)
                }
              }
              for dir in descriptor.include_dirs {
                if !@fs.exists(root + "/" + dir) {
                  raise Failure(
                    "native: missing include directory " + root + "/" + dir,
                  )
                }
              }
              found.push({
                dir: clean_path(root),
                stubs,
                text: Some(descriptor_text),
                descriptor: Some(descriptor),
              })
            } else {
              found.push({
                dir: clean_path(root),
                stubs,
                text: None,
                descriptor: None,
              })
            }
          }
        }
      _ => raise Failure("stage: symlinks/special files unsupported: " + path)
    }
  }
}

///|
fn known_descriptors(
  found : Array[NativePackage],
) -> Array[@lib.NativeDescriptor] {
  let result : Array[@lib.NativeDescriptor] = []
  for item in found {
    if item.descriptor is Some(descriptor) {
      result.push(descriptor)
    }
  }
  result
}

///|
/// Native packages actually linked into the bridge, verified against descriptors.
fn linked_native(
  link_core : Array[String],
  root : String,
  found : Array[NativePackage],
  abis : Array[String],
) -> Array[NativePackage] raise BuildFailure {
  let result : Array[NativePackage] = []
  for entry in @lib.linked_packages(link_core) {
    let (pkg, dir) = entry
    let absolute = clean_path(resolve(root, dir))
    guard found.search_by(f => f.dir == absolute) is Some(index) else {
      continue
    }
    let item = found[index]
    match item.descriptor {
      None =>
        raise Failure(
          "native: " +
          pkg +
          " has native stubs [" +
          item.stubs.join(", ") +
          "] but no " +
          @lib.native_descriptor_file() +
          "; event-loop and host-only C libraries cannot run inside a HarmonyOS module",
        )
      Some(descriptor) => {
        if descriptor.pkg != pkg {
          raise Failure(
            "native: descriptor in " +
            item.dir +
            " claims " +
            descriptor.pkg +
            " but the compiler links " +
            pkg,
          )
        }
        for abi in abis {
          if !descriptor.abis.contains(abi) {
            raise Failure("native: " + pkg + " does not support ABI " + abi)
          }
        }
        result.push(item)
      }
    }
  }
  result
}

///|
/// Copies linked stub packages into the CMake tree and records manifest data.
async fn prepare_native(
  linked : Array[NativePackage],
  generated : String,
  sdk : String,
  abis : Array[String],
) -> (@lib.NativeBuild, Array[Json]) {
  let sources : Array[String] = []
  let include_dirs : Array[String] = []
  let defines : Array[String] = []
  let libraries : Array[String] = []
  let manifest : Array[Json] = []
  for index, item in linked {
    guard item.descriptor is Some(descriptor) else { continue }
    let target = "deps/" + index.to_string()
    include_dirs.push(target)
    let files : Array[Json] = []
    for file in descriptor.sources {
      let data = @fs.read_file(item.dir + "/" + file).binary()
      ensure_dir(parent(generated + "/" + target + "/" + file))
      @fs.write_file(generated + "/" + target + "/" + file, data)
      sources.push(target + "/" + file)
      files.push({ "path": file, "sha256": @lib.sha256(data) })
    }
    copy_headers(item.dir, generated + "/" + target)
    for dir in descriptor.include_dirs {
      include_dirs.push(target + "/" + dir)
    }
    for definition in descriptor.defines {
      if !defines.contains(definition) {
        defines.push(definition)
      }
    }
    for library in descriptor.libraries {
      for abi in abis {
        let path = sdk +
          "/sysroot/usr/lib/" +
          @lib.abi_triple(abi) +
          "/" +
          library
        if !@fs.exists(path) {
          raise Failure(
            "native: SDK does not provide " + library + " for " + abi,
          )
        }
      }
      if !libraries.contains(library) {
        libraries.push(library)
      }
    }
    let descriptor_text = item.text.unwrap_or("")
    manifest.push({
      "package": descriptor.pkg,
      "descriptorSha256": @lib.sha256((descriptor_text : &@io.Data).binary()),
      "sources": files.to_json(),
      "systemLibraries": descriptor.libraries.to_json(),
      "adapters": descriptor.adapters.map(a => a.type_name).to_json(),
    })
  }
  ({ sources, include_dirs, defines, libraries, }, manifest)
}

///|
/// Headers next to stub sources keep their relative layout.
async fn copy_headers(from : String, to : String) -> Unit {
  for name in @fs.readdir(from, include_hidden=false, sort=true) {
    let path = from + "/" + name
    match @fs.kind(path, follow_symlink=false) {
      Directory =>
        if name != "_build" && name != "moonohos_bridge" {
          copy_headers(path, to + "/" + name)
        }
      Regular =>
        if name.has_suffix(".h") {
          ensure_dir(to)
          @fs.write_file(to + "/" + name, @fs.read_file(path))
        }
      _ => ()
    }
  }
}
