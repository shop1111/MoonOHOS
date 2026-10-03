///|
pub struct GeneratedArtifacts {
  wrapper : String
  package_file : String
  header : String
  embed : String
  native : String
  declarations : String
  cmake : String
}

///|
priv struct Accessor {
  name : String
  params : Array[FieldDef]
  result : TypeExpr
  expression : String
}

///|
fn accessor_definitions(
  plan : GenerationPlan,
) -> Array[Accessor] raise ConfigError {
  let result : Array[Accessor] = []
  for type_ in plan.types {
    let prefix = "type_" + type_.index.to_string()
    match type_.kind {
      List(element) => {
        let value : FieldDef = { name: "v", kind: type_.kind, }
        result.push({
          name: prefix + "_new",
          params: [],
          result: type_.kind,
          expression: "[]",
        })
        result.push({
          name: prefix + "_push",
          params: [value, { name: "x", kind: element, }],
          result: Scalar(Void),
          expression: "v.push(x)",
        })
        result.push({
          name: prefix + "_length",
          params: [value],
          result: Scalar(Int32),
          expression: "v.length()",
        })
        result.push({
          name: prefix + "_get",
          params: [value, { name: "i", kind: Scalar(Int32), }],
          result: element,
          expression: "v[i]",
        })
      }
      Record(_) =>
        for accessor in record_accessors(plan.project, type_) {
          result.push(accessor)
        }
      Scalar(_) => ()
    }
  }
  result
}

///|
fn cpp_reader(type_ : TypePlan, project : Project) -> String raise ConfigError {
  let index = type_.index.to_string()
  let mut source = "static bool Read_" +
    index +
    "(napi_env env, napi_value value, BridgeValue &out, Budget &budget, Ancestors &ancestors, size_t depth, const std::string &path) {\n"
  match type_.kind {
    Scalar(kind) => {
      let (wanted, reader, slot, width) = match kind {
        Int32 => ("napi_number", "ReadInteger", "integer", "sizeof(int32_t)")
        Float64 => ("napi_number", "ReadFinite", "number", "sizeof(double)")
        Boolean => ("napi_boolean", "ReadBool", "integer", "sizeof(int32_t)")
        Text =>
          (
            "napi_string", "ReadText", "text", "out.text.size() * sizeof(char16_t)",
          )
        Binary => ("napi_object", "ReadBytes", "bytes", "out.bytes.size()")
        Void => ("napi_undefined", "", "", "0")
      }
      if kind != Void {
        source += "  if (!LeafType(env, value, " +
          wanted +
          ", path)) return false;\n"
        if kind == Text || kind == Binary {
          source += "  if (!" +
            (if kind == Text { "PrepareText" } else { "PrepareBytes" }) +
            "(env, value, budget, depth, path)) return false;\n"
        }
        source += "  if (!" +
          reader +
          "(env, value, out." +
          slot +
          (if kind == Int32 || kind == Float64 { ", path" } else { "" }) +
          ")) return false;\n"
        if kind != Text && kind != Binary {
          source += "  budget.add(0, " + width + ", depth, path);\n"
        }
      }
    }
    List(_) => {
      let child = type_.dependencies[0].to_string()
      source += "  if (!Ordinary(env, value, true, path) || !ancestors.enter(value, path)) return false;\n  AncestorScope scope(ancestors);\n  uint32_t length;\n  if (!Check(env, napi_get_array_length(env, value, &length))) return false;\n  budget.add(length, 0, depth + 1, path);\n  MOONOHOS_BUFFER_ALLOCATE();\n  out.children.resize(length);\n  for (uint32_t i = 0; i < length; ++i) {\n    auto child_path = path + \"[\" + std::to_string(i) + \"]\";\n    napi_value child;\n    if (!Own(env, value, std::to_string(i), child, child_path)) return false;\n    if (!Read_" +
        child +
        "(env, child, out.children[i], budget, ancestors, depth + 1, child_path)) return false;\n  }\n"
    }
    Record(_) => source += record_reader(type_, project)
  }
  source + "  return true;\n}\n"
}

///|
fn cpp_make(type_ : TypePlan, types : Array[TypePlan]) -> String {
  let index = type_.index.to_string()
  let mut source = "static " +
    type_.kind.c_name() +
    " Make_" +
    index +
    "(const BridgeValue &value) {\n"
  match type_.kind {
    Scalar(kind) =>
      source += match kind {
        Int32 | Boolean => "  return value.integer;\n"
        Float64 => "  return value.number;\n"
        Text => "  return MakeText(value.text);\n"
        Binary => "  return MakeBytes(value.bytes);\n"
        Void => ""
      }
    List(element) => {
      let child = type_.dependencies[0].to_string()
      source += "  MoonOwner<void *> result{" +
        type_.symbol +
        "_new()};\n  for (const auto &item : value.children) {\n    "
      if element.is_reference() {
        source += "MoonOwner<" +
          types[type_.dependencies[0]].kind.c_name() +
          "> child{Make_" +
          child +
          "(item)};\n    " +
          type_.symbol +
          "_push(result.ptr, child.ptr);\n"
      } else {
        source += type_.symbol +
          "_push(result.ptr, Make_" +
          child +
          "(item));\n"
      }
      source += "  }\n  auto pointer = result.ptr; result.ptr = nullptr; return pointer;\n"
    }
    Record(_) => source += record_maker(type_, types)
  }
  source + "}\n"
}

///|
fn cpp_copy(
  type_ : TypePlan,
  types : Array[TypePlan],
  project : Project,
) -> String raise ConfigError {
  let index = type_.index.to_string()
  let mut source = "static BridgeValue Copy_" +
    index +
    "(" +
    type_.kind.c_name() +
    " value, Budget &budget, size_t depth, const std::string &path) {\n  BridgeValue out;\n"
  match type_.kind {
    Scalar(kind) =>
      source += match kind {
        Int32 | Boolean =>
          "  out.integer = value; budget.add(0, sizeof(int32_t), depth, path);\n"
        Float64 =>
          "  if (!std::isfinite(value)) throw RangeFault(path + \": non-finite result\");\n  out.number = value; budget.add(0, sizeof(double), depth, path);\n"
        Text =>
          "  budget.add(0, static_cast<size_t>(Moonbit_array_length(value)) * sizeof(char16_t), depth, path);\n  out.text = CopyText(value);\n"
        Binary =>
          "  budget.add(0, static_cast<size_t>(Moonbit_array_length(value)), depth, path);\n  out.bytes = CopyBytes(value);\n"
        Void => ""
      }
    List(element) => {
      let child = type_.dependencies[0].to_string()
      source += "  int32_t length = " +
        type_.symbol +
        "_length(value);\n  if (length < 0) throw RangeFault(path + \": invalid array length\");\n  budget.add(static_cast<size_t>(length), 0, depth + 1, path);\n  MOONOHOS_BUFFER_ALLOCATE();\n  out.children.reserve(length);\n  for (int32_t i = 0; i < length; ++i) {\n    "
      if element.is_reference() {
        source += "MoonOwner<" +
          types[type_.dependencies[0]].kind.c_name() +
          "> child{" +
          type_.symbol +
          "_get(value, i)};\n    out.children.push_back(Copy_" +
          child +
          "(child.ptr, budget, depth + 1, path + \"[\" + std::to_string(i) + \"]\"));\n"
      } else {
        source += "out.children.push_back(Copy_" +
          child +
          "(" +
          type_.symbol +
          "_get(value, i), budget, depth + 1, path + \"[\" + std::to_string(i) + \"]\"));\n"
      }
      source += "  }\n"
    }
    Record(_) => source += record_copier(type_, project, types)
  }
  source + "  return out;\n}\n"
}

///|
fn cpp_create(type_ : TypePlan, project : Project) -> String raise ConfigError {
  let index = type_.index.to_string()
  let mut source = "static bool Create_" +
    index +
    "(napi_env env, const BridgeValue &value, napi_value &result) {\n"
  match type_.kind {
    Scalar(kind) =>
      source += "  return Check(env, " +
        (match kind {
          Int32 => "napi_create_int32(env, value.integer, &result)"
          Float64 => "napi_create_double(env, value.number, &result)"
          Boolean => "napi_get_boolean(env, value.integer != 0, &result)"
          Text =>
            "napi_create_string_utf16(env, value.text.data(), value.text.size(), &result)"
          Binary => "CreateBytes(env, value.bytes, &result)"
          Void => "napi_get_undefined(env, &result)"
        }) +
        ");\n"
    List(_) =>
      source += "  if (!Check(env, napi_create_array_with_length(env, value.children.size(), &result))) return false;\n  for (size_t i = 0; i < value.children.size(); ++i) {\n    napi_value child;\n    if (!Create_" +
        type_.dependencies[0].to_string() +
        "(env, value.children[i], child)) return false;\n    if (!Check(env, napi_set_element(env, result, static_cast<uint32_t>(i), child))) return false;\n  }\n  return true;\n"
    Record(_) => source += record_creator(type_, project)
  }
  source + "}\n"
}

///|
fn cpp_callback(call : CallPlan, types : Array[TypePlan]) -> String {
  let count = call.inputs.length().to_string()
  let mut source = "static napi_value Call_" +
    call.function.name +
    "(napi_env env, napi_callback_info info) {\n try {\n  Budget input_budget{" +
    (if call.bounded { "true" } else { "false" }) +
    "}, output_budget{" +
    (if call.bounded { "true" } else { "false" }) +
    "};\n  Ancestors ancestors{env, {}};\n  BridgeValue result_value;\n"
  if !call.inputs.is_empty() {
    source += "  size_t argc = " +
      count +
      "; napi_value argv[" +
      count +
      "] = {};\n  if (!Check(env, napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr))) return nullptr;\n  if (argc < " +
      count +
      ") throw TypeFault(\"" +
      call.function.name +
      ": missing arguments\");\n"
  }
  for index, type_index in call.inputs {
    let suffix = index.to_string()
    source += "  BridgeValue arg" +
      suffix +
      ";\n  if (!Read_" +
      type_index.to_string() +
      "(env, argv[" +
      suffix +
      "], arg" +
      suffix +
      ", input_budget, ancestors, 0, \"" +
      call.function.name +
      "." +
      call.function.params[index].name +
      "\")) return nullptr;\n"
  }
  source += "  { std::lock_guard<std::mutex> lock(gate); std::call_once(initialized, moonohos_initialize);\n"
  let args : Array[String] = []
  for index, type_index in call.inputs {
    let type_ = types[type_index]
    let suffix = index.to_string()
    if type_.kind.is_reference() {
      source += "    MoonOwner<" +
        type_.kind.c_name() +
        "> owned" +
        suffix +
        "{Make_" +
        type_index.to_string() +
        "(arg" +
        suffix +
        ")};\n"
      args.push("owned" + suffix + ".ptr")
    } else {
      args.push("Make_" + type_index.to_string() + "(arg" + suffix + ")")
    }
  }
  let result = types[call.output]
  let expression = call.symbol + "(" + args.join(", ") + ")"
  if result.kind == Scalar(Void) {
    source += "    " + expression + ";\n"
  } else if result.kind.is_reference() {
    source += "    MoonOwner<" +
      result.kind.c_name() +
      "> returned{" +
      expression +
      "};\n    result_value = Copy_" +
      call.output.to_string() +
      "(returned.ptr, output_budget, 0, \"" +
      call.function.name +
      ".return\");\n"
  } else {
    source += "    result_value = Copy_" +
      call.output.to_string() +
      "(" +
      expression +
      ", output_budget, 0, \"" +
      call.function.name +
      ".return\");\n"
  }
  source += "  }\n  napi_value result;\n  if (!Create_" +
    call.output.to_string() +
    "(env, result_value, result)) return nullptr;\n  return result;\n } catch (const TypeFault &e) { Check(env, napi_throw_type_error(env, nullptr, e.what())); return nullptr; }\n catch (const RangeFault &e) { Check(env, napi_throw_range_error(env, nullptr, e.what())); return nullptr; }\n catch (const std::length_error &e) { Check(env, napi_throw_range_error(env, nullptr, e.what())); return nullptr; }\n catch (const std::exception &) { Check(env, napi_throw_error(env, nullptr, \"native allocation failed\")); return nullptr; }\n}\n"
  source
}

///|
pub fn Project::generate(
  self : Project,
) -> GeneratedArtifacts raise ConfigError {
  let plan = make_generation_plan(self)
  let accessors = accessor_definitions(plan)
  let mut wrapper = self.business_wrapper()
  let exports = self.functions.map(f => "\"moonohos_raw_" + f.name + "\"")
  let mut header = self
    .business_header()
    .replace_all(old="#ifdef __cplusplus\n}\n#endif\n", new="")
  let mut embed = "#include \"moonohos.h\"\n#define main moonohos_unused_main\n#include \"core.c\"\n#undef main\nvoid moonohos_initialize(void) { static char name[] = \"moonohos\"; static char *args[] = {name, 0}; moonbit_runtime_init(1, args); moonbit_init(); }\n" +
    self.business_adapters()
  for accessor in accessors {
    wrapper += moon_export(
      accessor.name,
      accessor.params,
      accessor.result,
      accessor.expression,
    )
    exports.push("\"moonohos_raw_" + accessor.name + "\"")
    header += accessor.result.c_name() +
      " moonohos_" +
      accessor.name +
      "(" +
      c_parameters(accessor.params) +
      ");\n"
    embed += raw_adapter(accessor.name, accessor.params, accessor.result)
  }
  header += "#ifdef __cplusplus\n}\n#endif\n"
  let package_file = "import { \"" +
    self.package_name +
    "\" @core, }\npkgtype(kind: \"executable\")\noptions(link: { \"native\": { \"exports\": [" +
    exports.join(", ") +
    "] } })\n"
  let mut native = native_prelude() + container_runtime()
  for type_ in plan.types {
    if type_.kind != Scalar(Void) {
      native += cpp_reader(type_, self) +
        cpp_make(type_, plan.types) +
        cpp_copy(type_, plan.types, self)
    }
    native += cpp_create(type_, self)
  }
  for call in plan.calls {
    native += cpp_callback(call, plan.types)
  }
  native += "static napi_value Init(napi_env env, napi_value exports) { napi_property_descriptor properties[] = {\n"
  for call in plan.calls {
    native += "{\"" +
      call.function.name +
      "\", nullptr, Call_" +
      call.function.name +
      ", nullptr, nullptr, nullptr, napi_default, nullptr},\n"
  }
  native += "}; if (!Check(env, napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties))) return nullptr; return exports; }\nNAPI_MODULE(" +
    self.native_module +
    ", Init)\n"
  let declarations = record_declarations(self) +
    self.functions
    .map(f => {
      "export const " +
      f.name +
      ": (" +
      f.params.map(p => p.name + ": " + p.kind.ark_name()).join(", ") +
      ") => " +
      f.result.ark_name() +
      ";\n"
    })
    .join("")
  let shell : Config = {
    module_dir: self.module_dir,
    package_name: self.package_name,
    native_module: self.native_module,
    functions: [],
  }
  {
    wrapper,
    package_file,
    header,
    embed,
    native,
    declarations,
    cmake: cmake_source(shell),
  }
}

///|
pub fn Project::generate_arrays(
  self : Project,
) -> GeneratedArtifacts raise ConfigError {
  self.generate()
}
