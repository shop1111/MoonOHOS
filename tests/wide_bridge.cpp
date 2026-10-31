#include "napi_init.cpp"
#include <cassert>
#include <iostream>
// Int64 <-> bigint: scalars, arrays and record fields, lossless range checks,
// Node-API failure injection and leak checks.
extern "C" size_t moonohos_live_allocations(void);
static Value Big(int64_t x, bool lossless = true) { Value v; v.type = napi_bigint; v.big = x; v.lossless = lossless; return v; }
static Value Number(double x) { return {napi_number, x, false}; }
static Value Text(std::u16string x) { Value v; v.type = napi_string; v.text = std::move(x); return v; }
static Value Array(std::vector<Value> children) { Value v; v.type = napi_object; v.kind = OrdinaryArray; for (auto &x : children) v.elements.push_back(Clone(x)); return v; }
static Value Object(std::initializer_list<std::pair<const char *, Value>> fields) { Value v; v.type = napi_object; for (const auto &f : fields) v.properties[f.first] = Clone(f.second); return v; }
static Value Invoke(napi_callback cb, std::vector<napi_value> args) {
  Env env; Call info{args}; auto before = moonohos_live_allocations(); auto out = cb(&env, &info);
  assert(out && env.exception.empty()); assert(moonohos_live_allocations() == before); return *Clone(*out);
}
static void Reject(napi_callback cb, std::vector<napi_value> args, const char *error, const char *where) {
  Env e; Call info{args}; auto before = moonohos_live_allocations();
  assert(!cb(&e, &info)); assert(e.exception == error); assert(e.message.find(where) != std::string::npos);
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
  const int64_t max = INT64_MAX, min = INT64_MIN, big = 9007199254740993LL; // 2^53 + 1 is not a safe double
  Value a = Big(big), b = Big(-2), top = Big(max), one = Big(1);
  auto sum = Invoke(Call_add_wide, {&a, &b});
  assert(sum.type == napi_bigint && sum.big == big - 2);
  assert(Invoke(Call_add_wide, {&top, &one}).big == min); // MoonBit Int64 wraps
  Value values = Array({Big(max), Big(min), Big(big)});
  assert(Invoke(Call_sum_wide, {&values}).big == big - 1);
  Value empty = Array({});
  assert(Invoke(Call_sum_wide, {&empty}).big == 0);
  auto parts = Invoke(Call_split_wide, {&a});
  assert(parts.elements.size() == 2 && parts.elements[0]->type == napi_bigint);
  assert(parts.elements[0]->big == (big >> 32) && parts.elements[1]->big == (big & 0xFFFFFFFFLL));
  Value stamp = Object({{"id", Big(big)}, {"offsets", Array({Big(0), Big(-big)})}, {"label", Text(u"t")}});
  Value delta = Big(10);
  auto shifted = Invoke(Call_shift_stamp, {&stamp, &delta});
  assert(shifted.properties.at("id")->big == big + 10);
  assert(shifted.properties.at("offsets")->elements[1]->big == -big + 10);
  assert(shifted.properties.at("label")->text == u"t");
  // A JS number is not a bigint, and a bigint outside int64 is a RangeError.
  Value number = Number(1);
  Reject(Call_add_wide, {&number, &b}, "TypeError", "add_wide.a");
  Value huge = Big(0, false);
  Reject(Call_add_wide, {&a, &huge}, "RangeError", "add_wide.b");
  Value bad_values = Array({Big(1), huge});
  Reject(Call_sum_wide, {&bad_values}, "RangeError", "sum_wide.values[1]");
  Value bad_stamp = stamp; bad_stamp.properties["id"] = Clone(Number(3));
  Reject(Call_shift_stamp, {&bad_stamp, &delta}, "TypeError", "shift_stamp.stamp.id");
  FailureSweep(Call_add_wide, {&a, &b}); FailureSweep(Call_sum_wide, {&values});
  FailureSweep(Call_shift_stamp, {&stamp, &delta}); FailureSweep(Call_split_wide, {&a});
  auto baseline = moonohos_live_allocations();
  for (int i = 0; i < 10000; ++i) { Invoke(Call_sum_wide, {&values}); Invoke(Call_shift_stamp, {&stamp, &delta}); Invoke(Call_split_wide, {&a}); }
  assert(moonohos_live_allocations() == baseline);
  std::cout << "HOST_WIDE_PASS int64/bigint scalars/arrays/records/range/status/repeat=10000 live_delta=0\n";
}
