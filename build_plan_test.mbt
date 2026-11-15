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

///|
test "restore_source_paths maps staged members back to their sources" {
  let mappings = [
    ("D:/p/_build/moonohos/work-4/ws/m0", "D:/p/core"),
    ("D:/p/_build/moonohos/work-4/ws/m1", "D:/ohos"),
  ]
  inspect(
    @moonohos.restore_source_paths(
      "D:\\p\\_build\\moonohos\\work-4\\ws\\m0\\lib.mbt:4:17 and D:/p/_build/moonohos/work-4/ws/m1/hilog/x.mbt, ws/m10",
      mappings,
    ),
    content="D:\\p\\core\\lib.mbt:4:17 and D:/ohos/hilog/x.mbt, ws/m10",
  )
}
