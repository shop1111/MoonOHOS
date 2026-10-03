#include "napi_init.cpp"
#include <cassert>
#include <iostream>
extern "C" size_t moonohos_live_allocations(void);
static Value Number(double x) { return {napi_number, x, false}; }
static Value Text(std::u16string x) { Value v; v.type = napi_string; v.text = std::move(x); return v; }
static Value Array(std::vector<Value> children) { Value v; v.type = napi_object; v.kind = OrdinaryArray; for (auto &x : children) v.elements.push_back(Clone(x)); return v; }
static Value Object(std::initializer_list<std::pair<const char *, Value>> fields) { Value v; v.type = napi_object; for (const auto &f : fields) v.properties[f.first] = Clone(f.second); return v; }
static Value Invoke(napi_callback cb, std::vector<napi_value> args) {
  Env env; Call info{args}; auto before = moonohos_live_allocations(); auto out = cb(&env, &info);
  assert(out && env.exception.empty()); assert(moonohos_live_allocations() == before); return *Clone(*out);
}
static void Reject(napi_callback cb, std::vector<napi_value> args, const char *error) {
  Env e; Call info{args}; auto before = moonohos_live_allocations(); assert(!cb(&e, &info)); assert(e.exception == error); assert(moonohos_live_allocations() == before);
}
static void FailureSweep(napi_callback cb, std::vector<napi_value> args) {
  Env success; Call info{args}; assert(cb(&success, &info));
  for (int i = 0; i < success.operations; ++i) for (bool pending : {false, true}) {
    Env e; e.fail_at = i; e.pending = pending; auto before = moonohos_live_allocations();
    assert(!cb(&e, &info)); assert(e.exception == (pending ? "PendingException" : "Error")); assert(moonohos_live_allocations() == before);
  }
}
int main() {
  Value buffer; buffer.type = napi_object; buffer.kind = ArrayBuffer; buffer.storage = {0, 255};
  Value bytes; bytes.type = napi_object; bytes.kind = TypedArray; bytes.buffer = &buffer; bytes.length = 2;
  Value meta = Object({{"active", Value{napi_boolean, 0, true}}});
  Value box = Object({{"label", Text(std::u16string{u'中', 0, 0xD800})}, {"values", Array({Number(-1), Number(2), Number(41)})}, {"meta", meta}, {"payload", bytes}, {"ignored", Number(9)}});
  Value boxes = Array({box, box});
  auto copied = Invoke(Call_echo_box, {&box});
  assert(copied.properties.size() == 4 && copied.properties.at("meta")->properties.at("active")->boolean);
  assert(copied.properties.at("payload")->buffer->storage == buffer.storage);
  copied.properties.at("label")->text = u"changed"; assert(box.properties.at("label")->text != u"changed");
  assert(Invoke(Call_echo_boxes, {&boxes}).elements.size() == 2);
  assert(Invoke(Call_select_box, {&box, &box}).properties.at("label")->text == box.properties.at("label")->text);
  auto summary = Invoke(Call_summarize, {&boxes}); assert(summary.properties.at("count")->number == 2 && summary.properties.at("total")->number == 84);
  Value missing = box; missing.properties.erase("meta"); Reject(Call_echo_box, {&missing}, "TypeError");
  { Env e; Call call{{&missing}}; assert(!Call_echo_box(&e, &call)); assert(e.message.find("echo_box.v.meta") != std::string::npos); }
  auto independent = Invoke(Call_echo_boxes, {&boxes});
  independent.elements[0]->properties.at("meta")->properties.at("active")->boolean = false;
  assert(independent.elements[1]->properties.at("meta")->properties.at("active")->boolean);
  Value wrong = box; wrong.properties["label"] = Clone(Number(7)); Reject(Call_select_box, {&box, &wrong}, "TypeError");
  Value null_value; null_value.type = napi_object; null_value.null_value = true; Reject(Call_echo_box, {&null_value}, "TypeError");
  Value shared = box; shared.sendable = true; Reject(Call_echo_box, {&shared}, "TypeError");
  Value cyclic = box; cyclic.properties["meta"] = std::shared_ptr<Value>(&cyclic, [](Value *){}); Reject(Call_echo_box, {&cyclic}, "TypeError"); cyclic.properties.erase("meta");
  Reject(Call_echo_box, {&boxes}, "TypeError");
  FailureSweep(Call_echo_box, {&box}); FailureSweep(Call_echo_boxes, {&boxes}); FailureSweep(Call_select_box, {&box, &box}); FailureSweep(Call_summarize, {&boxes});
  for (int i = 0; i < 18; ++i) {
    Env e; Call info{{&box}}; auto before = moonohos_live_allocations(); buffer_failure_after = i;
    auto result = Call_echo_box(&e, &info); buffer_failure_after = -1; if (!result) assert(e.exception == "Error"); assert(moonohos_live_allocations() == before);
  }
  auto baseline = moonohos_live_allocations();
  for (int i = 0; i < 10000; ++i) { Invoke(Call_echo_box, {&box}); Invoke(Call_echo_boxes, {&boxes}); Invoke(Call_select_box, {&box, &box}); Invoke(Call_summarize, {&boxes}); }
  assert(moonohos_live_allocations() == baseline);
  std::cout << "HOST_RECORD_PASS nested/alias/copy/cycles/status/repeat=10000 live_delta=0\n";
}
