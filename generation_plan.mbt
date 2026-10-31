///|
priv struct TypePlan {
  index : Int32
  kind : TypeExpr
  symbol : String
  dependencies : Array[Int32]
}

///|
priv struct CallPlan {
  function : Callable
  symbol : String
  inputs : Array[Int32]
  output : Int32
  /// Type crossing the C boundary; differs from `output` for raising calls.
  raw_output : Int32
  bounded : Bool
}

///|
priv struct GenerationPlan {
  project : Project
  types : Array[TypePlan]
  calls : Array[CallPlan]
}

///|
fn type_index(
  types : Array[TypeExpr],
  kind : TypeExpr,
) -> Int32 raise ConfigError {
  match types.search_by(t => t == kind) {
    Some(index) => index
    None => raise Invalid("generation: unresolved type " + kind.moon_name())
  }
}

///|
fn direct_children(
  project : Project,
  kind : TypeExpr,
) -> Array[TypeExpr] raise ConfigError {
  match kind {
    Scalar(_) | Enum(_) | Handle(_) | External(_, _) => []
    List(element) | Optional(element) => [element]
    Record(name) => project.record_def(name).fields.map(f => f.kind)
  }
}

///|
fn make_generation_plan(project : Project) -> GenerationPlan raise ConfigError {
  let kinds = project.reachable_types()
  let types : Array[TypePlan] = []
  let symbols : Map[String, Bool] = Map([])
  for
    reserved in [
      "moonohos_initialize", "moonohos_business_error", "moonohos_bridge_cancelled",
      "moonohos_diagnostics",
    ] {
    symbols[reserved] = true
  }
  for index, kind in kinds {
    let symbol = "moonohos_type_" + index.to_string()
    types.push({
      index,
      kind,
      symbol,
      dependencies: direct_children(project, kind).map(k => type_index(kinds, k)),
    })
    let suffixes = match kind {
      List(_) | Optional(_) => ["new", "push", "length", "get"]
      Record(name) => {
        let suffixes = ["new"]
        for field_index in 0..<project.record_def(name).fields.length() {
          suffixes.push("field_" + field_index.to_string())
        }
        suffixes
      }
      _ => []
    }
    for suffix in suffixes {
      symbols[symbol + "_" + suffix] = true
      symbols["moonohos_raw_type_" + index.to_string() + "_" + suffix] = true
    }
  }
  let calls : Array[CallPlan] = []
  for function in project.functions {
    let symbol = "moonohos_" + function.name
    if function.name.has_prefix("type_") ||
      function.name == "initialize" ||
      symbols.contains(symbol) ||
      symbols.contains("moonohos_raw_" + function.name) {
      raise Invalid(
        "generation: reserved/colliding function symbol " + function.name,
      )
    }
    symbols[symbol] = true
    symbols["moonohos_raw_" + function.name] = true
    let inputs = function.params.map(p => type_index(kinds, p.kind))
    let output = type_index(kinds, function.result)
    let raw_output = type_index(kinds, function.raw_result())
    let bounded = function.params.any(p => {
        match p.kind {
          List(_) | Optional(_) | Record(_) => true
          _ => false
        }
      }) ||
      (match function.result {
        List(_) | Optional(_) | Record(_) => true
        _ => false
      })
    calls.push({ function, symbol, inputs, output, raw_output, bounded, })
  }
  { project, types, calls, }
}

///|
fn TypePlan::to_json(self : TypePlan) -> Json {
  let reference = self.kind.is_reference()
  {
    "index": self.index,
    "type": self.kind.moon_name(),
    "symbol": self.symbol,
    "cType": self.kind.c_name(),
    "dependencies": Json(self.dependencies),
    "argument": if reference {
      "borrowed"
    } else {
      "value"
    },
    "result": if reference {
      "owned"
    } else {
      "value"
    },
  }
}

///|
fn CallPlan::to_json(self : CallPlan) -> Json {
  {
    "name": self.function.name,
    "signature": self.function.signature(),
    "symbol": self.symbol,
    "inputs": Json(self.inputs),
    "output": self.output,
    "boundedContainers": self.bounded,
    "async": self.function.is_async,
    "raises": self.function.raises,
    "stages": Json(
      if self.function.is_async {
        [
          "read-arkts", "queue-async-work", "worker-locked-call-and-copy", "complete-create-arkts",
        ]
      } else {
        ["read-arkts", "locked-runtime-call-and-copy", "create-arkts"]
      },
    ),
  }
}

///|
pub fn Project::generation_plan(self : Project) -> Json raise ConfigError {
  let plan = make_generation_plan(self)
  {
    "module": plan.project.native_module,
    "types": Json(plan.types.map(t => t.to_json())),
    "calls": Json(plan.calls.map(c => c.to_json())),
    "limits": conversion_limits().to_json(),
  }
}

///|
fn generated_parameters(fields : Array[FieldDef], moon~ : Bool) -> String {
  fields
  .map(f => {
    f.name +
    " : " +
    (if moon { boundary_name(f.kind) } else { f.kind.moon_name() })
  })
  .join(", ")
}

///|
/// MoonBit type of a value at the C boundary: `Option[T]` travels as a zero- or
/// one-element `Array[T]` because the compiler's Option layout is not ABI.
fn boundary_name(kind : TypeExpr) -> String {
  match kind {
    Optional(inner) => "Array[" + inner.wrapper_name() + "]"
    Enum(_) => "Int"
    _ => kind.wrapper_name()
  }
}

///|
/// MoonBit expression turning a boundary value back into the business type.
fn lift(kind : TypeExpr, value : String, enums : Array[EnumDef]) -> String {
  match kind {
    Optional(_) => value + ".get(0)"
    Enum(name) => {
      let arms = enum_cases(name, enums).mapi((i, c) => {
        i.to_string() + " => @core." + name + "::" + c
      })
      "match " +
      value +
      " { " +
      arms.join("; ") +
      "; _ => abort(\"moonohos: invalid " +
      name +
      " tag\") }"
    }
    _ => value
  }
}

///|
/// MoonBit expression turning a business value into its boundary form.
fn lower(kind : TypeExpr, value : String, enums : Array[EnumDef]) -> String {
  match kind {
    Optional(_) => "match (" + value + ") { Some(x) => [x]; None => [] }"
    Enum(name) => {
      let arms = enum_cases(name, enums).mapi((i, c) => {
        "@core." + name + "::" + c + " => " + i.to_string()
      })
      "match (" + value + ") { " + arms.join("; ") + " }"
    }
    _ => value
  }
}

///|
fn enum_cases(name : String, enums : Array[EnumDef]) -> Array[String] {
  for def in enums {
    if def.name == name {
      return def.cases
    }
  }
  []
}

///|
fn c_parameters(fields : Array[FieldDef]) -> String {
  if fields.is_empty() {
    "void"
  } else {
    fields.mapi((i, f) => f.kind.c_name() + " arg" + i.to_string()).join(", ")
  }
}

///|
fn raw_adapter(
  name : String,
  fields : Array[FieldDef],
  result : TypeExpr,
) -> String {
  let args = fields.mapi((i, _) => "arg" + i.to_string()).join(", ")
  let expression = "moonohos_raw_" + name + "(" + args + ")"
  let body = if result == Scalar(Void) {
    "(void)" + expression + ";"
  } else {
    "return " + expression + ";"
  }
  result.c_name() +
  " moonohos_" +
  name +
  "(" +
  c_parameters(fields) +
  ") { " +
  body +
  " }\n"
}

///|
fn moon_export(
  name : String,
  fields : Array[FieldDef],
  result : TypeExpr,
  expression : String,
  enums : Array[EnumDef],
) -> String {
  // Lift boundary values (Option arrays, enum tags) before the body and lower
  // the result back to its boundary form.
  let mut body = ""
  for field in fields {
    let lifted = lift(field.kind, field.name, enums)
    if lifted != field.name {
      body += "let " + field.name + " = " + lifted + "; "
    }
  }
  body += lower(result, expression, enums)
  "///|\npub fn moonohos_raw_" +
  name +
  "(" +
  generated_parameters(fields, moon=true) +
  ") -> " +
  boundary_name(result) +
  " { " +
  body +
  " }\n"
}

///|
/// Generates only business exports; container accessors are added by the backend.
pub fn Project::business_wrapper(self : Project) -> String raise ConfigError {
  let plan = make_generation_plan(self)
  let mut source = "///|\nfn main { () }\n"
  if self.functions.any(f => f.raises) {
    source += "///|\n#borrow(message)\nextern \"C\" fn moonohos_business_error(message : String) -> Unit = \"moonohos_business_error\"\n"
  }
  for call in plan.calls {
    let invocation = "@core." +
      call.function.name +
      "(" +
      call.function.params.map(p => p.name).join(", ") +
      ")"
    let expression = if !call.function.raises {
      invocation
    } else {
      // Raising calls report the error text and return an empty envelope.
      let value = if call.function.result == Scalar(Void) {
        "{ " + invocation + "; [true] }"
      } else {
        "[" + invocation + "]"
      }
      value +
      " catch { e => { let error : Error = e; moonohos_business_error(error.to_string()); [] } }"
    }
    source += moon_export(
      call.function.name,
      call.function.params,
      call.function.raw_result(),
      expression,
      self.enums,
    )
  }
  source
}

///|
pub fn Project::business_header(self : Project) -> String raise ConfigError {
  let plan = make_generation_plan(self)
  let mut source = "#pragma once\n#include <stdint.h>\n#include <moonbit.h>\n#ifdef __cplusplus\nextern \"C\" {\n#endif\nvoid moonohos_initialize(void);\n"
  for call in plan.calls {
    source += call.function.raw_result().c_name() +
      " " +
      call.symbol +
      "(" +
      c_parameters(call.function.params) +
      ");\n"
  }
  source + "#ifdef __cplusplus\n}\n#endif\n"
}

///|
pub fn Project::business_adapters(self : Project) -> String raise ConfigError {
  let plan = make_generation_plan(self)
  plan.calls
  .map(c => {
    raw_adapter(c.function.name, c.function.params, c.function.raw_result())
  })
  .join("")
}
