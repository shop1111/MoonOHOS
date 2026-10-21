#pragma once
// Host unit-test double for the Node-API subset used by the generated bridge.
// It does not emulate the HarmonyOS loader or ArkTS engine.
#include <cstddef>
#include <string>
#include <vector>
#include <cstring>
#include <limits>
#include <new>
#include <memory>
#include <map>
#include <functional>
#include <thread>
#include <cstdint>
#include <stdexcept>
#define NAPI_AUTO_LENGTH SIZE_MAX
enum napi_status { napi_ok, napi_generic_failure, napi_pending_exception, napi_invalid_arg, napi_cancelled };
enum napi_qos_t { napi_qos_background, napi_qos_utility, napi_qos_default, napi_qos_user_initiated };
struct Env;
using napi_env = Env *;
using napi_finalize = void (*)(napi_env, void *, void *);
using napi_async_execute_callback = void (*)(napi_env, void *);
using napi_async_complete_callback = void (*)(napi_env, napi_status, void *);
enum napi_valuetype { napi_undefined, napi_number, napi_boolean, napi_string, napi_object };
enum napi_typedarray_type { napi_uint8_array, napi_uint8_clamped_array, napi_int8_array, napi_int16_array };
enum ObjectKind { PlainObject, ArrayBuffer, TypedArray, DataView, SharedBuffer, OrdinaryArray };
enum napi_property_attributes { napi_default };
struct Value {
  napi_valuetype type = napi_undefined; double number = 0; bool boolean = false;
  std::u16string text; std::vector<uint8_t> storage;
  ObjectKind kind = PlainObject; Value *buffer = nullptr;
  napi_typedarray_type array_type = napi_uint8_array;
  size_t offset = 0, length = 0, reported_length = std::numeric_limits<size_t>::max();
  bool detached = false, sendable = false;
  bool null_value = false;
  std::vector<std::shared_ptr<Value>> elements;
  std::map<std::string, std::shared_ptr<Value>> properties;
  std::shared_ptr<Value> buffer_owner;
  // Functions, wrapped native data, errors and promises.
  Value *(*method)(Env *, struct Call *) = nullptr; void *method_data = nullptr;
  void *native = nullptr; napi_finalize finalize = nullptr;
  std::string error_kind; int promise_state = 0; std::shared_ptr<Value> settled;
};
using napi_value = Value *;
struct Call { std::vector<napi_value> args; napi_value self = nullptr; void *data = nullptr; };
using napi_callback_info = Call *;
struct AsyncWork { napi_async_execute_callback execute; napi_async_complete_callback complete; void *data; bool queued = false, deleted = false; };
using napi_async_work = AsyncWork *;
struct Deferred { napi_value promise; bool settled = false; };
using napi_deferred = Deferred *;
struct Env {
  std::string exception; std::string message; int operations = 0; int fail_at = -1; bool pending = false;
  Value result; Value buffer; size_t exports = 0; std::vector<std::unique_ptr<Value>> arena;
  std::vector<std::unique_ptr<AsyncWork>> works; std::vector<AsyncWork *> queue;
  std::vector<std::unique_ptr<Deferred>> deferreds;
  std::vector<std::pair<void (*)(void *), void *>> hooks; bool destroyed = false;
  // Runs queued work: execute on worker threads (all at once when threaded), complete here.
  void RunWorks(bool threaded = false, napi_status status = napi_ok) {
    while (!queue.empty()) {
      std::vector<AsyncWork *> batch; batch.swap(queue);
      if (status == napi_ok) {
        std::vector<std::thread> workers;
        for (auto *work : batch) {
          if (threaded) workers.emplace_back([this, work] { work->execute(this, work->data); });
          else { std::thread worker([this, work] { work->execute(this, work->data); }); worker.join(); }
        }
        for (auto &worker : workers) worker.join();
      }
      for (auto *work : batch) work->complete(this, status, work->data);
    }
  }
  // Env teardown: cleanup hooks in reverse registration order.
  void Teardown() { for (auto it = hooks.rbegin(); it != hooks.rend(); ++it) it->first(it->second); hooks.clear(); destroyed = true; }
  // Simulated GC of every wrapped object allocated in this env.
  void Collect() { for (auto &value : arena) if (value->native && value->finalize) { value->finalize(this, value->native, nullptr); value->native = nullptr; } }
  ~Env() { if (!destroyed) Teardown(); Collect(); }
};
using napi_callback = napi_value (*)(napi_env, napi_callback_info);
struct napi_property_descriptor {
  const char *utf8name; napi_value name; napi_callback method; void *getter;
  void *setter; napi_value value; napi_property_attributes attributes; void *data;
};
inline napi_status Step(napi_env e) {
  if (e->operations++ == e->fail_at) {
    if (e->pending) { e->exception = "PendingException"; return napi_pending_exception; }
    return napi_generic_failure;
  }
  return napi_ok;
}
inline napi_status napi_throw_error(napi_env e, const char *, const char *message) { e->exception = "Error"; e->message = message; return napi_ok; }
inline napi_status napi_throw_type_error(napi_env e, const char *, const char *message) { e->exception = "TypeError"; e->message = message; return napi_ok; }
inline napi_status napi_throw_range_error(napi_env e, const char *, const char *message) { e->exception = "RangeError"; e->message = message; return napi_ok; }
inline napi_status napi_get_cb_info(napi_env e, napi_callback_info info, size_t *argc, napi_value *argv, napi_value *self, void **data) {
  auto status = Step(e); if (status != napi_ok) return status;
  size_t count = *argc < info->args.size() ? *argc : info->args.size();
  for (size_t i = 0; argv && i < count; ++i) argv[i] = info->args[i];
  if (self) *self = info->self;
  if (data) *data = info->data;
  *argc = count; return napi_ok;
}
inline napi_status napi_typeof(napi_env e, napi_value value, napi_valuetype *out) {
  auto s = Step(e); if (s == napi_ok) *out = value->type; return s;
}
inline napi_status napi_get_value_double(napi_env e, napi_value value, double *out) {
  auto s = Step(e); if (s == napi_ok) *out = value->number; return s;
}
inline napi_status napi_get_value_bool(napi_env e, napi_value value, bool *out) {
  auto s = Step(e); if (s == napi_ok) *out = value->boolean; return s;
}
inline napi_status napi_create_double(napi_env e, double value, napi_value *out) {
  auto s = Step(e); if (s == napi_ok) { e->result = {napi_number, value, false}; *out = &e->result; } return s;
}
inline napi_status napi_create_int32(napi_env e, int value, napi_value *out) { return napi_create_double(e, value, out); }
inline napi_status napi_get_boolean(napi_env e, bool value, napi_value *out) {
  auto s = Step(e); if (s == napi_ok) { e->result = {napi_boolean, 0, value}; *out = &e->result; } return s;
}
inline napi_status napi_get_undefined(napi_env e, napi_value *out) {
  auto s = Step(e); if (s == napi_ok) { e->result = {}; *out = &e->result; } return s;
}
inline napi_status napi_define_properties(napi_env e, napi_value object, size_t count, const napi_property_descriptor *descriptors) {
  auto s = Step(e); if (s != napi_ok) return s;
  if (e->exports == 0) e->exports = count; // first definition is the module exports
  for (size_t i = 0; object && i < count; ++i) {
    auto method = std::make_shared<Value>(); method->type = napi_object;
    method->method = descriptors[i].method; method->method_data = descriptors[i].data;
    object->properties[descriptors[i].utf8name] = method;
  }
  return s;
}
#define NAPI_MODULE(name, init)

// Host-only failure injection at actual C++ buffer allocation boundaries.
inline int buffer_failure_after = -1;
inline void BufferAllocate() {
  if (buffer_failure_after == 0) throw std::bad_alloc();
  if (buffer_failure_after > 0) --buffer_failure_after;
}
#define MOONOHOS_BUFFER_ALLOCATE() BufferAllocate()
inline napi_status napi_get_value_string_utf16(napi_env e, napi_value v, char16_t *out, size_t capacity, size_t *length) {
  auto status = Step(e); if (status != napi_ok) return status;
  if (!out) { *length = v->reported_length == std::numeric_limits<size_t>::max() ? v->text.size() : v->reported_length; return napi_ok; }
  *length = v->text.size();
  if (capacity < *length + 1) return napi_generic_failure;
  if (*length) std::memcpy(out, v->text.data(), *length * sizeof(char16_t));
  out[*length] = 0; return napi_ok;
}
inline napi_status napi_create_string_utf16(napi_env e, const char16_t *data, size_t length, napi_value *out) {
  auto status = Step(e); if (status != napi_ok) return status;
  e->result = Value{}; e->result.type = napi_string;
  e->result.text.assign(data, length); *out = &e->result; return napi_ok;
}
inline napi_status napi_is_typedarray(napi_env e, napi_value v, bool *out) {
  auto status = Step(e); if (status == napi_ok) *out = v->kind == TypedArray; return status;
}
inline napi_status napi_get_typedarray_info(napi_env e, napi_value v, napi_typedarray_type *type, size_t *length, void **data, napi_value *buffer, size_t *offset) {
  auto status = Step(e); if (status != napi_ok) return status;
  *type = v->array_type; *length = v->length; *buffer = v->buffer; *offset = v->offset;
  *data = v->buffer->storage.empty() ? nullptr : v->buffer->storage.data() + v->offset;
  return napi_ok;
}
inline napi_status napi_is_arraybuffer(napi_env e, napi_value v, bool *out) {
  auto status = Step(e); if (status == napi_ok) *out = v->kind == ArrayBuffer; return status;
}
inline napi_status napi_is_sendable(napi_env e, napi_value v, bool *out) {
  auto status = Step(e); if (status == napi_ok) *out = v->sendable; return status;
}
inline napi_status napi_is_detached_arraybuffer(napi_env e, napi_value v, bool *out) {
  auto status = Step(e); if (status == napi_ok) *out = v->detached; return status;
}
inline napi_status napi_create_arraybuffer(napi_env e, size_t length, void **data, napi_value *out) {
  auto status = Step(e); if (status != napi_ok) return status;
  e->buffer = Value{}; e->buffer.type = napi_object; e->buffer.kind = ArrayBuffer;
  e->buffer.storage.resize(length); *data = e->buffer.storage.data(); *out = &e->buffer; return napi_ok;
}
inline napi_status napi_create_typedarray(napi_env e, napi_typedarray_type type, size_t length, napi_value buffer, size_t offset, napi_value *out) {
  auto status = Step(e); if (status != napi_ok) return status;
  e->result = Value{}; e->result.type = napi_object; e->result.kind = TypedArray;
  e->result.array_type = type; e->result.length = length; e->result.offset = offset;
  e->result.buffer = buffer; *out = &e->result; return napi_ok;
}

inline napi_value Allocate(napi_env env, Value value) {
  env->arena.push_back(std::make_unique<Value>(std::move(value)));
  return env->arena.back().get();
}
inline std::shared_ptr<Value> Clone(const Value &value) {
  auto result = std::make_shared<Value>(value);
  if (value.buffer) { result->buffer_owner = Clone(*value.buffer); result->buffer = result->buffer_owner.get(); }
  return result;
}
inline std::string Key(napi_value v) { std::string result; for (char16_t unit : v->text) result.push_back(static_cast<char>(unit)); return result; }
inline napi_status napi_create_string_utf8(napi_env e, const char *data, size_t size, napi_value *out) {
  auto s = Step(e); if (s != napi_ok) return s;
  if (size == NAPI_AUTO_LENGTH) size = std::strlen(data);
  Value v; v.type = napi_string; v.text.assign(data, data + size); *out = Allocate(e, std::move(v)); return s;
}
inline napi_status napi_is_array(napi_env e, napi_value v, bool *out) {
  auto s = Step(e); if (s == napi_ok) *out = v->kind == OrdinaryArray; return s;
}
inline napi_status napi_get_array_length(napi_env e, napi_value v, uint32_t *out) {
  auto s = Step(e); if (s == napi_ok) *out = static_cast<uint32_t>(v->reported_length == std::numeric_limits<size_t>::max() ? v->elements.size() : v->reported_length); return s;
}
inline napi_status napi_strict_equals(napi_env e, napi_value a, napi_value b, bool *out) {
  auto s = Step(e); if (s == napi_ok) *out = a == b || (a->null_value && b->null_value); return s;
}
inline napi_status napi_get_null(napi_env e, napi_value *out) {
  auto s = Step(e); if (s != napi_ok) return s;
  Value value; value.type = napi_object; value.null_value = true; *out = Allocate(e, std::move(value)); return s;
}
inline napi_status napi_is_dataview(napi_env e, napi_value value, bool *out) {
  auto s = Step(e); if (s == napi_ok) *out = value->kind == DataView; return s;
}
inline napi_status napi_has_own_property(napi_env e, napi_value value, napi_value key, bool *out) {
  auto s = Step(e); if (s != napi_ok) return s;
  auto name = Key(key);
  if (value->kind == OrdinaryArray) { size_t i = std::stoull(name); *out = i < value->elements.size() && value->elements[i] != nullptr; }
  else *out = value->properties.count(name) != 0;
  return s;
}
inline napi_status napi_get_property(napi_env e, napi_value value, napi_value key, napi_value *out) {
  auto s = Step(e); if (s != napi_ok) return s;
  auto name = Key(key);
  *out = value->kind == OrdinaryArray ? value->elements[std::stoull(name)].get() : value->properties.at(name).get(); return s;
}
inline napi_status napi_create_array_with_length(napi_env e, size_t size, napi_value *out) {
  auto s = Step(e); if (s != napi_ok) return s;
  Value value; value.type = napi_object; value.kind = OrdinaryArray; value.elements.resize(size); *out = Allocate(e, std::move(value)); return s;
}
inline napi_status napi_set_element(napi_env e, napi_value array, uint32_t i, napi_value value) {
  auto s = Step(e); if (s == napi_ok) array->elements.at(i) = Clone(*value); return s;
}
inline napi_status napi_create_object(napi_env e, napi_value *out) {
  auto s = Step(e); if (s != napi_ok) return s;
  Value value; value.type = napi_object; *out = Allocate(e, std::move(value)); return s;
}
inline napi_status napi_set_named_property(napi_env e, napi_value object, const char *name, napi_value value) {
  auto s = Step(e); if (s == napi_ok) object->properties[name] = Clone(*value); return s;
}

// Errors, wrapping, promises, async work and env lifecycle.
inline napi_status MakeErrorValue(napi_env e, const char *kind, napi_value code, napi_value message, napi_value *out) {
  auto s = Step(e); if (s != napi_ok) return s;
  Value v; v.type = napi_object; v.error_kind = kind; v.text = message->text;
  if (code) v.properties["code"] = Clone(*code);
  *out = Allocate(e, std::move(v)); return s;
}
inline napi_status napi_create_error(napi_env e, napi_value code, napi_value message, napi_value *out) { return MakeErrorValue(e, "Error", code, message, out); }
inline napi_status napi_create_type_error(napi_env e, napi_value code, napi_value message, napi_value *out) { return MakeErrorValue(e, "TypeError", code, message, out); }
inline napi_status napi_create_range_error(napi_env e, napi_value code, napi_value message, napi_value *out) { return MakeErrorValue(e, "RangeError", code, message, out); }
inline std::string Utf8(const std::u16string &text) { std::string result; for (char16_t unit : text) result.push_back(static_cast<char>(unit)); return result; }
inline std::string ErrorCode(const Value &error) { auto it = error.properties.find("code"); return it == error.properties.end() ? "" : Utf8(it->second->text); }
inline napi_status napi_throw(napi_env e, napi_value error) {
  e->exception = error->error_kind.empty() ? "Thrown" : error->error_kind; e->message = Utf8(error->text);
  auto code = ErrorCode(*error); if (!code.empty()) e->message = code + ": " + e->message; return napi_ok;
}
inline napi_status napi_get_and_clear_last_exception(napi_env e, napi_value *out) {
  Value v; if (!e->exception.empty()) { v.type = napi_object; v.error_kind = e->exception; v.text.assign(e->message.begin(), e->message.end()); }
  e->exception.clear(); e->message.clear(); *out = Allocate(e, std::move(v)); return napi_ok;
}
inline napi_status napi_wrap(napi_env e, napi_value object, void *native, napi_finalize finalize, void *, void *result) {
  auto s = Step(e); if (s != napi_ok) return s;
  if (object->native || result) return napi_invalid_arg;
  object->native = native; object->finalize = finalize; return s;
}
inline napi_status napi_unwrap(napi_env e, napi_value object, void **out) {
  auto s = Step(e); if (s != napi_ok) return s;
  if (!object->native) return napi_invalid_arg;
  *out = object->native; return s;
}
inline napi_status napi_create_promise(napi_env e, napi_deferred *deferred, napi_value *promise) {
  auto s = Step(e); if (s != napi_ok) return s;
  Value v; v.type = napi_object; v.promise_state = 1; *promise = Allocate(e, std::move(v));
  e->deferreds.push_back(std::make_unique<Deferred>()); e->deferreds.back()->promise = *promise;
  *deferred = e->deferreds.back().get(); return s;
}
inline napi_status Settle(napi_env e, napi_deferred deferred, napi_value value, int state) {
  auto s = Step(e); if (s != napi_ok) return s;
  if (deferred->settled) throw std::logic_error("promise settled twice");
  deferred->settled = true; deferred->promise->promise_state = state; deferred->promise->settled = Clone(*value); return s;
}
inline napi_status napi_resolve_deferred(napi_env e, napi_deferred d, napi_value v) { return Settle(e, d, v, 2); }
inline napi_status napi_reject_deferred(napi_env e, napi_deferred d, napi_value v) { return Settle(e, d, v, 3); }
inline napi_status napi_create_async_work(napi_env e, napi_value, napi_value, napi_async_execute_callback execute, napi_async_complete_callback complete, void *data, napi_async_work *out) {
  auto s = Step(e); if (s != napi_ok) return s;
  e->works.push_back(std::make_unique<AsyncWork>(AsyncWork{execute, complete, data}));
  *out = e->works.back().get(); return s;
}
inline napi_status napi_queue_async_work_with_qos(napi_env e, napi_async_work work, napi_qos_t) {
  auto s = Step(e); if (s != napi_ok) return s;
  if (work->queued || work->deleted) throw std::logic_error("async work queued twice or after delete");
  work->queued = true; e->queue.push_back(work); return s;
}
inline napi_status napi_delete_async_work(napi_env, napi_async_work work) {
  if (work->deleted) throw std::logic_error("async work deleted twice");
  work->deleted = true; return napi_ok;
}
inline napi_status napi_add_env_cleanup_hook(napi_env e, void (*hook)(void *), void *arg) {
  auto s = Step(e); if (s != napi_ok) return s;
  e->hooks.emplace_back(hook, arg); return s;
}
// Test helpers: call an exported or object method with `this` and descriptor data.
inline napi_value CallMethod(napi_env e, Value &object, const std::string &name, std::vector<napi_value> args = {}) {
  auto &method = object.properties.at(name);
  Call call{std::move(args), &object, method->method_data};
  return method->method(e, &call);
}
