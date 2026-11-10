///|
pub(all) struct Progress {
  done : Int
  total : Int
}

///|
pub(all) enum Level {
  Low
  High
}

///|
/// Synchronous: calls `visit` once per space-separated word.
pub fn each_word(text : String, visit : (String, Int) -> Unit) -> Int {
  let words = text.split(" ").filter(w => w != "").to_array()
  for i, word in words {
    visit(word.to_owned(), i)
  }
  words.length()
}

///|
/// Records, Options, Bytes, Int64 and enums as callback arguments.
pub fn report(
  steps : Int,
  on_step : (Progress, Int?, Bytes, Int64, Level) -> Unit,
) -> Unit {
  for i in 0..<steps {
    let hint = if i % 2 == 0 { Some(i) } else { None }
    let level = if i + 1 == steps { High } else { Low }
    on_step(
      { done: i + 1, total: steps },
      hint,
      Bytes::from_array([b'a' + i.to_byte()]),
      i.to_int64() * 1000000000000L,
      level,
    )
  }
}

///|
/// Asynchronous with progress; stops when cancelled (including by a throwing
/// callback).
pub fn count_up(
  n : Int,
  on_progress : (Int) -> Unit,
) -> Int raise @task.Cancelled {
  let mut sum = 0
  for i in 1..=n {
    sum = sum + i
    if i % 10 == 0 {
      on_progress(i)
      @task.check()
    }
  }
  sum
}

///|
/// Asynchronous with two callbacks.
pub fn scan(
  words : Array[String],
  on_word : (String) -> Unit,
  on_done : (Array[String]) -> Unit,
) -> Int {
  let seen = []
  for word in words {
    on_word(word)
    seen.push(word + "!")
  }
  on_done(seen)
  seen.length()
}

///|
let saved : Array[(Int) -> Unit] = []

///|
/// Keeps the callback beyond the call; later invocations must be ignored.
pub fn remember(callback : (Int) -> Unit) -> Unit {
  callback(1)
  saved.clear()
  saved.push(callback)
}

///|
pub fn replay(x : Int) -> Int {
  match saved.get(0) {
    Some(f) => {
      f(x)
      1
    }
    None => 0
  }
}

///|
/// A non-finite Double cannot be passed to ArkTS.
pub fn emit_ratio(a : Double, b : Double, on_ratio : (Double) -> Unit) -> Unit {
  on_ratio(a / b)
}

///|
pub fn plain(x : Int) -> Int {
  x + 1
}
