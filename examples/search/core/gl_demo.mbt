///|
/// OpenGL ES (0.9): a second XComponent rendered through EGL. A triangle
/// with per-vertex colors rotates once every 4 seconds; each frame reads
/// back the center pixel to show that GL, not just the clear color, drew it.
priv struct GlScene {
  gl : @gl.GlSurface
  vsync : @surface.VSync
  mut program : UInt
  mut vao : UInt
  mut vbo : UInt
  mut angle_location : Int
  mut aspect_location : Int
  mut running : Bool
  mut frames : Int
  mut size : String
  mut center : UInt
  mut error : String
}

///|
let gl_scenes : Array[GlScene] = []

///|
/// Background color (RGB bytes 16, 24, 64).
let gl_clear : (Float, Float, Float) = (0.0625, 0.09375, 0.25)

///|
let vertex_source =
  #|#version 300 es
  #|layout(location = 0) in vec2 a_pos;
  #|layout(location = 1) in vec3 a_color;
  #|uniform float u_angle;
  #|uniform float u_aspect;
  #|out vec3 v_color;
  #|void main() {
  #|  float c = cos(u_angle);
  #|  float s = sin(u_angle);
  #|  vec2 p = vec2(c * a_pos.x - s * a_pos.y, s * a_pos.x + c * a_pos.y);
  #|  gl_Position = vec4(p.x * u_aspect, p.y, 0.0, 1.0);
  #|  v_color = a_color;
  #|}

///|
let fragment_source =
  #|#version 300 es
  #|precision mediump float;
  #|in vec3 v_color;
  #|out vec4 o_color;
  #|void main() {
  #|  o_color = vec4(v_color, 1.0);
  #|}

///|
/// Program, vertex array and buffer, created in the first frame (a context
/// is current only inside `frame`).
fn GlScene::setup(self : GlScene) -> Unit raise {
  self.program = @gl.link_program(vertex_source, fragment_source)
  self.angle_location = @gles.get_uniform_location(self.program, "u_angle")
  self.aspect_location = @gles.get_uniform_location(self.program, "u_aspect")
  self.vao = @gl.gen_vertex_array()
  self.vbo = @gl.gen_buffer()
  @gles.bind_vertex_array(self.vao)
  @gles.bind_buffer(@gl.ARRAY_BUFFER, self.vbo)
  // x, y, r, g, b for each corner; the centroid is at the origin.
  @gl.buffer_data_floats(
    @gl.ARRAY_BUFFER,
    [0, 0.8, 1, 0, 0, -0.7, -0.4, 0, 1, 0, 0.7, -0.4, 0, 0, 1],
    @gl.STATIC_DRAW,
  )
  @gl.vertex_attrib_pointer(0, 2, @gl.FLOAT, false, 20, 0)
  @gles.enable_vertex_attrib_array(0)
  @gl.vertex_attrib_pointer(1, 3, @gl.FLOAT, false, 20, 8)
  @gles.enable_vertex_attrib_array(1)
}

///|
fn GlScene::render(
  self : GlScene,
  width : Int,
  height : Int,
  ts : Int64,
) -> Unit raise {
  if self.program == 0 {
    self.setup()
  }
  let (r, g, b) = gl_clear
  @gles.clear_color(r, g, b, 1)
  @gles.clear(@gl.COLOR_BUFFER_BIT)
  @gles.use_program(self.program)
  let phase = (ts / 1_000_000L % 4000L).to_int()
  @gles.uniform1f(
    self.angle_location,
    Float::from_int(phase) / 4000 * 6.2831855,
  )
  // Keeps the triangle's shape on a wide surface.
  @gles.uniform1f(
    self.aspect_location,
    if width > 0 { Float::from_int(height) / Float::from_int(width) } else { 1 },
  )
  @gles.bind_vertex_array(self.vao)
  @gles.draw_arrays(@gl.TRIANGLES, 0, 3)
  self.center = @gl.read_pixels(width / 2, height / 2, 1, 1)[0]
  let error = @gles.get_error()
  if error != @gl.NO_ERROR {
    fail("glGetError " + error.to_string())
  }
}

///|
fn GlScene::frame(self : GlScene, ts : Int64) -> Unit {
  guard self.running && self.gl.is_open() else { return }
  try {
    let (width, height) = self.gl.frame((w, h) => self.render(w, h, ts))
    self.frames += 1
    self.size = width.to_string() + "x" + height.to_string()
    self.vsync.request_frame(t => self.frame(t))
  } catch {
    error => {
      self.error = error.to_string()
      self.running = false
    }
  }
}

///|
/// Opens the GL surface with the given id and starts the animation.
pub fn gl_attach(surface_id : String) -> String {
  ignore(gl_detach())
  try {
    let scene = {
      gl: @gl.GlSurface::open(surface_id),
      vsync: @surface.VSync::open("moonsearch-gl"),
      program: 0,
      vao: 0,
      vbo: 0,
      angle_location: -1,
      aspect_location: -1,
      running: true,
      frames: 0,
      size: "",
      center: 0,
      error: "",
    }
    gl_scenes.push(scene)
    scene.vsync.request_frame(t => scene.frame(t))
    "attached=true"
  } catch {
    error => "attach!" + error.to_string()
  }
}

///|
/// `name=value` fields describing the GL scene. `center` is the RGBA 8888
/// value at the middle of the surface (bytes r, g, b, a).
pub fn gl_report() -> String {
  guard gl_scenes.last() is Some(scene) else { return "attached=false" }
  let (r, g, b, a) = @surface.components(scene.center)
  "attached=true,running=" +
  scene.running.to_string() +
  ",size=" +
  scene.size +
  ",frames=" +
  scene.frames.to_string() +
  ",swapped=" +
  scene.gl.frames().to_string() +
  ",center=" +
  r.to_string() +
  "/" +
  g.to_string() +
  "/" +
  b.to_string() +
  "/" +
  a.to_string() +
  ",error=" +
  scene.error
}

///|
/// Stops the animation and releases the context and window.
pub fn gl_detach() -> String {
  guard gl_scenes.last() is Some(scene) else { return "attached=false" }
  let report = gl_report()
  scene.running = false
  scene.gl.close()
  scene.vsync.close()
  gl_scenes.clear()
  report + ",closed=" + (!scene.gl.is_open()).to_string()
}
