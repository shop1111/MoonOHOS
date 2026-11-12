///|
/// An XComponent surface rendered with OpenGL ES 3 through EGL. GL calls
/// (`@gles.*` and the helpers below) are valid only inside `frame`, which
/// makes the context current on the calling thread and releases it again.
pub type GlSurface

///|
#borrow(code)
extern "C" fn gl_open_raw(id : UInt64, code : FixedArray[Int32]) -> GlSurface = "moonohos_ohos_gl_open"

///|
#borrow(gl)
extern "C" fn gl_live_raw(gl : GlSurface) -> Int32 = "moonohos_ohos_gl_live"

///|
#borrow(gl)
extern "C" fn gl_frames_raw(gl : GlSurface) -> Int64 = "moonohos_ohos_gl_frames"

///|
#borrow(gl)
extern "C" fn gl_close_raw(gl : GlSurface) = "moonohos_ohos_gl_close"

///|
#borrow(gl, render, info)
extern "C" fn gl_frame_raw(
  gl : GlSurface,
  tramp : FuncRef[((Int32, Int32) -> Unit, Int32, Int32) -> Unit],
  render : (Int32, Int32) -> Unit,
  info : FixedArray[Int32],
) -> Int32 = "moonohos_ohos_gl_frame"

///|
/// Opens the surface with the given id (from `onSurfaceCreated`) and creates
/// an OpenGL ES 3 context for it (RGBA 8888). Buffers follow the
/// XComponent's size.
pub fn GlSurface::open(
  surface_id : String,
) -> GlSurface raise @surface.SurfaceError {
  let id = @surface.parse_surface_id(surface_id)
  let code : FixedArray[Int32] = [0]
  let gl = gl_open_raw(id, code)
  if code[0] != 0 {
    raise Failed("EGL setup", code[0])
  }
  gl
}

///|
pub fn GlSurface::is_open(self : GlSurface) -> Bool {
  gl_live_raw(self) != 0
}

///|
/// Frames swapped so far.
pub fn GlSurface::frames(self : GlSurface) -> Int64 {
  gl_frames_raw(self)
}

///|
/// Destroys the context, the EGL surface and the window. Closing twice is
/// fine; later frames raise `Closed`.
pub fn GlSurface::close(self : GlSurface) -> Unit {
  gl_close_raw(self)
}

///|
/// Renders one frame: makes the context current, sets the viewport to the
/// surface size, runs `render(width, height)`, swaps buffers and releases
/// the context. Returns the surface size. An error raised by `render` is
/// re-raised after the swap.
pub fn GlSurface::frame(
  self : GlSurface,
  render : (Int32, Int32) -> Unit raise,
) -> (Int32, Int32) raise {
  if !self.is_open() {
    raise @surface.SurfaceError::Closed("frame")
  }
  let failures : Array[Error] = []
  let info : FixedArray[Int32] = [0, 0]
  let code = gl_frame_raw(
    self,
    fn(f, w, h) { f(w, h) },
    (w, h) => render(w, h) catch { error => failures.push(error) },
    info,
  )
  if code != 0 {
    raise @surface.SurfaceError::Failed("eglSwapBuffers", code)
  }
  if failures.length() > 0 {
    raise failures[0]
  }
  (info[0], info[1])
}

///|
#borrow(source)
extern "C" fn shader_source_raw(shader : UInt32, source : Bytes) = "moonohos_ohos_gl_shader_source"

///|
#borrow(buffer)
extern "C" fn info_log_raw(
  program : Int32,
  object : UInt32,
  buffer : FixedArray[Byte],
  capacity : Int32,
) = "moonohos_ohos_gl_info_log"

///|
extern "C" fn gen_raw(kind : Int32) -> UInt32 = "moonohos_ohos_gl_gen"

///|
extern "C" fn delete_raw(kind : Int32, id : UInt32) = "moonohos_ohos_gl_delete"

///|
#borrow(data)
extern "C" fn buffer_floats_raw(
  target : UInt32,
  data : FixedArray[Float],
  count : Int32,
  usage : UInt32,
) = "moonohos_ohos_gl_buffer_floats"

///|
extern "C" fn vertex_attrib_pointer_raw(
  index : UInt32,
  size : Int32,
  type_ : UInt32,
  normalized : Int32,
  stride : Int32,
  offset : Int32,
) = "moonohos_ohos_gl_vertex_attrib_pointer"

///|
#borrow(values)
extern "C" fn uniform_matrix_raw(
  location : Int32,
  size : Int32,
  count : Int32,
  values : FixedArray[Float],
) = "moonohos_ohos_gl_uniform_matrix"

///|
#borrow(pixels)
extern "C" fn read_pixels_raw(
  x : Int32,
  y : Int32,
  width : Int32,
  height : Int32,
  pixels : FixedArray[UInt32],
) = "moonohos_ohos_gl_read_pixels"

///|
#borrow(values)
extern "C" fn get_integers_raw(
  pname : UInt32,
  values : FixedArray[Int32],
  capacity : Int32,
) = "moonohos_ohos_gl_get_integers"

///|
/// `glShaderSource` with one source string.
pub fn shader_source(shader : UInt32, source : String) -> Unit {
  shader_source_raw(shader, @utf8.encode(source + "\u{0}"))
}

///|
fn info_log(program : Int32, object : UInt32) -> String {
  let buffer : FixedArray[Byte] = FixedArray::make(1024, 0)
  info_log_raw(program, object, buffer, buffer.length())
  let mut end = 0
  while end < buffer.length() && buffer[end] != 0 {
    end += 1
  }
  @utf8.decode_lossy(Bytes::from_array(buffer[:end]))
}

///|
/// `glGetShaderInfoLog` (first 1023 bytes).
pub fn shader_info_log(shader : UInt32) -> String {
  info_log(0, shader)
}

///|
/// `glGetProgramInfoLog` (first 1023 bytes).
pub fn program_info_log(program : UInt32) -> String {
  info_log(1, program)
}

///|
/// Compiles a shader of `kind` (`VERTEX_SHADER` or `FRAGMENT_SHADER`);
/// raises `Failure` with the info log when compilation fails.
pub fn compile_shader(kind : UInt32, source : String) -> UInt32 raise {
  let shader = @gles.create_shader(kind)
  shader_source(shader, source)
  @gles.compile_shader(shader)
  if @gles.get_shaderiv(shader, COMPILE_STATUS) == 0 {
    let log = shader_info_log(shader)
    @gles.delete_shader(shader)
    fail("shader compilation failed: " + log)
  }
  shader
}

///|
/// Compiles and links a program from vertex and fragment shader sources.
pub fn link_program(vertex : String, fragment : String) -> UInt32 raise {
  let vs = compile_shader(VERTEX_SHADER, vertex)
  let fs = compile_shader(FRAGMENT_SHADER, fragment)
  let program = @gles.create_program()
  @gles.attach_shader(program, vs)
  @gles.attach_shader(program, fs)
  @gles.link_program(program)
  @gles.delete_shader(vs)
  @gles.delete_shader(fs)
  if @gles.get_programiv(program, LINK_STATUS) == 0 {
    let log = program_info_log(program)
    @gles.delete_program(program)
    fail("program link failed: " + log)
  }
  program
}

///|
/// `glGenBuffers` for one buffer.
pub fn gen_buffer() -> UInt32 {
  gen_raw(0)
}

///|
/// `glGenVertexArrays` for one vertex array.
pub fn gen_vertex_array() -> UInt32 {
  gen_raw(1)
}

///|
/// `glGenTextures` for one texture.
pub fn gen_texture() -> UInt32 {
  gen_raw(2)
}

///|
/// `glGenFramebuffers` for one framebuffer.
pub fn gen_framebuffer() -> UInt32 {
  gen_raw(3)
}

///|
pub fn delete_buffer(id : UInt32) -> Unit {
  delete_raw(0, id)
}

///|
pub fn delete_vertex_array(id : UInt32) -> Unit {
  delete_raw(1, id)
}

///|
pub fn delete_texture(id : UInt32) -> Unit {
  delete_raw(2, id)
}

///|
pub fn delete_framebuffer(id : UInt32) -> Unit {
  delete_raw(3, id)
}

///|
/// `glBufferData` with float data.
pub fn buffer_data_floats(
  target : UInt32,
  data : FixedArray[Float],
  usage : UInt32,
) -> Unit {
  buffer_floats_raw(target, data, data.length(), usage)
}

///|
/// `glVertexAttribPointer` reading the bound `ARRAY_BUFFER` at byte
/// `offset` (client-side arrays are not supported).
pub fn vertex_attrib_pointer(
  index : UInt32,
  size : Int32,
  type_ : UInt32,
  normalized : Bool,
  stride : Int32,
  offset : Int32,
) -> Unit {
  vertex_attrib_pointer_raw(
    index,
    size,
    type_,
    if normalized {
      1
    } else {
      0
    },
    stride,
    offset,
  )
}

///|
/// `glUniformMatrix{2,3,4}fv` (column-major, not transposed) for
/// `values.length() / (size * size)` matrices.
pub fn uniform_matrix(
  location : Int32,
  size : Int32,
  values : FixedArray[Float],
) -> Unit {
  guard size >= 2 && size <= 4 && values.length() % (size * size) == 0 else {
    abort("uniform_matrix: size must be 2..4 and values a multiple of size^2")
  }
  uniform_matrix_raw(location, size, values.length() / (size * size), values)
}

///|
/// `glReadPixels` as RGBA 8888 (bytes r, g, b, a; origin bottom-left).
pub fn read_pixels(
  x : Int32,
  y : Int32,
  width : Int32,
  height : Int32,
) -> FixedArray[UInt32] {
  let w = if width < 0 { 0 } else { width }
  let h = if height < 0 { 0 } else { height }
  let pixels : FixedArray[UInt32] = FixedArray::make(w * h, 0)
  if w * h > 0 {
    read_pixels_raw(x, y, w, h, pixels)
  }
  pixels
}

///|
/// The first `count` values of `glGetIntegerv(pname)` (at most 64; the
/// compressed/binary format lists are not read).
pub fn get_integers(pname : UInt32, count : Int32) -> FixedArray[Int32] {
  let n = if count < 0 { 0 } else if count > 64 { 64 } else { count }
  let values : FixedArray[Int32] = FixedArray::make(n, 0)
  get_integers_raw(pname, values, n)
  values
}
