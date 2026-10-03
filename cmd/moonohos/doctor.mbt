///|
fn moon_home() -> String {
  normalized(
    @env.get_env_var("MOON_HOME").unwrap_or(
      @env.get_env_var("USERPROFILE").unwrap_or("") + "/.moon",
    ),
  )
}

///|
async fn native_sdk(path : String) -> String {
  for candidate in @lib.sdk_candidates(normalized(@fs.realpath(path))) {
    if @fs.exists(candidate + "/build/cmake/ohos.toolchain.cmake") {
      return candidate
    }
  }
  raise Failure("toolchain: OHOS Native SDK not found: " + path)
}

///|
async fn doctor(options : @lib.CliOptions) -> Json {
  let base = @env.current_dir().unwrap_or(".")
  let facts : Array[@lib.EnvironmentFact] = []
  for (name, expected) in @lib.pinned_environment() {
    if name == "sdkApi" {
      continue
    }
    let actual = if name == "moon" || name == "moonc" {
      command(
        "doctor/" + name,
        name,
        if name == "moon" {
          ["version"]
        } else {
          ["-v"]
        },
        base,
      ) catch {
        error => error.to_string()
      }
    } else {
      let location = if name == "core" {
        moon_home() + "/lib/core/moon.mod.json"
      } else {
        base + "/.mooncakes/moonbitlang/async/moon.mod.json"
      }
      if @fs.exists(location) {
        let metadata = @json.parse(read(location))
        match metadata {
          { "version": String(value), .. } => value
          _ => "version missing"
        }
      } else if @fs.exists(location.replace_all(old=".json", new="")) {
        let text = read(location.replace_all(old=".json", new=""))
        let mut version = "missing version"
        for line in text.split("\n") {
          let tokens = @lib.tokenize(line.to_owned())
          if tokens.length() == 3 && tokens[0] == "version" && tokens[1] == "=" {
            version = tokens[2]
          }
        }
        version
      } else if name == "async" {
        "0.21.0 (compiled dependency)"
      } else {
        "missing metadata"
      }
    }
    facts.push(
      @lib.environment_fact(name, actual.trim().to_owned(), expected, true),
    )
  }
  for path in @lib.runtime_files() {
    facts.push(
      @lib.environment_fact(
        "runtime/" + path,
        path,
        "",
        @fs.exists(moon_home() + "/" + path),
      ),
    )
  }
  match options.sdk {
    Some(path) => {
      let native = native_sdk(resolve(base, path))
      let metadata = @json.parse(read(native + "/oh-uni-package.json"))
      let api = match metadata {
        { "apiVersion": String(value), .. } => value
        _ => "unknown"
      }
      facts.push(@lib.environment_fact("sdkApi", api, "26", true))
      for file in @lib.sdk_files() {
        facts.push(
          @lib.environment_fact(
            "sdk/" + file,
            file,
            "",
            @fs.exists(native + "/" + file),
          ),
        )
      }
    }
    None => ()
  }
  let report = @lib.environment_report(facts)
  if facts.any(f => !f.passed()) {
    raise Failure(
      "doctor: incompatible environment\n" + report.stringify(indent=2),
    )
  }
  report
}
