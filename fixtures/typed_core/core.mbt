///|
pub(all) struct Series {
  name : String
  samples : FixedArray[Double]
  marks : FixedArray[Int]?
}

///|
pub fn scale(values : FixedArray[Double], factor : Double) -> FixedArray[Double] {
  FixedArray::makei(values.length(), i => values[i] * factor)
}

///|
pub fn narrow(values : FixedArray[Double]) -> FixedArray[Float] {
  FixedArray::makei(values.length(), i => Float::from_double(values[i]))
}

///|
pub fn sum_float(values : FixedArray[Float]) -> Double {
  let mut total = 0.0
  for value in values {
    total += value.to_double()
  }
  total
}

///|
/// Counts values into `buckets` buckets of width 10; out-of-range values land
/// in the first or last bucket.
pub fn histogram(values : FixedArray[Int], buckets : Int) -> FixedArray[Int] {
  let counts = FixedArray::make(buckets.max(0), 0)
  for value in values {
    if buckets > 0 {
      let bucket = (value / 10).max(0).min(buckets - 1)
      counts[bucket] = counts[bucket] + 1
    }
  }
  counts
}

///|
/// Wrapping running sums, so the Int64 extremes cross unchanged.
pub fn prefix(values : FixedArray[Int64]) -> FixedArray[Int64] {
  let result = FixedArray::make(values.length(), 0L)
  let mut total = 0L
  for i, value in values {
    total = total + value
    result[i] = total
  }
  result
}

///|
pub fn normalize(series : Series) -> Series {
  let mut peak = 0.0
  for value in series.samples {
    peak = peak.max(value.abs())
  }
  let samples = if peak == 0.0 {
    series.samples
  } else {
    FixedArray::makei(series.samples.length(), i => series.samples[i] / peak)
  }
  let marks = match series.marks {
    Some(marks) => Some(FixedArray::makei(marks.length(), i => marks[i] + 1))
    None => None
  }
  { name: series.name + "/normalized", samples, marks }
}

///|
pub fn chunk(values : FixedArray[Double], size : Int) -> Array[FixedArray[Double]] {
  let parts : Array[FixedArray[Double]] = []
  if size <= 0 {
    return parts
  }
  let mut start = 0
  while start < values.length() {
    let end = (start + size).min(values.length())
    parts.push(FixedArray::makei(end - start, i => values[start + i]))
    start = end
  }
  parts
}

///|
pub fn peak(values : FixedArray[Float]?) -> Double? {
  match values {
    Some(values) if values.length() > 0 => {
      let mut best = values[0].to_double()
      for value in values {
        best = best.max(value.to_double())
      }
      Some(best)
    }
    _ => None
  }
}

///|
/// Async: reports each window of four samples, then returns the mean.
pub fn mean_later(
  values : FixedArray[Double],
  on_window : (FixedArray[Double]) -> Unit,
) -> Double raise @task.Cancelled {
  let mut total = 0.0
  let mut start = 0
  while start < values.length() {
    let end = (start + 4).min(values.length())
    on_window(FixedArray::makei(end - start, i => values[start + i]))
    @task.check()
    start = end
  }
  for value in values {
    total += value
  }
  if values.length() == 0 {
    0.0
  } else {
    total / values.length().to_double()
  }
}
