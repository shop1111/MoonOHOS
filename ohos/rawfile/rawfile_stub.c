// RawFile bridge. On HarmonyOS the manager is a NativeResourceManager obtained
// from an ArkTS resourceManager by the generated adapter and released after the
// call or task; on the host it is a directory used for tests.
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "moonbit.h"
#ifdef MOONOHOS_TARGET_OHOS
#include <rawfile/raw_file_manager.h>
#else
#include <stdio.h>
#ifdef _WIN32
#include <io.h>
#else
#include <dirent.h>
#endif
#endif

#define MOONOHOS_RAWFILE_LIMIT (64 * 1024 * 1024)

#ifndef MOONOHOS_TARGET_OHOS
typedef struct { char root[1024]; } moonohos_host_rawfile;

static int moonohos_host_path(void *manager, const char *path, char *out, size_t size) {
  if (!manager) return 0;
  int written = snprintf(out, size, "%s/%s", ((moonohos_host_rawfile *)manager)->root, path);
  return written > 0 && (size_t)written < size;
}

static void *moonohos_host_open(const char *root) {
  moonohos_host_rawfile *manager = (moonohos_host_rawfile *)malloc(sizeof(moonohos_host_rawfile));
  if (!manager) return NULL;
  if (strlen(root) >= sizeof(manager->root)) { free(manager); return NULL; }
  memset(manager, 0, sizeof(*manager));
  strcpy(manager->root, root);
  return manager;
}
#endif

// Returns the byte size, -1 when missing and -2 when above the 64 MiB limit.
int32_t moonohos_rawfile_size(void *manager, moonbit_bytes_t path) {
#ifdef MOONOHOS_TARGET_OHOS
  RawFile *file = manager ? OH_ResourceManager_OpenRawFile((const NativeResourceManager *)manager, (const char *)path) : NULL;
  if (!file) return -1;
  long size = OH_ResourceManager_GetRawFileSize(file);
  OH_ResourceManager_CloseRawFile(file);
#else
  char full[2048];
  if (!moonohos_host_path(manager, (const char *)path, full, sizeof(full))) return -1;
  FILE *file = fopen(full, "rb");
  if (!file) return -1;
  long size = fseek(file, 0, SEEK_END) == 0 ? ftell(file) : -1;
  fclose(file);
#endif
  if (size < 0) return -1;
  if (size > MOONOHOS_RAWFILE_LIMIT) return -2;
  return (int32_t)size;
}

// Reads up to `length` bytes into `buffer`; returns the count or -1.
int32_t moonohos_rawfile_read(void *manager, moonbit_bytes_t path, moonbit_bytes_t buffer, int32_t length) {
  int32_t total = 0;
#ifdef MOONOHOS_TARGET_OHOS
  RawFile *file = manager ? OH_ResourceManager_OpenRawFile((const NativeResourceManager *)manager, (const char *)path) : NULL;
  if (!file) return -1;
  while (total < length) {
    int read = OH_ResourceManager_ReadRawFile(file, buffer + total, (size_t)(length - total));
    if (read <= 0) break;
    total += read;
  }
  OH_ResourceManager_CloseRawFile(file);
#else
  char full[2048];
  if (!moonohos_host_path(manager, (const char *)path, full, sizeof(full))) return -1;
  FILE *file = fopen(full, "rb");
  if (!file) return -1;
  while (total < length) {
    size_t read = fread(buffer + total, 1, (size_t)(length - total), file);
    if (read == 0) break;
    total += (int32_t)read;
  }
  fclose(file);
#endif
  return total;
}

// Writes newline-separated entry names of `dir` into `buffer` when it is large
// enough and returns the total length needed, or -1 when the directory is missing.
int32_t moonohos_rawfile_list(void *manager, moonbit_bytes_t dir, moonbit_bytes_t buffer, int32_t capacity) {
  int64_t needed = 0;
#define MOONOHOS_APPEND(name)                                                    \
  do {                                                                           \
    size_t length = strlen(name);                                                \
    if (needed + (int64_t)length + 1 > MOONOHOS_RAWFILE_LIMIT) return -2;        \
    if (needed + (int64_t)length + 1 <= capacity) {                              \
      memcpy(buffer + needed, name, length);                                     \
      buffer[needed + (int64_t)length] = '\n';                                   \
    }                                                                            \
    needed += (int64_t)length + 1;                                               \
  } while (0)
#ifdef MOONOHOS_TARGET_OHOS
  RawDir *raw = manager ? OH_ResourceManager_OpenRawDir((const NativeResourceManager *)manager, (const char *)dir) : NULL;
  if (!raw) return -1;
  int count = OH_ResourceManager_GetRawFileCount(raw);
  for (int i = 0; i < count; ++i) {
    const char *name = OH_ResourceManager_GetRawFileName(raw, i);
    if (name) MOONOHOS_APPEND(name);
  }
  OH_ResourceManager_CloseRawDir(raw);
#else
  char full[2048];
  if (!moonohos_host_path(manager, (const char *)dir, full, sizeof(full))) return -1;
#ifdef _WIN32
  char pattern[2100];
  snprintf(pattern, sizeof(pattern), "%s/*", full);
  struct _finddata_t entry;
  intptr_t handle = _findfirst(pattern, &entry);
  if (handle == -1) return -1;
  do {
    if (strcmp(entry.name, ".") != 0 && strcmp(entry.name, "..") != 0) MOONOHOS_APPEND(entry.name);
  } while (_findnext(handle, &entry) == 0);
  _findclose(handle);
#else
  DIR *raw = opendir(full);
  if (!raw) return -1;
  struct dirent *entry;
  while ((entry = readdir(raw)) != NULL) {
    if (strcmp(entry->d_name, ".") != 0 && strcmp(entry->d_name, "..") != 0) MOONOHOS_APPEND(entry->d_name);
  }
  closedir(raw);
#endif
#endif
#undef MOONOHOS_APPEND
  return (int32_t)needed;
}

// Host-only manager rooted at a directory; NULL on HarmonyOS.
void *moonohos_rawfile_host(moonbit_bytes_t root) {
#ifdef MOONOHOS_TARGET_OHOS
  (void)root;
  return NULL;
#else
  return moonohos_host_open((const char *)root);
#endif
}

#ifdef MOONOHOS_BRIDGE
#ifndef MOONOHOS_TARGET_OHOS
// Host bridge tests supply ArkTS stand-ins: the value names a directory.
extern const char *moonohos_host_adapter_text(void *value);
#endif
// Adapter for @rawfile.Manager parameters, called on the JS thread.
void *moonohos_rawfile_acquire(void *env, void *value) {
#ifdef MOONOHOS_TARGET_OHOS
  return OH_ResourceManager_InitNativeResourceManager((napi_env)env, (napi_value)value);
#else
  (void)env;
  const char *root = moonohos_host_adapter_text(value);
  return root ? moonohos_host_open(root) : NULL;
#endif
}

void moonohos_rawfile_release(void *manager) {
#ifdef MOONOHOS_TARGET_OHOS
  OH_ResourceManager_ReleaseNativeResourceManager((NativeResourceManager *)manager);
#else
  free(manager);
#endif
}
#endif
