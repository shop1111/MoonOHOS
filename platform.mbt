///|
/// Host operating system. It decides executable names, the Moon home fallback
/// and where DevEco Studio keeps node, ohpm, hvigor and the JDK.
pub(all) enum HostOs {
  Windows
  MacOS
  Linux
} derive(Eq, Debug)

///|
#deprecated
pub extend HostOs with Eq::{equal, not_equal}

///|
#deprecated
pub extend HostOs with @debug.Debug::{to_repr}

///|
/// Directory that only exists on macOS.
pub let macos_marker : String = "/System/Library/CoreServices"

///|
/// `os_env` is the value of the `OS` environment variable (`Windows_NT` on every
/// Windows); `has_macos_marker` tells whether `macos_marker` exists.
pub fn detect_host_os(os_env : String?, has_macos_marker : Bool) -> HostOs {
  if os_env is Some(value) && value.to_lower() == "windows_nt" {
    Windows
  } else if has_macos_marker {
    MacOS
  } else {
    Linux
  }
}

///|
/// `name` with the platform's executable suffix.
pub fn HostOs::exe(self : HostOs, name : String) -> String {
  match self {
    Windows => name + ".exe"
    MacOS | Linux => name
  }
}

///|
/// Whether paths on this host compare case-insensitively (NTFS and the default
/// APFS volume do; Linux file systems do not).
pub fn HostOs::case_insensitive_paths(self : HostOs) -> Bool {
  self != Linux
}

///|
/// `MOON_HOME`, else `~/.moon`, where `~` is `USERPROFILE` on Windows and
/// `HOME` elsewhere. Backslashes are normalized to `/`.
pub fn moon_home_dir(
  os : HostOs,
  moon_home : String?,
  user_profile : String?,
  home : String?,
) -> String {
  let path = match moon_home {
    Some(value) if value != "" => value
    _ => {
      let base = match os {
        Windows => user_profile.unwrap_or(home.unwrap_or(""))
        MacOS | Linux => home.unwrap_or(user_profile.unwrap_or(""))
      }
      base + "/.moon"
    }
  }
  path.replace_all(old="\\", new="/")
}

///|
/// Absolute path of a tool shipped in the HarmonyOS Native SDK directory.
pub fn native_tool(os : HostOs, native : String, tool : String) -> String {
  let dir = match tool {
    "cmake" | "ninja" => "/build-tools/cmake/bin/"
    _ => "/llvm/bin/"
  }
  native + dir + os.exe(tool)
}

///|
/// Tools `moonohos har --assemble` runs from a DevEco Studio installation.
pub struct DevEcoTools {
  sdk : String
  node : String
  node_home : String
  ohpm_cli : String
  ohpm_home : String
  hvigor_cli : String
  java_home : String?
}

///|
/// Candidate locations, in preference order, for each DevEco tool.
fn deveco_candidates(
  os : HostOs,
  deveco : String,
) -> (Array[String], Array[String], Array[String], Array[String], Array[String]) {
  let roots = [deveco, deveco + "/Contents"]
  let bases : Array[String] = []
  for root in roots {
    bases.push(root + "/tools")
    bases.push(root + "/tool")
    bases.push(root)
  }
  (
    bases.map(b => b + "/node/" + os.exe("node")) +
    bases.map(b => b + "/node/bin/node"),
    bases.map(b => b + "/ohpm/bin/pm-cli.js"),
    bases.map(b => b + "/hvigor/bin/hvigorw.js"),
    roots.map(r => r + "/sdk"),
    roots.map(r => r + "/jbr/Contents/Home") + roots.map(r => r + "/jbr"),
  )
}

///|
/// Every path `resolve_deveco` may look at; the caller reports which exist.
pub fn deveco_probe_paths(os : HostOs, deveco : String) -> Array[String] {
  let (node, ohpm, hvigor, sdk, java) = deveco_candidates(os, deveco)
  node + ohpm + hvigor + sdk + java
}

///|
/// Locates node, ohpm, hvigor, the SDK and the bundled JDK in a DevEco Studio
/// installation (Windows `DevEco Studio/`, macOS `DevEco-Studio.app`) or in the
/// command-line tools archive (`command-line-tools/`). `existing` holds the
/// paths from `deveco_probe_paths` that exist.
pub fn resolve_deveco(
  os : HostOs,
  deveco : String,
  existing : Array[String],
) -> DevEcoTools raise ConfigError {
  let (nodes, ohpms, hvigors, sdks, javas) = deveco_candidates(os, deveco)
  let first = (candidates : Array[String]) => {
    for candidate in candidates {
      if existing.contains(candidate) {
        return Some(candidate)
      }
    }
    None
  }
  let node = first(nodes)
  let ohpm = first(ohpms)
  let hvigor = first(hvigors)
  let sdk = first(sdks)
  match (node, ohpm, hvigor, sdk) {
    (Some(node), Some(ohpm), Some(hvigor), Some(sdk)) => {
      let node_home = if node.has_suffix("/bin/node") {
        node[:node.length() - "/bin/node".length()].to_owned()
      } else {
        node[:node.length() - ("/" + os.exe("node")).length()].to_owned()
      }
      let java_home = first(javas)
      {
        sdk,
        node,
        node_home,
        ohpm_cli: ohpm,
        ohpm_home: ohpm[:ohpm.length() - "/bin/pm-cli.js".length()].to_owned(),
        hvigor_cli: hvigor,
        java_home,
      }
    }
    _ =>
      raise Invalid(
        "har: DevEco tools not found under " +
        deveco +
        " (need node, ohpm/bin/pm-cli.js, hvigor/bin/hvigorw.js and sdk; e.g. " +
        nodes[0] +
        ")",
      )
  }
}

///|
/// Environment for running ohpm and hvigor from `tools`.
pub fn DevEcoTools::env(self : DevEcoTools) -> Map[String, String] {
  let env : Map[String, String] = {
    "DEVECO_SDK_HOME": self.sdk,
    "NODE_HOME": self.node_home,
    "OHPM_HOME": self.ohpm_home,
  }
  if self.java_home is Some(java) {
    env["JAVA_HOME"] = java
  }
  env
}
