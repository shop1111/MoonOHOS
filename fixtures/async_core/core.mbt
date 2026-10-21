///|
/// Opaque state owned by an ArkTS handle.
pub struct Counter {
  mut total : Int
  history : Array[Int]
}

///|
pub(all) suberror FixtureError {
  DivisionByZero
  Negative(Int)
}

///|
pub impl Show for FixtureError with fn output(self, logger) {
  match self {
    DivisionByZero => logger.write_string("division by zero")
    Negative(value) =>
      logger.write_string("negative total " + value.to_string())
  }
}

///|
pub extend FixtureError with Show::{to_string, output}

///|
pub fn open_counter(start : Int) -> Counter {
  { total: start, history: [start], }
}

///|
pub fn open_counter_later(start : Int) -> Counter {
  open_counter(start)
}

///|
pub fn add(counter : Counter, value : Int) -> Int {
  counter.total += value
  counter.history.push(counter.total)
  counter.total
}

///|
pub fn add_later(counter : Counter, value : Int) -> Int {
  add(counter, value)
}

///|
pub fn reset(counter : Counter) -> Unit raise FixtureError {
  if counter.total < 0 {
    raise Negative(counter.total)
  }
  counter.total = 0
}

///|
/// Busy loop polling cooperative cancellation; returns the iteration count.
pub fn spin(rounds : Int) -> Int raise @task.Cancelled {
  let mut sum = 0
  for i in 0..<rounds {
    sum = sum + i % 7
    if i % 1024 == 0 {
      @task.check()
    }
  }
  sum
}

///|
pub fn checked_div(a : Int, b : Int) -> Int raise FixtureError {
  if b == 0 {
    raise DivisionByZero
  }
  a / b
}

///|
pub fn read_doc(
  resources : @rawfile.Manager,
  path : String,
) -> String raise @rawfile.RawFileError {
  let logger = @hilog.Logger::new(0x4d4f, "MoonOHOSFixture") catch {
    _ => panic()
  }
  logger.info("read_doc " + path)
  @rawfile.read_text(resources, path)
}

///|
pub fn count_docs(
  resources : @rawfile.Manager,
  dir : String,
) -> Int raise @rawfile.RawFileError {
  @rawfile.list(resources, dir).length()
}

///|
pub fn echo_words(words : Array[String]) -> Array[String] {
  words.map(w => w + "!")
}
