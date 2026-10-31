///|
fn enum_project() -> @moonohos.Project raise {
  @moonohos.parse_project(
    (
      #|{"version":1,"module":"core","package":"a/core","nativeModule":"demo","enums":[{"name":"Level","cases":["Debug","Info"]}],"types":[{"name":"Event","fields":[{"name":"level","type":"Level"},{"name":"before","type":"Level?"}]}],"functions":[{"name":"bump","params":[{"name":"l","type":"Level"}],"return":"Level"},{"name":"echo","params":[{"name":"e","type":"Array[Event]"}],"return":"Array[Event]"}]}
    ),
  )
}

///|
test "enums become string unions and Int tags at the C boundary" {
  let generated = enum_project().generate()
  assert_true(
    generated.declarations.contains("export type Level = 'Debug' | 'Info';"),
  )
  assert_true(generated.declarations.contains("before?: Level;"))
  assert_true(generated.declarations.contains("bump: (l: Level) => Level;"))
  assert_true(
    generated.wrapper.contains(
      "pub fn moonohos_raw_bump(l : Int) -> Int { let l = match l { 0 => @core.Level::Debug; 1 => @core.Level::Info; _ => abort(\"moonohos: invalid Level tag\") }; match (@core.bump(l)) { @core.Level::Debug => 0; @core.Level::Info => 1 } }",
    ),
  )
  assert_true(generated.native.contains("expected 'Debug' | 'Info'"))
  assert_true(
    @moonohos.har_facade("demo", generated.declarations).contains(
      "export { Level, Event,",
    ),
  )
}

///|
test "enum manifests and interfaces are validated" {
  let p = enum_project()
  p.verify_interface(
    (
      #|pub fn bump(Level) -> Level
      #|pub fn echo(Array[Event]) -> Array[Event]
      #|pub(all) struct Event {
      #|  level : Level
      #|  before : Level?
      #|}
      #|pub(all) enum Level {
      #|  Info
      #|  Debug
      #|}
    ),
  )
  let mismatch = try {
    p.verify_interface(
      "pub fn bump(Level) -> Level\npub fn echo(Array[Event]) -> Array[Event]\npub(all) struct Event { level : Level\n before : Level? }\npub(all) enum Level { Debug\n Warn }",
    )
    ""
  } catch {
    Invalid(message) => message
  }
  assert_true(mismatch.contains("enum Level has cases Debug, Warn"))
  let payload = @moonohos.parse_package_interface(
    "pub(all) enum Shape { Circle(Double) }",
  )
  assert_true(payload.enums[0].unsupported is Some(_))
  for
    bad in [
      "{\"version\":1,\"module\":\"c\",\"package\":\"a/c\",\"nativeModule\":\"d\",\"enums\":[{\"name\":\"E\",\"cases\":[]}],\"functions\":[{\"name\":\"f\",\"params\":[],\"return\":\"Int\"}]}",
      "{\"version\":1,\"module\":\"c\",\"package\":\"a/c\",\"nativeModule\":\"d\",\"enums\":[{\"name\":\"E\",\"cases\":[\"A\",\"A\"]}],\"functions\":[{\"name\":\"f\",\"params\":[],\"return\":\"Int\"}]}",
      "{\"version\":1,\"module\":\"c\",\"package\":\"a/c\",\"nativeModule\":\"d\",\"enums\":[{\"name\":\"Int\",\"cases\":[\"A\"]}],\"functions\":[{\"name\":\"f\",\"params\":[],\"return\":\"Int\"}]}",
    ] {
    let rejected = try {
      @moonohos.parse_project(bad) |> ignore
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}
