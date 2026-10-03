///|
test "stage dependencies form a deterministic ordered build" {
  let project = @moonohos.parse_project(
    "{\"version\":1,\"module\":\".\",\"package\":\"a/b\",\"nativeModule\":\"moonohos\",\"functions\":[{\"name\":\"add\",\"params\":[],\"return\":\"Int\"}]}",
  )
  let stages = @moonohos.build_stages(project, ["arm64-v8a", "x86_64"])
  assert_eq(stages.length(), 14)
  assert_eq(stages.last().map(s => s.id), Some("publish"))
  assert_eq(project.build_plan(["x86_64"]), project.build_plan(["x86_64"]))
}
