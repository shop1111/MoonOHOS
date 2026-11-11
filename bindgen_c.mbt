///|
let c_helpers : String =
  #|#ifdef MOONOHOS_TARGET_OHOS
  #|// MoonBit hands over NUL-terminated UTF-8; C fields have a fixed size.
  #|static __attribute__((unused)) void moonohos_copy_text(char *dst, size_t size, const uint8_t *src) {
  #|  size_t n = strlen((const char *)src);
  #|  if (n >= size) n = size - 1;
  #|  memcpy(dst, src, n);
  #|  dst[n] = 0;
  #|}
  #|// Copies at most `limit` chars of `src` into a MoonBit buffer, NUL-terminated.
  #|static __attribute__((unused)) void moonohos_export_text(uint8_t *dst, size_t capacity, const char *src, size_t limit) {
  #|  size_t n = 0;
  #|  if (src) { while (n < limit && n + 1 < capacity && src[n]) n++; memcpy(dst, src, n); }
  #|  dst[n] = 0;
  #|}
  #|#endif
  #|

///|
fn Generator::struct_spelling(self : Generator, record : String) -> String {
  match self.model.records.get(record) {
    Some(def) => def.spelling
    None => "struct " + record
  }
}

///|
/// C statements filling slot struct `slot` from the parameters of `prefix`.
fn Generator::c_struct_in(
  self : Generator,
  prefix : String,
  record : String,
  from_buffers : Bool,
  pre : Array[String],
) -> String {
  let slot = "s_" + prefix
  pre.push(self.struct_spelling(record) + " " + slot + ";")
  pre.push("memset(&" + slot + ", 0, sizeof " + slot + ");")
  match self.fields(record) {
    Some(fields) =>
      for field in fields {
        match field {
          FScalar(c, m, _) => {
            let source = prefix +
              "_" +
              m +
              (if from_buffers { "[0]" } else { "" })
            pre.push(slot + "." + c + " = " + source + ";")
          }
          FText(c, m, _) =>
            pre.push(
              "moonohos_copy_text(" +
              slot +
              "." +
              c +
              ", sizeof " +
              slot +
              "." +
              c +
              ", " +
              prefix +
              "_" +
              m +
              ");",
            )
          FBytes(c, m, _) =>
            pre.push(
              "memcpy(" +
              slot +
              "." +
              c +
              ", " +
              prefix +
              "_" +
              m +
              ", sizeof " +
              slot +
              "." +
              c +
              ");",
            )
        }
      }
    None => ()
  }
  slot
}

///|
/// C statements copying struct `slot` back into the buffers of `prefix`.
fn Generator::c_struct_out(
  self : Generator,
  prefix : String,
  record : String,
  slot : String,
  post : Array[String],
) -> Unit {
  match self.fields(record) {
    Some(fields) =>
      for field in fields {
        match field {
          FScalar(c, m, kind) =>
            post.push(
              prefix +
              "_" +
              m +
              "[0] = (" +
              c_scalar(kind) +
              ")" +
              slot +
              "." +
              c +
              ";",
            )
          FText(c, m, n) =>
            post.push(
              "moonohos_export_text(" +
              prefix +
              "_" +
              m +
              ", " +
              (n + 1).to_string() +
              ", " +
              slot +
              "." +
              c +
              ", sizeof " +
              slot +
              "." +
              c +
              ");",
            )
          FBytes(c, m, _) =>
            post.push(
              "memcpy(" +
              prefix +
              "_" +
              m +
              ", " +
              slot +
              "." +
              c +
              ", sizeof " +
              slot +
              "." +
              c +
              ");",
            )
        }
      }
    None => ()
  }
}

///|
fn array_maker(kind : Scalar) -> String {
  match kind {
    SFloat => "moonbit_make_float_array_raw"
    SDouble => "moonbit_make_double_array_raw"
    SInt64 | SUInt64 => "moonbit_make_int64_array_raw"
    _ => "moonbit_make_int32_array_raw"
  }
}

///|
/// Finalizer-side release for an owned handle: frees the callbacks keyed by
/// it, then calls the paired Destroy function.
fn Generator::destroy_helper(self : Generator, record : String) -> String {
  match self.handles.get(record) {
    Some(Some(_)) => "moonohos_sys_destroy_" + record
    _ => "NULL"
  }
}

///|
fn Generator::c_function(self : Generator, binding : Binding) -> String {
  let lowered = self.lower(binding)
  let c_name = binding.function.name
  let object = self.object_type(binding)
  let c_result = match object {
    Some(_) => "void *"
    None =>
      match binding.result {
        RValue(kind, _) => c_scalar(kind)
        RCheck(_) => "int32_t"
        _ => "void"
      }
  }
  let pre : Array[String] = []
  let post : Array[String] = []
  let args : Array[String] = []
  let consumed : Array[String] = []
  let mut callback : (String, String)? = None
  for param in binding.params {
    match param {
      InValue(name, _, spelling) => args.push("(" + spelling + ")" + name)
      InString(name) => args.push("(const char *)" + name)
      InBytes(name, pointer, length) => {
        args.push("(" + pointer + ")" + name)
        args.push("(" + length + ")" + name + "_length")
      }
      OutValue(name, kind, pointee) => {
        pre.push(pointee + " o_" + name + " = 0;")
        args.push("&o_" + name)
        post.push(name + "[0] = (" + c_scalar(kind) + ")o_" + name + ";")
      }
      OutString(name, length, by_pointer) => {
        if by_pointer {
          pre.push(
            length +
            " " +
            name +
            "_length = (" +
            length +
            ")(" +
            name +
            "_capacity - 1);",
          )
          args.push("(char *)" + name)
          args.push("&" + name + "_length")
          post.push(
            "if ((int64_t)" +
            name +
            "_length >= 0 && (int64_t)" +
            name +
            "_length < " +
            name +
            "_capacity) " +
            name +
            "[" +
            name +
            "_length] = 0;",
          )
        } else {
          args.push("(char *)" + name)
          args.push("(" + length + ")(" + name + "_capacity - 1)")
        }
        post.push(name + "[" + name + "_capacity - 1] = 0;")
      }
      InStruct(name, record, by_pointer) => {
        let slot = self.c_struct_in(name, record, false, pre)
        args.push(if by_pointer { "&" + slot } else { slot })
      }
      InOutStruct(name, record) | OutStruct(name, record) => {
        let slot = self.c_struct_in(name, record, true, pre)
        args.push("&" + slot)
        self.c_struct_out(name, record, slot, post)
      }
      InHandle(name, record, destroys, spelling) => {
        pre.push(
          "void *p_" + name + " = ((moonohos_sys_handle *)" + name + ")->ptr;",
        )
        args.push("(" + spelling + ")p_" + name)
        if destroys {
          for site in self.handle_sites.get(record).unwrap_or([]) {
            pre.push(
              "moonohos_release_key_" +
              site +
              "((int64_t)(intptr_t)p_" +
              name +
              ");",
            )
          }
          consumed.push(name)
        }
      }
      OutHandle(name, record, pointee) => {
        pre.push(pointee + " o_" + name + " = NULL;")
        args.push("&o_" + name)
        post.push(
          "object = moonohos_sys_wrap((void *)o_" +
          name +
          ", " +
          self.destroy_helper(record) +
          ");",
        )
      }
      OutArray(name, element, element_spelling, length_spelling) => {
        pre.push(element_spelling + " *o_" + name + " = NULL;")
        pre.push(length_spelling + " o_" + name + "_length = 0;")
        args.push("&o_" + name)
        args.push("&o_" + name + "_length")
        post.push(
          "object = " +
          array_maker(element) +
          "((int32_t)o_" +
          name +
          "_length);",
        )
        post.push(
          "if (o_" +
          name +
          " && o_" +
          name +
          "_length) memcpy(object, o_" +
          name +
          ", (size_t)o_" +
          name +
          "_length * sizeof *o_" +
          name +
          ");",
        )
      }
      InCallback(name, site, _, spelling) => {
        let slot = "moonohos_slots_" + site + "[" + name + "_slot]"
        pre.push(slot + ".tramp = " + name + "_tramp;")
        pre.push(slot + ".closure = " + name + ";")
        pre.push("moonbit_incref(" + name + ");")
        args.push(
          "(" + spelling + ")moonohos_cbs_" + site + "[" + name + "_slot]",
        )
        callback = Some((name, site))
      }
    }
  }
  let call = c_name + "(" + args.join(", ") + ")"
  let body : Array[String] = []
  if object is Some(_) {
    body.push("void *object = NULL;")
  }
  for statement in pre {
    body.push(statement)
  }
  let ok = match binding.result {
    RCheck(_) => "r == 0"
    RValue(_, _) if binding.key is Some(KeyResult) => "r >= 0"
    RValue(_, _) => "r == 0"
    _ => "1"
  }
  let finals : Array[String] = []
  match binding.result {
    RVoid => body.push(call + ";")
    RValue(kind, spelling) => {
      body.push(spelling + " r = " + call + ";")
      if object is Some(_) {
        post.push("result_slot[0] = (" + c_scalar(kind) + ")r;")
      } else {
        finals.push("return (" + c_scalar(kind) + ")r;")
      }
    }
    RCheck(_) => {
      body.push("int32_t r = (int32_t)" + call + ";")
      if object is Some(_) {
        post.push("result_slot[0] = r;")
      } else {
        finals.push("return r;")
      }
    }
    RStruct(record) => {
      body.push(self.struct_spelling(record) + " r = " + call + ";")
      self.c_struct_out("result", record, "r", post)
    }
    RCString => {
      body.push("const char *r = " + call + ";")
      post.insert(
        0, "moonohos_export_text(result_text, (size_t)result_capacity, r, (size_t)result_capacity);",
      )
    }
    RHandle(record, owned) => {
      body.push(binding.function.result_spelling + " r = " + call + ";")
      post.push(
        "object = moonohos_sys_wrap((void *)r, " +
        (if owned { self.destroy_helper(record) } else { "NULL" }) +
        ");",
      )
    }
  }
  match callback {
    Some((name, site)) => {
      let key = match binding.key {
        Some(KeyOut(out)) =>
          "moonohos_slots_" +
          site +
          "[" +
          name +
          "_slot].key = (int64_t)o_" +
          out +
          ";"
        Some(KeyResult) =>
          "moonohos_slots_" + site + "[" + name + "_slot].key = (int64_t)r;"
        Some(KeyHandle(owner, _)) =>
          "moonohos_rekey_" +
          site +
          "(" +
          name +
          "_slot, (int64_t)(intptr_t)p_" +
          owner +
          ");"
        None => ""
      }
      post.push(
        "if (!(" +
        ok +
        ")) moonohos_release_slot_" +
        site +
        "(" +
        name +
        "_slot); else { " +
        key +
        " }",
      )
    }
    None => ()
  }
  for name in consumed {
    post.push(
      "if (" + ok + ") ((moonohos_sys_handle *)" + name + ")->ptr = NULL;",
    )
  }
  match binding.release {
    Some((site, param)) =>
      post.push(
        "if (" +
        ok +
        ") moonohos_release_key_" +
        site +
        "((int64_t)" +
        param +
        ");",
      )
    None => ()
  }
  for statement in post {
    body.push(statement)
  }
  if object is Some(_) {
    finals.push("return object;")
  }
  for statement in finals {
    body.push(statement)
  }
  let host : Array[String] = lowered.c_params.map(p => {
    let words = p.replace_all(old="*", new=" ").split(" ").to_array()
    "(void)" + words[words.length() - 1].to_owned() + ";"
  })
  // On the host no SDK is called: zero values, 801 (not supported) for
  // error codes, dead handles and empty arrays.
  let host_code = match binding.result {
    RCheck(_) => "801"
    _ => "0"
  }
  match object {
    Some(_) => {
      match binding.result {
        RCheck(_) | RValue(_, _) =>
          host.push("result_slot[0] = " + host_code + ";")
        _ => ()
      }
      let empty = binding.params.search_by(p => p is OutArray(_, _, _, _))
      match empty {
        Some(index) =>
          match binding.params[index] {
            OutArray(_, element, _, _) =>
              host.push("return " + array_maker(element) + "(0);")
            _ => ()
          }
        None => host.push("return moonohos_sys_wrap(NULL, NULL);")
      }
    }
    None =>
      match binding.result {
        RValue(_, _) | RCheck(_) => host.push("return " + host_code + ";")
        _ => ()
      }
  }
  let lines : Array[String] = [
    c_result +
    " moonohos_sys_" +
    c_name +
    "(" +
    (if lowered.c_params.is_empty() {
      "void"
    } else {
      lowered.c_params.join(", ")
    }) +
    ") {",
    "#ifdef MOONOHOS_TARGET_OHOS",
  ]
  for statement in body {
    lines.push("  " + statement)
  }
  lines.push("#else")
  for statement in host {
    lines.push("  " + statement)
  }
  lines.push("#endif")
  lines.push("}")
  lines.join("\n") + "\n"
}

///|
let c_handle_runtime : String =
  #|// Handles are MoonBit external objects: the payload holds the SDK pointer
  #|// and, for owned handles, the function that releases it. The finalizer
  #|// runs when MoonBit drops the last reference.
  #|typedef struct { void *ptr; void (*destroy)(void *); } moonohos_sys_handle;
  #|static void moonohos_sys_finalize(void *self) {
  #|  moonohos_sys_handle *handle = (moonohos_sys_handle *)self;
  #|  void *ptr = handle->ptr;
  #|  handle->ptr = NULL;
  #|  if (ptr && handle->destroy) handle->destroy(ptr);
  #|}
  #|static MOONOHOS_UNUSED void *moonohos_sys_wrap(void *ptr, void (*destroy)(void *)) {
  #|  moonohos_sys_handle *handle = (moonohos_sys_handle *)moonbit_make_external_object(moonohos_sys_finalize, sizeof(moonohos_sys_handle));
  #|  handle->ptr = ptr;
  #|  handle->destroy = destroy;
  #|  return handle;
  #|}
  #|

///|
let c_gate : String =
  #|#ifdef MOONOHOS_TARGET_OHOS
  #|// Exported by the MoonOHOS bridge: SDK threads enter the MoonBit gate
  #|// before running MoonBit callbacks (re-entrant on the owning thread).
  #|extern void moonohos_gate_enter(void) __attribute__((weak));
  #|extern void moonohos_gate_leave(void) __attribute__((weak));
  #|static void moonohos_enter(void) { if (moonohos_gate_enter) moonohos_gate_enter(); }
  #|static void moonohos_leave(void) { if (moonohos_gate_leave) moonohos_gate_leave(); }
  #|static MOONOHOS_UNUSED moonbit_bytes_t moonohos_sys_bytes(const char *text) {
  #|  size_t n = text ? strlen(text) : 0;
  #|  moonbit_bytes_t bytes = moonbit_make_bytes_raw((int32_t)(n + 1));
  #|  if (n) memcpy(bytes, text, n);
  #|  bytes[n] = 0;
  #|  return bytes;
  #|}
  #|#endif
  #|

///|
/// Eight C trampolines per callback site: the SDK callbacks carry no user
/// data, so the trampoline itself identifies the stored MoonBit closure.
fn Generator::site_source(
  self : Generator,
  site : String,
  args : Array[CbArg],
) -> String {
  ignore(self)
  let boundary = args.map(arg => {
    match arg {
      CbScalar(kind, _) => c_scalar(kind)
      CbHandle(_, _) => "void *"
      CbText(_) => "moonbit_bytes_t"
    }
  })
  let spelled = args.mapi((j, arg) => {
    let spelling = match arg {
      CbScalar(_, s) | CbHandle(_, s) | CbText(s) => s
    }
    spelling + " a" + j.to_string()
  })
  let names = args.mapi((j, _) => "a" + j.to_string())
  let tramp_params = ["void *closure"]
  for item in boundary {
    tramp_params.push(item)
  }
  let slots = "moonohos_slots_" + site
  let lines = [
    "typedef void (*moonohos_tramp_" +
    site +
    ")(" +
    tramp_params.join(", ") +
    ");",
    "static struct { moonohos_tramp_" +
    site +
    " tramp; void *closure; int64_t key; } " +
    slots +
    "[8];",
    "int32_t moonohos_sys_slot_" + site + "(void) {",
    "  for (int32_t i = 0; i < 8; i++) if (!" + slots + "[i].closure) return i;",
    "  return -1;",
    "}",
    "static MOONOHOS_UNUSED void moonohos_release_slot_" +
    site +
    "(int32_t i) {",
    "  void *closure = " + slots + "[i].closure;",
    "  " + slots + "[i].closure = NULL;",
    "  if (closure) moonbit_decref(closure);",
    "}",
    "static MOONOHOS_UNUSED void moonohos_release_key_" +
    site +
    "(int64_t key) {",
    "  for (int32_t i = 0; i < 8; i++) if (" +
    slots +
    "[i].closure && " +
    slots +
    "[i].key == key) moonohos_release_slot_" +
    site +
    "(i);",
    "}",
    "static MOONOHOS_UNUSED void moonohos_rekey_" +
    site +
    "(int32_t slot, int64_t key) {",
    "  for (int32_t i = 0; i < 8; i++) if (i != slot && " +
    slots +
    "[i].closure && " +
    slots +
    "[i].key == key) moonohos_release_slot_" +
    site +
    "(i);",
    "  " + slots + "[slot].key = key;",
    "}",
    "#ifdef MOONOHOS_TARGET_OHOS",
    "static void moonohos_fire_" +
    site +
    "(" +
    (["int32_t i"] + spelled).join(", ") +
    ") {",
    "  moonohos_enter();",
    "  if (" + slots + "[i].closure) {",
    "    void *closure = " + slots + "[i].closure;",
  ]
  let call_args = ["closure"]
  let after : Array[String] = []
  for j, arg in args {
    let a = "a" + j.to_string()
    match arg {
      CbScalar(kind, _) => call_args.push("(" + c_scalar(kind) + ")" + a)
      CbHandle(_, _) => {
        lines.push(
          "    void *h" +
          j.to_string() +
          " = moonohos_sys_wrap((void *)" +
          a +
          ", NULL);",
        )
        lines.push("    moonbit_incref(h" + j.to_string() + ");")
        call_args.push("h" + j.to_string())
        // The SDK owns the object; it must not outlive the callback.
        after.push(
          "    ((moonohos_sys_handle *)h" + j.to_string() + ")->ptr = NULL;",
        )
        after.push("    moonbit_decref(h" + j.to_string() + ");")
      }
      CbText(_) => {
        lines.push(
          "    moonbit_bytes_t t" +
          j.to_string() +
          " = moonohos_sys_bytes(" +
          a +
          ");",
        )
        call_args.push("t" + j.to_string())
      }
    }
  }
  lines.push("    moonbit_incref(closure);")
  lines.push("    " + slots + "[i].tramp(" + call_args.join(", ") + ");")
  for statement in after {
    lines.push(statement)
  }
  lines.push("  }")
  lines.push("  moonohos_leave();")
  lines.push("}")
  let params = if spelled.is_empty() { "void" } else { spelled.join(", ") }
  let entries : Array[String] = []
  for i in 0..<8 {
    let fn_name = "moonohos_cb_" + site + "_" + i.to_string()
    lines.push(
      "static void " +
      fn_name +
      "(" +
      params +
      ") { moonohos_fire_" +
      site +
      "(" +
      ([i.to_string()] + names).join(", ") +
      "); }",
    )
    entries.push(fn_name)
  }
  lines.push(
    "static void (*const moonohos_cbs_" +
    site +
    "[8])(" +
    params +
    ") = { " +
    entries.join(", ") +
    " };",
  )
  lines.push("#endif")
  lines.join("\n") + "\n"
}

///|
/// C accessors behind the generated `T::field` methods.
fn Generator::getter_source(self : Generator, record : String) -> String {
  let spelling = self.struct_spelling(record)
  let parts : Array[String] = []
  for field in self.readable_fields(record) {
    let read = "  " +
      spelling +
      " *p = (" +
      spelling +
      " *)((moonohos_sys_handle *)handle)->ptr;"
    match field {
      FScalar(c, _, kind) =>
        parts.push(
          c_scalar(kind) +
          " moonohos_sys_get_" +
          record +
          "_" +
          c +
          "(void *handle) {\n#ifdef MOONOHOS_TARGET_OHOS\n" +
          read +
          "\n  return p ? (" +
          c_scalar(kind) +
          ")p->" +
          c +
          " : 0;\n#else\n  (void)handle;\n  return 0;\n#endif\n}\n",
        )
      FText(c, _, n) =>
        parts.push(
          "void moonohos_sys_get_" +
          record +
          "_" +
          c +
          "(void *handle, uint8_t *buffer) {\n#ifdef MOONOHOS_TARGET_OHOS\n" +
          read +
          "\n  if (p) moonohos_export_text(buffer, " +
          (n + 1).to_string() +
          ", p->" +
          c +
          ", sizeof p->" +
          c +
          ");\n#else\n  (void)handle;\n  (void)buffer;\n#endif\n}\n",
        )
      FBytes(c, _, _) =>
        parts.push(
          "void moonohos_sys_get_" +
          record +
          "_" +
          c +
          "(void *handle, uint8_t *buffer) {\n#ifdef MOONOHOS_TARGET_OHOS\n" +
          read +
          "\n  if (p) memcpy(buffer, p->" +
          c +
          ", sizeof p->" +
          c +
          ");\n#else\n  (void)handle;\n  (void)buffer;\n#endif\n}\n",
        )
    }
  }
  parts.join("\n")
}

///|
fn Generator::c_source(self : Generator, bindings : Array[Binding]) -> String {
  let parts : Array[String] = [
    "// Generated by `moonohos bindgen`. Do not edit; regenerate instead.\n" +
    "// On the host (no MOONOHOS_TARGET_OHOS) functions return 0 values,\n" +
    "// error-code functions return 801 (not supported), handles are dead.\n" +
    "#include <stdbool.h>\n#include <stddef.h>\n#include <stdint.h>\n#include <string.h>\n" +
    "#include \"moonbit.h\"\n" +
    "#if defined(__GNUC__) || defined(__clang__)\n#define MOONOHOS_UNUSED __attribute__((unused))\n#else\n#define MOONOHOS_UNUSED\n#endif\n" +
    "#ifdef MOONOHOS_TARGET_OHOS\n" +
    self.spec.headers.map(h => "#include <" + h + ">").join("\n") +
    "\n#endif\n",
    c_helpers,
  ]
  let handles = self.handles_used.keys().collect()
  handles.sort()
  if !handles.is_empty() {
    parts.push(c_handle_runtime)
    parts.push(
      "int32_t moonohos_sys_" +
      self.spec.name +
      "_live(void *handle) {\n  return ((moonohos_sys_handle *)handle)->ptr != NULL;\n}\n",
    )
  }
  let sites = self.sites.keys().collect()
  sites.sort()
  if !sites.is_empty() {
    parts.push(c_gate)
    for site in sites {
      parts.push(self.site_source(site, self.sites.get(site).unwrap_or([])))
    }
  }
  for record in handles {
    match self.handles.get(record) {
      Some(Some(destroy)) => {
        let lines = [
          "#ifdef MOONOHOS_TARGET_OHOS",
          "static MOONOHOS_UNUSED void moonohos_sys_destroy_" +
          record +
          "(void *ptr) {",
        ]
        for site in self.handle_sites.get(record).unwrap_or([]) {
          lines.push(
            "  moonohos_release_key_" + site + "((int64_t)(intptr_t)ptr);",
          )
        }
        lines.push(
          "  (void)" +
          destroy +
          "((" +
          self.struct_spelling(record) +
          " *)ptr);",
        )
        lines.push("}")
        lines.push("#endif")
        parts.push(lines.join("\n") + "\n")
      }
      _ => ()
    }
    let getters = self.getter_source(record)
    if getters != "" {
      parts.push(getters)
    }
  }
  for binding in bindings {
    parts.push(self.c_function(binding))
  }
  parts.join("\n")
}

///|
fn bindings_report(
  spec : BindgenSpec,
  bindings : Array[Binding],
  skipped : Array[(String, String)],
  libraries : Array[String],
  sdk_api : Int32,
  gen : Generator,
) -> String {
  let lines : Array[String] = [
    "# " + spec.package_name,
    "",
    "Generated by `moonohos bindgen` from HarmonyOS SDK API " +
    sdk_api.to_string() +
    " headers: " +
    spec.headers.map(h => "`" + h + "`").join(", ") +
    ".",
    "",
    "Libraries: " + libraries.map(l => "`" + l + "`").join(", ") + ".",
    "",
    "Bound: " +
    bindings.length().to_string() +
    ", skipped: " +
    skipped.length().to_string() +
    ".",
    "",
    "| C function | MoonBit |",
    "|---|---|",
  ]
  for binding in bindings {
    let signature = gen.moon_function(binding)
    let declaration = match signature.find("pub fn ") {
      Some(index) => {
        let rest = signature[index + 7:].to_owned()
        match rest.find(" {") {
          Some(end) => rest[:end].to_owned()
          None => rest
        }
      }
      None => binding.moon_name
    }
    lines.push(
      "| `" +
      binding.function.name +
      "` | `" +
      declaration.replace_all(old="|", new="\\|") +
      "` |",
    )
  }
  if !skipped.is_empty() {
    lines.push("")
    lines.push("## Skipped")
    lines.push("")
    lines.push("| C function | Reason |")
    lines.push("|---|---|")
    for item in skipped {
      lines.push("| `" + item.0 + "` | " + item.1 + " |")
    }
  }
  lines.join("\n") + "\n"
}
