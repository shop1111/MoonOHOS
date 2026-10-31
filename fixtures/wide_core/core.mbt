///|
pub(all) struct Stamp {
  id : Int64
  offsets : Array[Int64]
  label : String
}

///|
/// Wrapping addition, so the extremes of the range are exercised.
pub fn add_wide(a : Int64, b : Int64) -> Int64 {
  a + b
}

///|
pub fn sum_wide(values : Array[Int64]) -> Int64 {
  let mut total = 0L
  for value in values {
    total += value
  }
  total
}

///|
pub fn shift_stamp(stamp : Stamp, delta : Int64) -> Stamp {
  {
    id: stamp.id + delta,
    offsets: stamp.offsets.map(o => o + delta),
    label: stamp.label,
  }
}

///|
pub fn split_wide(value : Int64) -> Array[Int64] {
  [value >> 32, value & 0xFFFFFFFFL]
}
