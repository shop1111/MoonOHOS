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
pub fn EnvironmentFact::passed(self : EnvironmentFact) -> Bool {
  self.available && (self.expected == "" || self.actual.contains(self.expected))
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
  { "compatible": passed, "checks": facts.map(f => f.to_json()).to_json() }
}

///|
pub fn pinned_environment() -> Array[(String, String)] {
  [
    ("moon", "0.1.20260920"),
    ("moonc", "v0.10.14+7d59c7ec9"),
    ("core", "0.10.14+7d59c7ec9"),
    ("async", "0.21.0"),
    ("sdkApi", "26"),
  ]
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
pub fn sdk_files() -> Array[String] {
  [
    "build/cmake/ohos.toolchain.cmake", "build-tools/cmake/bin/cmake.exe", "build-tools/cmake/bin/ninja.exe",
    "llvm/bin/clang.exe", "llvm/bin/llvm-readelf.exe", "sysroot/usr/include/napi/native_api.h",
    "NOTICE.txt",
  ]
}
