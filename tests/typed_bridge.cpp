// Host ASan checks for typed arrays (0.7): FixedArray[Double/Float/Int/Int64]
// <-> Float64Array/Float32Array/Int32Array/BigInt64Array as parameters,
// results, record fields, Option, array elements, async results and callback
// arguments. Views at an offset, empty arrays and non-finite elements cross
// unchanged; wrong element types, plain arrays, Sendable and detached buffers
// are rejected. Node-API failure injection and leak checks as elsewhere.
#include "napi_init.cpp"
#include <cassert>
#include <cmath>
#include <iostream>
extern "C" size_t moonohos_live_allocations(void);
// Linked by the rawfile stub; this fixture has no adapters.
extern "C" const char *moonohos_host_adapter_text(void *) { return nullptr; }

static Value Number(double x) { return {napi_number, x, false}; }
static Value Text(std::u16string x) { Value v; v.type = napi_string; v.text = std::move(x); return v; }
static Value Array(std::vector<Value> children) { Value v; v.type = napi_object; v.kind = OrdinaryArray; for (auto &x : children) v.elements.push_back(Clone(x)); return v; }
static Value Object(std::initializer_list<std::pair<const char *, Value>> fields) { Value v; v.type = napi_object; for (const auto &f : fields) v.properties[f.first] = Clone(f.second); return v; }
static Value Undefined() { return Value{}; }
// A typed array over its own ArrayBuffer; `lead` elements before the view
// make the view start at a byte offset, as `subarray` does.
template <class T> static Value Typed(napi_typedarray_type type, std::vector<T> items, size_t lead = 0) {
  auto buffer = std::make_shared<Value>(); buffer->type = napi_object; buffer->kind = ArrayBuffer;
  buffer->storage.assign((items.size() + lead) * sizeof(T), 0xEE);
  if (!items.empty()) std::memcpy(buffer->storage.data() + lead * sizeof(T), items.data(), items.size() * sizeof(T));
  Value v; v.type = napi_object; v.kind = TypedArray; v.array_type = type;
  v.length = items.size(); v.offset = lead * sizeof(T); v.buffer_owner = buffer; v.buffer = buffer.get();
  return v;
}
static Value F64(std::vector<double> x, size_t lead = 0) { return Typed(napi_float64_array, std::move(x), lead); }
static Value F32(std::vector<float> x) { return Typed(napi_float32_array, std::move(x)); }
static Value I32(std::vector<int32_t> x) { return Typed(napi_int32_array, std::move(x)); }
static Value I64(std::vector<int64_t> x) { return Typed(napi_bigint64_array, std::move(x)); }
template <class T> static std::vector<T> Items(const Value &v, napi_typedarray_type type) {
  assert(v.type == napi_object && v.kind == TypedArray && v.array_type == type && v.buffer);
  assert(v.offset + v.length * sizeof(T) <= v.buffer->storage.size());
  std::vector<T> out(v.length);
  if (v.length) std::memcpy(out.data(), v.buffer->storage.data() + v.offset, v.length * sizeof(T));
  return out;
}
static Value Invoke(napi_callback cb, std::vector<napi_value> args) {
  Env env; Call info{args}; auto before = moonohos_live_allocations(); auto out = cb(&env, &info);
  assert(out && env.exception.empty());
  if (moonohos_live_allocations() != before) { std::cerr << "leak delta=" << (long long)(moonohos_live_allocations() - before) << std::endl; assert(false); }
  return *Clone(*out);
}
static void Reject(napi_callback cb, std::vector<napi_value> args, const char *error, const char *where) {
  Env e; Call info{args}; auto before = moonohos_live_allocations();
  assert(!cb(&e, &info));
  if (e.exception != error || e.message.find(where) == std::string::npos) {
    std::cerr << "expected " << error << " at " << where << ", got " << e.exception << ": "; std::cerr << "message: " << e.message << "\n"; assert(false); }
  assert(moonohos_live_allocations() == before);
}
static void FailureSweep(napi_callback cb, std::vector<napi_value> args) {
  Env success; Call info{args}; assert(cb(&success, &info));
  for (int i = 0; i < success.operations; ++i) for (bool pending : {false, true}) {
    Env e; e.fail_at = i; e.pending = pending; auto before = moonohos_live_allocations();
    assert(!cb(&e, &info)); assert(e.exception == (pending ? "PendingException" : "Error")); assert(moonohos_live_allocations() == before);
  }
}

struct Module {
  Env env;
  Value exports;
  Module() { env.stable_results = true; exports.type = napi_object; assert(Init(&env, &exports) == &exports); }
  napi_value Call(const char *name, std::vector<napi_value> args) {
    env.exception.clear(); env.message.clear();
    return CallMethod(&env, exports, name, std::move(args));
  }
  void Settled() { assert(env.live_refs == 0 && env.open_scopes == 0 && env.LiveThreadsafeFunctions() == 0); }
};
static Value &Resolved(napi_value promise) { assert(promise && promise->promise_state == 2); return *promise->settled; }
static Value &Rejected(napi_value promise) { assert(promise && promise->promise_state == 3); return *promise->settled; }

static void Scalars() {
  // Float64Array: offset view, NaN, -0 and infinities copy bit-exactly.
  const double nan = std::nan("");
  Value values = F64({1.5, -0.0, nan, INFINITY, -2.25}, 3), two = Number(2);
  auto scaled = Items<double>(Invoke(Call_scale, {&values, &two}), napi_float64_array);
  assert(scaled.size() == 5 && scaled[0] == 3.0 && scaled[1] == 0.0 && std::signbit(scaled[1]));
  assert(std::isnan(scaled[2]) && scaled[3] == INFINITY && scaled[4] == -4.5);
  Value empty = F64({});
  assert(Items<double>(Invoke(Call_scale, {&empty, &two}), napi_float64_array).empty());
  // Float32Array both ways: narrowing rounds to float.
  Value wide = F64({0.1, 1e40, -3.5});
  auto narrow = Items<float>(Invoke(Call_narrow, {&wide}), napi_float32_array);
  assert(narrow.size() == 3 && narrow[0] == 0.1f && std::isinf(narrow[1]) && narrow[2] == -3.5f);
  Value floats = F32({0.5f, 0.25f, 1.0f});
  assert(Invoke(Call_sum_float, {&floats}).number == 1.75);
  // Int32Array.
  Value ints = I32({-5, 0, 9, 10, 25, 2147483647}), three = Number(3);
  assert((Items<int32_t>(Invoke(Call_histogram, {&ints, &three}), napi_int32_array) == std::vector<int32_t>{3, 1, 2}));
  // BigInt64Array: wrapping sums keep the int64 extremes.
  Value longs = I64({INT64_MAX, 1, -1, INT64_MIN});
  assert((Items<int64_t>(Invoke(Call_prefix, {&longs}), napi_bigint64_array) == std::vector<int64_t>{INT64_MAX, INT64_MIN, INT64_MAX, -1}));
}

static void Containers() {
  // Record fields, including an Option typed array present and absent.
  Value series = Object({{"name", Text(u"s")}, {"samples", F64({2, -4, 1}, 1)}, {"marks", I32({7, 8})}});
  auto normalized = Invoke(Call_normalize, {&series});
  assert(normalized.properties.at("name")->text == u"s/normalized");
  assert((Items<double>(*normalized.properties.at("samples"), napi_float64_array) == std::vector<double>{0.5, -1, 0.25}));
  assert((Items<int32_t>(*normalized.properties.at("marks"), napi_int32_array) == std::vector<int32_t>{8, 9}));
  Value bare = Object({{"name", Text(u"b")}, {"samples", F64({})}});
  auto plain = Invoke(Call_normalize, {&bare});
  assert(plain.properties.at("marks")->type == napi_undefined && Items<double>(*plain.properties.at("samples"), napi_float64_array).empty());
  // Array of typed arrays.
  Value values = F64({1, 2, 3, 4, 5}), two = Number(2);
  auto parts = Invoke(Call_chunk, {&values, &two});
  assert(parts.kind == OrdinaryArray && parts.elements.size() == 3);
  assert((Items<double>(*parts.elements[2], napi_float64_array) == std::vector<double>{5}));
  // Option parameter and result.
  Value none = Undefined();
  assert(Invoke(Call_peak, {&none}).type == napi_undefined);
  Value floats = F32({1.5f, 4.0f, -2.0f});
  assert(Invoke(Call_peak, {&floats}).number == 4.0);
}

static void Rejections() {
  Value two = Number(2);
  Value bytes; bytes = Typed<uint8_t>(napi_uint8_array, {1, 2});
  Reject(Call_scale, {&bytes, &two}, "TypeError", "scale.values: Float64Array required");
  Value floats = F32({1});
  Reject(Call_scale, {&floats, &two}, "TypeError", "scale.values: Float64Array required");
  Value doubles = F64({1});
  Reject(Call_sum_float, {&doubles}, "TypeError", "sum_float.values: Float32Array required");
  Value list = Array({Number(1)});
  Reject(Call_scale, {&list, &two}, "TypeError", "scale.values: Float64Array required");
  Reject(Call_scale, {&two, &two}, "TypeError", "scale.values");
  Value shared = F64({1}); shared.sendable = true;
  Reject(Call_scale, {&shared, &two}, "TypeError", "Sendable view unsupported");
  Value detached = F64({1}); detached.buffer->detached = true;
  Reject(Call_scale, {&detached, &two}, "TypeError", "detached buffer");
  Value sendable_buffer = F64({1}); sendable_buffer.buffer->sendable = true;
  Reject(Call_scale, {&sendable_buffer, &two}, "TypeError", "shared buffer unsupported");
  Value bad_series = Object({{"name", Text(u"s")}, {"samples", I32({1})}});
  Reject(Call_normalize, {&bad_series}, "TypeError", "normalize.series.samples: Float64Array required");
  Value bad_marks = Object({{"name", Text(u"s")}, {"samples", F64({1})}, {"marks", F64({1})}});
  Reject(Call_normalize, {&bad_marks}, "TypeError", "normalize.series.marks: Int32Array required");
  // Like Bytes, a top-level typed array is limited by its element count only;
  // inside records and arrays it counts toward the 64 MiB copy budget.
  Value huge; huge = F64({}); huge.length = INT32_MAX / 8 + 1;
  Reject(Call_scale, {&huge, &two}, "RangeError", "scale.values: typed array length exceeded");
  Value big_samples; big_samples = F64({}); big_samples.length = 8 * 1024 * 1024 + 1;
  Value big_series = Object({{"name", Text(u"s")}, {"samples", big_samples}});
  Reject(Call_normalize, {&big_series}, "RangeError", "normalize.series.samples: conversion limit exceeded");
}

static void Async() {
  Module m;
  std::vector<std::vector<double>> windows;
  napi_value promise = nullptr;
  Value on_window = Function([&](Env *, const std::vector<std::shared_ptr<Value>> &args) {
    assert(promise->promise_state == 1);
    windows.push_back(Items<double>(*args[0], napi_float64_array));
  });
  Value values = F64({1, 2, 3, 4, 5, 6}, 2);
  promise = m.Call("mean_later", {&values, &on_window});
  assert(promise && promise->promise_state == 1);
  m.env.RunWorks(true);
  assert(Resolved(promise).number == 3.5);
  assert(windows.size() == 2 && (windows[1] == std::vector<double>{5, 6}));
  m.Settled();
  // Cancelled before it runs.
  napi_value token = m.Call("createCancelToken", {});
  CallMethod(&m.env, *token, "cancel");
  napi_value cancelled = m.Call("mean_later", {&values, &on_window, token});
  m.env.RunWorks();
  assert(ErrorCode(Rejected(cancelled)) == "ERR_MOONOHOS_CANCELLED");
  // A wrong element type is a TypeError before any work is queued.
  Value ints = I32({1});
  assert(!m.Call("mean_later", {&ints, &on_window}) && m.env.exception == "TypeError");
  assert(m.env.queue.empty());
  m.Settled();
}

int main() {
  // Warm up without the leak check: runtime initialization allocates once.
  { Value warm = F64({1}), one = Number(1); Env env; Call info{{&warm, &one}}; assert(Call_scale(&env, &info)); }
  Scalars(); Containers(); Rejections(); Async();
  Value values = F64({1, 2, 3}, 1), two = Number(2), floats = F32({1, 2}), ints = I32({1, 15}), longs = I64({1, -2});
  Value series = Object({{"name", Text(u"s")}, {"samples", F64({2, -4})}, {"marks", I32({7})}});
  Value none = Undefined();
  FailureSweep(Call_scale, {&values, &two}); FailureSweep(Call_narrow, {&values});
  FailureSweep(Call_sum_float, {&floats}); FailureSweep(Call_histogram, {&ints, &two});
  FailureSweep(Call_prefix, {&longs}); FailureSweep(Call_normalize, {&series});
  FailureSweep(Call_chunk, {&values, &two}); FailureSweep(Call_peak, {&floats}); FailureSweep(Call_peak, {&none});
  // Allocation failure at every C++ buffer boundary leaves nothing behind.
  for (int after = 0; after < 8; ++after) {
    Env e; Call info{{&series}}; auto before = moonohos_live_allocations();
    buffer_failure_after = after;
    napi_value out = Call_normalize(&e, &info);
    buffer_failure_after = -1;
    assert(out || e.exception == "RangeError" || e.exception == "Error");
    assert(moonohos_live_allocations() == before);
  }
  auto baseline = moonohos_live_allocations();
  for (int i = 0; i < 10000; ++i) {
    Invoke(Call_scale, {&values, &two}); Invoke(Call_normalize, {&series});
    Invoke(Call_chunk, {&values, &two}); Invoke(Call_prefix, {&longs});
  }
  assert(moonohos_live_allocations() == baseline);
  std::cout << "HOST_TYPED_PASS f64/f32/i32/i64 params/results/records/option/arrays/async/callbacks/offset/nan/reject/budget/status/repeat=10000 live_delta=0\n";
}
