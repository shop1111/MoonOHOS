///|
suberror BuildFailure {
  Failure(String)
} derive(Debug)

///|
fn normalized(path : String) -> String {
  path.replace_all(old="\\", new="/")
}

///|
fn parent(path : String) -> String {
  let parts = normalized(path).split("/").to_array()
  if parts.length() <= 1 {
    "."
  } else {
    parts[:parts.length() - 1].to_owned().join("/")
  }
}

///|
fn resolve(base : String, path : String) -> String {
  let path = normalized(path)
  if path.has_prefix("/") || path.contains(":") {
    path
  } else {
    base + "/" + path
  }
}

///|
async fn read(path : String) -> String {
  @fs.read_file(path).text()
}

///|
async fn write(path : String, text : String) -> Unit {
  ensure_dir(parent(path))
  @fs.write_file(path, text)
}

///|
async fn ensure_dir(path : String) -> Unit {
  if !@fs.exists(path) {
    @fs.mkdir(path, recursive=true)
  }
}

///|
async fn command(
  stage : String,
  exe : String,
  args : Array[String],
  cwd : String,
) -> String {
  let (code, stdout, stderr) = @process.collect_output(
    exe,
    args,
    cwd~,
    extra_env={ "MOONBIT_NEW_NATIVE": "0" },
    no_console_window=true,
  ) catch {
    error =>
      raise Failure(stage + ": cannot start " + exe + ": " + error.to_string())
  }
  if code != 0 {
    raise Failure(
      stage +
      " (exit " +
      code.to_string() +
      "):\n" +
      stdout.text() +
      stderr.text(),
    )
  }
  stdout.text()
}

///|
async fn copy_tree(from : String, to : String, module_tree~ : Bool) -> Unit {
  ensure_dir(to)
  for name in @fs.readdir(from, include_hidden=true, sort=true) {
    if module_tree &&
      (
        name == "_build" ||
        name == ".git" ||
        name == ".mooncakes" ||
        name == ".moonohos" ||
        name == "node_modules" ||
        name == "oh_modules"
      ) {
      continue
    }
    let source = from + "/" + name
    let destination = to + "/" + name
    match @fs.kind(source, follow_symlink=false) {
      Directory => {
        // Nested modules are independent of the selected computation module.
        if module_tree &&
          (
            @fs.exists(source + "/moon.mod") ||
            @fs.exists(source + "/moon.mod.json")
          ) {
          continue
        }
        copy_tree(source, destination, module_tree~)
      }
      Regular => @fs.write_file(destination, @fs.read_file(source))
      _ => raise Failure("stage: symlinks/special files unsupported: " + source)
    }
  }
}

///|
async fn module_metadata(root : String) -> (String, String) {
  if @fs.exists(root + "/moon.mod") {
    let text = read(root + "/moon.mod")
    let mut name = ""
    let mut source = "."
    for line in text.split("\n") {
      let line = line.trim().to_owned()
      if line.has_prefix("name =") || line.has_prefix("source =") {
        let tokens = @lib.tokenize(line)
        if tokens.length() != 3 {
          raise Failure("stage: unsupported module metadata")
        }
        if tokens[0] == "name" {
          name = tokens[2]
        } else {
          source = tokens[2]
        }
      }
    }
    if name == "" {
      raise Failure("stage: module name not found")
    }
    if source.contains("..") || source.contains(":") || source.has_prefix("/") {
      raise Failure("stage: source must be inside module")
    }
    (name, source)
  } else if @fs.exists(root + "/moon.mod.json") {
    let metadata = @json.parse(read(root + "/moon.mod.json"))
    match metadata {
      { "name": String(name), .. } => {
        let source = match metadata {
          { "source": String(source), .. } => source
          _ => "."
        }
        if source.contains("..") ||
          source.contains(":") ||
          source.has_prefix("/") {
          raise Failure("stage: source must be inside module")
        }
        (name, source)
      }
      _ => raise Failure("stage: module name missing")
    }
  } else {
    raise Failure("stage: no moon.mod / moon.mod.json")
  }
}

///|
async fn reject_stubs(root : String) -> Unit {
  for name in @fs.readdir(root, include_hidden=true) {
    let path = root + "/" + name
    if @fs.kind(path) == Directory {
      if name != "_build" && name != ".git" {
        reject_stubs(path)
      }
    } else if name == "moon.pkg" ||
      name == "moon.pkg.json" ||
      name == "moon.mod" ||
      name == "moon.mod.json" {
      let text = read(path)
      let compact = text
        .replace_all(old=" ", new="")
        .replace_all(old="\n", new="")
        .replace_all(old="\r", new="")
        .replace_all(old="\t", new="")
      if text.contains("native-stub") ||
        text.contains("native_stub") ||
        text.contains("pre-build") ||
        compact.contains("dev_build(") ||
        compact.contains("rule(") {
        raise Failure(
          "stage: Native stubs/pre-build hooks unsupported: " + path,
        )
      }
    }
  }
}
