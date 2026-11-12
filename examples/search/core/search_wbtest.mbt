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

///|
test "index builds report progress per file" {
  let resources = @rawfile.host_manager("testdata")
  let reported : Array[(Int, Int)] = []
  let index = build_index_reporting(resources, "docs", (done, total) => {
    reported.push((done, total))
  })
  assert_eq(stats(index).documents, 12)
  assert_eq(reported.length(), 12)
  assert_eq(reported[0], (1, 12))
  assert_eq(reported[11], (12, 12))
}

///|
test "term IDF and native size estimates" {
  let index = index_texts(["a.md", "b.md", "c.md"], [
    "# RawFile\nrawfile manager reads rawfile resources", "# HiLog\nlogging only",
    "# 离线检索\n离线检索适合帮助文档。rawfile appears once",
  ])
  let idf = term_idf(index, "rawfile hilog absent")
  assert_eq(idf.length(), 3)
  // A term in fewer documents weighs more; an unknown term weighs nothing.
  assert_true(idf[1] > idf[0] && idf[0] > 0.0)
  assert_eq(idf[2], 0.0)
  assert_eq(term_idf(index, "").length(), 0)
  let small = index_bytes(index)
  assert_true(small > stats(index).characters * 2)
  let empty = index_texts([], [])
  assert_eq(index_bytes(empty), 0)
}

///|
test "platform report runs every generated binding on the host" {
  let report = platform_report()
  assert_eq(report.length(), 19)
  // No SDK on the host: error-code calls fail with 801, others return zeros.
  assert_true(report.contains("battery.capacity=0"))
  assert_true(report.any(line => line.has_prefix("display.size!")))
  assert_true(report.contains("syscap.fake=false"))
}

///|
test "handle and callback probes fail cleanly on the host" {
  let handles = platform_handles()
  assert_true(handles[0].has_prefix("handle.primary!"))
  assert_eq(handles[1], "handle.subscriber=created_and_dropped=0")
  let started = platform_listen_start()
  assert_true(started[0].has_prefix("listen.display!"))
  assert_eq(started[1], "listen.light=no id")
  let stopped = platform_listen_stop()
  assert_true(stopped.contains("events.display=0"))
}

///|
test "surface demo fails cleanly on the host" {
  let attached = surface_attach("42", 360, 200)
  assert_true(attached.has_prefix("attach!"), msg=attached)
  assert_true(attached.contains("801"), msg=attached)
  assert_eq(surface_touch(0.5, 0.5), 0)
  assert_eq(surface_report(), "attached=false")
  assert_eq(surface_detach(), "attached=false")
  assert_true(surface_attach("not-a-number", 1, 1).contains("not a surface id"))
}

///|
test "surface mode switch needs an attached scene" {
  assert_eq(surface_mode(false), "attached=false")
}
