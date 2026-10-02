#include "napi_init.cpp"
#include <cassert>
#include <iostream>
extern "C" size_t moonohos_live_allocations(void);
int main() {
  Env env;
  Value text; text.type = napi_string; text.text = u"hello";
  Value offset; offset.type = napi_number; offset.number = 2;
  Value factor; factor.type = napi_number; factor.number = 1.5;
  Value flag; flag.type = napi_boolean; flag.boolean = true;
  Value buffer; buffer.type = napi_object; buffer.kind = ArrayBuffer; buffer.storage = {0, 127, 255};
  Value bytes; bytes.type = napi_object; bytes.kind = TypedArray; bytes.buffer = &buffer; bytes.length = 3;
  Call empty;
  assert(Call_constant_text(&env, &empty)->text == u"中文😀");
  const auto baseline = moonohos_live_allocations();
  Call length{{&text, &offset}}, weighted{{&bytes, &factor}}, enabled{{&text, &flag}}, discard{{&text, &bytes}};
  Call mixed{{&text, &bytes, &offset, &factor, &flag}};
  for (int repeat = 0; repeat < 10000; ++repeat) {
    assert(Call_length(&env, &length)->number == 7);
    assert(Call_weighted(&env, &weighted)->number == 4.5);
    assert(Call_enabled(&env, &enabled)->boolean);
    assert(Call_discard(&env, &discard)->type == napi_undefined);
    assert(Call_constant_text(&env, &empty)->text == u"中文😀");
    assert(Call_constant_bytes(&env, &empty)->length == 2 && env.buffer.storage == std::vector<uint8_t>({0, 255}));
    assert(Call_mixed(&env, &mixed)->text == u"hello5:1.5");
    assert(moonohos_live_allocations() == baseline);
  }
  factor.number = 1e308;
  env.exception.clear();
  assert(Call_weighted(&env, &weighted) == nullptr && env.exception == "RangeError");
  assert(moonohos_live_allocations() == baseline);
  std::cout << "HOST_MATRIX_PASS all_return_kinds/mixed_scalars/repeat=10000 live_delta=0\n";
}
