///|
pub fn add(left : Int, right : Int) -> Int {
  left + right
}

///|
pub fn scale(value : Double, factor : Double) -> Double {
  value * factor
}

///|
pub fn negate(value : Bool) -> Bool {
  !value
}

///|
pub fn ping() -> Unit {
  ()
}

///|
pub fn echo_text(value : String) -> String {
  value
}

///|
pub fn join_text(left : String, right : String) -> String {
  left + right
}

///|
pub fn echo_bytes(value : Bytes) -> Bytes {
  value
}

///|
pub fn concat_bytes(left : Bytes, right : Bytes) -> Bytes {
  left + right
}

///|
pub fn describe_bytes(label : String, value : Bytes) -> String {
  label + value.length().to_string()
}
