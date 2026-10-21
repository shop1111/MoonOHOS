///|
/// Expressions naming where one call keeps its converted values.
priv struct CallSlots {
  arg : (Int) -> String
  adapter : (Int) -> String
  value : String
  handle : String
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
  }
  let needs_info = count > 0 || call.function.result is Handle(_)
  let mut source = "static napi_value Call_" +
    name +
    "(napi_env env, napi_callback_info info) {\n try {\n  Budget input_budget{" +
    bounded_text(call) +
    "}, output_budget{" +
    bounded_text(call) +
    "};\n  Ancestors ancestors{env, {}};\n  BridgeValue result_value;\n  void *handle_result = nullptr;\n  std::vector<AdapterSlot> adapters;\n"
  if needs_info {
    source += "  size_t argc = " +
      count.to_string() +
      "; napi_value argv[" +
      count.max(1).to_string() +
      "] = {}; void *data = nullptr;\n  if (!Check(env, napi_get_cb_info(env, info, &argc, " +
      (if count > 0 { "argv" } else { "nullptr" }) +
      ", nullptr, &data))) return nullptr;\n"
    if count > 0 {
      source += "  if (argc < " +
        count.to_string() +
        ") throw TypeFault(\"" +
        name +
        ": missing arguments\");\n"
    }
    source += "  EnvState *state = static_cast<EnvState *>(data); (void)state;\n"
  }
  for index in 0..<count {
    source += "  BridgeValue arg" + index.to_string() + ";\n"
  }
  source += read_arguments(call, plan, slots)
  source += "  { GateLock lock; CancelScope scope(nullptr);\n" +
    locked_body(call, plan, slots) +
    "  }\n  napi_value result;\n  if (!" +
    result_creation(call, plan, "result_value", "handle_result", "state") +
    ") return nullptr;\n  return result;\n } catch (...) { ThrowCurrent(env); return nullptr; }\n}\n"
  source
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
  }
  let mut source = "static void Execute_" +
    name +
    "(napi_env, void *data) {\n  auto *task = static_cast<AsyncTask *>(data);\n  if (task->cancel->cancelled.load()) { task->outcome = Outcome::Cancelled; return; }\n  try {\n    Budget output_budget{" +
    bounded_text(call) +
    "};\n    { GateLock lock; CancelScope scope(task->cancel.get());\n" +
    locked_body(call, plan, slots) +
    "    if (task->cancel->cancelled.load() && task->handle_result) { moonbit_decref(task->handle_result); task->handle_result = nullptr; }\n    }\n    task->outcome = task->cancel->cancelled.load() ? Outcome::Cancelled : Outcome::Ok;\n  } catch (...) { task->outcome = Classify(std::current_exception(), task->message, task->business); }\n}\n"
  source += "static bool Result_" +
    name +
    "(napi_env env, AsyncTask &task, napi_value &result) {\n  return " +
    result_creation(
      call, plan, "task.result_value", "task.handle_result", "task.state.get()",
    ) +
    ";\n}\nstatic void Complete_" +
    name +
    "(napi_env env, napi_status status, void *data) {\n  SettleTask(env, std::unique_ptr<AsyncTask>(static_cast<AsyncTask *>(data)), status, Result_" +
    name +
    ");\n}\n"
  source += "static napi_value Call_" +
    name +
    "(napi_env env, napi_callback_info info) {\n try {\n  Budget input_budget{" +
    bounded_text(call) +
    "};\n  Ancestors ancestors{env, {}};\n  size_t argc = " +
    (count + 1).to_string() +
    "; napi_value argv[" +
    (count + 1).to_string() +
    "] = {}; void *data = nullptr;\n  if (!Check(env, napi_get_cb_info(env, info, &argc, argv, nullptr, &data))) return nullptr;\n  if (argc < " +
    count.to_string() +
    ") throw TypeFault(\"" +
    name +
    ": missing arguments\");\n  auto *state = static_cast<EnvState *>(data);\n  if (!state) throw std::runtime_error(\"module state unavailable\");\n  std::unique_ptr<AsyncTask> task(new AsyncTask());\n  task->state = state->shared_from_this();\n  task->args.resize(" +
    count.to_string() +
    ");\n" +
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
    ");\n } catch (...) { ThrowCurrent(env); return nullptr; }\n}\n"
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
      " {\n  close(): void;\n  isClosed(): boolean;\n}\n"
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
    source += if call.function.is_async {
      async_callback(call, plan)
    } else {
      sync_callback(call, plan)
    }
  }
  source
}
