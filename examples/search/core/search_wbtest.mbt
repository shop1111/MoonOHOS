///|
test "tokenizer emits lowercase words and CJK unigrams plus bigrams" {
  let terms = tokenize("MoonBit 离线检索 HAR", query=false).map(t => t.term)
  assert_eq(terms, [
    "moonbit", "离", "线", "离线", "检", "线检", "索", "检索", "har",
  ])
  assert_eq(query_terms("离线检索 rawfile"), [
    "离线", "线检", "检索", "rawfile",
  ])
  assert_eq(query_terms("库"), ["库"])
  let offsets = tokenize("a 中文", query=false).map(t => t.offset)
  assert_eq(offsets, [0, 2, 3, 2])
}

///|
test "BM25 ranks matching documents and builds snippets" {
  let index = index_texts(["a.md", "b.md", "c.md"], [
    "# RawFile\nrawfile manager reads rawfile resources", "# HiLog\nlogging only",
    "# 离线检索\n离线检索适合帮助文档。rawfile appears once",
  ])
  let hits = search(index, "rawfile", 10)
  assert_eq(hits.map(h => h.path), ["a.md", "c.md"])
  assert_eq(hits[0].title, "RawFile")
  assert_true(hits[0].score > hits[1].score)
  let chinese = search(index, "离线检索", 5)
  assert_eq(chinese.length(), 1)
  assert_true(chinese[0].snippet.contains("离线检索"))
  assert_true(search(index, "absent", 5).is_empty())
  assert_eq(search(index, "rawfile", 1).length(), 1)
  assert_eq(stats(index).documents, 3)
  assert_eq(search_now(index, "hilog", 3)[0].path, "b.md")
}

///|
test "cancellation interrupts indexing" {
  @task.host_set_cancelled(true)
  let cancelled = try {
    index_texts(["x"], ["text"]) |> ignore
    false
  } catch {
    _ => true
  }
  @task.host_set_cancelled(false)
  assert_true(cancelled)
}

///|
test "rawfile documents are indexed on the host" {
  let resources = @rawfile.host_manager("testdata")
  let index = build_index(resources, "docs")
  assert_eq(stats(index).documents, 12)
  let hits = search(index, "离线检索", 3)
  assert_true(
    hits[0].path == "docs/09-offline-search.md" ||
    hits[0].path == "docs/07-cjk-tokenizer.md",
  )
  assert_eq(search(index, "assembleHar", 3)[0].path, "docs/08-har.md")
  let missing = try {
    build_index(resources, "missing") |> ignore
    ""
  } catch {
    e => e.to_string()
  }
  assert_eq(missing, "rawfile not found: missing")
}
