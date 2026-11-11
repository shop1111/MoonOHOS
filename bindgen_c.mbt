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
fn Generator::c_function(self : Generator, binding : Binding) -> String {
  let lowered = self.lower(binding)
  let c_name = binding.function.name
  let c_result = match binding.result {
    RValue(kind, _) => c_scalar(kind)
    RCheck(_) => "int32_t"
    _ => "void"
  }
  let pre : Array[String] = []
  let post : Array[String] = []
  let args : Array[String] = []
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
    }
  }
  let call = c_name + "(" + args.join(", ") + ")"
  let body : Array[String] = pre.copy()
  match binding.result {
    RVoid => body.push(call + ";")
    RValue(kind, spelling) => {
      body.push(spelling + " r = " + call + ";")
      post.push("return (" + c_scalar(kind) + ")r;")
    }
    RCheck(_) => {
      body.push("int32_t r = (int32_t)" + call + ";")
      post.push("return r;")
    }
    RStruct(record) => {
      body.push(self.struct_spelling(record) + " r = " + call + ";")
      self.c_struct_out("result", record, "r", post)
      // Struct copies go first: a later `return` must stay last.
    }
    RCString => {
      body.push("const char *r = " + call + ";")
      post.insert(
        0, "moonohos_export_text(result_text, (size_t)result_capacity, r, (size_t)result_capacity);",
      )
    }
  }
  // Keep a trailing `return` after the copy-outs.
  let returns = post.filter(s => s.has_prefix("return "))
  for statement in post {
    if !statement.has_prefix("return ") {
      body.push(statement)
    }
  }
  for statement in returns {
    body.push(statement)
  }
  let host : Array[String] = lowered.c_params.map(p => {
    let words = p.replace_all(old="*", new=" ").split(" ").to_array()
    "(void)" + words[words.length() - 1].to_owned() + ";"
  })
  match binding.result {
    RValue(_, _) => host.push("return 0;")
    // 801: capability not supported (HarmonyOS convention), on the host.
    RCheck(_) => host.push("return 801;")
    _ => ()
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
fn Generator::c_source(self : Generator, bindings : Array[Binding]) -> String {
  let parts : Array[String] = [
    "// Generated by `moonohos bindgen`. Do not edit; regenerate instead.\n" +
    "// On the host (no MOONOHOS_TARGET_OHOS) functions return 0 values, and\n" +
    "// error-code functions return 801 (not supported).\n" +
    "#include <stdbool.h>\n#include <stddef.h>\n#include <stdint.h>\n#include <string.h>\n" +
    "#ifdef MOONOHOS_TARGET_OHOS\n" +
    self.spec.headers.map(h => "#include <" + h + ">").join("\n") +
    "\n#endif\n",
    c_helpers,
  ]
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
