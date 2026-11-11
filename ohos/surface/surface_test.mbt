///|
test "surface ids are decimal 64-bit numbers" {
  assert_eq(@surface.parse_surface_id("0"), 0UL)
  assert_eq(
    @surface.parse_surface_id("18446744073709551615"),
    18446744073709551615UL,
  )
  for bad in ["", "-1", "12a", "18446744073709551616", "99999999999999999999"] {
    let rejected = try {
      ignore(@surface.parse_surface_id(bad))
      false
    } catch {
      @surface.BadSurfaceId(_) => true
      _ => false
    }
    assert_true(rejected, msg="accepted " + bad)
  }
}

///|
test "host: opening fails with 801" {
  let surface_code = try {
    ignore(@surface.Surface::open("123", width=4, height=4))
    0
  } catch {
    @surface.Failed(_, code) => code
    _ => -1
  }
  assert_eq(surface_code, 801)
  let vsync_code = try {
    ignore(@surface.VSync::open("moonohos"))
    0
  } catch {
    @surface.Failed(_, code) => code
    _ => -1
  }
  assert_eq(vsync_code, 801)
}

///|
test "rgba packs bytes in r, g, b, a memory order" {
  let color = @surface.rgba(0x11, 0x22, 0x33, a=0x44)
  assert_eq(color, 0x44332211U)
  let (r, g, b, a) = @surface.components(color)
  assert_eq([r, g, b, a], [0x11, 0x22, 0x33, 0x44])
  assert_eq(@surface.rgba(300, -5, 128), 0xFF8000FFU)
}

///|
test "canvas drawing is clipped" {
  let canvas = @surface.Canvas::new(8, 6)
  let red = @surface.rgba(255, 0, 0)
  let blue = @surface.rgba(0, 0, 255)
  canvas.clear(blue)
  canvas.fill_rect(-2, -2, 4, 4, red)
  assert_true(canvas.get(1, 1) == Some(red))
  assert_true(canvas.get(2, 2) == Some(blue))
  assert_true(canvas.get(8, 0) is None)
  canvas.fill_circle(6, 4, 2, red)
  let mut lit = 0
  for color in canvas.pixels() {
    if color == red {
      lit += 1
    }
  }
  // 4 from the rectangle; the disc of radius 2 (rows of 1, 3, 5, 3, 1
  // pixels) loses its last row below the bottom edge and one pixel of the
  // middle row to the right edge: 11.
  assert_eq(lit, 15)
  canvas.set(100, 100, red)
  canvas.fill_circle(0, 0, -1, red)
  assert_true(canvas.get(0, 5) == Some(blue))
}

///|
test "blit copies rows into a strided buffer and clips" {
  let src = FixedArray::makei(3 * 2, i => (i + 1).reinterpret_as_uint())
  // Destination: 2 x 3 visible, rows 4 pixels apart.
  let dst : FixedArray[UInt32] = FixedArray::make(4 * 3, 0)
  @surface.blit(dst, 4, 2, 3, src, 3, 2)
  let expected : FixedArray[UInt32] = [1, 2, 0, 0, 4, 5, 0, 0, 0, 0, 0, 0]
  assert_true(dst == expected)
}
