// HiLog bridge. Messages are always passed as a "%{public}s" argument, never as
// the format string, so '%' in MoonBit text cannot be interpreted by HiLog.
#include <stdint.h>
#include "moonbit.h"
#ifdef MOONOHOS_TARGET_OHOS
#include <hilog/log.h>
#else
#include <stdio.h>
#endif

int32_t moonohos_hilog_print(int32_t level, int32_t domain, moonbit_bytes_t tag, moonbit_bytes_t message) {
#ifdef MOONOHOS_TARGET_OHOS
  return OH_LOG_Print(LOG_APP, (LogLevel)level, (unsigned int)domain, (const char *)tag, "%{public}s", (const char *)message);
#else
  static const char *names = "???DIWEF";
  char name = level >= 3 && level <= 7 ? names[level] : '?';
  return fprintf(stderr, "%c %05x/%s: %s\n", name, (unsigned int)domain, (const char *)tag, (const char *)message);
#endif
}

int32_t moonohos_hilog_loggable(int32_t level, int32_t domain, moonbit_bytes_t tag) {
#ifdef MOONOHOS_TARGET_OHOS
  return OH_LOG_IsLoggable((unsigned int)domain, (const char *)tag, (LogLevel)level) ? 1 : 0;
#else
  (void)domain;
  (void)tag;
  return level >= 3 ? 1 : 0;
#endif
}
