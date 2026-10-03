///|
fn record_accessors(
  project : Project,
  type_ : TypePlan,
) -> Array[Accessor] raise ConfigError {
  let name = match type_.kind {
    Record(name) => name
    _ => raise Invalid("generation: expected record")
  }
  let record = project.record_def(name)
  let prefix = "type_" + type_.index.to_string()
  let accessors : Array[Accessor] = [
    {
      name: prefix + "_new",
      params: record.fields,
      result: type_.kind,
      expression: "{" + record.fields.map(f => f.name).join(", ") + "}",
    },
  ]
  for i, field in record.fields {
    accessors.push({
      name: prefix + "_field_" + i.to_string(),
      params: [{ name: "v", kind: type_.kind, }],
      result: field.kind,
      expression: "v." + field.name,
    })
  }
  accessors
}

///|
fn planned_record(
  project : Project,
  type_ : TypePlan,
) -> RecordDef raise ConfigError {
  match type_.kind {
    Record(name) => project.record_def(name)
    _ => raise Invalid("generation: expected record type")
  }
}

///|
fn record_reader(
  type_ : TypePlan,
  project : Project,
) -> String raise ConfigError {
  let record = planned_record(project, type_)
  let count = record.fields.length().to_string()
  let mut source = "  if (!Ordinary(env, value, false, path) || !ancestors.enter(value, path)) return false;\n  AncestorScope scope(ancestors);\n  budget.add(" +
    count +
    ", 0, depth + 1, path);\n  MOONOHOS_BUFFER_ALLOCATE();\n  out.children.resize(" +
    count +
    ");\n"
  for i, field in record.fields {
    source += "  { napi_value child; auto child_path = path + \"." +
      field.name +
      "\";\n    if (!Own(env, value, \"" +
      field.name +
      "\", child, child_path)) return false;\n    if (!Read_" +
      type_.dependencies[i].to_string() +
      "(env, child, out.children[" +
      i.to_string() +
      "], budget, ancestors, depth + 1, child_path)) return false;\n  }\n"
  }
  source
}

///|
fn record_maker(type_ : TypePlan, types : Array[TypePlan]) -> String {
  let mut source = ""
  let args : Array[String] = []
  for i, child_index in type_.dependencies {
    let child = types[child_index]
    let variable = "child" + i.to_string()
    let expression = "Make_" +
      child_index.to_string() +
      "(value.children[" +
      i.to_string() +
      "])"
    if child.kind.is_reference() {
      source += "  MoonOwner<" +
        child.kind.c_name() +
        "> " +
        variable +
        "{" +
        expression +
        "};\n"
      args.push(variable + ".ptr")
    } else {
      args.push(expression)
    }
  }
  source + "  return " + type_.symbol + "_new(" + args.join(", ") + ");\n"
}

///|
fn record_copier(
  type_ : TypePlan,
  project : Project,
  types : Array[TypePlan],
) -> String raise ConfigError {
  let record = planned_record(project, type_)
  let count = record.fields.length().to_string()
  let mut source = "  budget.add(" +
    count +
    ", 0, depth + 1, path);\n  MOONOHOS_BUFFER_ALLOCATE();\n  out.children.reserve(" +
    count +
    ");\n"
  for i, field in record.fields {
    let child = types[type_.dependencies[i]]
    let expression = type_.symbol + "_field_" + i.to_string() + "(value)"
    if child.kind.is_reference() {
      source += "  { MoonOwner<" +
        child.kind.c_name() +
        "> child{" +
        expression +
        "};\n    out.children.push_back(Copy_" +
        child.index.to_string() +
        "(child.ptr, budget, depth + 1, path + \"." +
        field.name +
        "\"));\n  }\n"
    } else {
      source += "  out.children.push_back(Copy_" +
        child.index.to_string() +
        "(" +
        expression +
        ", budget, depth + 1, path + \"." +
        field.name +
        "\"));\n"
    }
  }
  source
}

///|
fn record_creator(
  type_ : TypePlan,
  project : Project,
) -> String raise ConfigError {
  let mut source = "  if (!Check(env, napi_create_object(env, &result))) return false;\n"
  for i, field in planned_record(project, type_).fields {
    source += "  { napi_value child;\n    if (!Create_" +
      type_.dependencies[i].to_string() +
      "(env, value.children[" +
      i.to_string() +
      "], child)) return false;\n    if (!Check(env, napi_set_named_property(env, result, \"" +
      field.name +
      "\", child))) return false;\n  }\n"
  }
  source + "  return true;\n"
}

///|
fn record_declarations(project : Project) -> String raise ConfigError {
  let mut source = ""
  for record in project.record_order() {
    source += "export interface " + record.name + " {\n"
    for field in record.fields {
      source += "  " + field.name + ": " + field.kind.ark_name() + ";\n"
    }
    source += "}\n"
  }
  source
}
