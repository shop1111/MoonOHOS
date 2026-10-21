// P1b: handwritten HarmonyOS probe for worker-thread MoonBit execution.
// MoonBit objects are created, used and released only while `gate` is held;
// Node-API values are touched only on the JS thread (Call/Complete).
#include <napi/native_api.h>
#include <hilog/log.h>
#include <rawfile/raw_file_manager.h>
#include <atomic>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>
#include <sys/syscall.h>
#include <unistd.h>
#include <moonbit.h>

extern "C" int32_t moonohos_probe_busy(int32_t);
extern "C" int32_t moonohos_probe_depth(int32_t);
extern "C" int32_t moonohos_probe_sum(moonbit_bytes_t);
extern "C" void moonohos_initialize(void);

static std::mutex gate;
static std::once_flag initialized;
static std::atomic<int32_t> cancel_requested{0};
static std::atomic<int32_t> pending{0};
static std::atomic<int32_t> cleanups{0};

extern "C" int32_t moonohos_probe_cancelled(void) { return cancel_requested.load(); }

static long Tid() { return static_cast<long>(syscall(SYS_gettid)); }

enum Kind { Busy, Depth, Raw };
static std::atomic<int32_t> next_id{0};
#define PROBE_LOG(...) OH_LOG_Print(LOG_APP, LOG_INFO, 0x4d4f, "MoonOHOSProbe", __VA_ARGS__)
struct Task {
  Kind kind;
  int32_t id = next_id.fetch_add(1) + 1;
  int32_t arg = 0;
  int32_t result = 0;
  long worker = 0;
  long caller = 0;
  NativeResourceManager *manager = nullptr;
  std::string path;
  std::string error;
  napi_deferred deferred = nullptr;
  napi_async_work work = nullptr;
};

static void Execute(napi_env, void *data) {
  auto *task = static_cast<Task *>(data);
  task->worker = Tid();
  PROBE_LOG("PROBE_EXEC_BEGIN id=%{public}d tid=%{public}ld", task->id, task->worker);
  std::vector<uint8_t> bytes;
  if (task->kind == Raw) {
    RawFile *file = OH_ResourceManager_OpenRawFile(task->manager, task->path.c_str());
    if (!file) { task->error = "rawfile open failed"; return; }
    long size = OH_ResourceManager_GetRawFileSize(file);
    if (size < 0 || size > (64 << 20)) { OH_ResourceManager_CloseRawFile(file); task->error = "rawfile size"; return; }
    bytes.resize(static_cast<size_t>(size));
    int read = size ? OH_ResourceManager_ReadRawFile(file, bytes.data(), bytes.size()) : 0;
    OH_ResourceManager_CloseRawFile(file);
    if (read != size) { task->error = "rawfile short read"; return; }
  }
  std::lock_guard<std::mutex> lock(gate);
  std::call_once(initialized, moonohos_initialize);
  switch (task->kind) {
    case Busy: task->result = moonohos_probe_busy(task->arg); PROBE_LOG("PROBE_EXEC_END id=%{public}d result=%{public}d", task->id, task->result); break;
    case Depth: task->result = moonohos_probe_depth(task->arg); break;
    case Raw: {
      moonbit_bytes_t value = moonbit_make_bytes_raw(static_cast<int32_t>(bytes.size()));
      if (!bytes.empty()) std::memcpy(value, bytes.data(), bytes.size());
      task->result = moonohos_probe_sum(value);
      moonbit_decref(value);
      break;
    }
  }
}

static void Complete(napi_env env, napi_status status, void *data) {
  auto *task = static_cast<Task *>(data);
  PROBE_LOG("PROBE_COMPLETE id=%{public}d status=%{public}d tid=%{public}ld", task->id, static_cast<int>(status), Tid());
  napi_value result = nullptr;
  if (status == napi_cancelled) {
    task->error = "cancelled before execution";
  }
  if (task->error.empty() && napi_create_object(env, &result) == napi_ok) {
    napi_value value, worker, caller;
    napi_create_int32(env, task->result, &value);
    napi_create_int64(env, task->worker, &worker);
    napi_create_int64(env, task->caller, &caller);
    napi_set_named_property(env, result, "value", value);
    napi_set_named_property(env, result, "workerTid", worker);
    napi_set_named_property(env, result, "callerTid", caller);
    napi_resolve_deferred(env, task->deferred, result);
  } else {
    napi_value message, error;
    napi_create_string_utf8(env, task->error.c_str(), task->error.size(), &message);
    napi_create_error(env, nullptr, message, &error);
    napi_reject_deferred(env, task->deferred, error);
  }
  napi_delete_async_work(env, task->work);
  if (task->manager) OH_ResourceManager_ReleaseNativeResourceManager(task->manager);
  pending.fetch_sub(1);
  delete task;
}

static napi_value Start(napi_env env, Task *task) {
  task->caller = Tid();
  napi_value promise, name;
  if (napi_create_promise(env, &task->deferred, &promise) != napi_ok ||
      napi_create_string_utf8(env, "moonohos.probe", NAPI_AUTO_LENGTH, &name) != napi_ok ||
      napi_create_async_work(env, nullptr, name, Execute, Complete, task, &task->work) != napi_ok) {
    if (task->manager) OH_ResourceManager_ReleaseNativeResourceManager(task->manager);
    delete task;
    napi_throw_error(env, nullptr, "cannot create async work");
    return nullptr;
  }
  if (napi_queue_async_work_with_qos(env, task->work, napi_qos_user_initiated) != napi_ok) {
    napi_delete_async_work(env, task->work);
    if (task->manager) OH_ResourceManager_ReleaseNativeResourceManager(task->manager);
    delete task;
    napi_throw_error(env, nullptr, "cannot queue async work");
    return nullptr;
  }
  pending.fetch_add(1);
  PROBE_LOG("PROBE_QUEUED id=%{public}d tid=%{public}ld", task->id, task->caller);
  return promise;
}

static bool IntArg(napi_env env, napi_callback_info info, int32_t &out) {
  size_t argc = 1; napi_value argv[1] = {nullptr};
  if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 1 ||
      napi_get_value_int32(env, argv[0], &out) != napi_ok) {
    napi_throw_type_error(env, nullptr, "integer required");
    return false;
  }
  return true;
}

static napi_value StartBusy(napi_env env, napi_callback_info info) {
  int32_t n; if (!IntArg(env, info, n)) return nullptr;
  auto *task = new Task{Busy}; task->arg = n; return Start(env, task);
}
static napi_value StartDepth(napi_env env, napi_callback_info info) {
  int32_t n; if (!IntArg(env, info, n)) return nullptr;
  auto *task = new Task{Depth}; task->arg = n; return Start(env, task);
}
static napi_value ReadRaw(napi_env env, napi_callback_info info) {
  size_t argc = 2; napi_value argv[2] = {nullptr, nullptr};
  if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 2) {
    napi_throw_type_error(env, nullptr, "resourceManager and path required"); return nullptr;
  }
  char path[256]; size_t length = 0;
  if (napi_get_value_string_utf8(env, argv[1], path, sizeof(path), &length) != napi_ok) {
    napi_throw_type_error(env, nullptr, "path string required"); return nullptr;
  }
  NativeResourceManager *manager = OH_ResourceManager_InitNativeResourceManager(env, argv[0]);
  if (!manager) { napi_throw_type_error(env, nullptr, "resourceManager required"); return nullptr; }
  auto *task = new Task{Raw}; task->manager = manager; task->path.assign(path, length);
  return Start(env, task);
}
static napi_value SyncBusy(napi_env env, napi_callback_info info) {
  int32_t n; if (!IntArg(env, info, n)) return nullptr;
  int32_t value;
  { std::lock_guard<std::mutex> lock(gate); std::call_once(initialized, moonohos_initialize); value = moonohos_probe_busy(n); }
  napi_value result; napi_create_int32(env, value, &result); return result;
}
static napi_value SetCancel(napi_env env, napi_callback_info info) {
  int32_t n; if (!IntArg(env, info, n)) return nullptr;
  cancel_requested.store(n); napi_value result; napi_get_undefined(env, &result); return result;
}
static napi_value Stats(napi_env env, napi_callback_info) {
  napi_value result, a, b, c;
  napi_create_object(env, &result);
  napi_create_int32(env, pending.load(), &a);
  napi_create_int32(env, cleanups.load(), &b);
  napi_create_int64(env, Tid(), &c);
  napi_set_named_property(env, result, "pending", a);
  napi_set_named_property(env, result, "cleanups", b);
  napi_set_named_property(env, result, "tid", c);
  return result;
}

static void Cleanup(void *) {
  int32_t count = cleanups.fetch_add(1) + 1;
  OH_LOG_Print(LOG_APP, LOG_INFO, 0x4d4f, "MoonOHOSProbe", "PROBE_ENV_CLEANUP count=%{public}d pending=%{public}d tid=%{public}ld",
               count, pending.load(), Tid());
}

static napi_value Init(napi_env env, napi_value exports) {
  napi_add_env_cleanup_hook(env, Cleanup, nullptr);
  napi_property_descriptor desc[] = {
    {"startBusy", nullptr, StartBusy, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"startDepth", nullptr, StartDepth, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"readRaw", nullptr, ReadRaw, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"syncBusy", nullptr, SyncBusy, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"setCancel", nullptr, SetCancel, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"stats", nullptr, Stats, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  if (napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc) != napi_ok) return nullptr;
  return exports;
}
NAPI_MODULE(asyncprobe, Init)
