///|
test "host fallback reports configurable network state and errors" {
  @netconn.set_host_state(has_default=true, metered=false)
  assert_true(@netconn.has_default_network())
  assert_false(@netconn.is_metered())
  @netconn.set_host_state(has_default=false, metered=true)
  assert_false(@netconn.has_default_network())
  assert_true(@netconn.is_metered())
  @netconn.set_host_state(has_default=true, metered=false, error=201)
  let message = try {
    @netconn.has_default_network() |> ignore
    ""
  } catch {
    e => e.to_string()
  }
  assert_true(message.contains("GET_NETWORK_INFO"))
  @netconn.set_host_state(has_default=true, metered=false)
}
