///|
/// FIPS 180-4 SHA-256. All arithmetic intentionally wraps at 32 bits.
pub struct Sha256 {
  state : Array[UInt]
  pending : Array[Byte]
  mut count : UInt64
}

///|
pub fn Sha256::new() -> Sha256 {
  {
    state: [
      0x6a09e667U, 0xbb67ae85U, 0x3c6ef372U, 0xa54ff53aU, 0x510e527fU, 0x9b05688cU,
      0x1f83d9abU, 0x5be0cd19U,
    ],
    pending: [],
    count: 0UL,
  }
}

///|
fn rotate(value : UInt, bits : Int) -> UInt {
  (value >> bits) | (value << (32 - bits))
}

///|
fn compress_sha(state : Array[UInt], block : Array[Byte]) -> Unit {
  let constants = [
    0x428a2f98U, 0x71374491U, 0xb5c0fbcfU, 0xe9b5dba5U, 0x3956c25bU, 0x59f111f1U,
    0x923f82a4U, 0xab1c5ed5U, 0xd807aa98U, 0x12835b01U, 0x243185beU, 0x550c7dc3U,
    0x72be5d74U, 0x80deb1feU, 0x9bdc06a7U, 0xc19bf174U, 0xe49b69c1U, 0xefbe4786U,
    0x0fc19dc6U, 0x240ca1ccU, 0x2de92c6fU, 0x4a7484aaU, 0x5cb0a9dcU, 0x76f988daU,
    0x983e5152U, 0xa831c66dU, 0xb00327c8U, 0xbf597fc7U, 0xc6e00bf3U, 0xd5a79147U,
    0x06ca6351U, 0x14292967U, 0x27b70a85U, 0x2e1b2138U, 0x4d2c6dfcU, 0x53380d13U,
    0x650a7354U, 0x766a0abbU, 0x81c2c92eU, 0x92722c85U, 0xa2bfe8a1U, 0xa81a664bU,
    0xc24b8b70U, 0xc76c51a3U, 0xd192e819U, 0xd6990624U, 0xf40e3585U, 0x106aa070U,
    0x19a4c116U, 0x1e376c08U, 0x2748774cU, 0x34b0bcb5U, 0x391c0cb3U, 0x4ed8aa4aU,
    0x5b9cca4fU, 0x682e6ff3U, 0x748f82eeU, 0x78a5636fU, 0x84c87814U, 0x8cc70208U,
    0x90befffaU, 0xa4506cebU, 0xbef9a3f7U, 0xc67178f2U,
  ]
  let words = Array::make(64, 0U)
  for i in 0..<16 {
    let start = i * 4
    words[i] = (block[start].to_uint() << 24) |
      (block[start + 1].to_uint() << 16) |
      (block[start + 2].to_uint() << 8) |
      block[start + 3].to_uint()
  }
  for i in 16..<64 {
    let a = words[i - 15]
    let b = words[i - 2]
    let small0 = rotate(a, 7) ^ rotate(a, 18) ^ (a >> 3)
    let small1 = rotate(b, 17) ^ rotate(b, 19) ^ (b >> 10)
    words[i] = words[i - 16] + small0 + words[i - 7] + small1
  }
  let mut a = state[0]
  let mut b = state[1]
  let mut c = state[2]
  let mut d = state[3]
  let mut e = state[4]
  let mut f = state[5]
  let mut g = state[6]
  let mut h = state[7]
  for i in 0..<64 {
    let sum1 = rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25)
    let choice = (e & f) ^ (e.lnot() & g)
    let temp1 = h + sum1 + choice + constants[i] + words[i]
    let sum0 = rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22)
    let majority = (a & b) ^ (a & c) ^ (b & c)
    h = g
    g = f
    f = e
    e = d + temp1
    d = c
    c = b
    b = a
    a = temp1 + sum0 + majority
  }
  for i, value in [a, b, c, d, e, f, g, h] {
    state[i] += value
  }
}

///|
pub fn Sha256::update(self : Sha256, data : Bytes) -> Unit {
  self.count += data.length().to_uint64()
  for byte in data {
    self.pending.push(byte)
    if self.pending.length() == 64 {
      compress_sha(self.state, self.pending)
      self.pending.clear()
    }
  }
}

///|
/// Finalization uses a copy; calling digest repeatedly does not mutate state.
pub fn Sha256::digest(self : Sha256) -> String {
  let state = self.state.copy()
  let pending = self.pending.copy()
  pending.push(0x80)
  while pending.length() % 64 != 56 {
    pending.push(0)
  }
  let bits = self.count * 8UL
  for shift = 56; shift >= 0; shift = shift - 8 {
    pending.push((bits >> shift).to_byte())
  }
  let mut offset = 0
  while offset < pending.length() {
    compress_sha(state, pending[offset:offset + 64].to_owned())
    offset += 64
  }
  let buffer = StringBuilder()
  for word in state {
    for shift in [24, 16, 8, 0] {
      buffer.write_string((word >> shift).to_byte().to_hex())
    }
  }
  buffer.to_string()
}

///|
pub fn sha256(data : Bytes) -> String {
  let state = Sha256::new()
  state.update(data)
  state.digest()
}
