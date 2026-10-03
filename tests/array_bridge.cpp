#include "napi_init.cpp"
#include <cassert>
#include <iostream>
extern "C" size_t moonohos_live_allocations(void);
static Value Number(double x) { return {napi_number, x, false}; }
static Value Text(std::u16string x) { Value v; v.type = napi_string; v.text = std::move(x); return v; }
static Value Array(std::vector<Value> children) {
  Value v; v.type = napi_object; v.kind = OrdinaryArray;
  for (auto &child : children) v.elements.push_back(Clone(child)); return v;
}
static Value Invoke(napi_callback callback, std::vector<napi_value> args) {
  Env env; Call info{args}; auto before = moonohos_live_allocations();
  auto result = callback(&env, &info);
  assert(result && env.exception.empty()); assert(moonohos_live_allocations() == before);
  return *Clone(*result);
}
static void Reject(napi_callback callback, std::vector<napi_value> args, const char *error) {
  Env env; Call info{args}; auto before = moonohos_live_allocations();
  assert(!callback(&env, &info) && env.exception == error);
  assert(moonohos_live_allocations() == before);
}
static void Failures(napi_callback callback, std::vector<napi_value> args) {
  Env success; Call info{args}; assert(callback(&success, &info));
  for (int i = 0; i < success.operations; ++i) {
    for (bool pending : {false, true}) {
      Env e; e.fail_at = i; e.pending = pending; auto before = moonohos_live_allocations();
      assert(!callback(&e, &info)); assert(e.exception == (pending ? "PendingException" : "Error"));
      assert(moonohos_live_allocations() == before);
    }
  }
}
int main() {
  Value ints = Array({Number(INT32_MIN), Number(0), Number(INT32_MAX)});
  Value empty = Array({}); Value doubles = Array({Number(-1.5), Number(2.25)});
  Value booleans = Array({Value{napi_boolean, 0, true}, Value{napi_boolean, 0, false}});
  Value strings = Array({Text(u""), Text(std::u16string{u'中', 0, 0xD800})});
  Value nested = Array({strings, empty});
  Value buffer; buffer.type = napi_object; buffer.kind = ArrayBuffer; buffer.storage = {0, 255};
  Value bytes; bytes.type = napi_object; bytes.kind = TypedArray; bytes.buffer = &buffer; bytes.length = 2;
  Value binary = Array({bytes, bytes});
  assert(Invoke(Call_echo_ints, {&ints}).elements[2]->number == INT32_MAX);
  assert(Invoke(Call_echo_ints, {&empty}).elements.empty());
  assert(Invoke(Call_echo_doubles, {&doubles}).elements[0]->number == -1.5);
  assert(Invoke(Call_echo_bools, {&booleans}).elements[0]->boolean);
  assert(Invoke(Call_echo_strings, {&strings}).elements[1]->text == strings.elements[1]->text);
  assert(Invoke(Call_echo_binary, {&binary}).elements[1]->buffer->storage == buffer.storage);
  auto copied = Invoke(Call_echo_nested, {&nested}); copied.elements[0]->elements[1]->text = u"changed";
  assert(nested.elements[0]->elements[1]->text != u"changed");
  assert(Invoke(Call_join_ints, {&ints, &ints}).elements.size() == 6);
  Value hole = Array({Number(1)}); hole.elements[0].reset(); Reject(Call_echo_ints, {&hole}, "TypeError");
  Value wrong = Array({Text(u"bad")}); Reject(Call_echo_ints, {&wrong}, "TypeError");
  Value fractional = Array({Number(0.5)}); Reject(Call_echo_ints, {&fractional}, "RangeError");
  Value shared = ints; shared.sendable = true; Reject(Call_echo_ints, {&shared}, "TypeError");
  Value huge = empty; huge.reported_length = 1048577; Reject(Call_echo_ints, {&huge}, "RangeError");
  Value cyclic = Array({}); cyclic.elements.push_back(std::shared_ptr<Value>(&cyclic, [](Value *){}));
  Reject(Call_echo_nested, {&cyclic}, "TypeError"); cyclic.elements.clear();
  Value oversized_text = Text(u"x"); oversized_text.reported_length = 33554433;
  Value oversized_array = Array({oversized_text}); Reject(Call_echo_strings, {&oversized_array}, "RangeError");
  { Env e; Call call{{&wrong}}; assert(!Call_echo_ints(&e, &call)); assert(e.message.find("echo_ints.v[0]") != std::string::npos); }
  { Budget b{true}; b.add(1048576, 67108864, 32, "boundary");
    for (int kind = 0; kind < 3; ++kind) { bool caught = false;
      try { b.add(kind == 0 ? 1 : 0, kind == 1 ? 1 : 0, kind == 2 ? 33 : 32, "boundary"); }
      catch (const RangeFault &) { caught = true; } assert(caught);
    }
  }
  Reject(Call_echo_ints, {&bytes}, "TypeError"); Reject(Call_join_ints, {&ints, &wrong}, "TypeError");
  Failures(Call_echo_nested, {&nested}); Failures(Call_join_ints, {&ints, &ints}); Failures(Call_echo_binary, {&binary});
  for (int point = 0; point < 6; ++point) {
    Env e; Call info{{&nested}}; auto before = moonohos_live_allocations(); buffer_failure_after = point;
    auto result = Call_echo_nested(&e, &info); buffer_failure_after = -1;
    if (!result) assert(e.exception == "Error"); assert(moonohos_live_allocations() == before);
  }
  auto baseline = moonohos_live_allocations();
  for (int i = 0; i < 10000; ++i) { Invoke(Call_echo_nested, {&nested}); Invoke(Call_echo_binary, {&binary}); Invoke(Call_join_ints, {&ints, &ints}); }
  assert(moonohos_live_allocations() == baseline);
  std::cout << "HOST_ARRAY_PASS leaf_types/nested/alias/failures/repeat=10000 live_delta=0\n";
}
