///|
pub struct EnvironmentFact {
  name : String
  actual : String
  expected : String
  available : Bool
}

///|
pub fn environment_fact(
  name : String,
  actual : String,
  expected : String,
  available : Bool,
) -> EnvironmentFact {
  { name, actual, expected, available, }
}

///|
/// An `expected` value of `">= x.y.z"` is a version floor; any other non-empty
/// value must appear verbatim in `actual`.
pub fn EnvironmentFact::passed(self : EnvironmentFact) -> Bool {
  if !self.available {
    return false
  }
  if self.expected.has_prefix(">=") {
    return version_at_least(self.actual, self.expected[2:].trim().to_owned())
  }
  self.expected == "" || self.actual.contains(self.expected)
}

///|
pub fn EnvironmentFact::to_json(self : EnvironmentFact) -> Json {
  {
    "name": self.name,
    "actual": self.actual,
    "expected": self.expected,
    "available": self.available,
    "passed": self.passed(),
  }
}

///|
pub fn environment_report(facts : Array[EnvironmentFact]) -> Json {
  let mut passed = true
  for fact in facts {
    if !fact.passed() {
      passed = false
    }
  }
  { "compatible": passed, "checks": Json(facts.map(f => f.to_json())) }
}

///|
/// Oldest moonc accepted by `build`, `doctor` and package verification.
/// 0.10.20 is the first release that parses `#derive(...)`, which the
/// platform packages use since 0.7.
pub let minimum_moonc_version : String = "0.10.20"

///|
/// Oldest HarmonyOS SDK API level the generated Native code targets.
pub let minimum_sdk_api : Int32 = 26

///|
/// Toolchain this release was validated with. Newer releases are accepted;
/// `doctor` reports them as untested.
pub fn tested_environment() -> Array[(String, String)] {
  [
    ("moon", "0.1.20261104"),
    ("moonc", "v0.10.20+65efd5b93"),
    ("core", "0.10.20+65efd5b93"),
    ("async", "0.21.0"),
    ("sdkApi", "26"),
  ]
}

///|
/// Requirement checked by `doctor` for each toolchain component.
pub fn required_environment() -> Array[(String, String)] {
  [
    ("moon", ""),
    ("moonc", ">= " + minimum_moonc_version),
    ("core", ">= " + minimum_moonc_version),
    ("async", "0.21."),
    ("sdkApi", ">= " + minimum_sdk_api.to_string() + ".0.0"),
  ]
}

///|
/// Extracts the first `major.minor.patch` triple from tool output such as
/// `moonc v0.10.18+6c83a7f62 (2026-10-28)`. A bare integer (an SDK API level)
/// is read as `n.0.0`.
pub fn parse_version(text : String) -> (Int32, Int32, Int32)? {
  let mut single : (Int32, Int32, Int32)? = None
  let run = StringBuilder()
  let runs : Array[String] = []
  for char in text + " " {
    if (char >= '0' && char <= '9') || char == '.' {
      run.write_char(char)
    } else if run.to_string() != "" {
      runs.push(run.to_string())
      run.reset()
    }
  }
  for candidate in runs {
    let numbers : Array[Int32] = []
    for part in candidate.split(".") {
      if part == "" || part.length() > 9 {
        break
      }
      let mut value = 0
      for char in part {
        value = value * 10 + (char.to_int() - '0'.to_int())
      }
      numbers.push(value)
    }
    match numbers {
      [major, minor, patch, ..] => return Some((major, minor, patch))
      [only] if single is None => single = Some((only, 0, 0))
      _ => ()
    }
  }
  single
}

///|
/// True when `actual` contains a version not older than `minimum`.
pub fn version_at_least(actual : String, minimum : String) -> Bool {
  match (parse_version(actual), parse_version(minimum)) {
    (Some((a, b, c)), Some((x, y, z))) =>
      a > x || (a == x && (b > y || (b == y && c >= z)))
    _ => false
  }
}

///|
/// True when moonc output (`moonc -v`) satisfies `minimum_moonc_version`.
pub fn moonc_supported(version : String) -> Bool {
  version_at_least(version, minimum_moonc_version)
}

///|
/// Oldest moonc whose packages `verify` and HAR assembly still accept.
/// Packages are compiled artifacts, so the source-syntax floor of
/// `minimum_moonc_version` does not apply; 0.4.1 to 0.6.x packages were built
/// with moonc 0.10.16 to 0.10.18.
pub let minimum_package_moonc_version : String = "0.10.16"

///|
/// True when a package manifest's `moonc` field is new enough to verify.
pub fn package_moonc_supported(version : String) -> Bool {
  version_at_least(version, minimum_package_moonc_version)
}

///|
pub fn sdk_candidates(path : String) -> Array[String] {
  [
    path + "/default/openharmony/native",
    path + "/openharmony/native",
    path + "/native",
    path,
  ]
}

///|
pub fn runtime_files() -> Array[String] {
  [
    "include/moonbit.h", "lib/runtime/runtime.c", "lib/runtime/env.c", "lib/runtime/backtrace.c",
    "lib/runtime/sync_io.c", "lib/runtime/utf.c",
  ]
}

///|
/// Files a usable HarmonyOS Native SDK provides, relative to its `native`
/// directory, with executable names for `os`.
pub fn sdk_files(os~ : HostOs = Windows) -> Array[String] {
  [
    "build/cmake/ohos.toolchain.cmake",
    "build-tools/cmake/bin/" + os.exe("cmake"),
    "build-tools/cmake/bin/" + os.exe("ninja"),
    "llvm/bin/" + os.exe("clang"),
    "llvm/bin/" + os.exe("llvm-readelf"),
    "sysroot/usr/include/napi/native_api.h",
    "NOTICE.txt",
  ]
}
