///|
pub(all) struct Profile {
  name : String
  nickname : String?
  age : Int32?
  tags : Array[String?]
}

///|
pub fn greet(name : String?) -> String {
  match name {
    Some(n) => "Hello, " + n
    None => "Hello, stranger"
  }
}

///|
pub fn find_index(values : Array[Int32], target : Int32) -> Int32? {
  for i, v in values {
    if v == target {
      return Some(i)
    }
  }
  None
}

///|
pub fn echo_profile(p : Profile) -> Profile {
  p
}

///|
/// The profile with the greatest known age; profiles without an age are skipped.
pub fn oldest(people : Array[Profile]) -> Profile? {
  let mut best : Profile? = None
  for p in people {
    match (p.age, best) {
      (Some(age), Some(b)) if age > b.age.unwrap_or(0) => best = Some(p)
      (Some(_), None) => best = Some(p)
      _ => ()
    }
  }
  best
}

///|
pub fn next_wide(x : Int64?) -> Int64? {
  x.map(v => v + 1L)
}
