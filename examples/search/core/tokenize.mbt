///|
/// One term occurrence with its UTF-16 offset in the source text.
priv struct Token {
  term : String
  offset : Int
}

///|
/// Han, kana and Hangul characters are indexed as unigrams and bigrams.
fn is_cjk(ch : Char) -> Bool {
  let c = ch.to_int()
  (c >= 0x4E00 && c <= 0x9FFF) ||
  (c >= 0x3400 && c <= 0x4DBF) ||
  (c >= 0xF900 && c <= 0xFAFF) ||
  (c >= 0x3040 && c <= 0x30FF) ||
  (c >= 0xAC00 && c <= 0xD7AF)
}

///|
fn is_word(ch : Char) -> Bool {
  ch.is_ascii_alphabetic() || (ch >= '0' && ch <= '9') || ch == '_'
}

///|
fn lower(ch : Char) -> Char {
  if ch >= 'A' && ch <= 'Z' {
    Int::unsafe_to_char(ch.to_int() + 32)
  } else {
    ch
  }
}

///|
/// Longer ASCII runs (hashes, encoded data) are not useful search terms.
let max_word : Int = 40

///|
/// Lowercase ASCII words; CJK runs as unigrams plus bigrams. In query mode a
/// CJK run of two or more characters yields bigrams only, so a phrase does not
/// match every document that merely shares one character.
fn tokenize(text : String, query~ : Bool) -> Array[Token] {
  let tokens : Array[Token] = []
  let mut word = ""
  let mut word_start = 0
  let mut previous : Char? = None
  let mut previous_offset = 0
  let mut run = 0
  let mut offset = 0
  for ch in text {
    if is_word(ch) {
      if word == "" {
        word_start = offset
      }
      word = word + lower(ch).to_string()
    } else if word != "" {
      if word.length() <= max_word {
        tokens.push({ term: word, offset: word_start, })
      }
      word = ""
    }
    if is_cjk(ch) {
      if !query {
        tokens.push({ term: ch.to_string(), offset, })
      }
      if previous is Some(prior) {
        tokens.push({
          term: prior.to_string() + ch.to_string(),
          offset: previous_offset,
        })
      }
      previous = Some(ch)
      previous_offset = offset
      run += 1
    } else {
      if query && run == 1 && previous is Some(single) {
        tokens.push({ term: single.to_string(), offset: previous_offset, })
      }
      previous = None
      run = 0
    }
    offset += ch.utf16_len()
  }
  if word != "" && word.length() <= max_word {
    tokens.push({ term: word, offset: word_start, })
  }
  if query && run == 1 && previous is Some(single) {
    tokens.push({ term: single.to_string(), offset: previous_offset, })
  }
  tokens
}

///|
/// Distinct query terms in first-occurrence order.
fn query_terms(query : String) -> Array[String] {
  let terms : Array[String] = []
  for token in tokenize(query, query=true) {
    if !terms.contains(token.term) {
      terms.push(token.term)
    }
  }
  terms
}
