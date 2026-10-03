///|
pub(all) enum Command {
  Build
  Doctor
  Check
  Inspect
  Plan
  Verify
  Help
  Version
} derive(Eq, Debug)

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
    "context": self.context.to_json(),
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
    "--help" | "-h" => Help
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
    "--config" => command != Verify && command != Help && command != Version
    "--sdk" => command == Build || command == Doctor || command == Plan
    "--abi" => command == Build || command == Plan
    "--out" => command == Build || command == Verify
    "--dry-run" | "--cache" => command == Build
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
  let seen : Map[String, Bool] = Map([])
  let mut index = 1
  while index < args.length() {
    let option = args[index]
    if option == "--help" || option == "-h" {
      return { command: Help, config, sdk, abis, output, json, dry_run, cache, }
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
          _ => raise Invalid("unknown option: " + option)
        }
      }
    }
    index += 1
  }
  if command == Build && sdk is None {
    raise Invalid("build requires --sdk <SDK directory>")
  }
  { command, config, sdk, abis, output, json, dry_run, cache, }
}

///|
pub fn success_report(command : String, result : Json) -> Json {
  { "command": command, "ok": true, "exitCode": 0, "result": result }
}

///|
pub fn failure_report(
  command : String,
  diagnostic : Diagnostic,
  parameter? : Bool = false,
) -> Json {
  {
    "command": command,
    "ok": false,
    "exitCode": if parameter {
      2
    } else {
      3
    },
    "diagnostics": [diagnostic.to_json()].to_json(),
  }
}

///|
#deprecated
pub extend Command with Eq::{equal, not_equal}

///|
#deprecated
pub extend Command with @debug.Debug::{to_repr}
