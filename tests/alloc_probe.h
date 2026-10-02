#pragma once
// Forced into the generated C and runtime C units only, for host verification.
#include <stdlib.h>
#ifdef __cplusplus
extern "C" {
#endif
void *moonohos_count_malloc(size_t size);
void moonohos_count_free(void *pointer);
size_t moonohos_live_allocations(void);
#ifdef __cplusplus
}
#endif
#define malloc moonohos_count_malloc
#define free moonohos_count_free
