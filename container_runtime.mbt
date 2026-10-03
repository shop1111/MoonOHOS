///|
fn container_runtime() -> String {
  (
    #|#include <algorithm>
    #|#include <utility>
    #|struct TypeFault : std::runtime_error { using std::runtime_error::runtime_error; };
    #|struct RangeFault : std::runtime_error { using std::runtime_error::runtime_error; };
    #|struct BridgeValue {
    #|  int32_t integer = 0;
    #|  double number = 0;
    #|  std::u16string text;
    #|  std::vector<uint8_t> bytes;
    #|  std::vector<BridgeValue> children;
    #|};
    #|struct Budget {
    #|  bool enabled;
    #|  size_t nodes = 0, bytes = 0;
    #|  void add(size_t count, size_t size, size_t depth, const std::string &path) {
    #|    if (!enabled) return;
    #|    if (depth > __DEPTH__ || count > __NODES__ - nodes || size > __BYTES__ - bytes)
    #|      throw RangeFault(path + ": conversion limit exceeded");
    #|    nodes += count; bytes += size;
    #|  }
    #|};
    #|struct Ancestors {
    #|  napi_env env;
    #|  std::vector<napi_value> values;
    #|  bool enter(napi_value value, const std::string &path) {
    #|    for (auto ancestor : values) {
    #|      bool same;
    #|      if (!Check(env, napi_strict_equals(env, ancestor, value, &same))) return false;
    #|      if (same) throw TypeFault(path + ": cyclic object");
    #|    }
    #|    values.push_back(value); return true;
    #|  }
    #|};
    #|struct AncestorScope {
    #|  Ancestors &stack;
    #|  explicit AncestorScope(Ancestors &value) : stack(value) {}
    #|  ~AncestorScope() { stack.values.pop_back(); }
    #|};
    #|static bool Own(napi_env env, napi_value value, const std::string &name, napi_value &result, const std::string &path) {
    #|  napi_value key;
    #|  if (!Check(env, napi_create_string_utf8(env, name.data(), name.size(), &key))) return false;
    #|  bool present;
    #|  if (!Check(env, napi_has_own_property(env, value, key, &present))) return false;
    #|  if (!present) throw TypeFault(path + ": missing own property");
    #|  return Check(env, napi_get_property(env, value, key, &result));
    #|}
    #|static bool Ordinary(napi_env env, napi_value value, bool array, const std::string &path) {
    #|  bool actual, sendable;
    #|  if (!Check(env, napi_is_array(env, value, &actual))) return false;
    #|  if (actual != array) throw TypeFault(path + (array ? ": array required" : ": record required"));
    #|  if (!Check(env, napi_is_sendable(env, value, &sendable))) return false;
    #|  if (sendable) throw TypeFault(path + ": Sendable containers unsupported");
    #|  if (!array) {
    #|    napi_valuetype type;
    #|    if (!Check(env, napi_typeof(env, value, &type))) return false;
    #|    napi_value null_value;
    #|    bool is_null;
    #|    if (!Check(env, napi_get_null(env, &null_value))) return false;
    #|    if (!Check(env, napi_strict_equals(env, value, null_value, &is_null))) return false;
    #|    if (type != napi_object || is_null) throw TypeFault(path + ": record required");
    #|    bool special;
    #|    if (!Check(env, napi_is_typedarray(env, value, &special))) return false;
    #|    if (special) throw TypeFault(path + ": record required");
    #|    if (!Check(env, napi_is_arraybuffer(env, value, &special))) return false;
    #|    if (special) throw TypeFault(path + ": record required");
    #|    if (!Check(env, napi_is_dataview(env, value, &special))) return false;
    #|    if (special) throw TypeFault(path + ": record required");
    #|  }
    #|  return true;
    #|}
    #|static bool LeafType(napi_env env, napi_value value, napi_valuetype wanted, const std::string &path) {
    #|  napi_valuetype actual;
    #|  if (!Check(env, napi_typeof(env, value, &actual))) return false;
    #|  if (actual != wanted) throw TypeFault(path + ": incorrect value type");
    #|  return true;
    #|}
    #|
  )
  .replace_all(old="__DEPTH__", new=conversion_limits().depth.to_string())
  .replace_all(old="__NODES__", new=conversion_limits().nodes.to_string())
  .replace_all(old="__BYTES__", new=conversion_limits().bytes.to_string()) +
  "\n"
}
