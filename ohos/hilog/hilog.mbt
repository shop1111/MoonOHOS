///|
/// HiLog severity levels (values of `LogLevel` in `hilog/log.h`).
pub(all) enum Level {
  Debug
  Info
  Warn
  Error
  Fatal
}

///|
fn Level::code(self : Level) -> Int {
  match self {
    Debug => 3
    Info => 4
    Warn => 5
    Error => 6
    Fatal => 7
  }
}

///|
pub(all) suberror HilogError {
  InvalidDomain(Int)
  InvalidTag(String)
}

///|
pub impl Show for HilogError with fn output(self, logger) {
  match self {
    InvalidDomain(domain) =>
      logger.write_string(
        "hilog domain must be 0..0xFFFF: " + domain.to_string(),
      )
    InvalidTag(tag) =>
      logger.write_string("hilog tag must be 1..31 bytes without NUL: " + tag)
  }
}

///|
/// Application log channel identified by a HiLog domain and tag.
pub struct Logger {
  domain : Int
  tag : String
  priv tag_bytes : Bytes
}

///|
#borrow(tag, message)
extern "C" fn print_raw(
  level : Int,
  domain : Int,
  tag : Bytes,
  message : Bytes,
) -> Int = "moonohos_hilog_print"

///|
#borrow(tag)
extern "C" fn loggable_raw(level : Int, domain : Int, tag : Bytes) -> Int = "moonohos_hilog_loggable"

///|
fn c_text(text : String) -> Bytes {
  @utf8.encode(text.replace_all(old="\u{0}", new="\\0") + "\u{0}")
}

///|
pub fn Logger::new(domain : Int, tag : String) -> Logger raise HilogError {
  if domain < 0 || domain > 0xFFFF {
    raise InvalidDomain(domain)
  }
  let encoded = @utf8.encode(tag)
  if encoded.length() == 0 || encoded.length() > 31 || tag.contains("\u{0}") {
    raise InvalidTag(tag)
  }
  { domain, tag, tag_bytes: c_text(tag), }
}

///|
pub fn Logger::is_loggable(self : Logger, level : Level) -> Bool {
  loggable_raw(level.code(), self.domain, self.tag_bytes) != 0
}

///|
/// Writes one message; embedded NUL characters are shown as `\0`.
pub fn Logger::log(self : Logger, level : Level, message : String) -> Unit {
  print_raw(level.code(), self.domain, self.tag_bytes, c_text(message))
  |> ignore
}

///|
pub fn Logger::debug(self : Logger, message : String) -> Unit {
  self.log(Debug, message)
}

///|
pub fn Logger::info(self : Logger, message : String) -> Unit {
  self.log(Info, message)
}

///|
pub fn Logger::warn(self : Logger, message : String) -> Unit {
  self.log(Warn, message)
}

///|
pub fn Logger::error(self : Logger, message : String) -> Unit {
  self.log(Error, message)
}

///|
pub fn Logger::fatal(self : Logger, message : String) -> Unit {
  self.log(Fatal, message)
}

///|
pub extend HilogError with Show::{to_string, output}
