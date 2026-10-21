// Cooperative cancellation for MoonBit code running in a MoonOHOS async task.
#include <stdint.h>
#ifdef MOONOHOS_BRIDGE
// Defined by the generated bridge; reads the token of the task holding the gate.
extern int32_t moonohos_bridge_cancelled(void);
int32_t moonohos_task_cancelled(void) { return moonohos_bridge_cancelled(); }
void moonohos_task_host_set(int32_t value) { (void)value; }
#else
static int32_t moonohos_task_host_flag = 0;
int32_t moonohos_task_cancelled(void) { return moonohos_task_host_flag; }
void moonohos_task_host_set(int32_t value) { moonohos_task_host_flag = value; }
#endif
