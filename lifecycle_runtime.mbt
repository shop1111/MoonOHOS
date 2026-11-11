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
    #|// Bytes reported to the ArkTS GC for live handles (declared `size` functions).
    #|static std::atomic<int64_t> native_bytes{0};
    #|// Environments that loaded this module and have not been torn down.
    #|static std::atomic<int32_t> live_envs{0};
    #|class Gate {
    #| public:
    #|  // Re-entrant on the owning thread: an ArkTS callback invoked during a sync
    #|  // call may call the module again.
    #|  void lock() {
    #|    if (held()) { ++depth_; return; }
    #|    m_.lock(); owner_.store(std::this_thread::get_id()); std::call_once(initialized, moonohos_initialize);
    #|  }
    #|  void unlock() {
    #|    if (depth_ > 0) { --depth_; return; }
    #|    Drain(); owner_.store(std::thread::id()); m_.unlock(); Retry();
    #|  }
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
    #|  // Every gate holder re-checks the queue after unlocking, so a value queued
    #|  // while the gate was held is drained by that holder; without the loop a
    #|  // release queued during Drain() stayed until the next MoonBit call.
    #|  void Retry() noexcept {
    #|    while (true) {
    #|      { std::lock_guard<std::mutex> guard(queue_); if (deferred_.empty()) return; }
    #|      if (!m_.try_lock()) return; // the current holder drains on its way out
    #|      owner_.store(std::this_thread::get_id());
    #|      std::call_once(initialized, moonohos_initialize);
    #|      Drain();
    #|      owner_.store(std::thread::id());
    #|      m_.unlock();
    #|    }
    #|  }
    #|  std::mutex m_, queue_;
    #|  int32_t depth_ = 0; // owner only
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
    #|// For generated system bindings (0.8): SDK threads delivering callbacks
    #|// enter the gate before running MoonBit code.
    #|extern "C" void moonohos_gate_enter(void) { gate.lock(); }
    #|extern "C" void moonohos_gate_leave(void) { gate.unlock(); }
    #|struct CancelState { std::atomic<bool> cancelled{false}; };
    #|static CancelState *current_cancel = nullptr; // gate-protected
    #|static const std::atomic<bool> *current_failed = nullptr; // gate-protected: a callback of the running call failed
    #|extern "C" int32_t moonohos_bridge_cancelled(void) {
    #|  return (current_cancel && current_cancel->cancelled.load()) || (current_failed && current_failed->load()) ? 1 : 0;
    #|}
    #|struct CancelScope {
    #|  CancelState *previous;
    #|  explicit CancelScope(CancelState *state) : previous(current_cancel) { current_cancel = state; }
    #|  ~CancelScope() { current_cancel = previous; }
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
    #|  size_t bytes = 0; // reported to the GC when wrapped
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
    #|  void Release() { void *value = ptr; ptr = nullptr; gate.release(value); native_bytes.fetch_sub(static_cast<int64_t>(bytes)); live_handles.fetch_sub(1); released_handles.fetch_add(1); }
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
    #|// Generated per module: the type tag carried by every object this module wraps.
    #|static const napi_type_tag &ModuleTag();
    #|// Sets `own` when `value` (an object) was wrapped by this module.
    #|static bool OwnObject(napi_env env, napi_value value, bool &own) {
    #|  return Check(env, napi_check_object_type_tag(env, value, &ModuleTag(), &own));
    #|}
    #|static bool UnwrapKind(napi_env env, napi_value value, uint32_t kind, const std::string &path, Wrapped *&out) {
    #|  napi_valuetype type;
    #|  if (!Check(env, napi_typeof(env, value, &type))) return false;
    #|  if (type != napi_object) throw TypeFault(path + ": MoonOHOS object required");
    #|  bool own = false;
    #|  if (!OwnObject(env, value, own)) return false;
    #|  if (!own) throw TypeFault(path + ": MoonOHOS object of this module required");
    #|  void *data = nullptr;
    #|  if (napi_unwrap(env, value, &data) != napi_ok || !data) throw TypeFault(path + ": MoonOHOS object required");
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
    #|  bool own = false;
    #|  if (self) {
    #|    napi_valuetype type;
    #|    if (!Check(env, napi_typeof(env, self, &type))) return false;
    #|    if (type == napi_object && !OwnObject(env, self, own)) return false;
    #|  }
    #|  void *data = nullptr;
    #|  if (!own || napi_unwrap(env, self, &data) != napi_ok || !data ||
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
    #|static bool CreateWrapped(napi_env env, std::unique_ptr<Wrapped> wrapped, napi_callback first, const char *first_name, napi_callback second, const char *second_name, napi_value &result, size_t size = 0) {
    #|  if (!Check(env, napi_create_object(env, &result))) return false;
    #|  napi_property_descriptor methods[] = {
    #|    {first_name, nullptr, first, nullptr, nullptr, nullptr, napi_default, nullptr},
    #|    {second_name, nullptr, second, nullptr, nullptr, nullptr, napi_default, nullptr},
    #|  };
    #|  if (!Check(env, napi_define_properties(env, result, 2, methods))) return false;
    #|  // A declared size makes the ArkTS GC account for the MoonBit object (HarmonyOS
    #|  // does not export napi_adjust_external_memory; napi_wrap_enhance is API 18+).
    #|  napi_status wrapped_status = size
    #|    ? napi_wrap_enhance(env, result, wrapped.get(), FinalizeWrapped, false, nullptr, size, nullptr)
    #|    : napi_wrap(env, result, wrapped.get(), FinalizeWrapped, nullptr, nullptr);
    #|  if (!Check(env, wrapped_status)) return false;
    #|  wrapped.release();
    #|  return Check(env, napi_type_tag_object(env, result, &ModuleTag()));
    #|}
    #|// Generated per module: defines the methods declared for a handle kind.
    #|static bool AttachMethods(napi_env env, uint32_t kind, napi_value object, EnvState *state);
    #|// Takes ownership of one MoonBit reference; failures release it.
    #|static bool CreateHandle(napi_env env, EnvState *state, void *value, uint32_t kind, napi_value &result, size_t size) {
    #|  std::shared_ptr<HandleState> handle;
    #|  try { handle = std::make_shared<HandleState>(value, kind); } catch (...) { gate.release(value); throw; }
    #|  handle->bytes = size; native_bytes.fetch_add(static_cast<int64_t>(size));
    #|  if (!state) throw std::runtime_error("module state unavailable");
    #|  state->TrackHandle(handle);
    #|  std::unique_ptr<Wrapped> wrapped(new Wrapped{kind, handle, nullptr});
    #|  if (!CreateWrapped(env, std::move(wrapped), HandleClose, "close", HandleIsClosed, "isClosed", result, size)) return false;
    #|  return AttachMethods(env, kind, result, state);
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
    #|    {"liveEnvs", live_envs.load()},
    #|  };
    #|  for (const auto &entry : values) {
    #|    napi_value value;
    #|    if (!Check(env, napi_create_int32(env, entry.second, &value))) return nullptr;
    #|    if (!Check(env, napi_set_named_property(env, result, entry.first, value))) return nullptr;
    #|  }
    #|  napi_value bytes;
    #|  if (!Check(env, napi_create_double(env, static_cast<double>(native_bytes.load()), &bytes))) return nullptr;
    #|  if (!Check(env, napi_set_named_property(env, result, "nativeBytes", bytes))) return nullptr;
    #|  return result;
    #|}
    #|struct EventChannel;
    #|struct AsyncTask {
    #|  std::shared_ptr<EnvState> state;
    #|  std::shared_ptr<CancelState> cancel;
    #|  std::shared_ptr<EventChannel> events; // set when the function takes callbacks
    #|  napi_async_work work = nullptr;
    #|  napi_deferred deferred = nullptr;
    #|  std::vector<BridgeValue> args;
    #|  std::vector<AdapterSlot> adapters;
    #|  BridgeValue result_value;
    #|  void *handle_result = nullptr;
    #|  size_t handle_size = 0;
    #|  Outcome outcome = Outcome::Native;
    #|  std::string message;
    #|  std::u16string business;
    #|  ~AsyncTask() { gate.release(handle_result); }
    #|};
    #|using TaskCreator = bool (*)(napi_env, AsyncTask &, napi_value &);
    #|using EventMaker = bool (*)(napi_env, const std::vector<BridgeValue> &, std::vector<napi_value> &);
    #|struct PendingEvent { size_t slot; std::vector<BridgeValue> args; EventMaker make; };
    #|static std::atomic<int64_t> next_channel{1};
    #|// The ArkTS callbacks of one call. Sync calls invoke them directly on the JS
    #|// thread; async calls copy the arguments under the gate and queue them through
    #|// a threadsafe function, and the Promise settles after the queue drains. The
    #|// first failure wins, cancels the call cooperatively and skips later events.
    #|struct EventChannel {
    #|  const int64_t id = next_channel.fetch_add(1);
    #|  napi_env env; // JS thread; null once closed
    #|  const bool threaded;
    #|  std::vector<napi_value> functions; // sync: valid for the duration of the call
    #|  std::vector<napi_ref> refs;        // async
    #|  napi_threadsafe_function tsfn = nullptr;
    #|  std::atomic<bool> failed{false};
    #|  std::atomic<int32_t> pending{0};
    #|  std::exception_ptr fault;   // written once, by the first failure
    #|  napi_ref thrown = nullptr;  // JS thread
    #|  std::unique_ptr<AsyncTask> parked; // completed task waiting for queued events
    #|  napi_status parked_status = napi_ok;
    #|  TaskCreator parked_create = nullptr;
    #|  EventChannel(napi_env value, bool queue) : env(value), threaded(queue) {}
    #|  ~EventChannel() { Close(); }
    #|  EventChannel(const EventChannel &) = delete;
    #|  EventChannel &operator=(const EventChannel &) = delete;
    #|  void Close() noexcept {
    #|    if (!env) return;
    #|    napi_env e = std::exchange(env, nullptr);
    #|    for (napi_ref ref : refs) napi_delete_reference(e, ref);
    #|    refs.clear();
    #|    if (thrown) napi_delete_reference(e, std::exchange(thrown, nullptr));
    #|    if (tsfn) napi_release_threadsafe_function(std::exchange(tsfn, nullptr), napi_tsfn_release);
    #|  }
    #|  void Fail(std::exception_ptr error) noexcept { if (!failed.exchange(true)) fault = error; }
    #|  // JS thread: keeps the pending exception (or a native error) for the caller.
    #|  void Capture(napi_env e) noexcept {
    #|    napi_value error = nullptr;
    #|    napi_valuetype type = napi_undefined;
    #|    if (napi_get_and_clear_last_exception(e, &error) != napi_ok || !error || napi_typeof(e, error, &type) != napi_ok) error = nullptr;
    #|    if (!error || type == napi_undefined) error = MakeError(e, Outcome::Native, "callback failed", u"");
    #|    if (failed.exchange(true)) return;
    #|    if (!error || napi_create_reference(e, error, 1, &thrown) != napi_ok) {
    #|      thrown = nullptr;
    #|      fault = std::make_exception_ptr(std::runtime_error("callback failed"));
    #|    }
    #|  }
    #|  void Call(napi_env e, napi_value function, const std::vector<BridgeValue> &args, EventMaker make) noexcept {
    #|    try {
    #|      std::vector<napi_value> argv;
    #|      napi_value receiver, ignored;
    #|      if (!make(e, args, argv) || !Check(e, napi_get_undefined(e, &receiver)) ||
    #|          napi_call_function(e, receiver, function, argv.size(), argv.data(), &ignored) != napi_ok) Capture(e);
    #|    } catch (...) { Fail(std::current_exception()); }
    #|  }
    #|  // Gate holder: deliver now (sync) or queue for the JS thread (async).
    #|  void Emit(size_t slot, std::vector<BridgeValue> args, EventMaker make) {
    #|    if (!threaded) {
    #|      napi_handle_scope scope;
    #|      if (napi_open_handle_scope(env, &scope) != napi_ok) { Capture(env); return; }
    #|      Call(env, functions[slot], args, make);
    #|      napi_close_handle_scope(env, scope);
    #|      return;
    #|    }
    #|    std::unique_ptr<PendingEvent> event(new PendingEvent{slot, std::move(args), make});
    #|    pending.fetch_add(1);
    #|    if (napi_call_threadsafe_function(tsfn, event.get(), napi_tsfn_nonblocking) != napi_ok) {
    #|      pending.fetch_sub(1);
    #|      throw std::runtime_error("cannot queue callback");
    #|    }
    #|    event.release();
    #|  }
    #|  // Sync calls, after the gate is released: rethrow the first failure.
    #|  napi_value Raise(napi_env e) {
    #|    if (thrown) {
    #|      napi_value error = nullptr;
    #|      bool found = napi_get_reference_value(e, thrown, &error) == napi_ok && error;
    #|      napi_delete_reference(e, std::exchange(thrown, nullptr));
    #|      if (found && napi_throw(e, error) == napi_ok) return nullptr;
    #|    }
    #|    if (fault) std::rethrow_exception(fault);
    #|    throw std::runtime_error("callback failed");
    #|  }
    #|};
    #|static EventChannel *current_events = nullptr; // gate-protected
    #|struct EventScope {
    #|  EventChannel *previous;
    #|  const std::atomic<bool> *previous_failed;
    #|  explicit EventScope(EventChannel *value) : previous(current_events), previous_failed(current_failed) {
    #|    current_events = value; current_failed = value ? &value->failed : nullptr;
    #|  }
    #|  ~EventScope() { current_events = previous; current_failed = previous_failed; }
    #|};
    #|// Called from generated `moonohos_event_*` while MoonBit runs. A closure kept
    #|// beyond its call no longer matches the running call and is ignored.
    #|static EventChannel *ActiveEvents(int64_t id) {
    #|  return current_events && current_events->id == id && !current_events->failed.load() ? current_events : nullptr;
    #|}
    #|static bool ReadCallback(napi_env env, napi_value value, EventChannel &events, const std::string &path) {
    #|  napi_valuetype type;
    #|  if (!Check(env, napi_typeof(env, value, &type))) return false;
    #|  if (type != napi_function) throw TypeFault(path + ": function required");
    #|  if (!events.threaded) { events.functions.push_back(value); return true; }
    #|  napi_ref ref;
    #|  if (!Check(env, napi_create_reference(env, value, 1, &ref))) return false;
    #|  try { events.refs.push_back(ref); } catch (...) { napi_delete_reference(env, ref); throw; }
    #|  return true;
    #|}
    #|// Runs on the JS thread; never resolves twice and never touches MoonBit objects.
    #|static void SettleTask(napi_env env, std::unique_ptr<AsyncTask> task, napi_status status, TaskCreator create) {
    #|  pending_tasks.fetch_sub(1);
    #|  napi_delete_async_work(env, task->work);
    #|  if (status == napi_cancelled) task->outcome = Outcome::Cancelled;
    #|  // A failing callback decides the outcome, whatever the task itself did.
    #|  napi_value thrown = nullptr;
    #|  if (task->events) {
    #|    EventChannel &events = *task->events;
    #|    if (events.failed.load()) {
    #|      if (events.thrown && napi_get_reference_value(env, events.thrown, &thrown) != napi_ok) thrown = nullptr;
    #|      if (thrown) task->outcome = Outcome::Native;
    #|      else if (events.fault) task->outcome = Classify(events.fault, task->message, task->business);
    #|      else { task->outcome = Outcome::Native; task->message = "callback failed"; }
    #|    }
    #|    events.Close();
    #|  }
    #|  if (task->outcome == Outcome::Cancelled) task->message = "task cancelled";
    #|  (task->outcome == Outcome::Cancelled ? cancelled_tasks : completed_tasks).fetch_add(1);
    #|  if (task->state->Closing()) return;
    #|  if (thrown) { napi_reject_deferred(env, task->deferred, thrown); return; }
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
    #|// Generated Complete_* entry: a task whose events are still queued settles
    #|// after the last one, so ArkTS sees every callback before the Promise.
    #|static void FinishTask(napi_env env, std::unique_ptr<AsyncTask> task, napi_status status, TaskCreator create) {
    #|  EventChannel *events = task->events.get();
    #|  if (events && events->pending.load() > 0) {
    #|    events->parked_status = status;
    #|    events->parked_create = create;
    #|    events->parked = std::move(task);
    #|    return;
    #|  }
    #|  SettleTask(env, std::move(task), status, create);
    #|}
    #|// Threadsafe-function call_js on the JS thread; `env` is null during teardown.
    #|static void DeliverEvent(napi_env env, napi_value, void *context, void *data) {
    #|  auto *events = static_cast<EventChannel *>(context);
    #|  std::unique_ptr<PendingEvent> event(static_cast<PendingEvent *>(data));
    #|  if (env && events->env && !events->failed.load()) {
    #|    napi_value function = nullptr;
    #|    if (napi_get_reference_value(env, events->refs[event->slot], &function) == napi_ok && function)
    #|      events->Call(env, function, event->args, event->make);
    #|    else events->Capture(env);
    #|  }
    #|  event.reset();
    #|  if (events->pending.fetch_sub(1) != 1 || !events->parked) return;
    #|  std::unique_ptr<AsyncTask> task = std::move(events->parked);
    #|  if (!env) { // teardown: drop JS state without Node-API
    #|    events->env = nullptr;
    #|    pending_tasks.fetch_sub(1); cancelled_tasks.fetch_add(1);
    #|    return;
    #|  }
    #|  SettleTask(env, std::move(task), events->parked_status, events->parked_create);
    #|}
    #|static bool OpenEvents(napi_env env, EventChannel &events, const char *name) {
    #|  napi_value resource;
    #|  if (!Check(env, napi_create_string_utf8(env, name, NAPI_AUTO_LENGTH, &resource))) return false;
    #|  return Check(env, napi_create_threadsafe_function(env, nullptr, nullptr, resource, 0, 1, nullptr, nullptr, &events, DeliverEvent, &events.tsfn));
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
    #|  live_envs.fetch_sub(1);
    #|  delete holder;
    #|}
    #|
  ) +
  "\n"
}
