///|
#derive(Eq, Debug)
pub(all) enum Command {
  Build
  Doctor
  Check
  Inspect
  Plan
  Verify
  Init
  Har
  Help
  Version
}

///|
pub struct CliOptions {
  command : Command
  config : String
  sdk : String?
  abis : Array[String]
  output : String
  json : Bool
  dry_run : Bool
  cache : Bool
  /// `init`: project directory, module name, package and platform module path.
  target : String?
  name : String?
  package_name : String?
  ohos : String?
  /// `har`: verified dist, HAR module directory and optional hvigor assembly.
  dist : String?
  module_dir : String?
  deveco : String?
  assemble : Bool
  /// `har --app`: also assemble the demo app module `entry`.
  app : Bool
  /// `help`: the command whose help was requested, if any.
  help_topic : Command?
}

///|
pub(all) struct Diagnostic {
  stage : String
  code : String
  message : String
  context : Array[String]
}

///|
pub fn Diagnostic::to_json(self : Diagnostic) -> Json {
  {
    "stage": self.stage,
    "code": self.code,
    "message": self.message,
    "context": Json(self.context),
  }
}

///|
pub fn Diagnostic::render(self : Diagnostic) -> String {
  let prefix = self.stage + " [" + self.code + "]: " + self.message
  if self.context.is_empty() {
    prefix
  } else {
    prefix + "\n  " + self.context.join("\n  ")
  }
}

///|
pub fn command_name(command : Command) -> String {
  match command {
    Build => "build"
    Doctor => "doctor"
    Check => "check"
    Inspect => "inspect"
    Plan => "plan"
    Verify => "verify"
    Init => "init"
    Har => "har"
    Help => "help"
    Version => "version"
  }
}

///|
fn parse_command(text : String) -> Command raise ConfigError {
  match text {
    "build" => Build
    "doctor" => Doctor
    "check" => Check
    "inspect" => Inspect
    "plan" => Plan
    "verify" => Verify
    "init" => Init
    "har" => Har
    "help" | "--help" | "-h" => Help
    "--version" => Version
    _ => raise Invalid("unknown command: " + text)
  }
}

///|
pub fn parse_abis(text : String) -> Array[String] raise ConfigError {
  let result : Array[String] = []
  for part in text.split(",") {
    let abi = part.to_owned()
    if abi != "arm64-v8a" && abi != "x86_64" {
      raise Invalid("unsupported ABI: " + abi)
    }
    if result.contains(abi) {
      raise Invalid("duplicate ABI: " + abi)
    }
    result.push(abi)
  }
  if result.is_empty() {
    raise Invalid("at least one ABI is required")
  }
  result
}

///|
fn allowed_option(command : Command, option : String) -> Bool {
  match option {
    "--json" => command != Help && command != Version
    "--config" =>
      command != Verify &&
      command != Help &&
      command != Version &&
      command != Init &&
      command != Har
    "--sdk" => command == Build || command == Doctor || command == Plan
    "--abi" => command == Build || command == Plan
    "--out" => command == Build || command == Verify || command == Har
    "--dry-run" | "--cache" => command == Build
    "--name" | "--package" | "--ohos" => command == Init
    "--dist" | "--module" | "--deveco" | "--assemble" | "--app" =>
      command == Har
    _ => false
  }
}

///|
/// Arguments exclude the executable name. Paths are resolved by the command.
pub fn parse_cli(args : Array[String]) -> CliOptions raise ConfigError {
  let command = if args.is_empty() { Help } else { parse_command(args[0]) }
  let mut config = "moonohos.json"
  let mut sdk : String? = None
  let mut abis = ["arm64-v8a", "x86_64"]
  let mut output = "_build/moonohos/dist"
  let mut json = false
  let mut dry_run = false
  let mut cache = false
  let mut target : String? = None
  let mut name : String? = None
  let mut package_name : String? = None
  let mut ohos : String? = None
  let mut dist : String? = None
  let mut module_dir : String? = None
  let mut deveco : String? = None
  let mut assemble = false
  let mut app = false
  let mut help_topic : Command? = None
  let seen : Map[String, Bool] = Map([])
  let mut index = 1
  if command == Help && args.length() > 1 {
    let topic = parse_command(args[1])
    if topic != Help && topic != Version {
      help_topic = Some(topic)
    }
    index = args.length()
  }
  if command == Init && args.length() > 1 && !args[1].has_prefix("--") {
    target = Some(args[1])
    index = 2
  }
  while index < args.length() {
    let option = args[index]
    if option == "--help" || option == "-h" {
      return {
        command: Help,
        help_topic: if command == Help {
          None
        } else {
          Some(command)
        },
        config,
        sdk,
        abis,
        output,
        json,
        dry_run,
        cache,
        target,
        name,
        package_name,
        ohos,
        dist,
        module_dir,
        deveco,
        assemble,
        app,
      }
    }
    if !allowed_option(command, option) {
      raise Invalid(
        "option " + option + " is not supported by " + command_name(command),
      )
    }
    if seen.contains(option) {
      raise Invalid("duplicate option: " + option)
    }
    seen[option] = true
    match option {
      "--json" => json = true
      "--dry-run" => dry_run = true
      "--cache" => cache = true
      "--assemble" => assemble = true
      "--app" => app = true
      _ => {
        if index + 1 >= args.length() || args[index + 1].has_prefix("--") {
          raise Invalid("missing value for " + option)
        }
        index += 1
        let value = args[index]
        if value == "" {
          raise Invalid("empty value for " + option)
        }
        match option {
          "--config" => config = value
          "--sdk" => sdk = Some(value)
          "--abi" => abis = parse_abis(value)
          "--out" => output = value
          "--name" => name = Some(value)
          "--package" => package_name = Some(value)
          "--ohos" => ohos = Some(value)
          "--dist" => dist = Some(value)
          "--module" => module_dir = Some(value)
          "--deveco" => deveco = Some(value)
          _ => raise Invalid("unknown option: " + option)
        }
      }
    }
    index += 1
  }
  if command == Build && sdk is None {
    raise Invalid("build requires --sdk <SDK directory>")
  }
  if command == Init && target is None {
    raise Invalid("init requires a project directory: moonohos init <dir>")
  }
  if command == Har && (dist is None || module_dir is None) {
    raise Invalid("har requires --dist <package> and --module <HAR module>")
  }
  if app && !assemble {
    raise Invalid("--app requires --assemble")
  }
  if assemble && deveco is None {
    raise Invalid("--assemble requires --deveco <DevEco Studio directory>")
  }
  {
    command,
    config,
    sdk,
    abis,
    output,
    json,
    dry_run,
    cache,
    target,
    name,
    package_name,
    ohos,
    dist,
    module_dir,
    deveco,
    assemble,
    app,
    help_topic,
  }
}

///|
pub fn success_report(command : String, result : Json) -> Json {
  { "command": command, "ok": true, "exitCode": 0, "result": result }
}

///|
pub fn failure_report(
  command : String,
  diagnostic : Diagnostic,
  parameter~ : Bool = false,
) -> Json {
  {
    "command": command,
    "ok": false,
    "exitCode": if parameter {
      2
    } else {
      3
    },
    "diagnostics": Json([diagnostic.to_json()]),
  }
}

///|
/// One-line summary, usage line and option notes for each command.
fn command_doc(command : Command) -> (String, String, Array[String]) {
  match command {
    Init =>
      (
        "create a MoonBit module, manifest and HAR project",
        "moonohos init <dir> [--name <module>] [--package owner/name] [--ohos <path>] [--json]",
        [
          "--name      MoonBit module directory name (default: core)", "--package   MoonBit package and ohpm name (default: <you>/<dir>)",
          "--ohos      use a local MoonOHOS/ohos checkout instead of Mooncakes",
        ],
      )
    Build =>
      (
        "compile the module into HarmonyOS shared libraries and type declarations",
        "moonohos build --sdk <SDK> [--config moonohos.json] [--abi arm64-v8a,x86_64] [--out <dir>] [--dry-run] [--cache] [--json]",
        [
          "--sdk       DevEco Studio sdk directory (or the Native SDK inside it)",
          "--abi       comma separated subset of arm64-v8a,x86_64 (default: both)",
          "--out       new output directory (default: _build/moonohos/dist)", "--dry-run   validate the manifest, interface and toolchain only",
          "--cache     reuse a verified build with the same content key",
        ],
      )
    Har =>
      (
        "place a verified build into a HAR module, optionally running hvigor",
        "moonohos har --dist <package> --module <HAR module> [--assemble [--app] --deveco <DevEco Studio>] [--json]",
        [
          "--dist      output directory of `moonohos build`", "--module    Hvigor HAR module directory (e.g. harmony/<name>)",
          "--assemble  run ohpm install and hvigor assembleHar", "--deveco    DevEco Studio installation (required by --assemble)",
          "--app       also build the demo app module `entry` created by init (HAP)",
        ],
      )
    Doctor =>
      (
        "check the MoonBit toolchain, runtime files and HarmonyOS SDK",
        "moonohos doctor [--sdk <SDK>] [--json]",
        ["--sdk       also check the SDK API level and Native toolchain files"],
      )
    Check =>
      (
        "compile the generated wrapper package strictly, without the SDK",
        "moonohos check [--config moonohos.json] [--json]",
        [],
      )
    Inspect =>
      (
        "print the exported functions, records and handles MoonOHOS sees",
        "moonohos inspect [--config moonohos.json] [--json]",
        [],
      )
    Plan =>
      (
        "print the ordered build stages without running them",
        "moonohos plan [--config moonohos.json] [--sdk <SDK>] [--abi <list>] [--json]",
        [],
      )
    Verify =>
      (
        "verify a built package: SHA-256, type package, ELF architecture and dependencies",
        "moonohos verify --out <package> [--json]",
        [],
      )
    Help => ("show help", "moonohos help [<command>]", [])
    Version => ("print the MoonOHOS version", "moonohos --version", [])
  }
}

///|
/// Top-level usage listing every command.
pub fn usage_text(version : String) -> String {
  let lines = [
    "MoonOHOS " + version + " - HarmonyOS Native modules in MoonBit",
    "",
    "Usage: moonohos <command> [options]",
    "",
    "Commands:",
  ]
  for command in [Init, Build, Har, Doctor, Check, Inspect, Plan, Verify] {
    let (summary, _, _) = command_doc(command)
    let name = command_name(command)
    lines.push("  " + name + " ".repeat(10 - name.length()) + summary)
  }
  lines.push("")
  lines.push(
    "Run `moonohos <command> --help` for options. Every command accepts --json.",
  )
  lines.push("Exit codes: 0 success, 2 invalid arguments, 3 failure.")
  lines.join("\n")
}

///|
/// Usage and options for one command.
pub fn command_help(command : Command) -> String {
  let (summary, usage, options) = command_doc(command)
  let lines = ["moonohos " + command_name(command) + ": " + summary, "", usage]
  if !options.is_empty() {
    lines.push("")
    lines.push("Options:")
    for option in options {
      lines.push("  " + option)
    }
  }
  lines.join("\n")
}

///|
/// Category of a `category: message` failure, or `failed` when the message
/// has no such prefix.
fn failure_code(message : String) -> String {
  if message.has_prefix("OSError") {
    return "io"
  }
  match message.find(":") {
    Some(i) if i > 0 && i <= 24 => {
      let head = message[:i].to_owned()
      if head.iter().all(c => c.is_ascii_lowercase() || c == '-' || c == '/') {
        head
      } else {
        "failed"
      }
    }
    _ => "failed"
  }
}

///|
/// Turns a failure message into a diagnostic whose code is its category and
/// whose context suggests the next step.
pub fn failure_diagnostic(stage : String, message : String) -> Diagnostic {
  let code = failure_code(message)
  let hints : Array[String] = []
  match code {
    "toolchain" =>
      hints.push(
        if message.contains("SDK") {
          "pass the DevEco Studio sdk directory, e.g. --sdk \"<DevEco Studio>/sdk\""
        } else {
          "run `moonohos doctor --json` to see which component is missing or too old"
        },
      )
    "config" | "type" | "types" | "functions" | "handles" | "workspace" =>
      hints.push(
        "check moonohos.json against the manifest reference in README.md (moonohos.json section)",
      )
    "interface" | "analysis" => {
      hints.push(
        "run `moon info` in the MoonBit module and compare pkg.generated.mbti with moonohos.json",
      )
      hints.push("`moonohos inspect --json` prints what MoonOHOS read")
    }
    "elf" | "native" | "stage" | "generation" =>
      hints.push(
        "the phase logs in the work directory show the failing command; report a bug if the inputs are valid",
      )
    "package" | "cache" =>
      hints.push(
        "rebuild with the current CLI into a new --out directory, then run `moonohos verify --out <dir>`",
      )
    "har" =>
      hints.push(
        "check that --module is a HAR module (with oh-package.json5) and --deveco is the DevEco Studio installation",
      )
    "io" =>
      hints.push(
        "check that the path exists and is readable; quote paths that contain spaces",
      )
    _ => ()
  }
  { stage, code, message, context: hints, }
}

///|
#deprecated
pub extend Command with Eq::{equal, not_equal}

///|
#deprecated
pub extend Command with @debug.Debug::{to_repr}
