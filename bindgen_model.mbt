// System API bindings (0.8): reads the declarations of HarmonyOS NDK headers
// from clang's JSON AST (`clang -Xclang -ast-dump=json`, run by the CLI with the
// SDK's own compiler), so C types come from the compiler rather than from a
// hand-written C parser.

///|
/// Base of a C type after typedefs are resolved.
#derive(Eq, Debug)
pub(all) enum CBase {
  CVoid
  CBool
  /// Plain `char` (string data; signedness differs between ABIs).
  CChar
  /// Integer of `bits` (8, 16, 32 or 64; LP64 `long` is 64), signed or not.
  CInt(Int32, Bool)
  CFloat
  CDouble
  /// Enum by MoonBit-visible name (tag name, or typedef name if anonymous).
  CEnum(String)
  /// Struct by name (tag name, or typedef name if anonymous).
  CRecord(String)
  /// Anything the generator does not bind; the text says what it was.
  CUnsupported(String)
}

///|
#derive(Eq, Debug)
pub(all) struct CType {
  base : CBase
  /// Number of `*` levels.
  pointers : Int32
  /// `const` applies to the pointee (`const char *`).
  const_pointee : Bool
  /// Fixed array length of a struct field (`char name[33]`).
  array : Int32?
}

///|
pub(all) struct CEnumDef {
  name : String
  constants : Array[(String, Int64)]
}

///|
pub(all) struct CField {
  name : String
  kind : CType
  /// Spelling as written in the header (`QoS_Level *`), used for casts.
  spelling : String
}

///|
pub(all) struct CRecordDef {
  name : String
  /// How C code spells the type: `struct Tag` or the typedef name.
  spelling : String
  /// False for opaque (forward-declared) structs.
  complete : Bool
  fields : Array[CField]
}

///|
pub(all) struct CFunction {
  name : String
  result : CType
  result_spelling : String
  params : Array[CField]
  variadic : Bool
  /// Header the declaration comes from, relative to `usr/include`.
  header : String
}

///|
pub(all) struct CHeaderModel {
  functions : Array[CFunction]
  enums : Map[String, CEnumDef]
  records : Map[String, CRecordDef]
  /// Tag name -> typedef name (`HiTraceIdStruct` -> `HiTraceId`), used to
  /// name generated MoonBit types after the spelling the SDK documents.
  aliases : Map[String, String]
}

///|
fn json_text(value : Json?, key : String) -> String? {
  match value {
    Some(Object(fields)) =>
      match fields.get(key) {
        Some(String(text)) => Some(text)
        _ => None
      }
    _ => None
  }
}

///|
fn json_field(value : Json, key : String) -> Json? {
  match value {
    Object(fields) => fields.get(key)
    _ => None
  }
}

///|
fn json_children(value : Json) -> Array[Json] {
  match json_field(value, "inner") {
    Some(Array(items)) => items
    _ => []
  }
}

///|
/// The file a top-level declaration was written in, when clang records it
/// (it omits the file when it equals the previous declaration's).
fn decl_file(node : Json) -> String? {
  let loc = json_field(node, "loc")
  match json_text(loc, "file") {
    Some(file) => Some(file)
    None =>
      match loc {
        Some(l) =>
          match json_text(json_field(l, "spellingLoc"), "file") {
            Some(file) => Some(file)
            None => json_text(json_field(l, "expansionLoc"), "file")
          }
        None => None
      }
  }
}

///|
/// `include/` relative path of `file`, with `\` normalised to `/`.
fn include_relative(file : String) -> String? {
  let path = file.replace_all(old="\\", new="/")
  match path.find("/usr/include/") {
    Some(index) => Some(path[index + 13:].to_owned())
    None => None
  }
}

///|
fn type_text(node : Json) -> String {
  let kind = json_field(node, "type")
  match json_text(kind, "desugaredQualType") {
    Some(text) => text
    None => json_text(kind, "qualType").unwrap_or("")
  }
}

///|
/// Sugared spelling (`int32_t`, `Vibrator_Usage`), used to recognise typedef
/// names of anonymous enums and structs.
fn sugared_text(node : Json) -> String {
  json_text(json_field(node, "type"), "qualType").unwrap_or("")
}

///|
priv struct Resolver {
  /// Typedef name -> desugared type text.
  typedefs : Map[String, String]
  /// Typedef name of an anonymous enum or struct -> `enum`/`struct`.
  anonymous : Map[String, String]
}

///|
fn word_list(text : String) -> Array[String] {
  let words : Array[String] = []
  let current = StringBuilder()
  for ch in text {
    if ch == ' ' || ch == '\t' {
      if current.to_string() != "" {
        words.push(current.to_string())
        current.reset()
      }
    } else {
      current.write_char(ch)
    }
  }
  if current.to_string() != "" {
    words.push(current.to_string())
  }
  words
}

///|
fn Resolver::base(
  self : Resolver,
  words : Array[String],
  depth : Int32,
) -> CBase {
  let core = words.filter(w => w != "const" && w != "volatile")
  match core {
    ["void"] => CVoid
    ["_Bool"] | ["bool"] => CBool
    ["char"] => CChar
    ["signed", "char"] => CInt(8, true)
    ["unsigned", "char"] => CInt(8, false)
    ["short"] | ["short", "int"] | ["signed", "short"] => CInt(16, true)
    ["unsigned", "short"] | ["unsigned", "short", "int"] => CInt(16, false)
    ["int"] | ["signed"] | ["signed", "int"] => CInt(32, true)
    ["unsigned"] | ["unsigned", "int"] => CInt(32, false)
    ["long"] | ["long", "int"] | ["long", "long"] | ["long", "long", "int"] =>
      CInt(64, true)
    ["unsigned", "long"]
    | ["unsigned", "long", "int"]
    | ["unsigned", "long", "long"]
    | ["unsigned", "long", "long", "int"] => CInt(64, false)
    ["float"] => CFloat
    ["double"] => CDouble
    ["enum", name] => CEnum(name)
    ["struct", name] => CRecord(name)
    [name] if depth < 8 =>
      match self.anonymous.get(name) {
        Some("enum") => CEnum(name)
        Some(_) => CRecord(name)
        None =>
          match self.typedefs.get(name) {
            Some(text) if text != name => {
              let inner = self.resolve(text, depth + 1)
              if inner.pointers == 0 && inner.array is None {
                inner.base
              } else {
                CUnsupported(name + " (pointer typedef)")
              }
            }
            _ => CUnsupported(name)
          }
      }
    _ => CUnsupported(words.join(" "))
  }
}

///|
/// Parses a clang type spelling such as `const char *restrict`, `char[33]`,
/// `enum QoS_Level *` or `void (*)(bool)`.
fn Resolver::resolve(self : Resolver, text : String, depth : Int32) -> CType {
  let mut body = text.trim().to_owned()
  if body.contains("(") {
    return {
      base: CUnsupported("function pointer"),
      pointers: 0,
      const_pointee: false,
      array: None,
    }
  }
  let mut array : Int32? = None
  if body.has_suffix("]") {
    match body.rev_find("[") {
      Some(open) => {
        let count = body[open + 1:body.length() - 1].to_owned()
        array = Some(@string.parse_int(count)) catch { _ => None }
        body = body[:open].to_owned()
      }
      None => ()
    }
  }
  let star = body.find("*")
  let head = match star {
    Some(index) => body[:index].to_owned()
    None => body
  }
  let mut pointers = 0
  for ch in body {
    if ch == '*' {
      pointers += 1
    }
  }
  let words = word_list(head)
  {
    base: self.base(words, depth),
    pointers,
    const_pointee: words.contains("const"),
    array,
  }
}

///|
fn parse_constant_value(node : Json) -> Int64? {
  for child in json_children(node) {
    match json_field(child, "value") {
      Some(String(text)) =>
        return Some(@string.parse_int64(text)) catch { _ => None }
      _ => ()
    }
  }
  None
}

///|
/// Reads the declarations of `headers` (paths relative to `usr/include`) from
/// a clang JSON AST of a translation unit that includes them.
pub fn read_header_model(
  ast : String,
  headers : Array[String],
) -> CHeaderModel raise ConfigError {
  let root = @json.parse(ast) catch {
    _ => raise Invalid("bindgen: clang AST is not JSON")
  }
  let nodes = json_children(root)
  let resolver : Resolver = { typedefs: Map([]), anonymous: Map([]), }
  // Anonymous enums/structs are named by the typedef that owns them.
  let anonymous_ids : Map[String, String] = Map([])
  for node in nodes {
    let kind = json_text(Some(node), "kind").unwrap_or("")
    let name = json_text(Some(node), "name").unwrap_or("")
    if (kind == "EnumDecl" || kind == "RecordDecl") && name == "" {
      match json_text(Some(node), "id") {
        Some(id) =>
          anonymous_ids[id] = if kind == "EnumDecl" { "enum" } else { "struct" }
        None => ()
      }
    }
  }
  let owned : Map[String, String] = Map([])
  let aliases : Map[String, String] = Map([])
  for node in nodes {
    if json_text(Some(node), "kind") != Some("TypedefDecl") {
      continue
    }
    let name = json_text(Some(node), "name").unwrap_or("")
    resolver.typedefs[name] = type_text(node)
    match word_list(type_text(node)) {
      ["struct" | "enum", tag] if tag != name && !aliases.contains(tag) =>
        aliases[tag] = name
      _ => ()
    }
    for child in json_children(node) {
      match json_text(json_field(child, "ownedTagDecl"), "id") {
        Some(id) if anonymous_ids.contains(id) => {
          resolver.anonymous[name] = anonymous_ids.get(id).unwrap_or("enum")
          owned[id] = name
        }
        _ => ()
      }
    }
  }
  let enums : Map[String, CEnumDef] = Map([])
  let records : Map[String, CRecordDef] = Map([])
  let functions : Array[CFunction] = []
  let seen : Map[String, Bool] = Map([])
  let mut current = ""
  for node in nodes {
    match decl_file(node) {
      Some(file) => current = file
      None => ()
    }
    let kind = json_text(Some(node), "kind").unwrap_or("")
    let id = json_text(Some(node), "id").unwrap_or("")
    let tag = json_text(Some(node), "name").unwrap_or("")
    let name = if tag == "" { owned.get(id).unwrap_or("") } else { tag }
    if name == "" {
      continue
    }
    match kind {
      "EnumDecl" => {
        let constants : Array[(String, Int64)] = []
        let mut next = 0L
        for child in json_children(node) {
          if json_text(Some(child), "kind") != Some("EnumConstantDecl") {
            continue
          }
          let value = parse_constant_value(child).unwrap_or(next)
          constants.push((json_text(Some(child), "name").unwrap_or(""), value))
          next = value + 1L
        }
        if !constants.is_empty() {
          enums[name] = { name, constants, }
        }
      }
      "RecordDecl" if json_text(Some(node), "tagUsed") == Some("struct") => {
        let complete = match json_field(node, "completeDefinition") {
          Some(True) => true
          _ => false
        }
        let fields : Array[CField] = []
        for child in json_children(node) {
          if json_text(Some(child), "kind") == Some("FieldDecl") {
            fields.push({
              name: json_text(Some(child), "name").unwrap_or(""),
              kind: resolver.resolve(type_text(child), 0),
              spelling: sugared_text(child),
            })
          }
        }
        // A later complete definition replaces a forward declaration.
        if complete || !records.contains(name) {
          records[name] = {
            name,
            spelling: if tag == "" {
              name
            } else {
              "struct " + tag
            },
            complete,
            fields,
          }
        }
      }
      "FunctionDecl" => {
        guard include_relative(current) is Some(header) else { continue }
        if !headers.contains(header) || seen.contains(name) {
          continue
        }
        seen[name] = true
        let params : Array[CField] = []
        for child in json_children(node) {
          if json_text(Some(child), "kind") == Some("ParmVarDecl") {
            params.push({
              name: json_text(Some(child), "name").unwrap_or(
                "arg" + params.length().to_string(),
              ),
              kind: resolve_sugared(resolver, child),
              spelling: sugared_text(child),
            })
          }
        }
        let signature = sugared_text(node)
        let result_text = match signature.find("(") {
          Some(index) => signature[:index].to_owned()
          None => signature
        }
        let variadic = match json_field(node, "variadic") {
          Some(True) => true
          _ => false
        }
        functions.push({
          name,
          result: resolver.resolve(result_text, 0),
          result_spelling: result_text.trim().to_owned(),
          params,
          variadic,
          header,
        })
      }
      _ => ()
    }
  }
  { functions, enums, records, aliases, }
}

///|
/// Prefers the desugared spelling, but keeps typedef names of anonymous types
/// (clang prints those as the typedef name in both spellings).
fn resolve_sugared(resolver : Resolver, node : Json) -> CType {
  resolver.resolve(type_text(node), 0)
}

///|
#deprecated
pub extend CType with Eq::{equal, not_equal}

///|
#deprecated
pub extend CType with @debug.Debug::{to_repr}

///|
#deprecated
pub extend CBase with Eq::{equal, not_equal}

///|
#deprecated
pub extend CBase with @debug.Debug::{to_repr}
