///|
test "hitrace structs round-trip through the flattened buffers" {
  let id : @hitrace.HiTraceId = {
    valid: 1,
    ver: 2,
    chain_id: 0x123456789ABCUL,
    flags: 4,
    span_id: 5,
    parent_span_id: 6,
  }
  // On the host the C side copies the fields back unchanged.
  let same = @hitrace.set_chain_id(id, 42UL)
  assert_eq(same.chain_id, 0x123456789ABCUL)
  assert_eq(same.parent_span_id, 6UL)
  assert_eq(@hitrace.begin_chain("chain", 0).chain_id, 0UL)
  @hitrace.start_trace("host")
  @hitrace.finish_trace()
}

///|
test "generated enums keep unknown values" {
  let flag = @hitrace.HiTrace_Flag::from_raw(1 << 2)
  assert_eq(flag.to_raw(), 4)
  assert_eq(flag.c_name(), "HITRACE_FLAG_TP_INFO")
  let unknown = @hitrace.HiTrace_Flag::from_raw(1 << 20)
  assert_true(unknown is Other(1048576))
  assert_eq(unknown.to_string(), "HiTrace_Flag(1048576)")
}
