///|
priv struct Doc {
  path : String
  title : String
  text : String
  length : Int
}

///|
priv struct Posting {
  doc : Int
  mut freq : Int
  /// UTF-16 offset of the first occurrence, used for snippets.
  first : Int
}

///|
/// Inverted index over packaged documents. Opaque to ArkTS: it is exposed as a
/// handle object whose `close()` releases the MoonBit memory.
struct SearchIndex {
  docs : Array[Doc]
  terms : Map[String, Array[Posting]]
  mut total_length : Int
  mut postings : Int
  mut characters : Int
}

///|
pub(all) struct Hit {
  path : String
  title : String
  score : Double
  snippet : String
}

///|
pub(all) struct IndexStats {
  documents : Int
  terms : Int
  postings : Int
  characters : Int
}

///|
fn SearchIndex::empty() -> SearchIndex {
  { docs: [], terms: Map([]), total_length: 0, postings: 0, characters: 0, }
}

///|
/// First non-empty line without Markdown heading marks, else the path.
fn title_of(text : String, path : String) -> String {
  for line in text.split("\n") {
    let line = line.trim_start(chars="#").trim().to_owned()
    if line != "" {
      return if line.length() > 80 { line[:80].to_owned() } else { line }
    }
  }
  path
}

///|
/// Adds one document, polling cancellation while tokenizing large texts.
fn SearchIndex::add(
  self : SearchIndex,
  path : String,
  text : String,
) -> Unit raise @task.Cancelled {
  let doc = self.docs.length()
  let tokens = tokenize(text, query=false)
  let seen : Map[String, Posting] = Map([])
  for index, token in tokens {
    if index % 4096 == 0 {
      @task.check()
    }
    match seen.get(token.term) {
      Some(posting) => posting.freq += 1
      None => {
        let posting = { doc, freq: 1, first: token.offset, }
        seen[token.term] = posting
        match self.terms.get(token.term) {
          Some(list) => list.push(posting)
          None => self.terms[token.term] = [posting]
        }
        self.postings += 1
      }
    }
  }
  self.docs.push({
    path,
    title: title_of(text, path),
    text,
    length: tokens.length(),
  })
  self.total_length += tokens.length()
  self.characters += text.length()
}

///|
/// Builds an index from in-memory texts (used by tests and host checks).
pub fn index_texts(
  paths : Array[String],
  texts : Array[String],
) -> SearchIndex raise @task.Cancelled {
  let index = SearchIndex::empty()
  for i, path in paths {
    index.add(path, texts[i])
  }
  index
}

///|
fn logger() -> @hilog.Logger {
  @hilog.Logger::new(0x4d4f, "MoonSearch") catch {
    _ => panic()
  }
}

///|
/// Reads every `.md`/`.txt` file of a rawfile directory and indexes it. Runs on
/// a worker thread when exported as async; cancellation is checked per file and
/// while tokenizing.
pub fn build_index(
  resources : @rawfile.Manager,
  dir : String,
) -> SearchIndex raise {
  build_index_reporting(resources, dir, (_, _) => ())
}

///|
/// Like `build_index`, calling `on_progress(indexed, total)` after each file.
pub fn build_index_reporting(
  resources : @rawfile.Manager,
  dir : String,
  on_progress : (Int, Int) -> Unit,
) -> SearchIndex raise {
  let log = logger()
  let names = @rawfile.list(resources, dir).filter(name => {
    name.has_suffix(".md") || name.has_suffix(".txt")
  })
  log.info(
    "MOONSEARCH_INDEX_BEGIN dir=" + dir + " files=" + names.length().to_string(),
  )
  let index = SearchIndex::empty()
  for position, name in names {
    if @task.cancelled() {
      log.info("MOONSEARCH_INDEX_CANCELLED at=" + position.to_string())
      raise @task.Cancelled
    }
    let path = if dir == "" { name } else { dir + "/" + name }
    index.add(path, @rawfile.read_text(resources, path)) catch {
      @task.Cancelled => {
        log.info("MOONSEARCH_INDEX_CANCELLED at=" + position.to_string())
        raise @task.Cancelled
      }
      error => raise error
    }
    on_progress(position + 1, names.length())
  }
  let stats = stats(index)
  log.info(
    "MOONSEARCH_INDEX_END documents=" +
    stats.documents.to_string() +
    " terms=" +
    stats.terms.to_string() +
    " postings=" +
    stats.postings.to_string(),
  )
  index
}

///|
pub fn stats(index : SearchIndex) -> IndexStats {
  {
    documents: index.docs.length(),
    terms: index.terms.length(),
    postings: index.postings,
    characters: index.characters,
  }
}

///|
/// Approximate native size of the index in bytes: document text (UTF-16),
/// postings and term entries. MoonOHOS samples it once, when the ArkTS handle
/// is created, and reports it to the ArkTS GC (`"size"` in moonohos.json).
pub fn index_bytes(index : SearchIndex) -> Int {
  let estimate = index.characters.to_int64() * 2L +
    index.postings.to_int64() * 24L +
    index.terms.length().to_int64() * 64L +
    index.docs.length().to_int64() * 96L
  if estimate > 2147483647L {
    2147483647
  } else {
    estimate.to_int()
  }
}
