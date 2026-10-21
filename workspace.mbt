///|
/// Member directories listed in a `moon.work` file.
pub fn workspace_members(text : String) -> Array[String] raise ConfigError {
  let parts = text.split("members").to_array()
  if parts.length() < 2 {
    raise Invalid("workspace: moon.work has no members")
  }
  let list = parts[1].split("[").to_array()
  if list.length() < 2 {
    raise Invalid("workspace: members must be a list")
  }
  let members = quoted_strings(
    list[1].split("]").head().unwrap_or("").to_owned(),
  )
  if members.is_empty() {
    raise Invalid("workspace: moon.work has no members")
  }
  for entry in members {
    if entry.contains("\\") || entry.contains(":") || entry.has_prefix("/") {
      raise Invalid("workspace: members must be relative paths: " + entry)
    }
  }
  members
}

///|
/// A workspace file for staged members `./m0`, `./m1`, ...
pub fn staged_workspace(count : Int) -> String {
  let members : Array[String] = []
  for index in 0..<count {
    members.push("  \"./m" + index.to_string() + "\",\n")
  }
  "members = [\n" + members.join("") + "]\n"
}
