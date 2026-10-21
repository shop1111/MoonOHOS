///|
/// Process gate, handle and cancellation state used by generated callbacks.
/// MoonBit reference counts are not atomic and the runtime keeps process-wide
/// state, so every MoonBit object is created, used and released while the gate
/// is held, on whichever thread (JS or Node-API worker) holds it.
fn lifecycle_core() -> String {
  (
    #|#include <algorithm>
    #|#include <atomic>
    #|#include <memory>
    #|#include <thread>
    #|#include <utility>
    #|static std::atomic<int32_t> live_handles{0}, released_handles{0}, pending_tasks{0};
    #|static std::atomic<int32_t> completed_tasks{0}, cancelled_tasks{0}, env_cleanups{0};
    #|class Gate {
    #| public:
    #|  void lock() { m_.lock(); owner_.store(std::this_thread::get_id()); std::call_once(initialized, moonohos_initialize); }
    #|  void unlock() { Drain(); owner_.store(std::thread::id()); m_.unlock(); Retry(); }
    #|  bool held() const { return owner_.load() == std::this_thread::get_id(); }
    #|  // Releases one owned reference without blocking a JS thread behind a long task.
    #|  void release(void *value) noexcept {
    #|    if (!value) return;
    #|    if (held()) { moonbit_decref(value); return; }
    #|    try { std::lock_guard<std::mutex> guard(queue_); deferred_.push_back(value); } catch (...) { return; }
    #|    Retry();
    #|  }
    #| private:
    #|  void Drain() noexcept {
    #|    std::vector<void *> values;
    #|    { std::lock_guard<std::mutex> guard(queue_); values.swap(deferred_); }
    #|    for (void *value : values) moonbit_decref(value);
    #|  }
    #|  void Retry() noexcept {
    #|    { std::lock_guard<std::mutex> guard(queue_); if (deferred_.empty()) return; }
    #|    if (!m_.try_lock()) return;
    #|    owner_.store(std::this_thread::get_id());
    #|    std::call_once(initialized, moonohos_initialize);
    #|    Drain();
    #|    owner_.store(std::thread::id());
    #|    m_.unlock();
    #|  }
    #|  std::mutex m_, queue_;
    #|  std::atomic<std::thread::id> owner_{};
    #|  std::vector<void *> deferred_;
    #|};
    #|static Gate gate;
    #|struct GateLock {
    #|  GateLock() { gate.lock(); }
    #|  ~GateLock() { gate.unlock(); }
    #|  GateLock(const GateLock &) = delete;
    #|  GateLock &operator=(const GateLock &) = delete;
    #|};
    #|struct CancelState { std::atomic<bool> cancelled{false}; };
    #|static CancelState *current_cancel = nullptr; // gate-protected
    #|extern "C" int32_t moonohos_bridge_cancelled(void) { return current_cancel && current_cancel->cancelled.load() ? 1 : 0; }
    #|struct CancelScope {
    #|  explicit CancelScope(CancelState *state) { current_cancel = state; }
    #|  ~CancelScope() { current_cancel = nullptr; }
    #|};
    #|static bool business_raised = false; // gate-protected
    #|static std::u16string business_message;
    #|extern "C" void moonohos_business_error(moonbit_string_t message) {
    #|  business_raised = true;
    #|  try { business_message = CopyText(message); } catch (...) { business_message.clear(); }
    #|}
    #|struct ClosedFault : std::runtime_error { using std::runtime_error::runtime_error; };
    #|struct BusinessFault : std::runtime_error {
    #|  std::u16string text;
    #|  explicit BusinessFault(std::u16string value) : std::runtime_error("business error"), text(std::move(value)) {}
    #|};
    #|struct HandleState {
    #|  void *ptr;
    #|  uint32_t kind;
    #|  HandleState(void *value, uint32_t tag) : ptr(value), kind(tag) { live_handles.fetch_add(1); }
    #|  ~HandleState() { Close(); }
    #|  HandleState(const HandleState &) = delete;
    #|  HandleState &operator=(const HandleState &) = delete;
    #|  bool Pin() { std::lock_guard<std::mutex> guard(m_); if (closed_) return false; ++pins_; return true; }
    #|  void Unpin() { if (Settle(false)) Release(); }
    #|  void Close() { if (Settle(true)) Release(); }
    #|  bool IsClosed() { std::lock_guard<std::mutex> guard(m_); return closed_; }
    #| private:
    #|  // Closing while a task holds a pin defers the release to the last unpin.
    #|  bool Settle(bool closing) {
    #|    std::lock_guard<std::mutex> guard(m_);
    #|    if (closing) { if (closed_) return false; closed_ = true; } else { --pins_; }
    #|    if (!closed_ || pins_ > 0 || released_) return false;
    #|    released_ = true;
    #|    return true;
    #|  }
    #|  void Release() { void *value = ptr; ptr = nullptr; gate.release(value); live_handles.fetch_sub(1); released_handles.fetch_add(1); }
    #|  std::mutex m_;
    #|  int32_t pins_ = 0;
    #|  bool closed_ = false, released_ = false;
    #|};
    #|struct HandlePin {
    #|  std::shared_ptr<HandleState> state;
    #|  explicit HandlePin(std::shared_ptr<HandleState> value) : state(std::move(value)) {}
    #|  ~HandlePin() { if (state) state->Unpin(); }
    #|  HandlePin(const HandlePin &) = delete;
    #|  HandlePin &operator=(const HandlePin &) = delete;
    #|};
    #|struct AdapterSlot {
    #|  void *ptr = nullptr;
    #|  void (*release)(void *) = nullptr;
    #|  AdapterSlot(void *value, void (*finish)(void *)) : ptr(value), release(finish) {}
    #|  AdapterSlot(AdapterSlot &&other) noexcept : ptr(std::exchange(other.ptr, nullptr)), release(other.release) {}
    #|  AdapterSlot(const AdapterSlot &) = delete;
    #|  AdapterSlot &operator=(const AdapterSlot &) = delete;
    #|  AdapterSlot &operator=(AdapterSlot &&) = delete;
    #|  ~AdapterSlot() { if (ptr && release) release(ptr); }
    #|};
    #|struct EnvState : std::enable_shared_from_this<EnvState> {
    #|  std::mutex m;
    #|  bool closing = false;
    #|  std::vector<std::weak_ptr<HandleState>> handles;
    #|  std::vector<std::weak_ptr<CancelState>> tokens;
    #|  template <class T> static void Track(std::vector<std::weak_ptr<T>> &list, const std::shared_ptr<T> &value) {
    #|    list.erase(std::remove_if(list.begin(), list.end(), [](const std::weak_ptr<T> &item) { return item.expired(); }), list.end());
    #|    list.push_back(value);
    #|  }
    #|  void TrackHandle(const std::shared_ptr<HandleState> &value) { std::lock_guard<std::mutex> guard(m); Track(handles, value); }
    #|  void TrackToken(const std::shared_ptr<CancelState> &value) { std::lock_guard<std::mutex> guard(m); Track(tokens, value); }
    #|  bool Closing() { std::lock_guard<std::mutex> guard(m); return closing; }
    #|};
    #|
  ) +
  "\n"
}

///|
/// Node-API side of handles, tokens, errors, diagnostics and env cleanup.
fn lifecycle_napi() -> String {
  (
    #|#ifndef NAPI_AUTO_LENGTH
    #|#define NAPI_AUTO_LENGTH SIZE_MAX
    #|#endif
    #|constexpr uint32_t TokenKind = 0x4d4f0000u;
    #|struct Wrapped {
    #|  uint32_t kind;
    #|  std::shared_ptr<HandleState> handle;
    #|  std::shared_ptr<CancelState> cancel;
    #|};
    #|static void FinalizeWrapped(napi_env, void *data, void *) { delete static_cast<Wrapped *>(data); }
    #|enum class Outcome { Ok, Cancelled, Type, Range, Closed, Business, Native };
    #|static Outcome Classify(std::exception_ptr error, std::string &message, std::u16string &business) {
    #|  try { std::rethrow_exception(error); }
    #|  catch (const TypeFault &e) { message = e.what(); return Outcome::Type; }
    #|  catch (const RangeFault &e) { message = e.what(); return Outcome::Range; }
    #|  catch (const std::length_error &e) { message = e.what(); return Outcome::Range; }
    #|  catch (const ClosedFault &e) { message = e.what(); return Outcome::Closed; }
    #|  catch (const BusinessFault &e) { business = e.text; return Outcome::Business; }
    #|  catch (const std::exception &) { message = "native allocation failed"; return Outcome::Native; }
    #|  catch (...) { message = "native operation failed"; return Outcome::Native; }
    #|}
    #|static napi_value MakeError(napi_env env, Outcome outcome, const std::string &message, const std::u16string &business) {
    #|  // ArkRuntime rejects a null code for napi_create_*_error, so always pass one.
    #|  const char *code_text = outcome == Outcome::Cancelled ? "ERR_MOONOHOS_CANCELLED"
    #|    : outcome == Outcome::Closed ? "ERR_MOONOHOS_CLOSED"
    #|    : outcome == Outcome::Business ? "ERR_MOONOHOS_BUSINESS"
    #|    : outcome == Outcome::Type ? "ERR_MOONOHOS_TYPE"
    #|    : outcome == Outcome::Range ? "ERR_MOONOHOS_RANGE" : "ERR_MOONOHOS_NATIVE";
    #|  napi_value code = nullptr, text = nullptr, error = nullptr;
    #|  napi_status status = outcome == Outcome::Business
    #|    ? napi_create_string_utf16(env, business.data(), business.size(), &text)
    #|    : napi_create_string_utf8(env, message.data(), message.size(), &text);
    #|  if (status != napi_ok) return nullptr;
    #|  if (napi_create_string_utf8(env, code_text, NAPI_AUTO_LENGTH, &code) != napi_ok) return nullptr;
    #|  status = outcome == Outcome::Type ? napi_create_type_error(env, code, text, &error)
    #|    : outcome == Outcome::Range ? napi_create_range_error(env, code, text, &error)
    #|    : napi_create_error(env, code, text, &error);
    #|  if (status != napi_ok) return nullptr;
    #|  if (outcome == Outcome::Cancelled) {
    #|    napi_value name;
    #|    if (napi_create_string_utf8(env, "AbortError", NAPI_AUTO_LENGTH, &name) == napi_ok) napi_set_named_property(env, error, "name", name);
    #|  }
    #|  return error;
    #|}
    #|static void ThrowCurrent(napi_env env) {
    #|  std::string message;
    #|  std::u16string business;
    #|  Outcome outcome = Classify(std::current_exception(), message, business);
    #|  if (outcome == Outcome::Type) { napi_throw_type_error(env, nullptr, message.c_str()); return; }
    #|  if (outcome == Outcome::Range) { napi_throw_range_error(env, nullptr, message.c_str()); return; }
    #|  napi_value error = MakeError(env, outcome, message, business);
    #|  if (!error || napi_throw(env, error) != napi_ok) napi_throw_error(env, nullptr, "Node-API operation failed");
    #|}
    #|static bool UnwrapKind(napi_env env, napi_value value, uint32_t kind, const std::string &path, Wrapped *&out) {
    #|  napi_valuetype type;
    #|  if (!Check(env, napi_typeof(env, value, &type))) return false;
    #|  void *data = nullptr;
    #|  if (type != napi_object || napi_unwrap(env, value, &data) != napi_ok || !data) throw TypeFault(path + ": MoonOHOS object required");
    #|  out = static_cast<Wrapped *>(data);
    #|  if (out->kind != kind) throw TypeFault(path + ": MoonOHOS object of another kind");
    #|  return true;
    #|}
    #|static bool ReadHandle(napi_env env, napi_value value, uint32_t kind, BridgeValue &out, const std::string &path) {
    #|  Wrapped *wrapped = nullptr;
    #|  if (!UnwrapKind(env, value, kind, path, wrapped)) return false;
    #|  if (!wrapped->handle->Pin()) throw ClosedFault(path + ": handle is closed");
    #|  try { out.pin = std::make_shared<HandlePin>(wrapped->handle); } catch (...) { wrapped->handle->Unpin(); throw; }
    #|  return true;
    #|}
    #|static bool ReadToken(napi_env env, size_t argc, napi_value *argv, size_t index, std::shared_ptr<CancelState> &out, const std::string &path) {
    #|  if (argc > index) {
    #|    napi_valuetype type;
    #|    if (!Check(env, napi_typeof(env, argv[index], &type))) return false;
    #|    if (type != napi_undefined) {
    #|      Wrapped *wrapped = nullptr;
    #|      if (!UnwrapKind(env, argv[index], TokenKind, path, wrapped)) return false;
    #|      out = wrapped->cancel;
    #|      return true;
    #|    }
    #|  }
    #|  out = std::make_shared<CancelState>();
    #|  return true;
    #|}
    #|static AdapterSlot Acquire(napi_env env, napi_value value, void *(*acquire)(napi_env, napi_value), void (*release)(void *), const std::string &path) {
    #|  void *pointer = acquire(env, value);
    #|  if (!pointer) throw TypeFault(path + ": platform object required");
    #|  return AdapterSlot(pointer, release);
    #|}
    #|static bool ThisWrapped(napi_env env, napi_callback_info info, bool handle, Wrapped *&out) {
    #|  size_t argc = 0;
    #|  napi_value self = nullptr;
    #|  if (!Check(env, napi_get_cb_info(env, info, &argc, nullptr, &self, nullptr))) return false;
    #|  void *data = nullptr;
    #|  if (!self || napi_unwrap(env, self, &data) != napi_ok || !data ||
    #|      (handle ? !static_cast<Wrapped *>(data)->handle : !static_cast<Wrapped *>(data)->cancel)) {
    #|    Check(env, napi_throw_type_error(env, nullptr, "MoonOHOS method called on another object"));
    #|    return false;
    #|  }
    #|  out = static_cast<Wrapped *>(data);
    #|  return true;
    #|}
    #|static napi_value HandleClose(napi_env env, napi_callback_info info) {
    #|  Wrapped *wrapped;
    #|  if (!ThisWrapped(env, info, true, wrapped)) return nullptr;
    #|  wrapped->handle->Close();
    #|  napi_value result;
    #|  return Check(env, napi_get_undefined(env, &result)) ? result : nullptr;
    #|}
    #|static napi_value HandleIsClosed(napi_env env, napi_callback_info info) {
    #|  Wrapped *wrapped;
    #|  if (!ThisWrapped(env, info, true, wrapped)) return nullptr;
    #|  napi_value result;
    #|  return Check(env, napi_get_boolean(env, wrapped->handle->IsClosed(), &result)) ? result : nullptr;
    #|}
    #|static napi_value TokenCancel(napi_env env, napi_callback_info info) {
    #|  Wrapped *wrapped;
    #|  if (!ThisWrapped(env, info, false, wrapped)) return nullptr;
    #|  wrapped->cancel->cancelled.store(true);
    #|  napi_value result;
    #|  return Check(env, napi_get_undefined(env, &result)) ? result : nullptr;
    #|}
    #|static napi_value TokenIsCancelled(napi_env env, napi_callback_info info) {
    #|  Wrapped *wrapped;
    #|  if (!ThisWrapped(env, info, false, wrapped)) return nullptr;
    #|  napi_value result;
    #|  return Check(env, napi_get_boolean(env, wrapped->cancel->cancelled.load(), &result)) ? result : nullptr;
    #|}
    #|static bool CreateWrapped(napi_env env, std::unique_ptr<Wrapped> wrapped, napi_callback first, const char *first_name, napi_callback second, const char *second_name, napi_value &result) {
    #|  if (!Check(env, napi_create_object(env, &result))) return false;
    #|  napi_property_descriptor methods[] = {
    #|    {first_name, nullptr, first, nullptr, nullptr, nullptr, napi_default, nullptr},
    #|    {second_name, nullptr, second, nullptr, nullptr, nullptr, napi_default, nullptr},
    #|  };
    #|  if (!Check(env, napi_define_properties(env, result, 2, methods))) return false;
    #|  if (!Check(env, napi_wrap(env, result, wrapped.get(), FinalizeWrapped, nullptr, nullptr))) return false;
    #|  wrapped.release();
    #|  return true;
    #|}
    #|// Takes ownership of one MoonBit reference; failures release it.
    #|static bool CreateHandle(napi_env env, EnvState *state, void *value, uint32_t kind, napi_value &result) {
    #|  std::shared_ptr<HandleState> handle;
    #|  try { handle = std::make_shared<HandleState>(value, kind); } catch (...) { gate.release(value); throw; }
    #|  if (!state) throw std::runtime_error("module state unavailable");
    #|  state->TrackHandle(handle);
    #|  std::unique_ptr<Wrapped> wrapped(new Wrapped{kind, handle, nullptr});
    #|  return CreateWrapped(env, std::move(wrapped), HandleClose, "close", HandleIsClosed, "isClosed", result);
    #|}
    #|static napi_value Call_createCancelToken(napi_env env, napi_callback_info) {
    #|  try {
    #|    std::unique_ptr<Wrapped> wrapped(new Wrapped{TokenKind, nullptr, std::make_shared<CancelState>()});
    #|    napi_value result;
    #|    return CreateWrapped(env, std::move(wrapped), TokenCancel, "cancel", TokenIsCancelled, "isCancelled", result) ? result : nullptr;
    #|  } catch (...) { ThrowCurrent(env); return nullptr; }
    #|}
    #|static napi_value Call_moonohos_diagnostics(napi_env env, napi_callback_info) {
    #|  napi_value result;
    #|  if (!Check(env, napi_create_object(env, &result))) return nullptr;
    #|  const std::pair<const char *, int32_t> values[] = {
    #|    {"liveHandles", live_handles.load()}, {"releasedHandles", released_handles.load()},
    #|    {"pendingTasks", pending_tasks.load()}, {"completedTasks", completed_tasks.load()},
    #|    {"cancelledTasks", cancelled_tasks.load()}, {"envCleanups", env_cleanups.load()},
    #|  };
    #|  for (const auto &entry : values) {
    #|    napi_value value;
    #|    if (!Check(env, napi_create_int32(env, entry.second, &value))) return nullptr;
    #|    if (!Check(env, napi_set_named_property(env, result, entry.first, value))) return nullptr;
    #|  }
    #|  return result;
    #|}
    #|struct AsyncTask {
    #|  std::shared_ptr<EnvState> state;
    #|  std::shared_ptr<CancelState> cancel;
    #|  napi_async_work work = nullptr;
    #|  napi_deferred deferred = nullptr;
    #|  std::vector<BridgeValue> args;
    #|  std::vector<AdapterSlot> adapters;
    #|  BridgeValue result_value;
    #|  void *handle_result = nullptr;
    #|  Outcome outcome = Outcome::Native;
    #|  std::string message;
    #|  std::u16string business;
    #|  ~AsyncTask() { gate.release(handle_result); }
    #|};
    #|// Runs on the JS thread; never resolves twice and never touches MoonBit objects.
    #|static void SettleTask(napi_env env, std::unique_ptr<AsyncTask> task, napi_status status, bool (*create)(napi_env, AsyncTask &, napi_value &)) {
    #|  pending_tasks.fetch_sub(1);
    #|  napi_delete_async_work(env, task->work);
    #|  if (status == napi_cancelled) task->outcome = Outcome::Cancelled;
    #|  if (task->outcome == Outcome::Cancelled) task->message = "task cancelled";
    #|  (task->outcome == Outcome::Cancelled ? cancelled_tasks : completed_tasks).fetch_add(1);
    #|  if (task->state->Closing()) return;
    #|  if (task->outcome == Outcome::Ok) {
    #|    napi_value value = nullptr;
    #|    bool created = false;
    #|    try { created = create(env, *task, value); } catch (...) { task->outcome = Classify(std::current_exception(), task->message, task->business); }
    #|    if (created && napi_resolve_deferred(env, task->deferred, value) == napi_ok) return;
    #|    if (created) { task->outcome = Outcome::Native; task->message = "cannot resolve promise"; }
    #|  }
    #|  napi_value error = nullptr;
    #|  if (task->outcome == Outcome::Ok) {
    #|    if (napi_get_and_clear_last_exception(env, &error) != napi_ok) error = nullptr;
    #|    if (!error) error = MakeError(env, Outcome::Native, "cannot create result", u"");
    #|  } else {
    #|    error = MakeError(env, task->outcome, task->message, task->business);
    #|  }
    #|  if (!error) napi_get_undefined(env, &error);
    #|  napi_reject_deferred(env, task->deferred, error);
    #|}
    #|static napi_value QueueTask(napi_env env, std::unique_ptr<AsyncTask> task, const char *name, napi_async_execute_callback execute, napi_async_complete_callback complete) {
    #|  if (task->state->Closing()) throw ClosedFault(std::string(name) + ": environment is closing");
    #|  task->state->TrackToken(task->cancel);
    #|  napi_value resource, promise;
    #|  if (!Check(env, napi_create_string_utf8(env, name, NAPI_AUTO_LENGTH, &resource))) return nullptr;
    #|  if (!Check(env, napi_create_async_work(env, nullptr, resource, execute, complete, task.get(), &task->work))) return nullptr;
    #|  if (!Check(env, napi_create_promise(env, &task->deferred, &promise))) { napi_delete_async_work(env, task->work); return nullptr; }
    #|  pending_tasks.fetch_add(1);
    #|  if (!Check(env, napi_queue_async_work_with_qos(env, task->work, napi_qos_user_initiated))) {
    #|    pending_tasks.fetch_sub(1);
    #|    napi_delete_async_work(env, task->work);
    #|    napi_value error = nullptr;
    #|    if (napi_get_and_clear_last_exception(env, &error) == napi_ok && error) napi_reject_deferred(env, task->deferred, error);
    #|    return promise;
    #|  }
    #|  task.release();
    #|  return promise;
    #|}
    #|// Env teardown: cancel tracked tokens and close every live handle.
    #|static void CleanupEnv(void *data) {
    #|  auto *holder = static_cast<std::shared_ptr<EnvState> *>(data);
    #|  std::vector<std::shared_ptr<HandleState>> handles;
    #|  std::vector<std::shared_ptr<CancelState>> tokens;
    #|  try {
    #|    std::lock_guard<std::mutex> guard((*holder)->m);
    #|    (*holder)->closing = true;
    #|    for (auto &item : (*holder)->handles) if (auto value = item.lock()) handles.push_back(value);
    #|    for (auto &item : (*holder)->tokens) if (auto value = item.lock()) tokens.push_back(value);
    #|  } catch (...) {}
    #|  for (auto &token : tokens) token->cancelled.store(true);
    #|  for (auto &handle : handles) handle->Close();
    #|  env_cleanups.fetch_add(1);
    #|  delete holder;
    #|}
    #|
  ) +
  "\n"
}
