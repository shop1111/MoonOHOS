///|
fn sample() -> @moonohos.Config raise @moonohos.ConfigError {
  @moonohos.parse_config(
    (
      #|{"version":1,"module":"demo","package":"moonohos/demo","nativeModule":"moonohos","functions":[
      #|{"name":"add","params":[{"name":"a","type":"Int"},{"name":"b","type":"Int"}],"return":"Int"},
      #|{"name":"scale","params":[{"name":"v","type":"Double"}],"return":"Double"},
      #|{"name":"negate","params":[{"name":"v","type":"Bool"}],"return":"Bool"},
      #|{"name":"ping","params":[],"return":"Unit"}]}
    ),
  )
}

///|
test "one contract generates all four scalar interfaces" {
  let config = sample()
  assert_true(
    @moonohos.c_header(config).contains("int32_t moonohos_negate(int32_t)"),
  )
  assert_true(@moonohos.declarations(config).contains("ping: () => void"))
  assert_true(
    @moonohos.declarations(config).contains("scale: (v: number) => number"),
  )
  assert_true(
    @moonohos.native_source(config).contains("NAPI_MODULE(moonohos, Init)"),
  )
  assert_true(
    @moonohos.native_source(config).contains("ReadBool(env, argv[0], arg0)"),
  )
  assert_true(@moonohos.native_source(config).contains("std::call_once"))
  assert_true(@moonohos.wrapper_source(config).contains("@core.add(a, b)"))
  assert_true(
    @moonohos.embed_source(config).contains("(void)moonohos_raw_ping()"),
  )
}

///|
test "valid interface includes Unit; missing functions fail" {
  let config = sample()
  @moonohos.verify_interface(
    config, "pub fn add(Int, Int) -> Int\npub fn scale(Double) -> Double\npub fn negate(Bool) -> Bool\npub fn ping() -> Unit\n",
  )
  @moonohos.verify_interface(
    config, "pub fn ping() -> Unit\npub fn negate(Bool) -> Bool\npub fn add(Int, Int) -> Int\npub fn scale(Double) -> Double\n",
  )
  let rejected = try {
    @moonohos.verify_interface(config, "pub fn add(Int, Double) -> Int")
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "generic optional and raising signatures are rejected" {
  let config = @moonohos.parse_config(
    (
      #|{"version":1,"module":".","package":"demo/core","nativeModule":"demo","functions":[{"name":"f","params":[{"name":"x","type":"Int"}],"return":"Int"}]}
    ),
  )
  for
    signature in [
      "pub fn[T] f(T) -> T", "pub fn f(Int?) -> Int", "pub fn f(Int) -> Int raise",
      "pub fn f(x? : Int) -> Int",
    ] {
    assert_true(
      try {
        @moonohos.verify_interface(config, signature)
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "duplicate functions unsupported types and invalid schema fail" {
  let text =
    #|{"version":1,"module":".","package":"demo/core","nativeModule":"demo","functions":[{"name":"f","params":[],"return":"Int"}]}
  for
    bad in [
      text.replace_all(old="\"Int\"", new="\"Array[Int]\""),
      text.replace_all(old="\"version\":1", new="\"version\":2"),
      text.replace_all(
        old="\"nativeModule\":\"demo\"",
        new="\"nativeModule\":\"a-b\"",
      ),
      text.replace_all(
        old="\"params\":[]",
        new="\"params\":[{\"name\":\"x\",\"type\":\"Unit\"}]",
      ),
      text.replace_all(
        old="}]}",
        new="},{\"name\":\"f\",\"params\":[],\"return\":\"Int\"}]}",
      ),
    ] {
    assert_true(
      try {
        @moonohos.parse_config(bad) |> ignore
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "dry-run tokenizer preserves spaces Chinese paths and literal metacharacters" {
  assert_eq(
    @moonohos.tokenize(
      "moonc build-package 'D:/中文 目录/a.mbt' -o \"a b.c\"",
    ),
    ["moonc", "build-package", "D:/中文 目录/a.mbt", "-o", "a b.c"],
  )
  assert_eq(@moonohos.tokenize("moonc 'a'\\''b' '$HOME;$(evil)'"), [
    "moonc", "a'b", "$HOME;$(evil)",
  ])
  assert_true(
    try {
      @moonohos.tokenize("moonc 'unclosed") |> ignore
      false
    } catch {
      _ => true
    },
  )
}

///|
test "adapter selects only Moon compiler stages and removes absent IDE metadata" {
  let commands = @moonohos.compiler_commands(
    "moonc build-package x.mbt -all-pkgs missing.json -o x.core\ncl.exe /c host.c\n  env:\n    PATH=host\nmoonc link-core '$MOON_HOME/lib/core.core' -o x.c",
    "C:/Moon Home",
  )
  assert_eq(commands.length(), 2)
  assert_eq(commands[0], ["build-package", "x.mbt", "-o", "x.core"])
  assert_eq(commands[1][1], "C:/Moon Home/lib/core.core")
}

///|
test "adapter requires a link-core stage" {
  assert_true(
    try {
      @moonohos.compiler_commands("cl.exe host.c", ".") |> ignore
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      @moonohos.compiler_commands("moonc build-package a.mbt", ".") |> ignore
      false
    } catch {
      _ => true
    },
  )
}

///|
test "reference types generate UTF16 Uint8Array and scoped ownership" {
  let config = @moonohos.parse_config(
    (
      #|{"version":1,"module":".","package":"demo/core","nativeModule":"demo","functions":[{"name":"mixed","params":[{"name":"label","type":"String"},{"name":"data","type":"Bytes"},{"name":"count","type":"Int"}],"return":"Bytes"},{"name":"text","params":[],"return":"String"}]}
    ),
  )
  assert_true(
    @moonohos.declarations(config).contains(
      "label: string, data: Uint8Array, count: number",
    ),
  )
  assert_true(
    @moonohos.c_header(config).contains(
      "moonbit_bytes_t moonohos_mixed(moonbit_string_t, moonbit_bytes_t, int32_t)",
    ),
  )
  let source = @moonohos.native_source(config)
  assert_true(source.contains("MoonOwner<moonbit_string_t> owned0"))
  assert_true(source.contains("MoonOwner<moonbit_bytes_t> returned"))
  assert_true(source.contains("moonohos_mixed(owned0.ptr, owned1.ptr, arg2)"))
  assert_true(source.contains("napi_create_string_utf16"))
  assert_true(source.contains("napi_is_detached_arraybuffer"))
  @moonohos.verify_interface(
    config, "pub fn mixed(String, Bytes, Int) -> Bytes\npub fn text() -> String\n",
  )
}
