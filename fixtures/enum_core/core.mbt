///|
pub(all) enum Level {
  Debug
  Info
  Warn
  Error
}

///|
pub(all) struct Event {
  level : Level
  message : String
  seen : Array[Level]
  previous : Level?
}

///|
fn rank(level : Level) -> Int32 {
  match level {
    Debug => 0
    Info => 1
    Warn => 2
    Error => 3
  }
}

///|
/// The next level up; `Error` stays `Error`.
pub fn bump(level : Level) -> Level {
  match level {
    Debug => Info
    Info => Warn
    Warn | Error => Error
  }
}

///|
pub fn count_at_least(events : Array[Event], floor : Level) -> Int32 {
  events.filter(e => rank(e.level) >= rank(floor)).length()
}

///|
pub fn loudest(events : Array[Event]) -> Level? {
  let mut best : Level? = None
  for e in events {
    match best {
      Some(b) if rank(b) >= rank(e.level) => ()
      _ => best = Some(e.level)
    }
  }
  best
}

///|
pub fn echo_event(event : Event) -> Event {
  event
}
