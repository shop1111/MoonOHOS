///|
pub(all) struct Meta { active : Bool }
///|
pub(all) struct Box { label : String; values : Array[Int]; meta : Meta; payload : Bytes }
///|
pub(all) struct Summary { count : Int; total : Int; labels : Array[String] }
///|
pub fn echo_box(v : Box) -> Box { v }
///|
pub fn echo_boxes(v : Array[Box]) -> Array[Box] { v }
///|
pub fn select_box(a : Box, b : Box) -> Box { ignore(b); a }
///|
pub fn summarize(v : Array[Box]) -> Summary {
  let mut total = 0
  let labels : Array[String] = []
  for box in v { labels.push(box.label); for x in box.values { total += x } }
  {count: v.length(), total, labels}
}
