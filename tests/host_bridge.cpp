#include "napi_init.cpp"
#include <cassert>
#include <limits>
#include <iostream>
extern "C" size_t moonohos_live_allocations(void);

static Value Text(std::u16string text) { Value v; v.type = napi_string; v.text = std::move(text); return v; }
static Value Buffer(std::vector<uint8_t> bytes) { Value v; v.type = napi_object; v.kind = ArrayBuffer; v.storage = std::move(bytes); return v; }
static Value View(Value &buffer, size_t offset, size_t length, napi_typedarray_type type = napi_uint8_array) {
  Value v; v.type = napi_object; v.kind = TypedArray; v.buffer = &buffer; v.offset = offset; v.length = length; v.array_type = type; return v;
}
static Value Invoke(napi_callback callback, std::vector<napi_value> args) {
  const auto baseline = moonohos_live_allocations();
  Env env; Call info{args};
  assert(callback(&env, &info) != nullptr && env.exception.empty());
  assert(moonohos_live_allocations() == baseline);
  Value result = env.result;
  if (result.kind == TypedArray) { result.storage = env.buffer.storage; result.buffer = nullptr; }
  return result;
}
static void FailureSweep(napi_callback callback, std::vector<napi_value> args) {
  const auto baseline = moonohos_live_allocations();
  Env success; Call info{args};
  assert(callback(&success, &info) != nullptr);
  assert(moonohos_live_allocations() == baseline);
  for (int operation = 0; operation < success.operations; ++operation) {
    Env failure; failure.fail_at = operation;
    assert(callback(&failure, &info) == nullptr);
    assert(failure.exception == "Error");
    assert(failure.operations == operation + 1);
    assert(moonohos_live_allocations() == baseline);
    Env pending; pending.fail_at = operation; pending.pending = true;
    assert(callback(&pending, &info) == nullptr && pending.exception == "PendingException");
    assert(moonohos_live_allocations() == baseline);
  }
}

static Value Number(double value) { return {napi_number, value, false}; }
static void Reject(napi_callback callback, std::vector<napi_value> args, const char *type) {
  Env env; Call info{args};
  auto baseline = moonohos_live_allocations();
  assert(callback(&env, &info) == nullptr);
  assert(env.exception == type);
  assert(moonohos_live_allocations() == baseline);
}
int main() {
  Value a = Number(20), b = Number(22), boolean{napi_boolean, 0, true}, string{napi_string, 0, false};
  Call two{{&a, &b}};
  Env env;
  assert(Call_add(&env, &two)->number == 42);
  a = Number(-2147483648.0); b = Number(0);
  assert(Call_add(&env, &two)->number == -2147483648.0);
  a = Number(2147483647.0); b = Number(1);
  assert(Call_add(&env, &two)->number == -2147483648.0);
  a = Number(-2); b = Number(1);
  assert(Call_add(&env, &two)->number == -1);
  a = Number(1.5); b = Number(2);
  assert(Call_scale(&env, &two)->number == 3);
  Call one{{&boolean}};
  assert(Call_negate(&env, &one)->boolean == false);
  Call empty;
  assert(Call_ping(&env, &empty)->type == napi_undefined);
  Reject(Call_add, {}, "TypeError");
  Reject(Call_add, {&a}, "TypeError");
  Reject(Call_add, {&string, &b}, "TypeError");
  Reject(Call_negate, {&a}, "TypeError");
  for (double bad : {0.5, 2147483648.0, -2147483649.0, std::numeric_limits<double>::quiet_NaN(), std::numeric_limits<double>::infinity()}) {
    a = Number(bad); Reject(Call_add, {&a, &b}, "RangeError");
  }
  a = Number(std::numeric_limits<double>::infinity());
  Reject(Call_scale, {&a, &b}, "RangeError");
  a = Number(1e308); b = Number(1e308);
  Reject(Call_scale, {&a, &b}, "RangeError");
  a = Number(20); b = Number(22);
  // Failure at every API operation must stop before consuming its output.
  for (int step = 0; step < 6; ++step) {
    Env failure; failure.fail_at = step;
    assert(Call_add(&failure, &two) == nullptr);
    assert(failure.exception == "Error");
    assert(failure.operations == step + 1);
  }
  Env pending; pending.fail_at = 0; pending.pending = true;
  assert(Call_add(&pending, &two) == nullptr && pending.exception == "PendingException");
  Value exports;
  assert(Init(&env, &exports) == &exports && env.exports == 9);
  Env registration; registration.fail_at = 0;
  assert(Init(&registration, &exports) == nullptr && registration.exception == "Error");
  for (int i = 0; i < 10000; ++i) assert(Call_add(&env, &two)->number == 42);
  std::cout << "HOST_BRIDGE_PASS scalar/bounds/type/status/registration/repeat=10000\n";

  // Verify the pinned compiler ABI directly, including aliased return ownership.
  const auto baseline = moonohos_live_allocations();
  auto raw_text = moonbit_make_string_raw(3);
  auto returned_text = moonohos_echo_text(raw_text);
  assert(returned_text == raw_text && Moonbit_rc_count(Moonbit_object_header(raw_text)) == 2);
  moonbit_decref(returned_text);
  assert(Moonbit_rc_count(Moonbit_object_header(raw_text)) == 1);
  moonbit_decref(raw_text);
  auto raw_bytes = moonbit_make_bytes_raw(3);
  auto returned_bytes = moonohos_echo_bytes(raw_bytes);
  assert(returned_bytes == raw_bytes && Moonbit_rc_count(Moonbit_object_header(raw_bytes)) == 2);
  moonbit_decref(returned_bytes); moonbit_decref(raw_bytes);
  assert(moonohos_live_allocations() == baseline);

  for (std::u16string text : {std::u16string{}, std::u16string{u"中文😀"}, std::u16string{u'A', 0, u'B'}, std::u16string{char16_t(0xd800), u'X', char16_t(0xdc00)}, std::u16string(65536, u'文')}) {
    Value value = Text(text);
    assert(Invoke(Call_echo_text, {&value}).text == text);
  }
  Value label = Text(u"bytes="), word = Text(u"中文😀");
  assert(Invoke(Call_join_text, {&label, &word}).text == label.text + word.text);
  std::vector<uint8_t> all(256); for (size_t i = 0; i < all.size(); ++i) all[i] = static_cast<uint8_t>(i);
  Value buffer = Buffer(all), view = View(buffer, 0, 256), partial = View(buffer, 17, 31);
  auto copied = Invoke(Call_echo_bytes, {&view}); assert(copied.storage == all);
  copied.storage[0] = 123; assert(buffer.storage[0] == 0);
  auto sliced = Invoke(Call_echo_bytes, {&partial});
  assert(sliced.storage == std::vector<uint8_t>(all.begin() + 17, all.begin() + 48));
  auto joined = Invoke(Call_concat_bytes, {&view, &partial});
  std::vector<uint8_t> expected = all; expected.insert(expected.end(), all.begin() + 17, all.begin() + 48);
  assert(joined.storage == expected);
  assert(Invoke(Call_describe_bytes, {&label, &partial}).text == u"bytes=31");
  Value empty_buffer = Buffer({}), empty_view = View(empty_buffer, 0, 0);
  assert(Invoke(Call_echo_bytes, {&empty_view}).storage.empty());
  Value large_buffer = Buffer(std::vector<uint8_t>(65536, 255)), large_view = View(large_buffer, 0, 65536);
  assert(Invoke(Call_echo_bytes, {&large_view}).storage == large_buffer.storage);
  Reject(Call_echo_text, {&a}, "TypeError"); Reject(Call_echo_text, {}, "TypeError");
  Reject(Call_join_text, {&word, &a}, "TypeError");
  Reject(Call_describe_bytes, {&label, &a}, "TypeError");
  Reject(Call_echo_bytes, {&buffer}, "TypeError");
  Value data_view; data_view.type = napi_object; data_view.kind = DataView;
  Reject(Call_echo_bytes, {&data_view}, "TypeError");
  for (auto type : {napi_uint8_clamped_array, napi_int8_array, napi_int16_array}) {
    Value wrong = View(buffer, 0, 1, type); Reject(Call_echo_bytes, {&wrong}, "TypeError");
  }
  buffer.detached = true; Reject(Call_echo_bytes, {&view}, "TypeError"); buffer.detached = false;
  buffer.kind = SharedBuffer; Reject(Call_echo_bytes, {&view}, "TypeError"); buffer.kind = ArrayBuffer;
  view.sendable = true; Reject(Call_echo_bytes, {&view}, "TypeError"); view.sendable = false;
  buffer.sendable = true; Reject(Call_echo_bytes, {&view}, "TypeError"); buffer.sendable = false;
  Value too_long = word; too_long.reported_length = size_t(INT32_MAX) + 1;
  Reject(Call_echo_text, {&too_long}, "RangeError");
  Value huge_view = view; huge_view.length = size_t(INT32_MAX) + 1;
  Reject(Call_echo_bytes, {&huge_view}, "RangeError");
  assert(!CheckLength(&env, std::numeric_limits<size_t>::max(), 2));
  FailureSweep(Call_echo_text, {&word}); FailureSweep(Call_join_text, {&label, &word});
  FailureSweep(Call_echo_bytes, {&view}); FailureSweep(Call_concat_bytes, {&view, &partial});
  FailureSweep(Call_describe_bytes, {&label, &partial});
  for (int failure = 0; failure < 3; ++failure) {
    buffer_failure_after = failure;
    Reject(Call_describe_bytes, {&label, &partial}, "Error");
    buffer_failure_after = -1;
  }
  for (int failure = 0; failure < 2; ++failure) {
    buffer_failure_after = failure;
    Reject(Call_echo_bytes, {&partial}, "Error");
    buffer_failure_after = -1;
  }
  for (int i = 0; i < 10000; ++i) {
    assert(Invoke(Call_echo_text, {&word}).text == word.text);
    assert(Invoke(Call_echo_bytes, {&partial}).storage == sliced.storage);
    assert(Invoke(Call_describe_bytes, {&label, &partial}).text == u"bytes=31");
  }
  assert(moonohos_live_allocations() == baseline);
  std::cout << "HOST_REFERENCE_PASS utf16/bytes/alias/status/allocation/repeat=10000 live_delta=0\n";
}
