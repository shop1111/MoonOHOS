///|
/// A trimmed clang JSON AST: one header with an anonymous error enum, a
/// named enum, a flat struct, an opaque struct and one function per shape.
let sample_ast : String =
  #|{"kind":"TranslationUnitDecl","inner":[
  #| {"id":"t1","kind":"TypedefDecl","loc":{"file":"C:/sdk/sysroot/usr/include/stdint.h"},"name":"int32_t","type":{"qualType":"int"}},
  #| {"id":"t2","kind":"TypedefDecl","name":"uint64_t","type":{"qualType":"unsigned long"}},
  #| {"id":"e1","kind":"EnumDecl","loc":{"file":"C:/sdk/sysroot/usr/include/demo/demo.h"},"inner":[
  #|   {"kind":"EnumConstantDecl","name":"DEMO_OK","type":{"qualType":"int"}},
  #|   {"kind":"EnumConstantDecl","name":"DEMO_ERR_PERMISSION","type":{"qualType":"int"},"inner":[{"kind":"ConstantExpr","value":"201"}]},
  #|   {"kind":"EnumConstantDecl","name":"DEMO_ERR_NEXT","type":{"qualType":"int"}}]},
  #| {"id":"t3","kind":"TypedefDecl","name":"Demo_ErrCode","type":{"desugaredQualType":"Demo_ErrCode","qualType":"enum Demo_ErrCode"},
  #|   "inner":[{"kind":"ElaboratedType","ownedTagDecl":{"id":"e1","kind":"EnumDecl","name":""}}]},
  #| {"id":"e2","kind":"EnumDecl","name":"Demo_Mode","inner":[
  #|   {"kind":"EnumConstantDecl","name":"MODE_A","type":{"qualType":"int"}},
  #|   {"kind":"EnumConstantDecl","name":"MODE_B","type":{"qualType":"int"},"inner":[{"kind":"ConstantExpr","value":"4294967295"}]}]},
  #| {"id":"r1","kind":"RecordDecl","name":"Demo_Info","tagUsed":"struct","completeDefinition":true,"inner":[
  #|   {"kind":"FieldDecl","name":"deviceId","type":{"desugaredQualType":"int","qualType":"int32_t"}},
  #|   {"kind":"FieldDecl","name":"label","type":{"qualType":"char[16]"}},
  #|   {"kind":"FieldDecl","name":"mode","type":{"qualType":"enum Demo_Mode"}}]},
  #| {"id":"t4","kind":"TypedefDecl","name":"DemoInfo","type":{"qualType":"struct Demo_Info"}},
  #| {"id":"r2","kind":"RecordDecl","name":"Demo_Handle","tagUsed":"struct"},
  #| {"id":"f1","kind":"FunctionDecl","name":"OH_Demo_GetLevel","type":{"qualType":"int32_t (void)"}},
  #| {"id":"f2","kind":"FunctionDecl","name":"OH_Demo_GetSize","type":{"qualType":"Demo_ErrCode (int32_t *, float *)"},"inner":[
  #|   {"kind":"ParmVarDecl","name":"width","type":{"desugaredQualType":"int *","qualType":"int32_t *"}},
  #|   {"kind":"ParmVarDecl","name":"scale","type":{"qualType":"float *"}}]},
  #| {"id":"f3","kind":"FunctionDecl","name":"OH_Demo_GetName","type":{"qualType":"Demo_ErrCode (char *, unsigned int)"},"inner":[
  #|   {"kind":"ParmVarDecl","name":"buffer","type":{"qualType":"char *"}},
  #|   {"kind":"ParmVarDecl","name":"size","type":{"qualType":"unsigned int"}}]},
  #| {"id":"f4","kind":"FunctionDecl","name":"OH_Demo_HasCapability","type":{"qualType":"_Bool (const char *)"},"inner":[
  #|   {"kind":"ParmVarDecl","name":"cap","type":{"qualType":"const char *"}}]},
  #| {"id":"f5","kind":"FunctionDecl","name":"OH_Demo_Describe","type":{"qualType":"void (const DemoInfo *, enum Demo_Mode)"},"inner":[
  #|   {"kind":"ParmVarDecl","name":"info","type":{"desugaredQualType":"const struct Demo_Info *","qualType":"const DemoInfo *"}},
  #|   {"kind":"ParmVarDecl","name":"mode","type":{"qualType":"enum Demo_Mode"}}]},
  #| {"id":"f6","kind":"FunctionDecl","name":"OH_Demo_Current","type":{"qualType":"DemoInfo (void)"}},
  #| {"id":"f7","kind":"FunctionDecl","name":"OH_Demo_Version","type":{"qualType":"const char *(void)"}},
  #| {"id":"f8","kind":"FunctionDecl","name":"OH_Demo_Listen","type":{"qualType":"int (void (*)(int))"},"inner":[
  #|   {"kind":"ParmVarDecl","name":"callback","type":{"qualType":"void (*)(int)"}}]},
  #| {"id":"f9","kind":"FunctionDecl","name":"OH_Demo_Open","type":{"qualType":"int (struct Demo_Handle **)"},"inner":[
  #|   {"kind":"ParmVarDecl","name":"handle","type":{"qualType":"struct Demo_Handle **"}}]},
  #| {"id":"f10","kind":"FunctionDecl","name":"OH_Demo_Log","variadic":true,"type":{"qualType":"void (const char *, ...)"},"inner":[
  #|   {"kind":"ParmVarDecl","name":"fmt","type":{"qualType":"const char *"}}]},
  #| {"id":"f11","kind":"FunctionDecl","name":"OH_Demo_Missing","type":{"qualType":"int (void)"}},
  #| {"id":"f13","kind":"FunctionDecl","name":"OH_Demo_DestroyHandle","type":{"qualType":"int (struct Demo_Handle *)"},"inner":[
  #|   {"kind":"ParmVarDecl","name":"handle","type":{"qualType":"struct Demo_Handle *"}}]},
  #| {"id":"f14","kind":"FunctionDecl","name":"OH_Demo_HandleLevel","type":{"qualType":"int (const struct Demo_Handle *)"},"inner":[
  #|   {"kind":"ParmVarDecl","name":"handle","type":{"qualType":"const struct Demo_Handle *"}}]},
  #| {"id":"f15","kind":"FunctionDecl","name":"OH_Demo_RegisterListener","type":{"qualType":"Demo_ErrCode (void (*)(uint64_t, struct Demo_Handle *), uint32_t *)"},"inner":[
  #|   {"kind":"ParmVarDecl","name":"callback","type":{"desugaredQualType":"void (*)(unsigned long, struct Demo_Handle *)","qualType":"Demo_Listener"}},
  #|   {"kind":"ParmVarDecl","name":"listenerIndex","type":{"desugaredQualType":"unsigned int *","qualType":"uint32_t *"}}]},
  #| {"id":"f16","kind":"FunctionDecl","name":"OH_Demo_UnregisterListener","type":{"qualType":"Demo_ErrCode (uint32_t)"},"inner":[
  #|   {"kind":"ParmVarDecl","name":"listenerIndex","type":{"desugaredQualType":"unsigned int","qualType":"uint32_t"}}]},
  #| {"id":"f17","kind":"FunctionDecl","name":"OH_Demo_ReadSamples","type":{"qualType":"int (struct Demo_Handle *, float **, uint32_t *)"},"inner":[
  #|   {"kind":"ParmVarDecl","name":"handle","type":{"qualType":"struct Demo_Handle *"}},
  #|   {"kind":"ParmVarDecl","name":"data","type":{"qualType":"float **"}},
  #|   {"kind":"ParmVarDecl","name":"length","type":{"desugaredQualType":"unsigned int *","qualType":"uint32_t *"}}]},
  #| {"id":"f12","kind":"FunctionDecl","loc":{"file":"C:/sdk/sysroot/usr/include/unistd.h"},"name":"close","type":{"qualType":"int (int)"}}
  #|]}

///|
fn sample_output() -> @moonohos.BindgenOutput raise {
  let model = @moonohos.read_header_model(sample_ast, ["demo/demo.h"])
  let spec = @moonohos.parse_bindgen_spec(
    (
      #|{"schema":"moonohos-bindgen-v1","package":"a/sys/demo","name":"demo","headers":["demo/demo.h"],"prefixes":["OH_Demo_"],"stringBuffer":64}
    ),
  )
  let libraries : Map[String, String] = Map([])
  for function in model.functions {
    if function.name != "OH_Demo_Missing" {
      libraries[function.name] = "libdemo.so"
    }
  }
  @moonohos.generate_bindings(spec, model, libraries, 26)
}

///|
fn output_file(output : @moonohos.BindgenOutput, name : String) -> String {
  for file in output.files {
    if file.0 == name {
      return file.1
    }
  }
  ""
}

///|
test "header model resolves typedefs, anonymous enums and header scope" {
  let model = @moonohos.read_header_model(sample_ast, ["demo/demo.h"])
  // `close` comes from unistd.h and is not part of the bound header.
  assert_false(model.functions.any(f => f.name == "close"))
  assert_eq(model.functions.length(), 16)
  let errors = model.enums.get("Demo_ErrCode").unwrap()
  assert_eq(errors.constants.map(c => c.1), [0L, 201L, 202L])
  assert_eq(model.aliases.get("Demo_Info"), Some("DemoInfo"))
  assert_false(model.records.get("Demo_Handle").unwrap().complete)
  let size = model.functions
    .search_by(f => f.name == "OH_Demo_GetSize")
    .unwrap()
  let width = model.functions[size].params[0].kind
  assert_eq(width.pointers, 1)
  assert_true(width.base is CInt(32, true))
}

///|
test "functions bind by shape; unsupported shapes are reported" {
  let output = sample_output()
  assert_eq(output.bound, [
    "OH_Demo_GetLevel", "OH_Demo_GetSize", "OH_Demo_GetName", "OH_Demo_HasCapability",
    "OH_Demo_Describe", "OH_Demo_Current", "OH_Demo_Version", "OH_Demo_Open", "OH_Demo_DestroyHandle",
    "OH_Demo_HandleLevel", "OH_Demo_RegisterListener", "OH_Demo_UnregisterListener",
    "OH_Demo_ReadSamples",
  ])
  let reasons = output.skipped.map(s => s.0 + ": " + s.1)
  assert_true(
    reasons.any(r => {
      r.has_prefix("OH_Demo_Listen") &&
      r.contains("no Unregister function and no owning handle")
    }),
  )
  assert_true(
    reasons.any(r => r.has_prefix("OH_Demo_Log") && r.contains("variadic")),
  )
  assert_true(
    reasons.any(r => {
      r.has_prefix("OH_Demo_Missing") && r.contains("not exported")
    }),
  )
  assert_eq(output.libraries, ["libdemo.so"])
  let moon = output_file(output, "demo.mbt")
  // Out parameters become results; an error-code result raises SysError.
  assert_true(
    moon.contains("pub fn get_size() -> (Int, Float) raise SysError {"),
  )
  assert_true(moon.contains("pub fn get_name() -> String raise SysError {"))
  assert_true(moon.contains("pub fn has_capability(cap : String) -> Bool {"))
  assert_true(
    moon.contains(
      "pub fn describe(info : DemoInfo, mode : Demo_Mode) -> Unit {",
    ),
  )
  assert_true(moon.contains("pub fn current() -> DemoInfo {"))
  assert_true(moon.contains("pub fn version() -> String {"))
  // Enums keep unknown values; 0xFFFFFFFF is the 32-bit pattern -1.
  assert_true(moon.contains("Other(Int)"))
  assert_true(moon.contains("ModeB => (-1)"))
  assert_true(moon.contains("DemoErrPermission => 201"))
  // Structs flatten to fields; char[16] becomes a String.
  assert_true(moon.contains("pub(all) struct DemoInfo {"))
  assert_true(moon.contains("  label : String"))
  // Handles: owned when created, checked before use; arrays are copied.
  assert_true(moon.contains("pub type Demo_Handle"))
  assert_true(
    moon.contains("pub fn Demo_Handle::is_live(self : Demo_Handle) -> Bool {"),
  )
  assert_true(moon.contains("pub fn open() -> (Int, Demo_Handle) {"))
  assert_true(
    moon.contains(
      "pub fn destroy_handle(handle : Demo_Handle) -> Int raise SysError {",
    ),
  )
  assert_true(
    moon.contains("raise Closed(\"OH_Demo_HandleLevel: handle was destroyed\")"),
  )
  assert_true(
    moon.contains(
      "pub fn read_samples(handle : Demo_Handle) -> (Int, FixedArray[Float]) raise SysError {",
    ),
  )
  // Callbacks: a closure, stored in a C slot until Unregister.
  assert_true(
    moon.contains(
      "pub fn register_listener(callback : (UInt64, Demo_Handle) -> Unit) -> UInt raise SysError {",
    ),
  )
  assert_true(
    moon.contains(
      "fn(moonohos_cb, moonohos_a0, moonohos_a1) { moonohos_cb(moonohos_a0, moonohos_a1) }",
    ),
  )
  assert_true(
    moon.contains("let callback_slot = raw_slot_OH_Demo_RegisterListener_0()"),
  )
  assert_true(moon.contains("Bytes::make(64, b'\\x00')"))
}

///|
test "C stubs call the SDK only for the target and fall back on the host" {
  let output = sample_output()
  let stub = output_file(output, "demo_stub.c")
  assert_true(stub.contains("#include <demo/demo.h>"))
  assert_true(
    stub.contains(
      "int32_t moonohos_sys_OH_Demo_GetSize(int32_t *width, float *scale) {",
    ),
  )
  assert_true(
    stub.contains("int32_t r = (int32_t)OH_Demo_GetSize(&o_width, &o_scale);"),
  )
  assert_true(stub.contains("width[0] = (int32_t)o_width;"))
  assert_true(stub.contains("return 801;"))
  assert_true(
    stub.contains(
      "OH_Demo_GetName((char *)buffer, (unsigned int)(buffer_capacity - 1))",
    ),
  )
  assert_true(
    stub.contains(
      "moonohos_copy_text(s_info.label, sizeof s_info.label, info_label);",
    ),
  )
  assert_true(stub.contains("OH_Demo_Describe(&s_info, (enum Demo_Mode)mode);"))
  let descriptor = output_file(output, "moonohos.native.json")
  assert_true(descriptor.contains("\"libdemo.so\""))
  let report = output_file(output, "BINDINGS.md")
  assert_true(report.contains("Bound: 13, skipped: 3."))
  assert_true(
    stub.contains(
      "object = moonohos_sys_wrap((void *)o_handle, moonohos_sys_destroy_Demo_Handle);",
    ),
  )
  assert_true(
    stub.contains("if (r == 0) ((moonohos_sys_handle *)handle)->ptr = NULL;"),
  )
  assert_true(stub.contains("moonohos_cbs_OH_Demo_RegisterListener_0[8]"))
  assert_true(
    stub.contains(
      "moonohos_slots_OH_Demo_RegisterListener_0[callback_slot].key = (int64_t)o_listener_index;",
    ),
  )
  assert_true(
    stub.contains(
      "if (r == 0) moonohos_release_key_OH_Demo_RegisterListener_0((int64_t)listener_index);",
    ),
  )
  assert_true(
    stub.contains(
      "object = moonbit_make_float_array_raw((int32_t)o_data_length);",
    ),
  )
  // Callback handles die with the callback; SDK threads enter the gate.
  assert_true(stub.contains("((moonohos_sys_handle *)h1)->ptr = NULL;"))
  assert_true(stub.contains("moonohos_enter();"))
  assert_true(
    output_file(output, "moon.pkg").contains("moonbitlang/core/encoding/utf8"),
  )
}

///|
test "names follow MoonBit conventions" {
  assert_eq(
    @moonohos.snake_name("GetDefaultDisplayWidth"),
    "get_default_display_width",
  )
  assert_eq(@moonohos.snake_name("canIUse"), "can_i_use")
  assert_eq(@moonohos.snake_name("GetIDsByName"), "get_ids_by_name")
  assert_eq(@moonohos.snake_name("SetThreadQoS"), "set_thread_qos")
  assert_eq(@moonohos.snake_name("type"), "type_")
  assert_eq(@moonohos.snake_name("3d"), "v_3d")
}

///|
test "bindgen specs are validated" {
  for
    text in [
      "{}", "{\"schema\":\"moonohos-bindgen-v1\",\"package\":\"a/b\",\"name\":\"x\",\"headers\":[]}",
      "{\"schema\":\"moonohos-bindgen-v1\",\"package\":\"a/b\",\"name\":\"x\",\"headers\":[\"../etc\"]}",
      "{\"schema\":\"moonohos-bindgen-v1\",\"package\":\"a/b\",\"name\":\"x\",\"headers\":[\"h.h\"],\"stringBuffer\":1}",
    ] {
    let rejected = try {
      @moonohos.parse_bindgen_spec(text) |> ignore
      false
    } catch {
      Invalid(message) => message.has_prefix("bindgen:")
    }
    assert_true(rejected)
  }
}
