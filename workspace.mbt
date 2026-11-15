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
pub fn staged_workspace(count : Int32) -> String {
  let members : Array[String] = []
  for index in 0..<count {
    members.push("  \"./m" + index.to_string() + "\",\n")
  }
  "members = [\n" + members.join("") + "]\n"
}

///|
/// Rewrites paths under a staged copy back to the source they were copied
/// from, so compiler diagnostics name the developer's files. Each mapping is
/// `(staged, original)` with `/` separators; both separator styles are
/// matched and the replacement keeps the style the tool printed.
pub fn restore_source_paths(
  text : String,
  mappings : Array[(String, String)],
) -> String {
  let mut result = text
  for mapping in mappings {
    let (staged, original) = mapping
    result = result.replace_all(old=staged + "/", new=original + "/")
    let back_staged = staged.replace_all(old="/", new="\\")
    let back_original = original.replace_all(old="/", new="\\")
    result = result.replace_all(
      old=back_staged + "\\",
      new=back_original + "\\",
    )
  }
  result
}
