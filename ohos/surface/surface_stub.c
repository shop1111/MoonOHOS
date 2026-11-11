// MoonOHOS surface: an XComponent surface (by surface id) as a CPU-drawn
// NativeWindow, plus VSync frame callbacks. On the host (no
// MOONOHOS_TARGET_OHOS) opening fails with 801 and the pixel copy is
// still available for tests.
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "moonbit.h"

#ifdef MOONOHOS_TARGET_OHOS
#include <errno.h>
#include <poll.h>
#include <sys/mman.h>
#include <unistd.h>
#include <native_buffer/buffer_common.h>
#include <native_buffer/native_buffer.h>
#include <native_vsync/native_vsync.h>
#include <native_window/external_window.h>
#endif

#define MOONOHOS_SURFACE_UNSUPPORTED 801
// Errors of this file (not SDK codes): no mapping, fence timeout.
#define MOONOHOS_SURFACE_MMAP_FAILED -2
#define MOONOHOS_SURFACE_FENCE_TIMEOUT -3

// Copies a `width` x `height` block of 32-bit pixels into a destination
// whose rows are `dst_stride` pixels apart, clipped to `dst_width` x
// `dst_height`. Shared by `present` and the host tests.
static void moonohos_ohos_surface_blit(uint32_t *dst, int32_t dst_stride, int32_t dst_width,
                                  int32_t dst_height, const uint32_t *src, int32_t width,
                                  int32_t height) {
  int32_t w = width < dst_width ? width : dst_width;
  int32_t h = height < dst_height ? height : dst_height;
  if (w <= 0 || h <= 0) return;
  for (int32_t y = 0; y < h; y++) {
    memcpy(dst + (size_t)y * (size_t)dst_stride, src + (size_t)y * (size_t)width,
           (size_t)w * sizeof(uint32_t));
  }
}

void moonohos_ohos_surface_blit_test(uint32_t *dst, int32_t dst_stride, int32_t dst_width,
                                int32_t dst_height, uint32_t *src, int32_t width, int32_t height) {
  moonohos_ohos_surface_blit(dst, dst_stride, dst_width, dst_height, src, width, height);
}

// ---------------------------------------------------------------- handles
// Both handles are MoonBit external objects; the finalizer releases the SDK
// object if MoonBit did not close it explicitly.

typedef struct {
  void *window;  // OHNativeWindow *
  int32_t width;
  int32_t height;
  int64_t frames;
} moonohos_surface;

static void moonohos_ohos_surface_finalize(void *self) {
  moonohos_surface *surface = (moonohos_surface *)self;
  void *window = surface->window;
  surface->window = NULL;
#ifdef MOONOHOS_TARGET_OHOS
  if (window) OH_NativeWindow_DestroyNativeWindow((OHNativeWindow *)window);
#else
  (void)window;
#endif
}

static moonohos_surface *moonohos_ohos_surface_make(void *window, int32_t width, int32_t height) {
  moonohos_surface *surface =
      (moonohos_surface *)moonbit_make_external_object(moonohos_ohos_surface_finalize, sizeof(moonohos_surface));
  surface->window = window;
  surface->width = width;
  surface->height = height;
  surface->frames = 0;
  return surface;
}

// Always returns a handle; on failure it is closed and code[0] holds the
// error (SDK code, or 801 on the host).
void *moonohos_ohos_surface_open(uint64_t surface_id, int32_t width, int32_t height, int32_t *code) {
  code[0] = 0;
#ifdef MOONOHOS_TARGET_OHOS
  OHNativeWindow *window = NULL;
  int32_t r = OH_NativeWindow_CreateNativeWindowFromSurfaceId(surface_id, &window);
  if (r == 0 && window == NULL) r = -1;
  if (r == 0) {
    uint64_t usage = NATIVEBUFFER_USAGE_CPU_READ | NATIVEBUFFER_USAGE_CPU_WRITE | NATIVEBUFFER_USAGE_MEM_DMA;
    r = OH_NativeWindow_NativeWindowHandleOpt(window, SET_USAGE, usage);
    if (r == 0) r = OH_NativeWindow_NativeWindowHandleOpt(window, SET_FORMAT, (int32_t)NATIVEBUFFER_PIXEL_FMT_RGBA_8888);
    if (r == 0 && width > 0 && height > 0) {
      r = OH_NativeWindow_NativeWindowHandleOpt(window, SET_BUFFER_GEOMETRY, width, height);
    }
    if (r != 0) {
      OH_NativeWindow_DestroyNativeWindow(window);
      window = NULL;
    }
  }
  code[0] = r;
  return moonohos_ohos_surface_make(window, width, height);
#else
  (void)surface_id;
  code[0] = MOONOHOS_SURFACE_UNSUPPORTED;
  return moonohos_ohos_surface_make(NULL, width, height);
#endif
}

int32_t moonohos_ohos_surface_live(void *self) {
  return ((moonohos_surface *)self)->window != NULL;
}

int64_t moonohos_ohos_surface_frames(void *self) {
  return ((moonohos_surface *)self)->frames;
}

void moonohos_ohos_surface_close(void *self) {
  moonohos_ohos_surface_finalize(self);
}

int32_t moonohos_ohos_surface_resize(void *self, int32_t width, int32_t height) {
  moonohos_surface *surface = (moonohos_surface *)self;
#ifdef MOONOHOS_TARGET_OHOS
  int32_t r = OH_NativeWindow_NativeWindowHandleOpt((OHNativeWindow *)surface->window, SET_BUFFER_GEOMETRY,
                                                   width, height);
  if (r == 0) {
    surface->width = width;
    surface->height = height;
  }
  return r;
#else
  (void)surface;
  (void)width;
  (void)height;
  return MOONOHOS_SURFACE_UNSUPPORTED;
#endif
}

// size[0] = width, size[1] = height of the buffers the window hands out.
int32_t moonohos_ohos_surface_size(void *self, int32_t *size) {
  moonohos_surface *surface = (moonohos_surface *)self;
#ifdef MOONOHOS_TARGET_OHOS
  int32_t height = 0;
  int32_t width = 0;
  // GET_BUFFER_GEOMETRY writes height first, then width.
  int32_t r = OH_NativeWindow_NativeWindowHandleOpt((OHNativeWindow *)surface->window, GET_BUFFER_GEOMETRY,
                                                   &height, &width);
  size[0] = width;
  size[1] = height;
  return r;
#else
  (void)surface;
  size[0] = 0;
  size[1] = 0;
  return MOONOHOS_SURFACE_UNSUPPORTED;
#endif
}

// Requests a buffer, waits for its release fence, copies the pixels (RGBA
// 8888, rows of `width`) and queues it for composition. info[0..2] receive
// the buffer's width, height and stride in pixels.
int32_t moonohos_ohos_surface_present(void *self, uint32_t *pixels, int32_t width, int32_t height,
                                 int32_t *info) {
  moonohos_surface *surface = (moonohos_surface *)self;
  info[0] = 0;
  info[1] = 0;
  info[2] = 0;
#ifdef MOONOHOS_TARGET_OHOS
  OHNativeWindow *window = (OHNativeWindow *)surface->window;
  // ArkUI resets the geometry to the component's size when the surface
  // changes (e.g. on rotation), so a requested size is applied every frame.
  if (surface->width > 0 && surface->height > 0) {
    int32_t height = 0;
    int32_t width = 0;
    int32_t g = OH_NativeWindow_NativeWindowHandleOpt(window, GET_BUFFER_GEOMETRY, &height, &width);
    if (g == 0 && (width != surface->width || height != surface->height)) {
      g = OH_NativeWindow_NativeWindowHandleOpt(window, SET_BUFFER_GEOMETRY, surface->width, surface->height);
    }
    if (g != 0) return g;
  }
  OHNativeWindowBuffer *buffer = NULL;
  int fence = -1;
  int32_t r = OH_NativeWindow_NativeWindowRequestBuffer(window, &buffer, &fence);
  if (r != 0 || buffer == NULL) return r != 0 ? r : -1;
  if (fence >= 0) {
    struct pollfd pfd = {0};
    pfd.fd = fence;
    pfd.events = POLLIN;
    int ready;
    do {
      ready = poll(&pfd, 1, 3000);
    } while (ready == -1 && (errno == EINTR || errno == EAGAIN));
    close(fence);
    if (ready <= 0) {
      OH_NativeWindow_NativeWindowAbortBuffer(window, buffer);
      return MOONOHOS_SURFACE_FENCE_TIMEOUT;
    }
  }
  BufferHandle *handle = OH_NativeWindow_GetBufferHandleFromNative(buffer);
  if (handle == NULL) {
    OH_NativeWindow_NativeWindowAbortBuffer(window, buffer);
    return -1;
  }
  void *mapped = mmap(handle->virAddr, (size_t)handle->size, PROT_READ | PROT_WRITE, MAP_SHARED, handle->fd, 0);
  if (mapped == MAP_FAILED) {
    OH_NativeWindow_NativeWindowAbortBuffer(window, buffer);
    return MOONOHOS_SURFACE_MMAP_FAILED;
  }
  int32_t stride = handle->stride / 4;
  moonohos_ohos_surface_blit((uint32_t *)mapped, stride, handle->width, handle->height, pixels, width, height);
  munmap(mapped, (size_t)handle->size);
  info[0] = handle->width;
  info[1] = handle->height;
  info[2] = stride;
  Region region = {NULL, 0};
  r = OH_NativeWindow_NativeWindowFlushBuffer(window, buffer, -1, region);
  if (r == 0) surface->frames++;
  return r;
#else
  (void)surface;
  (void)pixels;
  (void)width;
  (void)height;
  return MOONOHOS_SURFACE_UNSUPPORTED;
#endif
}

// ------------------------------------------------------------------ vsync

typedef struct {
  void *vsync;  // OH_NativeVSync *
  int64_t requested;
} moonohos_vsync;

// Frames delivered to MoonBit callbacks, all VSync handles together. A
// request does not keep its handle alive: destroying the SDK object from
// inside its own callback (last reference dropped there) is avoided.
static int64_t moonohos_ohos_vsync_delivered_total = 0;

static void moonohos_ohos_vsync_finalize(void *self) {
  moonohos_vsync *vsync = (moonohos_vsync *)self;
  void *native = vsync->vsync;
  vsync->vsync = NULL;
#ifdef MOONOHOS_TARGET_OHOS
  if (native) OH_NativeVSync_Destroy((OH_NativeVSync *)native);
#else
  (void)native;
#endif
}

static moonohos_vsync *moonohos_ohos_vsync_make(void *native) {
  moonohos_vsync *vsync =
      (moonohos_vsync *)moonbit_make_external_object(moonohos_ohos_vsync_finalize, sizeof(moonohos_vsync));
  vsync->vsync = native;
  vsync->requested = 0;
  return vsync;
}

// `name` is NUL-terminated UTF-8 of `length` bytes. Always returns a handle;
// code[0] is non-zero when it is closed.
void *moonohos_ohos_vsync_open(uint8_t *name, int32_t length, int32_t *code) {
#ifdef MOONOHOS_TARGET_OHOS
  OH_NativeVSync *native = OH_NativeVSync_Create((const char *)name, (unsigned int)length);
  code[0] = native == NULL ? -1 : 0;
  return moonohos_ohos_vsync_make(native);
#else
  (void)name;
  (void)length;
  code[0] = MOONOHOS_SURFACE_UNSUPPORTED;
  return moonohos_ohos_vsync_make(NULL);
#endif
}

int32_t moonohos_ohos_vsync_live(void *self) {
  return ((moonohos_vsync *)self)->vsync != NULL;
}

void moonohos_ohos_vsync_close(void *self) {
  moonohos_ohos_vsync_finalize(self);
}

int64_t moonohos_ohos_vsync_requested(void *self) {
  return ((moonohos_vsync *)self)->requested;
}

int64_t moonohos_ohos_vsync_delivered(void) {
  return moonohos_ohos_vsync_delivered_total;
}

int32_t moonohos_ohos_vsync_period(void *self, int64_t *out) {
  out[0] = 0;
#ifdef MOONOHOS_TARGET_OHOS
  long long period = 0;
  int32_t r = OH_NativeVSync_GetPeriod((OH_NativeVSync *)((moonohos_vsync *)self)->vsync, &period);
  out[0] = (int64_t)period;
  return r;
#else
  (void)self;
  return MOONOHOS_SURFACE_UNSUPPORTED;
#endif
}

#ifdef MOONOHOS_TARGET_OHOS
// Exported by the MoonOHOS bridge: the VSync thread enters the MoonBit gate
// before running MoonBit code.
extern void moonohos_gate_enter(void) __attribute__((weak));
extern void moonohos_gate_leave(void) __attribute__((weak));

typedef void (*moonohos_frame_tramp)(void *closure, int64_t timestamp);

// One pending request; it holds one reference to the closure.
typedef struct {
  moonohos_frame_tramp tramp;
  void *closure;
} moonohos_frame_request;

static void moonohos_ohos_vsync_fire(long long timestamp, void *data) {
  moonohos_frame_request *request = (moonohos_frame_request *)data;
  if (moonohos_gate_enter) moonohos_gate_enter();
  moonohos_ohos_vsync_delivered_total++;
  // The trampoline consumes the closure reference held by the request.
  request->tramp(request->closure, (int64_t)timestamp);
  if (moonohos_gate_leave) moonohos_gate_leave();
  free(request);
}
#endif

// One-shot: `callback(timestamp_ns)` runs on the VSync thread at the next
// frame. Called with `callback` borrowed; the request keeps its own reference.
int32_t moonohos_ohos_vsync_request(void *self, void *tramp, void *callback) {
#ifdef MOONOHOS_TARGET_OHOS
  moonohos_vsync *vsync = (moonohos_vsync *)self;
  moonohos_frame_request *request = (moonohos_frame_request *)malloc(sizeof(moonohos_frame_request));
  if (request == NULL) return -1;
  request->tramp = (moonohos_frame_tramp)tramp;
  request->closure = callback;
  moonbit_incref(callback);
  int32_t r = OH_NativeVSync_RequestFrame((OH_NativeVSync *)vsync->vsync, moonohos_ohos_vsync_fire, request);
  if (r != 0) {
    moonbit_decref(callback);
    free(request);
    return r;
  }
  vsync->requested++;
  return 0;
#else
  (void)self;
  (void)tramp;
  (void)callback;
  return MOONOHOS_SURFACE_UNSUPPORTED;
#endif
}
