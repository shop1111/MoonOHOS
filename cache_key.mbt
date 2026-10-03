///|
pub struct ContentFingerprint {
  domain : String
  name : String
  digest : String
}

///|
pub fn fingerprint(
  domain : String,
  name : String,
  data : Bytes,
) -> ContentFingerprint {
  { domain, name, digest: sha256(data), }
}

///|
pub fn ContentFingerprint::to_json(self : ContentFingerprint) -> Json {
  { "domain": self.domain, "name": self.name, "sha256": self.digest }
}

///|
pub fn content_cache_key(
  entries : Array[ContentFingerprint],
) -> String raise ConfigError {
  let sorted = entries.copy()
  sorted.sort_by((a, b) => {
    let domain = a.domain.compare(b.domain)
    if domain != 0 {
      domain
    } else {
      a.name.compare(b.name)
    }
  })
  let mut previous : (String, String)? = None
  for entry in sorted {
    if !valid_checksum(entry.digest) {
      raise Invalid("cache: invalid content digest")
    }
    if previous == Some((entry.domain, entry.name)) {
      raise Invalid("cache: duplicate input " + entry.name)
    }
    previous = Some((entry.domain, entry.name))
  }
  sha256(@utf8.encode(sorted.map(e => e.to_json()).to_json().stringify()))
}

///|
pub fn ignored_cache_component(name : String) -> Bool {
  ["_build", ".git", ".moonohos", "node_modules", "oh_modules"].contains(name)
}
