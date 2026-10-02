///|
pub fn length(value : String, offset : Int) -> Int {
  value.length() + offset
}

///|
pub fn weighted(value : Bytes, factor : Double) -> Double {
  value.length().to_double() * factor
}

///|
pub fn enabled(value : String, flag : Bool) -> Bool {
  !value.is_empty() && flag
}

///|
pub fn discard(text : String, data : Bytes) -> Unit {
  ignore(text)
  ignore(data)
}

///|
pub fn constant_text() -> String {
  "中文😀"
}

///|
pub fn constant_bytes() -> Bytes {
  b"\x00\xff"
}

///|
pub fn mixed(
  text : String,
  data : Bytes,
  offset : Int,
  factor : Double,
  flag : Bool,
) -> String {
  if flag {
    text + (data.length() + offset).to_string() + ":" + factor.to_string()
  } else {
    ""
  }
}
