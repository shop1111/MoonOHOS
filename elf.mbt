///|
pub struct ElfInfo {
  abi : String
  dependencies : Array[String]
  imports : Array[String]
  exports : Array[String]
  soname : String?
}

///|
priv struct ElfSection {
  kind : Int
  offset : Int
  size : Int
  link : Int
  entry_size : Int
}

///|
fn binary_range(
  bytes : Bytes,
  offset : Int,
  size : Int,
) -> Unit raise ConfigError {
  if offset < 0 ||
    size < 0 ||
    offset > bytes.length() ||
    size > bytes.length() - offset {
    raise Invalid("elf: truncated or overflowing binary range")
  }
}

///|
fn elf_word(
  bytes : Bytes,
  offset : Int,
  size : Int,
) -> UInt64 raise ConfigError {
  binary_range(bytes, offset, size)
  let mut result = 0UL
  for index in 0..<size {
    result = result | (bytes[offset + index].to_uint64() << (index * 8))
  }
  result
}

///|
fn elf_offset(bytes : Bytes, offset : Int, size : Int) -> Int raise ConfigError {
  let result = elf_word(bytes, offset, size)
  if result > 2147483647UL {
    raise Invalid("elf: offsets larger than INT32_MAX are unsupported")
  }
  result.to_int()
}

///|
fn elf_string(
  bytes : Bytes,
  table : ElfSection,
  offset : Int,
) -> String raise ConfigError {
  if offset < 0 || offset >= table.size {
    raise Invalid("elf: string table index out of bounds")
  }
  let result = StringBuilder()
  let mut index = offset
  while index < table.size {
    let byte = bytes[table.offset + index]
    if byte == 0 {
      return result.to_string()
    }
    if byte.to_int() < 32 || byte.to_int() > 126 {
      raise Invalid("elf: non-ASCII dynamic string")
    }
    result.write_char(byte.to_char())
    index += 1
  }
  raise Invalid("elf: unterminated dynamic string")
}

///|
fn elf_sections(bytes : Bytes) -> Array[ElfSection] raise ConfigError {
  let offset = elf_offset(bytes, 40, 8)
  let entry_size = elf_offset(bytes, 58, 2)
  let count = elf_offset(bytes, 60, 2)
  if entry_size != 64 || count == 0 {
    raise Invalid("elf: unsupported section table")
  }
  binary_range(bytes, offset, count * entry_size)
  let sections : Array[ElfSection] = []
  for index in 0..<count {
    let start = offset + index * entry_size
    let section : ElfSection = {
      kind: elf_offset(bytes, start + 4, 4),
      offset: elf_offset(bytes, start + 24, 8),
      size: elf_offset(bytes, start + 32, 8),
      link: elf_offset(bytes, start + 40, 4),
      entry_size: elf_offset(bytes, start + 56, 8),
    }
    if section.kind != 8 {
      binary_range(bytes, section.offset, section.size)
    }
    sections.push(section)
  }
  sections
}

///|
fn linked_strings(
  sections : Array[ElfSection],
  section : ElfSection,
) -> ElfSection raise ConfigError {
  if section.link < 0 || section.link >= sections.length() {
    raise Invalid("elf: invalid linked section")
  }
  let table = sections[section.link]
  if table.kind != 3 {
    raise Invalid("elf: linked section is not a string table")
  }
  table
}

///|
fn inspect_programs(bytes : Bytes) -> Unit raise ConfigError {
  let offset = elf_offset(bytes, 32, 8)
  let entry_size = elf_offset(bytes, 54, 2)
  let count = elf_offset(bytes, 56, 2)
  if count == 0 || entry_size != 56 {
    raise Invalid("elf: missing or unsupported program headers")
  }
  binary_range(bytes, offset, count * entry_size)
  let mut dynamic = false
  for index in 0..<count {
    let start = offset + index * entry_size
    let kind = elf_offset(bytes, start, 4)
    let file_offset = elf_offset(bytes, start + 8, 8)
    let file_size = elf_offset(bytes, start + 32, 8)
    binary_range(bytes, file_offset, file_size)
    if kind == 3 {
      raise Invalid("elf: executable interpreter in shared library")
    }
    if kind == 2 {
      dynamic = true
    }
  }
  if !dynamic {
    raise Invalid("elf: shared library has no dynamic program segment")
  }
}

///|
pub fn inspect_elf(bytes : Bytes) -> ElfInfo raise ConfigError {
  binary_range(bytes, 0, 64)
  if bytes[0] != 127 || bytes[1] != 69 || bytes[2] != 76 || bytes[3] != 70 {
    raise Invalid("elf: invalid magic; host objects are not accepted")
  }
  if bytes[4] != 2 || bytes[5] != 1 || bytes[6] != 1 {
    raise Invalid("elf: requires little-endian ELF64 version 1")
  }
  if elf_word(bytes, 16, 2) != 3UL ||
    elf_word(bytes, 20, 4) != 1UL ||
    elf_word(bytes, 52, 2) != 64UL {
    raise Invalid("elf: requires an ELF64 shared object")
  }
  let abi = match elf_offset(bytes, 18, 2) {
    183 => "arm64-v8a"
    62 => "x86_64"
    _ => raise Invalid("elf: unsupported machine architecture")
  }
  inspect_programs(bytes)
  let sections = elf_sections(bytes)
  let dependencies : Array[String] = []
  let imports : Array[String] = []
  let exports : Array[String] = []
  let mut soname : String? = None
  let mut dynamic = false
  let mut symbols = false
  for section in sections {
    if section.kind == 6 {
      dynamic = true
      if section.entry_size != 16 || section.size % 16 != 0 {
        raise Invalid("elf: malformed dynamic table")
      }
      let strings = linked_strings(sections, section)
      let mut terminated = false
      for index in 0..<(section.size / 16) {
        let offset = section.offset + index * 16
        let tag = elf_word(bytes, offset, 8)
        if tag == 0UL {
          terminated = true
          break
        }
        if tag == 1UL || tag == 14UL || tag == 15UL || tag == 29UL {
          let name = elf_string(
            bytes,
            strings,
            elf_offset(bytes, offset + 8, 8),
          )
          if tag == 1UL {
            dependencies.push(name)
          } else if tag == 14UL {
            soname = Some(name)
          } else if name.contains(":") || name.has_prefix("/") {
            raise Invalid("elf: absolute runtime search path")
          }
        }
      }
      if !terminated {
        raise Invalid("elf: dynamic table lacks terminator")
      }
    } else if section.kind == 11 {
      symbols = true
      if section.entry_size != 24 || section.size % 24 != 0 {
        raise Invalid("elf: malformed dynamic symbol table")
      }
      let strings = linked_strings(sections, section)
      for index in 0..<(section.size / 24) {
        let offset = section.offset + index * 24
        let name = elf_string(bytes, strings, elf_offset(bytes, offset, 4))
        if name == "" {
          continue
        }
        if elf_word(bytes, offset + 6, 2) == 0UL {
          imports.push(name)
        } else {
          exports.push(name)
        }
      }
    }
  }
  if !dynamic || !symbols {
    raise Invalid("elf: missing dynamic metadata")
  }
  if !dependencies.contains("libace_napi.z.so") {
    raise Invalid("elf: missing HarmonyOS Node-API dependency")
  }
  if !imports.contains("napi_module_register") {
    raise Invalid("elf: missing Node-API registration symbol")
  }
  for dependency in dependencies {
    if dependency.contains("/") ||
      dependency.contains("\\") ||
      dependency.contains(":") ||
      dependency.contains(".dll") ||
      dependency == "libc++_shared.so" {
      raise Invalid(
        "elf: unexpected host or shared runtime dependency " + dependency,
      )
    }
  }
  { abi, dependencies, imports, exports, soname, }
}

///|
pub fn ElfInfo::to_json(self : ElfInfo) -> Json {
  {
    "abi": self.abi,
    "dependencies": self.dependencies.to_json(),
    "imports": self.imports.to_json(),
    "exports": self.exports.to_json(),
    "soname": self.soname.to_json(),
  }
}
