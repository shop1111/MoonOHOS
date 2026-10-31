#include "napi_init.cpp"
#include <cassert>
#include <iostream>
// Option[T] <-> T | undefined: parameters, results, record fields (missing,
// undefined or null), array elements, Int64 payloads, failures and leaks.
extern "C" size_t moonohos_live_allocations(void);
static Value Undefined() { return Value{}; }
static Value Null() { Value v; v.type = napi_object; v.null_value = true; return v; }
static Value Number(double x) { return {napi_number, x, false}; }
static Value Big(int64_t x) { Value v; v.type = napi_bigint; v.big = x; return v; }
static Value Text(std::u16string x) { Value v; v.type = napi_string; v.text = std::move(x); return v; }
static Value Array(std::vector<Value> children) { Value v; v.type = napi_object; v.kind = OrdinaryArray; for (auto &x : children) v.elements.push_back(Clone(x)); return v; }
static Value Object(std::initializer_list<std::pair<const char *, Value>> fields) { Value v; v.type = napi_object; for (const auto &f : fields) v.properties[f.first] = Clone(f.second); return v; }
static Value Invoke(napi_callback cb, std::vector<napi_value> args) {
  Env env; Call info{args}; auto before = moonohos_live_allocations(); auto out = cb(&env, &info);
  assert(out && env.exception.empty()); assert(moonohos_live_allocations() == before); return *Clone(*out);
}
static void Reject(napi_callback cb, std::vector<napi_value> args, const char *error) {
  Env e; Call info{args}; auto before = moonohos_live_allocations();
  assert(!cb(&e, &info)); assert(e.exception == error); assert(moonohos_live_allocations() == before);
}
static void FailureSweep(napi_callback cb, std::vector<napi_value> args) {
  Env success; Call info{args}; assert(cb(&success, &info));
  for (int i = 0; i < success.operations; ++i) for (bool pending : {false, true}) {
    Env e; e.fail_at = i; e.pending = pending; auto before = moonohos_live_allocations();
    assert(!cb(&e, &info)); assert(e.exception == (pending ? "PendingException" : "Error")); assert(moonohos_live_allocations() == before);
  }
}
int main() {
  Value ada = Text(u"Ada"), none = Undefined(), null_value = Null();
  assert(Invoke(Call_greet, {&ada}).text == u"Hello, Ada");
  assert(Invoke(Call_greet, {&none}).text == u"Hello, stranger");
  assert(Invoke(Call_greet, {&null_value}).text == u"Hello, stranger");
  Value number = Number(1); Reject(Call_greet, {&number}, "TypeError"); // Some(x) must still be a string
  Value values = Array({Number(5), Number(7)}), seven = Number(7), nine = Number(9);
  auto found = Invoke(Call_find_index, {&values, &seven}); assert(found.type == napi_number && found.number == 1);
  assert(Invoke(Call_find_index, {&values, &nine}).type == napi_undefined);
  // Optional fields: present, explicitly undefined, null, or missing entirely.
  Value full = Object({{"name", Text(u"a")}, {"nickname", Text(u"n")}, {"age", Number(30)}, {"tags", Array({Text(u"x"), Undefined(), Null()})}});
  auto echoed = Invoke(Call_echo_profile, {&full});
  assert(echoed.properties.at("nickname")->text == u"n" && echoed.properties.at("age")->number == 30);
  auto tags = echoed.properties.at("tags")->elements;
  assert(tags.size() == 3 && tags[0]->text == u"x" && tags[1]->type == napi_undefined && tags[2]->type == napi_undefined);
  Value sparse = Object({{"name", Text(u"b")}, {"age", Null()}, {"tags", Array({})}});
  auto sparse_echo = Invoke(Call_echo_profile, {&sparse});
  assert(sparse_echo.properties.at("nickname")->type == napi_undefined);
  assert(sparse_echo.properties.at("age")->type == napi_undefined);
  Value missing_name = Object({{"tags", Array({})}}); Reject(Call_echo_profile, {&missing_name}, "TypeError");
  Value wrong_age = full; wrong_age.properties["age"] = Clone(Text(u"old")); Reject(Call_echo_profile, {&wrong_age}, "TypeError");
  Value young = Object({{"name", Text(u"y")}, {"age", Number(3)}, {"tags", Array({})}});
  Value people = Array({sparse, full, young}), nobody = Array({sparse});
  auto best = Invoke(Call_oldest, {&people}); assert(best.type == napi_object && best.properties.at("name")->text == u"a");
  assert(Invoke(Call_oldest, {&nobody}).type == napi_undefined);
  Value wide = Big(INT64_MAX - 1);
  auto next = Invoke(Call_next_wide, {&wide}); assert(next.type == napi_bigint && next.big == INT64_MAX);
  assert(Invoke(Call_next_wide, {&none}).type == napi_undefined);
  FailureSweep(Call_greet, {&ada}); FailureSweep(Call_greet, {&null_value}); FailureSweep(Call_find_index, {&values, &seven});
  FailureSweep(Call_echo_profile, {&full}); FailureSweep(Call_echo_profile, {&sparse}); FailureSweep(Call_oldest, {&people});
  FailureSweep(Call_next_wide, {&wide});
  auto baseline = moonohos_live_allocations();
  for (int i = 0; i < 10000; ++i) { Invoke(Call_echo_profile, {&full}); Invoke(Call_oldest, {&people}); Invoke(Call_greet, {&none}); Invoke(Call_next_wide, {&wide}); }
  assert(moonohos_live_allocations() == baseline);
  std::cout << "HOST_OPTION_PASS params/results/fields(missing,undefined,null)/elements/int64/status/repeat=10000 live_delta=0\n";
}
