///|
fn v2_project() -> @moonohos.Project raise {
  @moonohos.parse_project(
    (
      #|{"version":2,"module":"core","package":"demo/search","nativeModule":"search",
      #| "workspace":"moon.work","handles":[{"name":"Index"}],
      #| "types":[{"name":"Hit","fields":[{"name":"path","type":"String"},{"name":"score","type":"Double"}]}],
      #| "functions":[
      #|  {"name":"build","params":[{"name":"resources","type":"@rawfile.Manager"},{"name":"dir","type":"String"}],"return":"Index","async":true,"raises":true},
      #|  {"name":"search","params":[{"name":"index","type":"Index"},{"name":"query","type":"String"}],"return":"Array[Hit]","async":true},
      #|  {"name":"size","params":[{"name":"index","type":"Index"}],"return":"Int"}]}
    ),
  )
}

///|
fn rawfile_descriptor() -> String {
  (
    #|{"schema":"moonohos-native-v1","package":"shop1111/moonohos_ohos/rawfile",
    #| "sources":["rawfile_stub.c"],"systemLibraries":["librawfile.z.so"],
    #| "abis":["arm64-v8a","x86_64"],
    #| "adapters":[{"type":"Manager","arkType":"resourceManager.ResourceManager",
    #|   "arkImport":"import { resourceManager } from '@kit.LocalizationKit';",
    #|   "acquire":"moonohos_rawfile_acquire","release":"moonohos_rawfile_release"}]}
  )
}

///|
test "manifest v2 binds handles, adapters, async and raises" {
  let project = v2_project()
  assert_eq(project.version, 2)
  assert_eq(project.workspace, Some("moon.work"))
  assert_true(
    project.functions[0].params[0].kind is External("rawfile", "Manager"),
  )
  assert_true(project.functions[0].result is Handle("Index"))
  assert_true(project.functions[1].params[0].kind is Handle("Index"))
  assert_true(project.functions[0].is_async && project.functions[0].raises)
  assert_eq(
    project.functions[0].signature(),
    "pub fn build(@rawfile.Manager, String) -> Index raise",
  )
  assert_true(project.functions[0].raw_result() is List(Handle("Index")))
  project.validate()
}

///|
test "version 1 rejects version 2 features and opaque nesting is rejected" {
  for
    text in [
      "{\"version\":1,\"module\":\".\",\"package\":\"a/b\",\"nativeModule\":\"m\",\"handles\":[],\"functions\":[{\"name\":\"f\",\"params\":[],\"return\":\"Int\"}]}",
      "{\"version\":1,\"module\":\".\",\"package\":\"a/b\",\"nativeModule\":\"m\",\"functions\":[{\"name\":\"f\",\"params\":[],\"return\":\"Int\",\"async\":true}]}",
    ] {
    assert_true(
      try {
        @moonohos.parse_project(text) |> ignore
        false
      } catch {
        _ => true
      },
    )
  }
  let nested = @moonohos.parse_project(
    "{\"version\":2,\"module\":\".\",\"package\":\"a/b\",\"nativeModule\":\"m\",\"handles\":[{\"name\":\"H\"}],\"functions\":[{\"name\":\"f\",\"params\":[{\"name\":\"v\",\"type\":\"Array[H]\"}],\"return\":\"Int\"}]}",
  )
  assert_true(
    try {
      nested.validate()
      false
    } catch {
      _ => true
    },
  )
  let returned = @moonohos.parse_project(
    "{\"version\":2,\"module\":\".\",\"package\":\"a/b\",\"nativeModule\":\"m\",\"functions\":[{\"name\":\"f\",\"params\":[],\"return\":\"@rawfile.Manager\"}]}",
  )
  assert_true(
    try {
      returned.validate()
      false
    } catch {
      _ => true
    },
  )
}

///|
test "abstract types end the previous declaration" {
  let text =
    #|package "demo/search"
    #|import {
    #|  "shop1111/moonohos_ohos/rawfile",
    #|}
    #|pub fn build(@rawfile.Manager, String) -> Index raise
    #|pub fn search(Index, String) -> Array[Hit]
    #|pub fn size(Index) -> Int
    #|type Index
    #|pub struct Hit {
    #|  path : String
    #|  score : Double
    #|}
  let interface = @moonohos.parse_package_interface(text)
  assert_true(interface.functions.iter().all(f => f.unsupported is None))
  assert_true(interface.types.iter().any(t => t.name == "Index" && !t.generic))
  assert_eq(
    @moonohos.interface_imports(text).get("rawfile"),
    Some("shop1111/moonohos_ohos/rawfile"),
  )
  v2_project().verify_interface(text)
  let missing = text.replace(old="type Index\n", new="")
  assert_true(
    try {
      v2_project().verify_interface(missing)
      false
    } catch {
      _ => true
    },
  )
}

///|
test "native descriptors are validated against declared stubs" {
  let descriptor = @moonohos.parse_native_descriptor(
    rawfile_descriptor(),
    "shop1111/moonohos_ohos/rawfile",
    ["rawfile_stub.c"],
  )
  assert_eq(descriptor.libraries, ["librawfile.z.so"])
  assert_eq(descriptor.adapters[0].acquire, "moonohos_rawfile_acquire")
  for
    (text, stubs) in [
      (rawfile_descriptor(), ["other.c"]),
      (
        rawfile_descriptor().replace(old="librawfile.z.so", new="libssl.so"),
        ["rawfile_stub.c"],
      ),
      (
        rawfile_descriptor().replace(old="rawfile_stub.c", new="../x.c"),
        ["../x.c"],
      ),
      (
        rawfile_descriptor().replace(old="moonohos_rawfile_release", new="free"),
        ["rawfile_stub.c"],
      ),
      (
        rawfile_descriptor().replace(old="'@kit.LocalizationKit'", new="'evil'"),
        ["rawfile_stub.c"],
      ),
    ] {
    assert_true(
      try {
        @moonohos.parse_native_descriptor(
          text, "shop1111/moonohos_ohos/rawfile", stubs,
        )
        |> ignore
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "stub lists, build hooks and linked packages are extracted" {
  assert_eq(
    @moonohos.native_stubs(
      "import {\n  \"a/b\",\n}\noptions(\n  \"native-stub\": [ \"x.c\", \"y.c\" ],\n)\n",
    ),
    ["x.c", "y.c"],
  )
  assert_eq(@moonohos.native_stubs("{\"native-stub\": [\"z.c\"]}"), ["z.c"])
  assert_eq(@moonohos.native_stubs("pkgtype(kind: \"executable\")"), [])
  assert_true(
    @moonohos.forbidden_build_hook("options(\"pre-build\": [])") is Some(_),
  )
  assert_true(
    @moonohos.forbidden_build_hook(
      "options(link: { \"native\": { \"cc-flags\": \"-O3\" } })",
    )
    is Some(_),
  )
  assert_true(@moonohos.forbidden_build_hook("import { \"a/b\" }") is None)
  let linked = @moonohos.linked_packages([
    "link-core", "a.core", "-pkg-sources", "probe/core:./core", "-pkg-sources", "probe/ohos/hilog:C:/x/ohos/hilog",
    "-o", "out.c",
  ])
  assert_eq(linked.length(), 2)
  assert_eq(linked[1].0, "probe/ohos/hilog")
  assert_eq(linked[1].1, "C:/x/ohos/hilog")
}

///|
test "adapters resolve through mbti imports and descriptors" {
  let descriptor = @moonohos.parse_native_descriptor(
    rawfile_descriptor(),
    "shop1111/moonohos_ohos/rawfile",
    ["rawfile_stub.c"],
  )
  let imports : Map[String, String] = {
    "rawfile": "shop1111/moonohos_ohos/rawfile",
  }
  let adapters = @moonohos.resolve_adapters(v2_project(), [descriptor], imports)
  assert_eq(adapters.length(), 1)
  assert_eq(adapters[0].ark_type, "resourceManager.ResourceManager")
  assert_true(
    try {
      @moonohos.resolve_adapters(v2_project(), [], imports) |> ignore
      false
    } catch {
      _ => true
    },
  )
}

///|
test "workspace members are staged under neutral names" {
  assert_eq(
    @moonohos.workspace_members(
      "members = [\n  \"./core\",\n  \"../../ohos\",\n]\n",
    ),
    ["./core", "../../ohos"],
  )
  assert_true(
    try {
      @moonohos.workspace_members("members = [\"C:/abs\"]") |> ignore
      false
    } catch {
      _ => true
    },
  )
  assert_true(@moonohos.staged_workspace(2).contains("\"./m1\""))
}

///|
test "native cmake links declared NDK libraries and bridge macros" {
  let cmake = @moonohos.native_cmake("search", {
    sources: ["deps/0/rawfile_stub.c"],
    include_dirs: ["deps/0"],
    defines: [],
    libraries: ["librawfile.z.so"],
  })
  assert_true(cmake.contains("libace_napi.z.so librawfile.z.so m"))
  assert_true(cmake.contains("MOONOHOS_BRIDGE=1 MOONOHOS_TARGET_OHOS=1"))
  assert_true(
    cmake.contains("${CMAKE_CURRENT_SOURCE_DIR}/deps/0/rawfile_stub.c"),
  )
}

///|
test "generated async bridge settles once and declares tokens" {
  let descriptor = @moonohos.parse_native_descriptor(
    rawfile_descriptor(),
    "shop1111/moonohos_ohos/rawfile",
    ["rawfile_stub.c"],
  )
  let project = v2_project()
  let project = project.with_adapters(
    @moonohos.resolve_adapters(project, [descriptor], {
      "rawfile": "shop1111/moonohos_ohos/rawfile",
    }),
  )
  let generated = project.generate()
  assert_true(
    generated.wrapper.contains("moonohos_business_error(error.to_string())"),
  )
  assert_true(
    generated.package_file.contains(
      "\"shop1111/moonohos_ohos/rawfile\" @rawfile",
    ),
  )
  assert_true(
    generated.declarations.contains(
      "export const build: (resources: resourceManager.ResourceManager, dir: string, token?: CancelToken) => Promise<Index>;",
    ),
  )
  assert_true(generated.declarations.contains("export interface Index {"))
  assert_true(
    generated.native.contains("static void Execute_build(napi_env, void *data)"),
  )
  assert_true(
    generated.native.contains("Acquire(env, argv[0], moonohos_rawfile_acquire"),
  )
  // Workers only run MoonBit under the gate; Node-API calls stay in Call/Complete.
  let execute = generated.native.split("static void Execute_search").to_array()[1]
  let execute = execute.split("static bool Result_search").to_array()[0]
    .to_owned()
    .replace(old="(napi_env, void *data)", new="")
  assert_true(!execute.contains("napi_"))
  // Work is deleted once in SettleTask or on a QueueTask failure path; never per call.
  assert_eq(
    generated.native.split("napi_delete_async_work(env, task->work);").count(),
    4,
  )
}

///|
test "package manifest v2 accepts declared NDK libraries only" {
  let manifest =
    #|{"schema":"moonohos-build-v2","moonohosVersion":"0.4.0","module":"search","moon":"moon 0.1.20260920","moonc":"v0.10.14+7d59c7ec9","sdkApi":26,
    #| "results":[{"abi":"x86_64","build":"passed","elf":"verified","runtime":"not_run"}],
    #| "functions":["pub fn size(Index) -> Int"],"exports":[{"name":"size","async":false,"raises":false}],"handles":["Index"],
    #| "nativeDependencies":[{"package":"shop1111/moonohos_ohos/rawfile","systemLibraries":["librawfile.z.so"]}],
    #| "files":[]}
  assert_true(
    try {
      @moonohos.parse_package_manifest(manifest) |> ignore
      false
    } catch {
      @moonohos.Invalid(message) => message.contains("omits required file")
    },
  )
  let bad = manifest.replace(old="librawfile.z.so", new="libssl.so")
  assert_true(
    try {
      @moonohos.parse_package_manifest(bad) |> ignore
      false
    } catch {
      @moonohos.Invalid(message) => message.contains("system library")
    },
  )
}
