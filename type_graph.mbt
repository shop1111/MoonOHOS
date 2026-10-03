///|
pub struct ConversionLimits {
  depth : Int
  nodes : Int
  bytes : Int
}

///|
pub fn conversion_limits() -> ConversionLimits {
  { depth: 32, nodes: 1048576, bytes: 67108864, }
}

///|
pub fn ConversionLimits::to_json(self : ConversionLimits) -> Json {
  { "maxDepth": self.depth, "maxNodes": self.nodes, "maxCopyBytes": self.bytes }
}

///|
pub fn Project::record_def(
  self : Project,
  name : String,
) -> RecordDef raise ConfigError {
  for record in self.records {
    if record.name == name {
      return record
    }
  }
  raise Invalid("type: undeclared record " + name)
}

///|
fn type_depth(
  project : Project,
  kind : TypeExpr,
  path : Array[String],
  depth : Int,
  heights : Map[String, Int],
) -> Int raise ConfigError {
  if depth > conversion_limits().depth {
    raise Invalid("type: nesting depth exceeds 32 at " + path.join(" -> "))
  }
  match kind {
    Scalar(Void) =>
      raise Invalid("type: Unit is not a container element or field")
    Scalar(_) => depth
    List(element) => type_depth(project, element, path, depth + 1, heights)
    Record(name) => {
      if path.contains(name) {
        raise Invalid(
          "type: recursive record dependency " +
          path.join(" -> ") +
          " -> " +
          name,
        )
      }
      match heights.get(name) {
        Some(height) => {
          if depth > conversion_limits().depth - height {
            raise Invalid("type: nesting depth exceeds 32 at " + name)
          }
          return depth + height
        }
        None => ()
      }
      let record = project.record_def(name)
      let mut maximum = depth + 1
      let next = path.copy()
      next.push(name)
      for field in record.fields {
        let child = type_depth(project, field.kind, next, depth + 1, heights)
        maximum = maximum.max(child)
      }
      if maximum > conversion_limits().depth {
        raise Invalid("type: nesting depth exceeds 32 at " + name)
      }
      heights[name] = maximum - depth
      maximum
    }
  }
}

///|
pub fn Project::validate(self : Project) -> Unit raise ConfigError {
  let names : Map[String, Bool] = Map([])
  for record in self.records {
    if names.contains(record.name) {
      raise Invalid("type: duplicate record " + record.name)
    }
    names[record.name] = true
  }
  let heights : Map[String, Int] = Map([])
  for record in self.records {
    type_depth(self, Record(record.name), [], 0, heights) |> ignore
  }
  for function in self.functions {
    for param in function.params {
      type_depth(self, param.kind, [], 0, heights) |> ignore
    }
    if function.result != Scalar(Void) {
      type_depth(self, function.result, [], 0, heights) |> ignore
    }
  }
}

///|
fn collect_type(
  project : Project,
  kind : TypeExpr,
  seen : Map[String, Bool],
  result : Array[TypeExpr],
) -> Unit raise ConfigError {
  let key = kind.moon_name()
  if seen.contains(key) {
    return
  }
  seen[key] = true
  match kind {
    Scalar(_) => ()
    List(element) => collect_type(project, element, seen, result)
    Record(name) =>
      for field in project.record_def(name).fields {
        collect_type(project, field.kind, seen, result)
      }
  }
  result.push(kind)
}

///|
/// Dependencies precede their users; declaration order is deterministic.
pub fn Project::reachable_types(
  self : Project,
) -> Array[TypeExpr] raise ConfigError {
  self.validate()
  let result : Array[TypeExpr] = []
  let seen : Map[String, Bool] = Map([])
  for function in self.functions {
    for param in function.params {
      collect_type(self, param.kind, seen, result)
    }
    collect_type(self, function.result, seen, result)
  }
  result
}

///|
pub fn Project::record_order(
  self : Project,
) -> Array[RecordDef] raise ConfigError {
  let records : Array[RecordDef] = []
  for kind in self.reachable_types() {
    if kind is Record(name) {
      records.push(self.record_def(name))
    }
  }
  records
}

///|
pub fn Callable::signature(self : Callable) -> String {
  "pub fn " +
  self.name +
  "(" +
  self.params.map(p => p.kind.moon_name()).join(", ") +
  ") -> " +
  self.result.moon_name()
}

///|
pub fn Project::summary(self : Project) -> Json raise ConfigError {
  let records : Array[Json] = self
    .record_order()
    .map(r => {
      "name": r.name,
      "fields": r.fields
      .map(f => { "name": f.name, "type": f.kind.moon_name() })
      .to_json(),
    })
  {
    "package": self.package_name,
    "nativeModule": self.native_module,
    "functions": self.functions.map(f => f.signature()).to_json(),
    "types": records.to_json(),
    "limits": conversion_limits().to_json(),
  }
}
