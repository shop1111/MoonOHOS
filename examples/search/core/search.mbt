///|
let k1 : Double = 1.2

///|
let b : Double = 0.75

///|
/// Text around a UTF-16 offset with whitespace collapsed.
fn snippet(text : String, offset : Int) -> String {
  let before = 24
  let after = 72
  let mut position = 0
  let mut out = ""
  let mut space = false
  let mut truncated = false
  for ch in text {
    let next = position + ch.utf16_len()
    if next > offset - before && position < offset + after {
      let blank = ch == '\n' || ch == '\r' || ch == '\t' || ch == ' '
      if blank {
        if !space && out != "" {
          out = out + " "
        }
        space = true
      } else {
        out = out + ch.to_string()
        space = false
      }
    } else if position >= offset + after {
      truncated = true
      break
    }
    position = next
  }
  (if offset - before > 0 { "…" } else { "" }) +
  out.trim().to_owned() +
  (if truncated { "…" } else { "" })
}

///|
/// BM25 ranking (k1 = 1.2, b = 0.75) over query terms; ties keep document order.
pub fn search(index : SearchIndex, query : String, limit : Int) -> Array[Hit] {
  let terms = query_terms(query)
  let count = index.docs.length()
  if terms.is_empty() || limit <= 0 || count == 0 {
    return []
  }
  let n = count.to_double()
  let average = (index.total_length.to_double() / n).max(1.0)
  let scores : Map[Int, Double] = Map([])
  let firsts : Map[Int, Int] = Map([])
  for term in terms {
    guard index.terms.get(term) is Some(list) else { continue }
    let df = list.length().to_double()
    let idf = @math.ln(1.0 + (n - df + 0.5) / (df + 0.5))
    for posting in list {
      let length = index.docs[posting.doc].length.to_double()
      let tf = posting.freq.to_double()
      let score = idf *
        tf *
        (k1 + 1.0) /
        (tf + k1 * (1.0 - b + b * length / average))
      scores[posting.doc] = scores.get(posting.doc).unwrap_or(0.0) + score
      if !firsts.contains(posting.doc) {
        firsts[posting.doc] = posting.first
      }
    }
  }
  let ranked : Array[(Int, Double)] = []
  for doc, score in scores {
    ranked.push((doc, score))
  }
  ranked.sort_by((x, y) => {
    if x.1 > y.1 {
      -1
    } else if x.1 < y.1 {
      1
    } else {
      x.0 - y.0
    }
  })
  let hits : Array[Hit] = []
  for entry in ranked {
    if hits.length() >= limit {
      break
    }
    let doc = index.docs[entry.0]
    hits.push({
      path: doc.path,
      title: doc.title,
      score: (entry.1 * 1000.0).round() / 1000.0,
      snippet: snippet(doc.text, firsts.get(entry.0).unwrap_or(0)),
    })
  }
  hits
}

///|
/// Synchronous variant for short interactive queries on the ArkTS thread.
pub fn search_now(
  index : SearchIndex,
  query : String,
  limit : Int,
) -> Array[Hit] {
  search(index, query, limit)
}
