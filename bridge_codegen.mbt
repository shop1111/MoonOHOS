///|
/// Expressions naming where one call keeps its converted values.
priv struct CallSlots {
  arg : (Int32) -> String
  adapter : (Int32) -> String
  value : String
  handle : String
  /// The call's EventChannel (an lvalue expression).
  events : String
}

///|
fn handle_kind(project : Project, name : String) -> String {
  let index = project.handles.search_by(h => h == name).unwrap_or(0)
  // 0x4d4f0001 + index; TokenKind is 0x4d4f0000.
  (1297022977 + index).to_string() + "u"
}

///|
fn find_adapter(
  project : Project,
  pkg_alias : String,
  type_name : String,
) -> AdapterDef raise ConfigError {
  for adapter in project.adapters {
    if adapter.pkg_alias == pkg_alias && adapter.type_name == type_name {
      return adapter
    }
  }
  raise Invalid(
    "generation: platform type @" +
    pkg_alias +
    "." +
    type_name +
    " has no native adapter; add its package with a moonohos.native.json descriptor",
  )
}

///|
/// Converts each argument on the JS thread into owned C++ data or pins.
fn read_arguments(
  call : CallPlan,
  plan : GenerationPlan,
  slots : CallSlots,
) -> String raise ConfigError {
  let mut source = ""
  let mut adapter = 0
  for index, type_index in call.inputs {
    let param = call.function.params[index]
    let path = "\"" + call.function.name + "." + param.name + "\""
    let argv = "argv[" + index.to_string() + "]"
    match param.kind {
      Callback(_) =>
        source += "  if (!ReadCallback(env, " +
          argv +
          ", " +
          slots.events +
          ", " +
          path +
          ")) return nullptr;\n"
      Handle(name) =>
        source += "  if (!ReadHandle(env, " +
          argv +
          ", " +
          handle_kind(plan.project, name) +
          ", " +
          (slots.arg)(index) +
          ", " +
          path +
          ")) return nullptr;\n"
      External(pkg_alias, type_name) => {
        let spec = find_adapter(plan.project, pkg_alias, type_name)
        source += "  " +
          (slots.adapter)(-1) +
          ".push_back(Acquire(env, " +
          argv +
          ", " +
          spec.acquire +
          ", " +
          spec.release +
          ", " +
          path +
          "));\n"
        adapter += 1
      }
      _ =>
        source += "  if (!Read_" +
          type_index.to_string() +
          "(env, " +
          argv +
          ", " +
          (slots.arg)(index) +
          ", input_budget, ancestors, 0, " +
          path +
          ")) return nullptr;\n"
    }
  }
  ignore(adapter)
  source
}

///|
/// Body executed while the gate is held: build MoonBit inputs, call, copy out.
fn locked_body(
  call : CallPlan,
  plan : GenerationPlan,
  slots : CallSlots,
) -> String {
  let types = plan.types
  let mut source = ""
  let args : Array[String] = []
  let mut adapter = 0
  for index, type_index in call.inputs {
    let kind = call.function.params[index].kind
    let suffix = index.to_string()
    match kind {
      Callback(_) => args.push(slots.events + ".id")
      Handle(_) => args.push((slots.arg)(index) + ".pin->state->ptr")
      External(_, _) => {
        args.push((slots.adapter)(adapter) + ".ptr")
        adapter += 1
      }
      _ if kind.is_reference() => {
        source += "    MoonOwner<" +
          kind.c_name() +
          "> owned" +
          suffix +
          "{Make_" +
          type_index.to_string() +
          "(" +
          (slots.arg)(index) +
          ")};\n"
        args.push("owned" + suffix + ".ptr")
      }
      _ =>
        args.push(
          "Make_" + type_index.to_string() + "(" + (slots.arg)(index) + ")",
        )
    }
  }
  let mut expression = call.symbol + "(" + args.join(", ") + ")"
  let result = call.function.result
  if call.function.raises {
    let envelope = types[call.raw_output].symbol
    source += "    business_raised = false; business_message.clear();\n    MoonOwner<void *> envelope{" +
      expression +
      "};\n    if (" +
      envelope +
      "_length(envelope.ptr) == 0) {\n      if (business_raised) throw BusinessFault(std::move(business_message));\n      throw std::runtime_error(\"empty result envelope\");\n    }\n"
    expression = envelope + "_get(envelope.ptr, 0)"
  }
  let output = "\"" + call.function.name + ".return\""
  match result {
    Scalar(Void) =>
      if !call.function.raises {
        source += "    " + expression + ";\n"
      }
    Handle(_) => source += "    " + slots.handle + " = " + expression + ";\n"
    _ if result.is_reference() =>
      source += "    MoonOwner<" +
        result.c_name() +
        "> returned{" +
        expression +
        "};\n    " +
        slots.value +
        " = Copy_" +
        call.output.to_string() +
        "(returned.ptr, output_budget, 0, " +
        output +
        ");\n"
    _ =>
      source += "    " +
        slots.value +
        " = Copy_" +
        call.output.to_string() +
        "(" +
        expression +
        ", output_budget, 0, " +
        output +
        ");\n"
  }
  source
}

///|
fn bounded_text(call : CallPlan) -> String {
  if call.bounded {
    "true"
  } else {
    "false"
  }
}

///|
fn result_creation(
  call : CallPlan,
  plan : GenerationPlan,
  value : String,
  handle : String,
  state : String,
) -> String {
  match call.function.result {
    Handle(name) =>
      "CreateHandle(env, " +
      state +
      ", std::exchange(" +
      handle +
      ", nullptr), " +
      handle_kind(plan.project, name) +
      ", result)"
    _ => "Create_" + call.output.to_string() + "(env, " + value + ", result)"
  }
}

///|
fn sync_callback(
  call : CallPlan,
  plan : GenerationPlan,
) -> String raise ConfigError {
  let name = call.function.name
  let count = call.inputs.length()
  let slots : CallSlots = {
    arg: i => "arg" + i.to_string(),
    adapter: i => {
      if i < 0 {
        "adapters"
      } else {
        "adapters[" + i.to_string() + "]"
      }
    },
    value: "result_value",
    handle: "handle_result",
    events: "events",
  }
  let callbacks = has_callbacks(call.function)
  let mut source = "static napi_value Impl_" +
    name +
    "(napi_env env, size_t argc, napi_value *argv, EnvState *state) {\n try {\n  (void)argc; (void)argv; (void)state;\n  Budget input_budget{" +
    bounded_text(call) +
    "}, output_budget{" +
    bounded_text(call) +
    "};\n  Ancestors ancestors{env, {}};\n  BridgeValue result_value;\n  void *handle_result = nullptr;\n  std::vector<AdapterSlot> adapters;\n"
  if count > 0 {
    source += "  if (argc < " +
      count.to_string() +
      ") throw TypeFault(\"" +
      name +
      ": missing arguments\");\n"
  }
  for index in 0..<count {
    source += "  BridgeValue arg" + index.to_string() + ";\n"
  }
  if callbacks {
    source += "  EventChannel events(env, false);\n"
  }
  source += read_arguments(call, plan, slots)
  source += if callbacks {
    // A failing callback wins over whatever the MoonBit call did afterwards.
    "  { GateLock lock; CancelScope scope(nullptr); EventScope event_scope(&events);\n   try {\n" +
    locked_body(call, plan, slots) +
    "   } catch (...) { if (!events.failed.load()) throw; }\n  }\n  if (events.failed.load()) { gate.release(std::exchange(handle_result, nullptr)); return events.Raise(env); }\n"
  } else {
    "  { GateLock lock; CancelScope scope(nullptr);\n" +
    locked_body(call, plan, slots) +
    "  }\n"
  }
  source += "  napi_value result;\n  if (!" +
    result_creation(call, plan, "result_value", "handle_result", "state") +
    ") return nullptr;\n  return result;\n } catch (...) { ThrowCurrent(env); return nullptr; }\n}\n" +
    entry_points(name, count)
  source
}

///|
/// `Call_` (module export) and `Method_` (handle method, `this` as the first
/// argument) both forward to `Impl_` with an explicit argument vector.
fn entry_points(name : String, slots : Int32) -> String {
  let size = slots.max(1).to_string()
  "static napi_value Call_" +
  name +
  "(napi_env env, napi_callback_info info) {\n  size_t argc = " +
  slots.to_string() +
  "; napi_value argv[" +
  size +
  "] = {}; void *data = nullptr;\n  if (!Check(env, napi_get_cb_info(env, info, &argc, argv, nullptr, &data))) return nullptr;\n  return Impl_" +
  name +
  "(env, argc, argv, static_cast<EnvState *>(data));\n}\n" +
  "[[maybe_unused]] static napi_value Method_" +
  name +
  "(napi_env env, napi_callback_info info) {\n  size_t argc = " +
  (slots - 1).max(0).to_string() +
  "; napi_value argv[" +
  size +
  "] = {}; napi_value self = nullptr; void *data = nullptr;\n  if (!Check(env, napi_get_cb_info(env, info, &argc, argv + 1, &self, &data))) return nullptr;\n  argv[0] = self;\n  return Impl_" +
  name +
  "(env, argc + 1, argv, static_cast<EnvState *>(data));\n}\n"
}

///|
fn async_callback(
  call : CallPlan,
  plan : GenerationPlan,
) -> String raise ConfigError {
  let name = call.function.name
  let count = call.inputs.length()
  let slots : CallSlots = {
    arg: i => "task->args[" + i.to_string() + "]",
    adapter: i => {
      if i < 0 {
        "task->adapters"
      } else {
        "task->adapters[" + i.to_string() + "]"
      }
    },
    value: "task->result_value",
    handle: "task->handle_result",
    events: "(*task->events)",
  }
  let mut source = "static void Execute_" +
    name +
    "(napi_env, void *data) {\n  auto *task = static_cast<AsyncTask *>(data);\n  if (task->cancel->cancelled.load()) { task->outcome = Outcome::Cancelled; return; }\n  try {\n    Budget output_budget{" +
    bounded_text(call) +
    "};\n    { GateLock lock; CancelScope scope(task->cancel.get()); EventScope events(task->events.get());\n" +
    locked_body(call, plan, slots) +
    "    if (task->cancel->cancelled.load() && task->handle_result) { moonbit_decref(task->handle_result); task->handle_result = nullptr; }\n    }\n    task->outcome = task->cancel->cancelled.load() ? Outcome::Cancelled : Outcome::Ok;\n  } catch (...) {\n    // A cancelled task reports cancellation even when MoonBit raised (e.g. @task.check()).\n    task->outcome = Classify(std::current_exception(), task->message, task->business);\n    if (task->cancel->cancelled.load()) task->outcome = Outcome::Cancelled;\n  }\n}\n"
  source += "static bool Result_" +
    name +
    "(napi_env env, AsyncTask &task, napi_value &result) {\n  return " +
    result_creation(
      call, plan, "task.result_value", "task.handle_result", "task.state.get()",
    ) +
    ";\n}\nstatic void Complete_" +
    name +
    "(napi_env env, napi_status status, void *data) {\n  FinishTask(env, std::unique_ptr<AsyncTask>(static_cast<AsyncTask *>(data)), status, Result_" +
    name +
    ");\n}\n"
  source += "static napi_value Impl_" +
    name +
    "(napi_env env, size_t argc, napi_value *argv, EnvState *state) {\n try {\n  Budget input_budget{" +
    bounded_text(call) +
    "};\n  Ancestors ancestors{env, {}};\n  if (argc < " +
    count.to_string() +
    ") throw TypeFault(\"" +
    name +
    ": missing arguments\");\n  if (!state) throw std::runtime_error(\"module state unavailable\");\n  std::unique_ptr<AsyncTask> task(new AsyncTask());\n  task->state = state->shared_from_this();\n  task->args.resize(" +
    count.to_string() +
    ");\n" +
    (if has_callbacks(call.function) {
      "  task->events = std::make_shared<EventChannel>(env, true);\n  if (!OpenEvents(env, *task->events, \"moonohos." +
      name +
      ".events\")) return nullptr;\n"
    } else {
      ""
    }) +
    read_arguments(call, plan, slots) +
    "  if (!ReadToken(env, argc, argv, " +
    count.to_string() +
    ", task->cancel, \"" +
    name +
    ".token\")) return nullptr;\n  return QueueTask(env, std::move(task), \"moonohos." +
    name +
    "\", Execute_" +
    name +
    ", Complete_" +
    name +
    ");\n } catch (...) { ThrowCurrent(env); return nullptr; }\n}\n" +
    entry_points(name, count + 1)
  source
}

///|
fn has_callbacks(function : Callable) -> Bool {
  function.params.any(p => p.kind is Callback(_))
}

///|
/// Per callback parameter: the `moonohos_event_*` function the MoonBit closure
/// calls (copies arguments under the gate) and the maker that creates the
/// ArkTS arguments on the JS thread.
fn event_functions(call : CallPlan, plan : GenerationPlan) -> String {
  let mut source = ""
  let mut slot = 0
  for index, param in call.function.params {
    guard param.kind is Callback(args) else { continue }
    let symbol = event_symbol(call.function.name, index)
    let types = plan.types[call.inputs[index]].dependencies
    let count = args.length().to_string()
    source += "static bool Args_" +
      symbol +
      "(napi_env env, const std::vector<BridgeValue> &args, std::vector<napi_value> &argv) {\n  (void)env; (void)args;\n  argv.resize(" +
      count +
      ");\n  return true"
    for i, t in types {
      source += " && Create_" +
        t.to_string() +
        "(env, args[" +
        i.to_string() +
        "], argv[" +
        i.to_string() +
        "])"
    }
    let params = args.mapi((i, a) => a.c_name() + " a" + i.to_string())
    params.insert(0, "int64_t id")
    source += ";\n}\nextern \"C\" void " +
      symbol +
      "(" +
      params.join(", ") +
      ") {\n  EventChannel *events = ActiveEvents(id);\n  if (!events) return;\n  try {\n    Budget budget{true};\n    std::vector<BridgeValue> args;\n    args.reserve(" +
      count +
      ");\n"
    for i, t in types {
      source += "    args.push_back(Copy_" +
        t.to_string() +
        "(a" +
        i.to_string() +
        ", budget, 0, \"" +
        call.function.name +
        "." +
        param.name +
        "[" +
        i.to_string() +
        "]\"));\n"
    }
    source += "    events->Emit(" +
      slot.to_string() +
      ", std::move(args), Args_" +
      symbol +
      ");\n  } catch (...) { events->Fail(std::current_exception()); }\n}\n"
    slot += 1
  }
  source
}

///|
fn adapter_declarations(project : Project) -> String {
  let mut source = ""
  let seen : Array[String] = []
  for adapter in project.adapters {
    if !seen.contains(adapter.acquire) {
      seen.push(adapter.acquire)
      source += "extern \"C\" void *" +
        adapter.acquire +
        "(napi_env, napi_value);\nextern \"C\" void " +
        adapter.release +
        "(void *);\n"
    }
  }
  source
}

///|
fn init_source(plan : GenerationPlan) -> String {
  let mut source = "static napi_value Init(napi_env env, napi_value exports) {\n  std::shared_ptr<EnvState> *holder = nullptr;\n  try { holder = new std::shared_ptr<EnvState>(std::make_shared<EnvState>()); }\n  catch (...) { Check(env, napi_throw_error(env, nullptr, \"native allocation failed\")); return nullptr; }\n  if (!Check(env, napi_add_env_cleanup_hook(env, CleanupEnv, holder))) { delete holder; return nullptr; }\n  EnvState *state = holder->get();\n  napi_property_descriptor properties[] = {\n"
  let names = plan.calls.map(c => c.function.name)
  names.push("createCancelToken")
  names.push("moonohos_diagnostics")
  for name in names {
    source += "{\"" +
      name +
      "\", nullptr, Call_" +
      name +
      ", nullptr, nullptr, nullptr, napi_default, state},\n"
  }
  source +
  "  };\n  if (!Check(env, napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties))) return nullptr;\n  return exports;\n}\nNAPI_MODULE(" +
  plan.project.native_module +
  ", Init)\n"
}

///|
fn ark_type(project : Project, kind : TypeExpr) -> String raise ConfigError {
  match kind {
    External(pkg_alias, type_name) =>
      find_adapter(project, pkg_alias, type_name).ark_type
    List(element) => "Array<" + ark_type(project, element) + ">"
    Optional(inner) => ark_type(project, inner) + " | undefined"
    Callback(args) =>
      "(" +
      args
      .mapi((i, a) => "arg" + i.to_string() + ": " + ark_type(project, a))
      .join(", ") +
      ") => void"
    _ => kind.ark_name()
  }
}

///|
fn bridge_declarations(project : Project) -> String raise ConfigError {
  let mut source = "// Generated by MoonOHOS " +
    moonohos_version() +
    ". Sync calls throw; async calls return Promises and accept an optional CancelToken.\n"
  let imports : Array[String] = []
  for adapter in project.adapters {
    if !imports.contains(adapter.ark_import) {
      imports.push(adapter.ark_import)
      source += adapter.ark_import + "\n"
    }
  }
  source += record_declarations(project)
  for handle in project.handles {
    source += "export interface " +
      handle +
      " {\n  close(): void;\n  isClosed(): boolean;\n"
    for meth in project.methods.filter(m => m.handle == handle) {
      match project.functions.search_by(f => f.name == meth.function) {
        Some(i) => {
          let function = project.functions[i]
          let params = function.params[1:]
            .to_owned()
            .map(p => p.name + ": " + ark_type(project, p.kind))
          let mut result = ark_type(project, function.result)
          if function.is_async {
            params.push("token?: CancelToken")
            result = "Promise<" + result + ">"
          }
          source += "  " +
            meth.function +
            "(" +
            params.join(", ") +
            "): " +
            result +
            ";\n"
        }
        None => ()
      }
    }
    source += "}\n"
  }
  source += "export interface CancelToken {\n  cancel(): void;\n  isCancelled(): boolean;\n}\nexport interface MoonOHOSDiagnostics {\n  liveHandles: number;\n  releasedHandles: number;\n  pendingTasks: number;\n  completedTasks: number;\n  cancelledTasks: number;\n  envCleanups: number;\n}\n"
  for function in project.functions {
    let params = function.params.map(p => {
      p.name + ": " + ark_type(project, p.kind)
    })
    let mut result = ark_type(project, function.result)
    if function.is_async {
      params.push("token?: CancelToken")
      result = "Promise<" + result + ">"
    }
    source += "export const " +
      function.name +
      ": (" +
      params.join(", ") +
      ") => " +
      result +
      ";\n"
  }
  source +
  "export const createCancelToken: () => CancelToken;\nexport const moonohos_diagnostics: () => MoonOHOSDiagnostics;\n"
}

///|
fn bridge_callbacks(plan : GenerationPlan) -> String raise ConfigError {
  let mut source = adapter_declarations(plan.project)
  for call in plan.calls {
    source += event_functions(call, plan)
    source += if call.function.is_async {
      async_callback(call, plan)
    } else {
      sync_callback(call, plan)
    }
  }
  source + attach_methods(plan.project)
}

///|
/// Tags every wrapped object with an identity derived from this module, so
/// objects created by another native module (including another MoonOHOS
/// module with the same struct layout) are rejected before `napi_unwrap`.
/// Approach borrowed from napi-mbt's use of `napi_type_tag_object`.
fn module_tag(project : Project) -> String {
  let digest = sha256(
    @utf8.encode(project.package_name + "\u{0}" + project.native_module),
  )
  let lower = digest[0:16]
  let upper = digest[16:32]
  "static const napi_type_tag &ModuleTag() {\n  static const napi_type_tag tag = {0x\{lower}ull, 0x\{upper}ull};\n  return tag;\n}\n"
}

///|
/// Defines each handle kind's methods on newly created handle objects.
fn attach_methods(project : Project) -> String {
  let mut source = module_tag(project) +
    "static bool AttachMethods(napi_env env, uint32_t kind, napi_value object, EnvState *state) {\n  (void)env; (void)object; (void)state;\n  switch (kind) {\n"
  for handle in project.handles {
    let methods = project.methods.filter(m => m.handle == handle)
    if methods.is_empty() {
      continue
    }
    source += "    case " +
      handle_kind(project, handle) +
      ": {\n      napi_property_descriptor methods[] = {\n"
    for meth in methods {
      source += "        {\"" +
        meth.function +
        "\", nullptr, Method_" +
        meth.function +
        ", nullptr, nullptr, nullptr, napi_default, state},\n"
    }
    source += "      };\n      return Check(env, napi_define_properties(env, object, " +
      methods.length().to_string() +
      ", methods));\n    }\n"
  }
  source + "    default: return true;\n  }\n}\n"
}
