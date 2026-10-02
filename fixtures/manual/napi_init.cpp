#include <napi/native_api.h>
#include <cmath>
#include <mutex>
#include <cstdint>
extern "C" int32_t moonohos_add(int32_t, int32_t);
extern "C" void moonohos_initialize(void);
static std::mutex gate;
static std::once_flag initialized;
static napi_value Add(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value argv[2] = {nullptr, nullptr};
  if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok) {
    napi_throw_error(env, nullptr, "cannot read arguments"); return nullptr;
  }
  if (argc < 2) { napi_throw_type_error(env, nullptr, "two arguments required"); return nullptr; }
  int32_t args[2];
  for (size_t i = 0; i < 2; ++i) {
    napi_valuetype type;
    if (napi_typeof(env, argv[i], &type) != napi_ok) { napi_throw_error(env, nullptr, "cannot read type"); return nullptr; }
    if (type != napi_number) { napi_throw_type_error(env, nullptr, "number required"); return nullptr; }
    double value;
    if (napi_get_value_double(env, argv[i], &value) != napi_ok) { napi_throw_error(env, nullptr, "cannot read number"); return nullptr; }
    if (!std::isfinite(value) || std::trunc(value) != value || value < INT32_MIN || value > INT32_MAX) {
      napi_throw_range_error(env, nullptr, "Int out of range"); return nullptr;
    }
    args[i] = static_cast<int32_t>(value);
  }
  int32_t value;
  { std::lock_guard<std::mutex> lock(gate); std::call_once(initialized, moonohos_initialize); value = moonohos_add(args[0], args[1]); }
  napi_value result;
  if (napi_create_int32(env, value, &result) != napi_ok) { napi_throw_error(env, nullptr, "cannot create result"); return nullptr; }
  return result;
}
static napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {{"add", nullptr, Add, nullptr, nullptr, nullptr, napi_default, nullptr}};
  if (napi_define_properties(env, exports, 1, desc) != napi_ok) { napi_throw_error(env, nullptr, "cannot register exports"); return nullptr; }
  return exports;
}
NAPI_MODULE(moonohos, Init)
