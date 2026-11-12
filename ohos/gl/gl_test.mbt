///|
test "host: opening a GL surface fails with 801" {
  let code = try {
    ignore(@gl.GlSurface::open("12"))
    0
  } catch {
    @surface.Failed(_, code) => code
    _ => -1
  }
  assert_eq(code, 801)
  let bad = try {
    ignore(@gl.GlSurface::open("twelve"))
    false
  } catch {
    @surface.BadSurfaceId(_) => true
    _ => false
  }
  assert_true(bad)
}

///|
test "host: pointer helpers return sized results without a context" {
  let pixels = @gl.read_pixels(0, 0, 3, 2)
  assert_eq(pixels.length(), 6)
  assert_true(pixels.iter().all(p => p == 0))
  assert_eq(@gl.read_pixels(0, 0, -1, 2).length(), 0)
  assert_eq(@gl.get_integers(@gl.VIEWPORT, 4).length(), 4)
  assert_eq(@gl.get_integers(@gl.VIEWPORT, 1000).length(), 64)
  assert_eq(@gl.gen_buffer(), 0)
  assert_eq(@gl.shader_info_log(1), "")
}

///|
test "constants match GLES3/gl3.h" {
  assert_eq(@gl.COLOR_BUFFER_BIT, 0x4000)
  assert_eq(@gl.TRIANGLES, 4)
  assert_eq(@gl.FLOAT, 0x1406)
  assert_eq(@gl.ARRAY_BUFFER, 0x8892)
  assert_eq(@gl.VERTEX_SHADER, 0x8B31)
  assert_eq(@gl.FRAGMENT_SHADER, 0x8B30)
}
