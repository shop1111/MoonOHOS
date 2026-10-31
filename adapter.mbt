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
      while index < original.length() {
        // Optional IDE metadata is absent when Moon only prints a dry-run plan.
        if original[index] == "-all-pkgs" {
          index += 2
        } else {
          args.push(
            original[index].replace_all(old="$MOON_HOME", new=moon_home),
          )
          index += 1
        }
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
