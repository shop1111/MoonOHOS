///|
pub struct InterfaceFunction {
  name : String
  params : Array[TypeExpr]
  result : TypeExpr
  raises : Bool
  unsupported : String?
}

///|
/// Any declared type name, including abstract `type X` and external types.
pub struct InterfaceType {
  name : String
  generic : Bool
}

///|
pub struct InterfaceRecord {
  name : String
  fields : Array[FieldDef]
  unsupported : String?
}

///|
pub struct InterfaceEnum {
  name : String
  cases : Array[String]
  unsupported : String?
}

///|
pub struct PackageInterface {
  functions : Array[InterfaceFunction]
  records : Array[InterfaceRecord]
  enums : Array[InterfaceEnum]
  types : Array[InterfaceType]
}

///|
priv struct InterfaceCursor {
  tokens : Array[String]
  mut offset : Int32
}

///|
fn interface_tokens(text : String) -> Array[String] {
  let tokens : Array[String] = []
  let mut word = ""
  let mut quoted = false
  let mut escaped = false
  let mut comment = false
  let mut slash = false
  for ch in text {
    if comment {
      if ch == '\n' {
        comment = false
      }
      continue
    }
    if quoted {
      if escaped {
        escaped = false
      } else if ch == '\\' {
        escaped = true
      } else if ch == '"' {
        quoted = false
        tokens.push("<string>")
      }
      continue
    }
    if slash {
      slash = false
      if ch == '/' {
        comment = true
        continue
      }
      tokens.push("/")
    }
    if (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') ||
      ch == '_' ||
      ch == '@' {
      word += ch.to_string()
      continue
    }
    if !word.is_empty() {
      tokens.push(word)
      word = ""
    }
    if ch == '"' {
      quoted = true
    } else if ch == '/' {
      slash = true
    } else if ch != ' ' && ch != '\t' && ch != '\n' && ch != '\r' {
      tokens.push(ch.to_string())
    }
  }
  if !word.is_empty() {
    tokens.push(word)
  }
  if slash {
    tokens.push("/")
  }
  tokens
}

///|
fn InterfaceCursor::peek(self : InterfaceCursor) -> String {
  self.tokens.get(self.offset).unwrap_or("<end>")
}

///|
fn InterfaceCursor::take(self : InterfaceCursor) -> String raise ConfigError {
  if self.offset >= self.tokens.length() {
    raise Invalid("interface: unexpected end of declaration")
  }
  let value = self.tokens[self.offset]
  self.offset += 1
  value
}

///|
fn InterfaceCursor::expect(
  self : InterfaceCursor,
  token : String,
) -> Unit raise ConfigError {
  let actual = self.take()
  if actual != token {
    raise Invalid("interface: expected " + token + ", found " + actual)
  }
}

///|
fn InterfaceCursor::kind(
  self : InterfaceCursor,
  depth : Int32,
) -> TypeExpr raise ConfigError {
  let primary = self.primary(depth)
  if self.peek() == "?" {
    self.take() |> ignore
    Optional(primary)
  } else {
    primary
  }
}

///|
fn InterfaceCursor::primary(
  self : InterfaceCursor,
  depth : Int32,
) -> TypeExpr raise ConfigError {
  if depth > 32 {
    raise Invalid("interface: type nesting exceeds 32")
  }
  let name = self.take()
  if name == "(" {
    // Function type `(T1, T2) -> R`; only `Unit` results without effects.
    let args : Array[TypeExpr] = []
    if self.peek() != ")" {
      while true {
        args.push(self.kind(depth + 1))
        if self.peek() != "," {
          break
        }
        self.take() |> ignore
      }
    }
    self.expect(")")
    self.expect("-")
    self.expect(">")
    if self.take() != "Unit" || self.peek() == "raise" || self.peek() == "?" {
      raise Invalid(
        "interface: callbacks must be (T1, T2) -> Unit without raise or Option",
      )
    }
    Callback(args)
  } else if name == "Array" || name == "Option" {
    self.expect("[")
    let element = self.kind(depth + 1)
    self.expect("]")
    if name == "Array" {
      List(element)
    } else {
      Optional(element)
    }
  } else if name.has_prefix("@") && self.peek() == "." {
    self.take() |> ignore
    let type_name = self.take()
    if !identifier(name[1:].to_owned()) ||
      !identifier(type_name) ||
      self.peek() == "[" {
      raise Invalid("interface: unsupported qualified type " + name)
    }
    External(name[1:].to_owned(), type_name)
  } else {
    let kind = parse_type_expr(name, result=true)
    if self.peek() == "[" || self.peek() == "." || self.peek() == "::" {
      raise Invalid(
        "interface: unsupported generic, optional or qualified type " + name,
      )
    }
    kind
  }
}

///|
fn parse_interface_function(tokens : Array[String]) -> InterfaceFunction {
  let cursor = InterfaceCursor::{ tokens, offset: 0, }
  let mut name = ""
  let params : Array[TypeExpr] = []
  let mut result = Scalar(Void)
  let mut raises = false
  let unsupported = try {
    name = cursor.take()
    if !identifier(name) {
      raise Invalid("generic functions are unsupported")
    }
    cursor.expect("(")
    if cursor.peek() != ")" {
      while true {
        params.push(cursor.kind(0))
        if cursor.peek() != "," {
          break
        }
        cursor.take() |> ignore
        if cursor.peek() == ")" {
          break
        }
        continue
      }
    }
    cursor.expect(")")
    cursor.expect("-")
    cursor.expect(">")
    result = cursor.kind(0)
    if cursor.peek() == "raise" {
      cursor.take() |> ignore
      raises = true
      // Optional error type: `Error`, `E` or `@pkg.E`.
      if cursor.offset < tokens.length() {
        let error = cursor.take()
        if error.has_prefix("@") {
          cursor.expect(".")
          cursor.take() |> ignore
        } else if !identifier(error) {
          raise Invalid("unsupported raise clause")
        }
      }
    }
    if cursor.offset != tokens.length() {
      raise Invalid(
        "labels, polymorphic effects and other signature syntax are unsupported",
      )
    }
    None
  } catch {
    Invalid(message) => Some(message)
  }
  { name, params, result, raises, unsupported, }
}

///|
fn parse_interface_record(
  tokens : Array[String],
  value_type : Bool,
) -> InterfaceRecord {
  let cursor = InterfaceCursor::{ tokens, offset: 0, }
  let mut name = ""
  let fields : Array[FieldDef] = []
  let unsupported = try {
    name = cursor.take()
    if value_type {
      raise Invalid("#value structures are unsupported")
    }
    cursor.expect("{")
    while cursor.peek() != "}" {
      if cursor.peek() == "mut" {
        cursor.take() |> ignore
      }
      let field_name = cursor.take()
      if !identifier(field_name) {
        raise Invalid("private/opaque record fields are unsupported")
      }
      cursor.expect(":")
      let kind = cursor.kind(0)
      fields.push({ name: field_name, kind, })
      if cursor.peek() == "," || cursor.peek() == ";" {
        cursor.take() |> ignore
      }
    }
    cursor.expect("}")
    if cursor.offset != tokens.length() {
      raise Invalid("generic or attributed record syntax is unsupported")
    }
    None
  } catch {
    Invalid(message) => Some(message)
  }
  { name, fields, unsupported, }
}

///|
/// `Name { A B C }`; cases with payloads or generic enums are unsupported.
fn parse_interface_enum(tokens : Array[String]) -> InterfaceEnum {
  let name = tokens.get(0).unwrap_or("")
  let cases : Array[String] = []
  let mut unsupported : String? = None
  if tokens.get(1) != Some("{") {
    unsupported = Some("generic enums are unsupported")
  } else {
    for token in tokens[2:] {
      if token == "}" {
        break
      }
      if token == "(" || token == "=" {
        unsupported = Some("enum cases with payloads or values are unsupported")
        break
      }
      if identifier(token) {
        cases.push(token)
      }
    }
  }
  { name, cases, unsupported, }
}

///|
/// Parses selected declarations structurally; unrelated traits remain opaque.
pub fn parse_package_interface(text : String) -> PackageInterface {
  let tokens = interface_tokens(text)
  let functions : Array[InterfaceFunction] = []
  let records : Array[InterfaceRecord] = []
  let enums : Array[InterfaceEnum] = []
  let types : Array[InterfaceType] = []
  // Abstract types (`type X`) and other non-pub items also end a declaration.
  let boundaries = [
    "pub", "#", "type", "fn", "struct", "enum", "suberror", "trait", "impl", "let",
    "const", "typealias", "fnalias", "async",
  ]
  let mut index = 0
  let mut value_type = false
  while index < tokens.length() {
    if tokens[index] == "#" {
      if tokens.get(index + 1) == Some("value") {
        value_type = true
      }
      index += 2
      continue
    }
    if tokens[index] == "pub" {
      index += 1
      if tokens.get(index) == Some("(") {
        while index < tokens.length() && tokens[index] != ")" {
          index += 1
        }
        index += 1
      }
    } else if !boundaries.contains(tokens[index]) {
      index += 1
      continue
    }
    let category = tokens.get(index).unwrap_or("")
    index += 1
    let start = index
    while index < tokens.length() && !boundaries.contains(tokens[index]) {
      index += 1
    }
    let declaration = tokens[start:index].to_owned()
    match category {
      "fn" => functions.push(parse_interface_function(declaration))
      "struct" => records.push(parse_interface_record(declaration, value_type))
      "enum" => enums.push(parse_interface_enum(declaration))
      _ => ()
    }
    if ["struct", "type", "enum", "suberror"].contains(category) &&
      !declaration.is_empty() {
      types.push({
        name: declaration[0],
        generic: declaration.get(1) == Some("["),
      })
    }
    value_type = false
  }
  { functions, records, enums, types, }
}

///|
/// Maps default package aliases (last path segment) to imported packages.
pub fn interface_imports(text : String) -> Map[String, String] {
  let result : Map[String, String] = Map([])
  let mut inside = false
  for line in text.split("\n") {
    let line = line.trim().to_owned()
    if line.has_prefix("import {") {
      inside = true
      continue
    }
    if inside {
      if line.has_prefix("}") {
        inside = false
        continue
      }
      let pkg = line.trim_end(chars=",").trim(chars="\"").to_owned()
      let pkg_alias = pkg.split("/").last().unwrap_or("").to_owned()
      if pkg_alias != "" {
        result[pkg_alias] = pkg
      }
    }
  }
  result
}

///|
pub fn Project::verify_interface(
  self : Project,
  text : String,
) -> Unit raise ConfigError {
  self.validate()
  let interface = parse_package_interface(text)
  for expected in self.functions {
    let actual = interface.functions
      .search_by(f => f.name == expected.name)
      .map(i => interface.functions[i])
    let actual = actual.unwrap_or_else(() => {
      raise Invalid("interface: missing public function " + expected.name)
    })
    if actual.unsupported is Some(reason) {
      raise Invalid("interface: " + expected.name + ": " + reason)
    }
    // Handles are declared opaque in the manifest but appear as names in mbti.
    if actual.params.map(k => k.moon_name()) !=
      expected.params.map(p => p.kind.moon_name()) ||
      actual.result.moon_name() != expected.result.moon_name() {
      raise Invalid(
        "interface: signature mismatch; expected " + expected.signature(),
      )
    }
    if actual.raises != expected.raises {
      raise Invalid(
        "interface: " +
        expected.name +
        (if actual.raises {
          " raises; declare \"raises\": true (manifest version 2)"
        } else {
          " does not raise; remove \"raises\""
        }),
      )
    }
  }
  for handle in self.handles {
    match interface.types.search_by(t => t.name == handle) {
      Some(i) if !interface.types[i].generic => ()
      Some(_) => raise Invalid("interface: generic handle type " + handle)
      None => raise Invalid("interface: missing public type " + handle)
    }
  }
  for expected in self.records {
    let actual = interface.records
      .search_by(r => r.name == expected.name)
      .map(i => interface.records[i])
    let actual = actual.unwrap_or_else(() => {
      raise Invalid("interface: missing public record " + expected.name)
    })
    if actual.unsupported is Some(reason) {
      raise Invalid("interface: " + expected.name + ": " + reason)
    }
    if actual.fields.length() != expected.fields.length() {
      raise Invalid("interface: incomplete fields for " + expected.name)
    }
    for field in expected.fields {
      let actual_field = actual.fields
        .search_by(f => f.name == field.name)
        .map(i => actual.fields[i])
      match actual_field {
        // Names, not variants: the interface does not know which names are enums.
        Some(actual_field) if actual_field.kind.moon_name() ==
          field.kind.moon_name() => ()
        _ =>
          raise Invalid(
            "interface: field mismatch " + expected.name + "." + field.name,
          )
      }
    }
  }
  for expected in self.enums {
    let actual = interface.enums
      .search_by(e => e.name == expected.name)
      .map(i => interface.enums[i])
    let actual = actual.unwrap_or_else(() => {
      raise Invalid("interface: missing public enum " + expected.name)
    })
    if actual.unsupported is Some(reason) {
      raise Invalid("interface: " + expected.name + ": " + reason)
    }
    let mut same = actual.cases.length() == expected.cases.length()
    for case_name in expected.cases {
      same = same && actual.cases.contains(case_name)
    }
    if !same {
      raise Invalid(
        "interface: enum " +
        expected.name +
        " has cases " +
        actual.cases.join(", ") +
        "; manifest lists " +
        expected.cases.join(", "),
      )
    }
  }
}
