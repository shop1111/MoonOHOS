// Device information (deviceinfo.h). Strings are copied into a caller buffer;
// the return value is the full UTF-8 length so the caller can retry.
#include <stdint.h>
#include <string.h>
#include "moonbit.h"
#ifdef MOONOHOS_TARGET_OHOS
#include <deviceinfo.h>
#endif

static const char *moonohos_deviceinfo_text(int32_t field) {
#ifdef MOONOHOS_TARGET_OHOS
  switch (field) {
    case 0: return OH_GetDeviceType();
    case 1: return OH_GetManufacture();
    case 2: return OH_GetBrand();
    case 3: return OH_GetMarketName();
    case 4: return OH_GetProductSeries();
    case 5: return OH_GetProductModel();
    case 6: return OH_GetSoftwareModel();
    case 7: return OH_GetHardwareModel();
    case 8: return OH_GetOSFullName();
    case 9: return OH_GetDisplayVersion();
    case 10: return OH_GetDistributionOSName();
    case 11: return OH_GetDistributionOSVersion();
    case 12: return OH_GetAbiList();
    case 13: return OH_GetBuildType();
    default: return 0;
  }
#else
  // Host fallback used by unit tests and desktop builds.
  static const char *const host[] = {
    "host", "MoonOHOS", "host", "Host", "host", "host", "host", "host",
    "Host-0.0.0", "host", "Host", "0.0.0", "host", "user",
  };
  return field >= 0 && field < 14 ? host[field] : 0;
#endif
}

int32_t moonohos_deviceinfo_copy(int32_t field, moonbit_bytes_t out, int32_t capacity) {
  const char *text = moonohos_deviceinfo_text(field);
  if (!text) return -1;
  size_t length = strlen(text);
  if (length > INT32_MAX) return -1;
  if ((size_t)capacity >= length) memcpy(out, text, length);
  return (int32_t)length;
}

int32_t moonohos_deviceinfo_api(int32_t which) {
#ifdef MOONOHOS_TARGET_OHOS
  switch (which) {
    case 0: return OH_GetSdkApiVersion();
    case 1: return OH_GetFirstApiVersion();
    case 2: return OH_GetDistributionOSApiVersion();
    default: return -1;
  }
#else
  return which >= 0 && which <= 2 ? 0 : -1;
#endif
}

int32_t moonohos_deviceinfo_is_device(void) {
#ifdef MOONOHOS_TARGET_OHOS
  return 1;
#else
  return 0;
#endif
}
