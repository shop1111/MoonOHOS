///|
priv struct TypePlan {
  index : Int
  kind : TypeExpr
  symbol : String
  dependencies : Array[Int]
}

///|
priv struct CallPlan {
  function : Callable
  symbol : String
  inputs : Array[Int]
  output : Int
  /// Type crossing the C boundary; differs from `output` for raising calls.
  raw_output : Int
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
) -> Int raise ConfigError {
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
    Scalar(_) | Handle(_) | External(_, _) => []
    List(element) => [element]
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
      List(_) => ["new", "push", "length", "get"]
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
          List(_) | Record(_) => true
          _ => false
        }
      }) ||
      (match function.result {
        List(_) | Record(_) => true
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
    "dependencies": self.dependencies.to_json(),
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
    "inputs": self.inputs.to_json(),
    "output": self.output,
    "boundedContainers": self.bounded,
    "async": self.function.is_async,
    "raises": self.function.raises,
    "stages": (if self.function.is_async {
      [
        "read-arkts", "queue-async-work", "worker-locked-call-and-copy", "complete-create-arkts",
      ]
    } else {
      ["read-arkts", "locked-runtime-call-and-copy", "create-arkts"]
    }).to_json(),
  }
}

///|
pub fn Project::generation_plan(self : Project) -> Json raise ConfigError {
  let plan = make_generation_plan(self)
  {
    "module": plan.project.native_module,
    "types": plan.types.map(t => t.to_json()).to_json(),
    "calls": plan.calls.map(c => c.to_json()).to_json(),
    "limits": conversion_limits().to_json(),
  }
}

///|
fn generated_parameters(fields : Array[FieldDef], moon~ : Bool) -> String {
  fields
  .map(f => {
    f.name +
    " : " +
    (if moon { f.kind.wrapper_name() } else { f.kind.moon_name() })
  })
  .join(", ")
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
) -> String {
  "///|\npub fn moonohos_raw_" +
  name +
  "(" +
  generated_parameters(fields, moon=true) +
  ") -> " +
  result.wrapper_name() +
  " { " +
  expression +
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
