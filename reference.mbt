///|
fn reference_helpers() -> String {
  (
    #|#ifndef MOONOHOS_BUFFER_ALLOCATE
    #|#define MOONOHOS_BUFFER_ALLOCATE() ((void)0)
    #|#endif
    #|template<class T> struct MoonOwner {
    #|  T ptr;
    #|  explicit MoonOwner(T value) : ptr(value) {}
    #|  MoonOwner(const MoonOwner &) = delete;
    #|  MoonOwner &operator=(const MoonOwner &) = delete;
    #|  ~MoonOwner() { if (ptr) moonbit_decref(ptr); }
    #|};
    #|static bool CheckLength(napi_env env, size_t length, size_t width) {
    #|  if (length > INT32_MAX || length > (std::numeric_limits<size_t>::max() - sizeof(moonbit_object)) / width - 1) {
    #|    Check(env, napi_throw_range_error(env, nullptr, "buffer length exceeded")); return false;
    #|  }
    #|  return true;
    #|}
    #|static bool ReadText(napi_env env, napi_value value, std::u16string &out) {
    #|  napi_valuetype type;
    #|  if (!Check(env, napi_typeof(env, value, &type))) return false;
    #|  if (type != napi_string) { Check(env, napi_throw_type_error(env, nullptr, "string required")); return false; }
    #|  size_t length;
    #|  if (!Check(env, napi_get_value_string_utf16(env, value, nullptr, 0, &length))) return false;
    #|  if (!CheckLength(env, length, sizeof(char16_t))) return false;
    #|  MOONOHOS_BUFFER_ALLOCATE();
    #|  out.resize(length + 1);
    #|  size_t written;
    #|  if (!Check(env, napi_get_value_string_utf16(env, value, out.data(), out.size(), &written))) return false;
    #|  if (written != length) { Check(env, napi_throw_error(env, nullptr, "string length changed")); return false; }
    #|  out.resize(length);
    #|  return true;
    #|}
    #|static bool ReadBytes(napi_env env, napi_value value, std::vector<uint8_t> &out) {
    #|  bool typed;
    #|  if (!Check(env, napi_is_typedarray(env, value, &typed))) return false;
    #|  if (!typed) { Check(env, napi_throw_type_error(env, nullptr, "Uint8Array required")); return false; }
    #|  bool sendable;
    #|  if (!Check(env, napi_is_sendable(env, value, &sendable))) return false;
    #|  if (sendable) { Check(env, napi_throw_type_error(env, nullptr, "shared/sendable Uint8Array unsupported")); return false; }
    #|  napi_typedarray_type type;
    #|  size_t length, offset;
    #|  void *data;
    #|  napi_value buffer;
    #|  if (!Check(env, napi_get_typedarray_info(env, value, &type, &length, &data, &buffer, &offset))) return false;
    #|  bool ordinary;
    #|  if (!Check(env, napi_is_arraybuffer(env, buffer, &ordinary))) return false;
    #|  if (type != napi_uint8_array || !ordinary) { Check(env, napi_throw_type_error(env, nullptr, "ordinary Uint8Array required")); return false; }
    #|  if (!Check(env, napi_is_sendable(env, buffer, &sendable))) return false;
    #|  if (sendable) { Check(env, napi_throw_type_error(env, nullptr, "shared/sendable ArrayBuffer unsupported")); return false; }
    #|  bool detached;
    #|  if (!Check(env, napi_is_detached_arraybuffer(env, buffer, &detached))) return false;
    #|  if (detached) { Check(env, napi_throw_type_error(env, nullptr, "detached ArrayBuffer")); return false; }
    #|  if (!CheckLength(env, length, 1)) return false;
    #|  if (length && !data) { Check(env, napi_throw_type_error(env, nullptr, "invalid Uint8Array storage")); return false; }
    #|  MOONOHOS_BUFFER_ALLOCATE();
    #|  out.resize(length);
    #|  // Node-API's data pointer already includes the view offset.
    #|  if (length) std::memcpy(out.data(), data, length);
    #|  return true;
    #|}
    #|static moonbit_string_t MakeText(const std::u16string &value) {
    #|  auto result = moonbit_make_string_raw(static_cast<int32_t>(value.size()));
    #|  if (!value.empty()) std::memcpy(result, value.data(), value.size() * sizeof(char16_t));
    #|  return result;
    #|}
    #|static moonbit_bytes_t MakeBytes(const std::vector<uint8_t> &value) {
    #|  auto result = moonbit_make_bytes_raw(static_cast<int32_t>(value.size()));
    #|  if (!value.empty()) std::memcpy(result, value.data(), value.size());
    #|  return result;
    #|}
    #|static std::u16string CopyText(moonbit_string_t value) {
    #|  int32_t length = Moonbit_array_length(value);
    #|  if (length < 0) throw std::length_error("invalid MoonBit string length");
    #|  MOONOHOS_BUFFER_ALLOCATE();
    #|  std::u16string result(static_cast<size_t>(length), 0);
    #|  if (length) std::memcpy(result.data(), value, static_cast<size_t>(length) * sizeof(char16_t));
    #|  return result;
    #|}
    #|static std::vector<uint8_t> CopyBytes(moonbit_bytes_t value) {
    #|  int32_t length = Moonbit_array_length(value);
    #|  if (length < 0) throw std::length_error("invalid MoonBit bytes length");
    #|  MOONOHOS_BUFFER_ALLOCATE();
    #|  std::vector<uint8_t> result(static_cast<size_t>(length));
    #|  if (length) std::memcpy(result.data(), value, length);
    #|  return result;
    #|}
    #|static napi_status CreateBytes(napi_env env, const std::vector<uint8_t> &value, napi_value *result) {
    #|  napi_value buffer;
    #|  void *data;
    #|  napi_status status = napi_create_arraybuffer(env, value.size(), &data, &buffer);
    #|  if (status != napi_ok) return status;
    #|  if (!value.empty()) std::memcpy(data, value.data(), value.size());
    #|  return napi_create_typedarray(env, napi_uint8_array, value.size(), buffer, 0, result);
    #|}
    #|
  ) +
  "\n"
}
