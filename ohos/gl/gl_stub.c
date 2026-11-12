// MoonOHOS gl: an XComponent surface (by surface id) rendered with EGL and
// OpenGL ES 3. Plain GL calls come from the generated sys/gles package;
// this file owns the EGL objects and the GL calls that take pointers. On
// the host (no MOONOHOS_TARGET_OHOS) opening fails with 801.
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include "moonbit.h"

#ifdef MOONOHOS_TARGET_OHOS
#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <native_window/external_window.h>
#endif

#define MOONOHOS_GL_UNSUPPORTED 801

typedef struct {
  void *window;   // OHNativeWindow *
  void *display;  // EGLDisplay
  void *context;  // EGLContext
  void *surface;  // EGLSurface
  int64_t frames;
} moonohos_gl;

#ifdef MOONOHOS_TARGET_OHOS
static void moonohos_ohos_gl_release(moonohos_gl *gl) {
  EGLDisplay display = (EGLDisplay)gl->display;
  if (display != NULL && display != EGL_NO_DISPLAY) {
    eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    if (gl->context) eglDestroyContext(display, (EGLContext)gl->context);
    if (gl->surface) eglDestroySurface(display, (EGLSurface)gl->surface);
  }
  // The display stays initialized: other surfaces of the process share it.
  if (gl->window) OH_NativeWindow_DestroyNativeWindow((OHNativeWindow *)gl->window);
  gl->window = NULL;
  gl->display = NULL;
  gl->context = NULL;
  gl->surface = NULL;
}
#endif

static void moonohos_ohos_gl_finalize(void *self) {
#ifdef MOONOHOS_TARGET_OHOS
  moonohos_ohos_gl_release((moonohos_gl *)self);
#else
  (void)self;
#endif
}

static moonohos_gl *moonohos_ohos_gl_make(void) {
  moonohos_gl *gl = (moonohos_gl *)moonbit_make_external_object(moonohos_ohos_gl_finalize, sizeof(moonohos_gl));
  memset(gl, 0, sizeof(moonohos_gl));
  return gl;
}

// Always returns a handle; on failure it is closed and code[0] holds the
// NativeWindow error, the EGL error (0x3001..0x300E), -1, or 801 (host).
void *moonohos_ohos_gl_open(uint64_t surface_id, int32_t *code) {
  moonohos_gl *gl = moonohos_ohos_gl_make();
#ifdef MOONOHOS_TARGET_OHOS
  OHNativeWindow *window = NULL;
  int32_t r = OH_NativeWindow_CreateNativeWindowFromSurfaceId(surface_id, &window);
  if (r != 0 || window == NULL) {
    code[0] = r != 0 ? r : -1;
    return gl;
  }
  gl->window = window;
  EGLDisplay display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
  EGLint major = 0;
  EGLint minor = 0;
  if (display == EGL_NO_DISPLAY || !eglInitialize(display, &major, &minor) || !eglBindAPI(EGL_OPENGL_ES_API)) {
    code[0] = (int32_t)eglGetError();
    moonohos_ohos_gl_release(gl);
    return gl;
  }
  gl->display = display;
  const EGLint config_attributes[] = {
      EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
      EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
      EGL_NONE};
  EGLConfig config = NULL;
  EGLint count = 0;
  if (!eglChooseConfig(display, config_attributes, &config, 1, &count) || count < 1) {
    code[0] = count < 1 ? -1 : (int32_t)eglGetError();
    moonohos_ohos_gl_release(gl);
    return gl;
  }
  EGLSurface surface = eglCreateWindowSurface(display, config, (EGLNativeWindowType)window, NULL);
  if (surface == EGL_NO_SURFACE) {
    code[0] = (int32_t)eglGetError();
    moonohos_ohos_gl_release(gl);
    return gl;
  }
  gl->surface = surface;
  const EGLint context_attributes[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
  EGLContext context = eglCreateContext(display, config, EGL_NO_CONTEXT, context_attributes);
  if (context == EGL_NO_CONTEXT) {
    code[0] = (int32_t)eglGetError();
    moonohos_ohos_gl_release(gl);
    return gl;
  }
  gl->context = context;
  code[0] = 0;
  return gl;
#else
  (void)surface_id;
  code[0] = MOONOHOS_GL_UNSUPPORTED;
  return gl;
#endif
}

int32_t moonohos_ohos_gl_live(void *self) {
  return ((moonohos_gl *)self)->context != NULL;
}

int64_t moonohos_ohos_gl_frames(void *self) {
  return ((moonohos_gl *)self)->frames;
}

void moonohos_ohos_gl_close(void *self) {
  moonohos_ohos_gl_finalize(self);
}

typedef void (*moonohos_gl_tramp)(void *closure, int32_t width, int32_t height);

// Makes the context current on the calling thread, sets the viewport to the
// surface size, runs `render(width, height)`, swaps and releases the
// context again, so the next frame may run on another thread. `render` is
// borrowed from MoonBit. info[0..1] receive the surface size.
int32_t moonohos_ohos_gl_frame(void *self, void *tramp, void *render, int32_t *info) {
  info[0] = 0;
  info[1] = 0;
#ifdef MOONOHOS_TARGET_OHOS
  moonohos_gl *gl = (moonohos_gl *)self;
  EGLDisplay display = (EGLDisplay)gl->display;
  EGLSurface surface = (EGLSurface)gl->surface;
  if (!eglMakeCurrent(display, surface, surface, (EGLContext)gl->context)) return (int32_t)eglGetError();
  EGLint width = 0;
  EGLint height = 0;
  eglQuerySurface(display, surface, EGL_WIDTH, &width);
  eglQuerySurface(display, surface, EGL_HEIGHT, &height);
  info[0] = width;
  info[1] = height;
  glViewport(0, 0, width, height);
  // The trampoline consumes one reference to the closure.
  moonbit_incref(render);
  ((moonohos_gl_tramp)tramp)(render, width, height);
  int32_t r = eglSwapBuffers(display, surface) ? 0 : (int32_t)eglGetError();
  eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
  if (r == 0) gl->frames++;
  return r;
#else
  (void)self;
  (void)tramp;
  (void)render;
  return MOONOHOS_GL_UNSUPPORTED;
#endif
}

// ------------------------------------------------- GL calls with pointers
// Valid only inside `frame` (a context must be current). On the host they
// do nothing and return zeros.

// `source` is NUL-terminated UTF-8.
void moonohos_ohos_gl_shader_source(uint32_t shader, uint8_t *source) {
#ifdef MOONOHOS_TARGET_OHOS
  const GLchar *text = (const GLchar *)source;
  glShaderSource(shader, 1, &text, NULL);
#else
  (void)shader;
  (void)source;
#endif
}

// Copies at most `capacity - 1` bytes of the info log, NUL-terminated.
void moonohos_ohos_gl_info_log(int32_t program, uint32_t object, uint8_t *buffer, int32_t capacity) {
  buffer[0] = 0;
#ifdef MOONOHOS_TARGET_OHOS
  GLsizei length = 0;
  if (program) {
    glGetProgramInfoLog(object, capacity, &length, (GLchar *)buffer);
  } else {
    glGetShaderInfoLog(object, capacity, &length, (GLchar *)buffer);
  }
  if (length >= 0 && length < capacity) buffer[length] = 0;
#else
  (void)program;
  (void)object;
  (void)capacity;
#endif
}

// kind: 0 buffer, 1 vertex array, 2 texture, 3 framebuffer.
uint32_t moonohos_ohos_gl_gen(int32_t kind) {
#ifdef MOONOHOS_TARGET_OHOS
  GLuint id = 0;
  switch (kind) {
    case 0: glGenBuffers(1, &id); break;
    case 1: glGenVertexArrays(1, &id); break;
    case 2: glGenTextures(1, &id); break;
    case 3: glGenFramebuffers(1, &id); break;
    default: break;
  }
  return id;
#else
  (void)kind;
  return 0;
#endif
}

void moonohos_ohos_gl_delete(int32_t kind, uint32_t id) {
#ifdef MOONOHOS_TARGET_OHOS
  GLuint name = id;
  switch (kind) {
    case 0: glDeleteBuffers(1, &name); break;
    case 1: glDeleteVertexArrays(1, &name); break;
    case 2: glDeleteTextures(1, &name); break;
    case 3: glDeleteFramebuffers(1, &name); break;
    default: break;
  }
#else
  (void)kind;
  (void)id;
#endif
}

void moonohos_ohos_gl_buffer_floats(uint32_t target, float *data, int32_t count, uint32_t usage) {
#ifdef MOONOHOS_TARGET_OHOS
  glBufferData(target, (GLsizeiptr)count * (GLsizeiptr)sizeof(float), data, usage);
#else
  (void)target;
  (void)data;
  (void)count;
  (void)usage;
#endif
}

// Attribute data from the bound GL_ARRAY_BUFFER at byte `offset`.
void moonohos_ohos_gl_vertex_attrib_pointer(uint32_t index, int32_t size, uint32_t type, int32_t normalized,
                                            int32_t stride, int32_t offset) {
#ifdef MOONOHOS_TARGET_OHOS
  glVertexAttribPointer(index, size, type, normalized ? GL_TRUE : GL_FALSE, stride,
                        (const void *)(intptr_t)offset);
#else
  (void)index;
  (void)size;
  (void)type;
  (void)normalized;
  (void)stride;
  (void)offset;
#endif
}

// `values` holds `count` matrices of `size` x `size` floats (size 2..4).
void moonohos_ohos_gl_uniform_matrix(int32_t location, int32_t size, int32_t count, float *values) {
#ifdef MOONOHOS_TARGET_OHOS
  switch (size) {
    case 2: glUniformMatrix2fv(location, count, GL_FALSE, values); break;
    case 3: glUniformMatrix3fv(location, count, GL_FALSE, values); break;
    case 4: glUniformMatrix4fv(location, count, GL_FALSE, values); break;
    default: break;
  }
#else
  (void)location;
  (void)size;
  (void)count;
  (void)values;
#endif
}

// Reads `width` x `height` RGBA 8888 pixels at (x, y) of the current read
// buffer (origin bottom-left) into `pixels`.
void moonohos_ohos_gl_read_pixels(int32_t x, int32_t y, int32_t width, int32_t height, uint32_t *pixels) {
#ifdef MOONOHOS_TARGET_OHOS
  glReadPixels(x, y, width, height, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
#else
  for (int32_t i = 0; i < width * height; i++) pixels[i] = 0;
  (void)x;
  (void)y;
#endif
}

// Up to `capacity` values of glGetIntegerv(pname); the caller sizes the
// array for the pname (e.g. 4 for GL_VIEWPORT).
void moonohos_ohos_gl_get_integers(uint32_t pname, int32_t *values, int32_t capacity) {
  int32_t scratch[64] = {0};
#ifdef MOONOHOS_TARGET_OHOS
  // GL writes as many values as the pname has; 64 covers every ES 3.0
  // pname except the format lists, whose length is device-specific.
  if (pname != GL_COMPRESSED_TEXTURE_FORMATS && pname != GL_PROGRAM_BINARY_FORMATS &&
      pname != GL_SHADER_BINARY_FORMATS) {
    glGetIntegerv(pname, (GLint *)scratch);
  }
#else
  (void)pname;
#endif
  int32_t n = capacity < 64 ? capacity : 64;
  memcpy(values, scratch, (size_t)n * sizeof(int32_t));
}
