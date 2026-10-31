// Vibrator (sensors/vibrator.h). Needs ohos.permission.VIBRATE in the app.
#include <stdint.h>
#ifdef MOONOHOS_TARGET_OHOS
#include <sensors/vibrator.h>
#else
static int32_t moonohos_vibrator_last[3] = {0, 0, 0}; // duration, usage, cancels
#endif

int32_t moonohos_vibrator_play(int32_t duration, int32_t usage) {
#ifdef MOONOHOS_TARGET_OHOS
  Vibrator_Attribute attribute = { 0, (Vibrator_Usage)usage };
  return OH_Vibrator_PlayVibration(duration, attribute);
#else
  moonohos_vibrator_last[0] = duration;
  moonohos_vibrator_last[1] = usage;
  return 0;
#endif
}

int32_t moonohos_vibrator_cancel(void) {
#ifdef MOONOHOS_TARGET_OHOS
  return OH_Vibrator_Cancel();
#else
  moonohos_vibrator_last[2] += 1;
  return 0;
#endif
}

// Host-only observation hook for tests: 0 duration, 1 usage, 2 cancel count.
int32_t moonohos_vibrator_host_last(int32_t which) {
#ifdef MOONOHOS_TARGET_OHOS
  (void)which;
  return -1;
#else
  return which >= 0 && which < 3 ? moonohos_vibrator_last[which] : -1;
#endif
}
