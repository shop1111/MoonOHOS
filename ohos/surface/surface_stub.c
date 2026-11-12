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
#include <native_drawing/drawing_bitmap.h>
#include <native_drawing/drawing_canvas.h>
#include <native_drawing/drawing_types.h>
#include <native_vsync/native_vsync.h>
#include <native_window/external_window.h>
#endif

#define MOONOHOS_SURFACE_UNSUPPORTED 801
// Errors of this file (not SDK codes): no mapping, fence timeout, no canvas.
#define MOONOHOS_SURFACE_MMAP_FAILED -2
#define MOONOHOS_SURFACE_FENCE_TIMEOUT -3
#define MOONOHOS_SURFACE_CANVAS_FAILED -4

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

#ifdef MOONOHOS_TARGET_OHOS
// A window buffer mapped for CPU access, between `acquire` and `submit`.
typedef struct {
  OHNativeWindowBuffer *buffer;
  BufferHandle *handle;
  void *mapped;
} moonohos_frame;

// Requests a buffer (re-applying a requested size first: ArkUI resets the
// geometry to the component's size when the surface changes, e.g. on
// rotation), waits for its release fence and maps it.
static int32_t moonohos_ohos_surface_acquire(moonohos_surface *surface, moonohos_frame *frame) {
  OHNativeWindow *window = (OHNativeWindow *)surface->window;
  if (surface->width > 0 && surface->height > 0) {
    int32_t height = 0;
    int32_t width = 0;
    int32_t g = OH_NativeWindow_NativeWindowHandleOpt(window, GET_BUFFER_GEOMETRY, &height, &width);
    if (g == 0 && (width != surface->width || height != surface->height)) {
      g = OH_NativeWindow_NativeWindowHandleOpt(window, SET_BUFFER_GEOMETRY, surface->width, surface->height);
    }
    if (g != 0) return g;
  }
  int fence = -1;
  frame->buffer = NULL;
  int32_t r = OH_NativeWindow_NativeWindowRequestBuffer(window, &frame->buffer, &fence);
  if (r != 0 || frame->buffer == NULL) return r != 0 ? r : -1;
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
      OH_NativeWindow_NativeWindowAbortBuffer(window, frame->buffer);
      return MOONOHOS_SURFACE_FENCE_TIMEOUT;
    }
  }
  frame->handle = OH_NativeWindow_GetBufferHandleFromNative(frame->buffer);
  if (frame->handle == NULL) {
    OH_NativeWindow_NativeWindowAbortBuffer(window, frame->buffer);
    return -1;
  }
  frame->mapped = mmap(frame->handle->virAddr, (size_t)frame->handle->size, PROT_READ | PROT_WRITE, MAP_SHARED,
                       frame->handle->fd, 0);
  if (frame->mapped == MAP_FAILED) {
    OH_NativeWindow_NativeWindowAbortBuffer(window, frame->buffer);
    return MOONOHOS_SURFACE_MMAP_FAILED;
  }
  return 0;
}

// Unmaps the buffer and queues it for composition; info[0..2] receive its
// width, height and stride in pixels.
static int32_t moonohos_ohos_surface_submit(moonohos_surface *surface, moonohos_frame *frame, int32_t *info) {
  info[0] = frame->handle->width;
  info[1] = frame->handle->height;
  info[2] = frame->handle->stride / 4;
  munmap(frame->mapped, (size_t)frame->handle->size);
  Region region = {NULL, 0};
  int32_t r = OH_NativeWindow_NativeWindowFlushBuffer((OHNativeWindow *)surface->window, frame->buffer, -1, region);
  if (r == 0) surface->frames++;
  return r;
}
#endif

// Copies the pixels (RGBA 8888, rows of `width`) into the next buffer and
// queues it. info[0..2] receive the buffer's width, height and stride.
int32_t moonohos_ohos_surface_present(void *self, uint32_t *pixels, int32_t width, int32_t height,
                                      int32_t *info) {
  moonohos_surface *surface = (moonohos_surface *)self;
  info[0] = 0;
  info[1] = 0;
  info[2] = 0;
#ifdef MOONOHOS_TARGET_OHOS
  moonohos_frame frame;
  int32_t r = moonohos_ohos_surface_acquire(surface, &frame);
  if (r != 0) return r;
  moonohos_ohos_surface_blit((uint32_t *)frame.mapped, frame.handle->stride / 4, frame.handle->width,
                             frame.handle->height, pixels, width, height);
  return moonohos_ohos_surface_submit(surface, &frame, info);
#else
  (void)surface;
  (void)pixels;
  (void)width;
  (void)height;
  return MOONOHOS_SURFACE_UNSUPPORTED;
#endif
}

// ------------------------------------------------------- native drawing
// `draw` hands MoonBit an `OH_Drawing_Canvas` of the generated sys/drawing
// package. Its handles are MoonBit external objects whose payload starts
// with the SDK pointer (`moonohos_sys_handle` in the generated stubs); this
// layout must stay in sync with bindgen_c.mbt. The canvas handle is
// invalidated when the callback returns, so it cannot escape the frame.
typedef struct {
  void *ptr;
  void (*destroy)(void *);
} moonohos_borrowed_handle;

static void moonohos_borrowed_finalize(void *self) {
  ((moonohos_borrowed_handle *)self)->ptr = NULL;
}

static moonohos_borrowed_handle *moonohos_borrow(void *ptr) {
  moonohos_borrowed_handle *handle =
      (moonohos_borrowed_handle *)moonbit_make_external_object(moonohos_borrowed_finalize, sizeof(moonohos_borrowed_handle));
  handle->ptr = ptr;
  handle->destroy = NULL;
  return handle;
}

// Host test: a live handle of the drawing layout around `tag`.
void *moonohos_ohos_surface_borrow_test(int32_t tag) {
  return moonohos_borrow((void *)(intptr_t)tag);
}

// Host test: invalidates a handle the way `draw` does after the callback.
void moonohos_ohos_surface_release_test(void *handle) {
  ((moonohos_borrowed_handle *)handle)->ptr = NULL;
}

typedef void (*moonohos_draw_tramp)(void *closure, void *canvas);

// Binds a Native Drawing canvas to the next buffer (RGBA 8888, premultiplied
// alpha, the buffer's own stride), runs `render(canvas)` and queues the
// buffer. `render` is borrowed from MoonBit.
int32_t moonohos_ohos_surface_draw(void *self, void *tramp, void *render, int32_t *info) {
  moonohos_surface *surface = (moonohos_surface *)self;
  info[0] = 0;
  info[1] = 0;
  info[2] = 0;
#ifdef MOONOHOS_TARGET_OHOS
  moonohos_frame frame;
  int32_t r = moonohos_ohos_surface_acquire(surface, &frame);
  if (r != 0) return r;
  OH_Drawing_Image_Info image = {frame.handle->width, frame.handle->height, COLOR_FORMAT_RGBA_8888,
                                 ALPHA_FORMAT_PREMUL};
  OH_Drawing_Bitmap *bitmap =
      OH_Drawing_BitmapCreateFromPixels(&image, frame.mapped, (uint32_t)frame.handle->stride);
  OH_Drawing_Canvas *canvas = OH_Drawing_CanvasCreate();
  if (bitmap == NULL || canvas == NULL) {
    if (canvas) OH_Drawing_CanvasDestroy(canvas);
    if (bitmap) OH_Drawing_BitmapDestroy(bitmap);
    munmap(frame.mapped, (size_t)frame.handle->size);
    OH_NativeWindow_NativeWindowAbortBuffer((OHNativeWindow *)surface->window, frame.buffer);
    return MOONOHOS_SURFACE_CANVAS_FAILED;
  }
  OH_Drawing_CanvasBind(canvas, bitmap);
  moonohos_borrowed_handle *handle = moonohos_borrow(canvas);
  // The trampoline consumes one reference to each argument.
  moonbit_incref(handle);
  moonbit_incref(render);
  ((moonohos_draw_tramp)tramp)(render, handle);
  handle->ptr = NULL;
  moonbit_decref(handle);
  OH_Drawing_CanvasDestroy(canvas);
  OH_Drawing_BitmapDestroy(bitmap);
  return moonohos_ohos_surface_submit(surface, &frame, info);
#else
  (void)surface;
  (void)tramp;
  (void)render;
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
