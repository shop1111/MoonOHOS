#define main moonohos_unused_main
#include "async_probe.c"
#undef main
void moonohos_initialize(void) {
  static char name[] = "moonohos";
  static char *args[] = {name, 0};
  moonbit_runtime_init(1, args);
  moonbit_init();
}
