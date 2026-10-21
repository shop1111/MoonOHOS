///|
extern "C" fn probe_cancelled() -> Bool = "moonohos_probe_cancelled"

///|
/// CPU-bound loop that polls cooperative cancellation every 4096 steps.
/// Returns -1 when cancelled.
pub fn moonohos_probe_busy(rounds : Int) -> Int {
  let mut hash = 216613626
  for i in 0..<rounds {
    hash = (hash ^ i) * 16777619
    let words : Array[Int] = [hash, i]
    hash = hash + words.length()
    if i % 4096 == 0 && probe_cancelled() {
      return -1
    }
  }
  hash
}

///|
/// Non-tail recursion to measure usable worker stack depth.
pub fn moonohos_probe_depth(n : Int) -> Int {
  if n <= 0 {
    0
  } else {
    let s = "d" + n.to_string()
    1 + moonohos_probe_depth(n - 1) + s.length() - s.length()
  }
}

///|
pub fn moonohos_probe_sum(data : Bytes) -> Int {
  let mut total = 0
  for b in data {
    total = total + b.to_int()
  }
  total
}

///|
fn main {
  ()
}
