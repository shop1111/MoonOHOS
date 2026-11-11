///|
/// Tokenizes `moon build --dry-run` command quoting. Never evaluates a shell.
pub fn tokenize(line : String) -> Array[String] raise ConfigError {
  let words : Array[String] = []
  let mut word = ""
  let mut quote = '\u0000'
  let mut escaped = false
  let mut started = false
  for ch in line {
    if escaped {
      word += ch.to_string()
      escaped = false
    } else if ch == '\\' && quote != '\'' {
      escaped = true
      started = true
    } else if quote != '\u0000' {
      if ch == quote {
        quote = '\u0000'
      } else {
        word += ch.to_string()
      }
    } else if ch == '\'' || ch == '"' {
      quote = ch
      started = true
    } else if ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' {
      if started {
        words.push(word)
        word = ""
        started = false
      }
    } else {
      word += ch.to_string()
      started = true
    }
  }
  if escaped || quote != '\u0000' {
    raise Invalid("unsupported dry-run quoting")
  }
  if started {
    words.push(word)
  }
  words
}

///|
/// Selects compiler-only commands; excludes host C compilers and runtime objects.
pub fn compiler_commands(
  plan : String,
  moon_home : String,
) -> Array[Array[String]] raise ConfigError {
  let commands : Array[Array[String]] = []
  for line in plan.split("\n") {
    if line.has_prefix("moonc ") {
      let original = tokenize(line.to_owned())
      if original.length() < 2 ||
        (original[1] != "build-package" && original[1] != "link-core") {
        raise Invalid("unsupported compiler step")
      }
      let args : Array[String] = []
      let mut index = 1
      // `-all-pkgs` is kept: moonc resolves packages behind prelude aliases
      // (e.g. methods of `Float`) through it. Moon writes that file during a
      // real build only, so `all_pkgs_table` rebuilds it from the plan.
      while index < original.length() {
        args.push(original[index].replace_all(old="$MOON_HOME", new=moon_home))
        index += 1
      }
      commands.push(args)
    }
  }
  if commands.is_empty() || commands.last().unwrap()[0] != "link-core" {
    raise Invalid("plan has no C link-core step; unsupported Moon toolchain")
  }
  commands
}

///|
pub fn signature(fn_ : Function) -> String {
  "pub fn " +
  fn_.name +
  "(" +
  fn_.params.map(p => p.kind.moon_name()).join(", ") +
  ") -> " +
  fn_.result.moon_name()
}

///|
/// Rewrites the `Int32` spelling used by newer `.mbti` output to `Int`, leaving
/// identifiers such as `UInt32` or `MyInt32` untouched.
fn canonical_int(line : String) -> String {
  let word = (c : Char) => {
    c.is_ascii_alphabetic() || c.is_ascii_digit() || c == '_'
  }
  let chars = line.to_array()
  let out = StringBuilder()
  let mut i = 0
  while i < chars.length() {
    let end = i + 5
    if (i == 0 || !word(chars[i - 1])) &&
      end <= chars.length() &&
      String::from_array(chars[i:end]) == "Int32" &&
      (end == chars.length() || !word(chars[end])) {
      out.write_string("Int")
      i = end
    } else {
      out.write_char(chars[i])
      i += 1
    }
  }
  out.to_string()
}

///|
pub fn verify_interface(
  config : Config,
  text : String,
) -> Unit raise ConfigError {
  let declarations = text
    .split("\n")
    .map(s => canonical_int(s.trim().to_owned()))
    .to_array()
  for fn_ in config.functions {
    let expected = signature(fn_)
    if !declarations.contains(expected) {
      raise Invalid("signature unsupported or mismatched; expected " + expected)
    }
  }
}

///|
/// Value of `flag` in a compiler command, if present.
fn command_flag(args : Array[String], flag : String) -> String? {
  for i, arg in args {
    if arg == flag && i + 1 < args.length() {
      return Some(args[i + 1])
    }
  }
  None
}

///|
/// The `-all-pkgs` path the plan names, if any.
pub fn all_pkgs_path(commands : Array[Array[String]]) -> String? {
  for args in commands {
    match command_flag(args, "-all-pkgs") {
      Some(path) => return Some(path)
      None => ()
    }
  }
  None
}

///|
/// Workspace packages of the plan: (package, workspace path, `.mi` artifact),
/// for the `all_pkgs.json` table Moon would have written.
pub fn planned_packages(
  commands : Array[Array[String]],
) -> Array[(String, String, String)] {
  let packages : Array[(String, String, String)] = []
  for args in commands {
    if args.get(0) != Some("build-package") {
      continue
    }
    match
      (
        command_flag(args, "-pkg"),
        command_flag(args, "-workspace-path"),
        command_flag(args, "-o"),
      ) {
      (Some(pkg), Some(workspace), Some(output)) if output.has_suffix(".core") =>
        packages.push(
          (pkg, workspace, output[:output.length() - 5].to_owned() + ".mi"),
        )
      _ => ()
    }
  }
  packages
}

///|
/// One `all_pkgs.json` entry: module root, path inside it, `.mi` artifact.
pub fn all_pkgs_entry(
  module_name : String,
  pkg : String,
  artifact : String,
) -> Json {
  let rel = if pkg == module_name {
    ""
  } else if pkg.has_prefix(module_name + "/") {
    pkg[module_name.length() + 1:].to_owned()
  } else {
    pkg
  }
  { "root": module_name, "rel": rel, "artifact": artifact }
}
