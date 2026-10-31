#include "napi_init.cpp"
#include <cassert>
#include <iostream>
// Payload-free enums <-> string literal unions: parameters, results, record
// fields, arrays, Option payloads, unknown names, failures and leaks.
extern "C" size_t moonohos_live_allocations(void);
static Value Text(std::u16string x) { Value v; v.type = napi_string; v.text = std::move(x); return v; }
static Value Number(double x) { return {napi_number, x, false}; }
static Value Array(std::vector<Value> children) { Value v; v.type = napi_object; v.kind = OrdinaryArray; for (auto &x : children) v.elements.push_back(Clone(x)); return v; }
static Value Object(std::initializer_list<std::pair<const char *, Value>> fields) { Value v; v.type = napi_object; for (const auto &f : fields) v.properties[f.first] = Clone(f.second); return v; }
static Value Invoke(napi_callback cb, std::vector<napi_value> args) {
  Env env; Call info{args}; auto before = moonohos_live_allocations(); auto out = cb(&env, &info);
  assert(out && env.exception.empty()); assert(moonohos_live_allocations() == before); return *Clone(*out);
}
static void Reject(napi_callback cb, std::vector<napi_value> args, const char *error, const char *text) {
  Env e; Call info{args}; auto before = moonohos_live_allocations();
  assert(!cb(&e, &info)); assert(e.exception == error); assert(e.message.find(text) != std::string::npos);
  assert(moonohos_live_allocations() == before);
}
static void FailureSweep(napi_callback cb, std::vector<napi_value> args) {
  Env success; Call info{args}; assert(cb(&success, &info));
  for (int i = 0; i < success.operations; ++i) for (bool pending : {false, true}) {
    Env e; e.fail_at = i; e.pending = pending; auto before = moonohos_live_allocations();
    assert(!cb(&e, &info)); assert(e.exception == (pending ? "PendingException" : "Error")); assert(moonohos_live_allocations() == before);
  }
}
int main() {
  Value debug = Text(u"Debug"), warn = Text(u"Warn"), error = Text(u"Error");
  auto up = Invoke(Call_bump, {&debug}); assert(up.type == napi_string && up.text == u"Info");
  assert(Invoke(Call_bump, {&error}).text == u"Error");
  Value missing; Reject(Call_bump, {&missing}, "TypeError", "bump.level");
  Value unknown = Text(u"Fatal"); Reject(Call_bump, {&unknown}, "TypeError", "'Debug' | 'Info' | 'Warn' | 'Error'");
  Value lower = Text(u"debug"); Reject(Call_bump, {&lower}, "TypeError", "bump.level");
  Value number = Number(0); Reject(Call_bump, {&number}, "TypeError", "bump.level");
  Value first = Object({{"level", Text(u"Info")}, {"message", Text(u"m")}, {"seen", Array({Text(u"Debug"), Text(u"Warn")})}, {"previous", Text(u"Debug")}});
  Value second = Object({{"level", Text(u"Error")}, {"message", Text(u"e")}, {"seen", Array({})}});
  Value events = Array({first, second}), empty = Array({});
  assert(Invoke(Call_count_at_least, {&events, &warn}).number == 1);
  assert(Invoke(Call_count_at_least, {&events, &debug}).number == 2);
  assert(Invoke(Call_loudest, {&events}).text == u"Error");
  assert(Invoke(Call_loudest, {&empty}).type == napi_undefined);
  auto echoed = Invoke(Call_echo_event, {&first});
  assert(echoed.properties.at("level")->text == u"Info" && echoed.properties.at("previous")->text == u"Debug");
  assert(echoed.properties.at("seen")->elements[1]->text == u"Warn");
  assert(Invoke(Call_echo_event, {&second}).properties.at("previous")->type == napi_undefined);
  Value bad_seen = first; bad_seen.properties["seen"] = Clone(Array({Text(u"Loud")}));
  Reject(Call_echo_event, {&bad_seen}, "TypeError", "echo_event.event.seen[0]");
  FailureSweep(Call_bump, {&debug}); FailureSweep(Call_count_at_least, {&events, &warn});
  FailureSweep(Call_loudest, {&events}); FailureSweep(Call_echo_event, {&first});
  auto baseline = moonohos_live_allocations();
  for (int i = 0; i < 10000; ++i) { Invoke(Call_echo_event, {&first}); Invoke(Call_loudest, {&events}); Invoke(Call_bump, {&warn}); }
  assert(moonohos_live_allocations() == baseline);
  std::cout << "HOST_ENUM_PASS params/results/fields/arrays/option/unknown/status/repeat=10000 live_delta=0\n";
}
