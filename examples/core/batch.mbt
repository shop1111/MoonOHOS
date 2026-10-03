///|
pub(all) struct SampleMeta {
  active : Bool
  source : String
}

///|
pub(all) struct Sample {
  label : String
  values : Array[Double]
  meta : SampleMeta
  bytes : Bytes
}

///|
pub(all) struct Analysis {
  count : Int
  total : Double
  labels : Array[String]
  groups : Array[Array[Double]]
  meta : SampleMeta
}

///|
pub fn echo_samples(samples : Array[Sample]) -> Array[Sample] {
  samples
}

///|
pub fn analyze_samples(samples : Array[Sample]) -> Analysis {
  let mut total = 0.0
  let labels : Array[String] = []
  let groups : Array[Array[Double]] = []
  let mut count = 0
  for sample in samples {
    if sample.meta.active {
      count += 1
      labels.push(sample.label)
      groups.push(sample.values)
      for value in sample.values {
        total += value
      }
    }
  }
  { count, total, labels, groups, meta: { active: true, source: "MoonBit", }, }
}
