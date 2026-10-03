///|
test "SHA256 standard vectors and incremental boundaries" {
  assert_eq(
    @moonohos.sha256(b""),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  assert_eq(
    @moonohos.sha256(b"abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
  assert_eq(
    @moonohos.sha256(
      b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
    ),
    "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
  )
  let state = @moonohos.Sha256::new()
  for _ in 0..<1000 {
    state.update(Bytes::make(1000, 97))
  }
  assert_eq(
    state.digest(),
    "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
  )
  assert_eq(state.digest(), state.digest())
}
