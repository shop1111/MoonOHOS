///|
test "cache keys are ordered content identities" {
  let a = @moonohos.fingerprint("source", "a.mbt", b"abc")
  let b = @moonohos.fingerprint("runtime", "runtime.c", b"xyz")
  assert_eq(
    @moonohos.content_cache_key([a, b]),
    @moonohos.content_cache_key([b, a]),
  )
  assert_true(
    @moonohos.content_cache_key([a, b]) !=
    @moonohos.content_cache_key([
      a,
      @moonohos.fingerprint("runtime", "runtime.c", b"changed"),
    ]),
  )
  assert_true(
    try @moonohos.content_cache_key([a, a]) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
}
