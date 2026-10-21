///|
/// Resource manager borrowed from ArkTS for the duration of one call or task.
/// The generated bridge acquires it from `resourceManager.ResourceManager` and
/// releases it afterwards, so MoonBit code must not keep it beyond the call.
#external
pub type Manager

///|
pub(all) suberror RawFileError {
  InvalidPath(String)
  NotFound(String)
  TooLarge(String)
  ReadFailed(String)
  InvalidText(String)
}

///|
pub impl Show for RawFileError with fn output(self, logger) {
  let (kind, path) = match self {
    InvalidPath(path) => ("invalid rawfile path", path)
    NotFound(path) => ("rawfile not found", path)
    TooLarge(path) => ("rawfile exceeds 64 MiB", path)
    ReadFailed(path) => ("rawfile read failed", path)
    InvalidText(path) => ("rawfile is not UTF-8", path)
  }
  logger.write_string(kind + ": " + path)
}

///|
#borrow(manager, path)
extern "C" fn size_raw(manager : Manager, path : Bytes) -> Int = "moonohos_rawfile_size"

///|
#borrow(manager, path, buffer)
extern "C" fn read_raw(
  manager : Manager,
  path : Bytes,
  buffer : FixedArray[Byte],
  length : Int,
) -> Int = "moonohos_rawfile_read"

///|
#borrow(manager, dir, buffer)
extern "C" fn list_raw(
  manager : Manager,
  dir : Bytes,
  buffer : FixedArray[Byte],
  capacity : Int,
) -> Int = "moonohos_rawfile_list"

///|
#borrow(root)
extern "C" fn host_raw(root : Bytes) -> Manager = "moonohos_rawfile_host"

///|
/// Relative resource paths under `resources/rawfile`, without `..` segments.
fn checked_path(path : String, allow_root~ : Bool) -> Bytes raise RawFileError {
  if (path == "" && !allow_root) ||
    path.has_prefix("/") ||
    path.contains("\\") ||
    path.contains("\u{0}") ||
    path.split("/").any(part => part == ".." || (part == "" && path != "")) {
    raise InvalidPath(path)
  }
  @utf8.encode(path + "\u{0}")
}

///|
/// Reads one packaged resource file, for example `docs/guide.md`.
pub fn read(manager : Manager, path : String) -> Bytes raise RawFileError {
  let name = checked_path(path, allow_root=false)
  let size = size_raw(manager, name)
  if size == -2 {
    raise TooLarge(path)
  }
  if size < 0 {
    raise NotFound(path)
  }
  let buffer = FixedArray::make(size, b'\x00')
  if size > 0 && read_raw(manager, name, buffer, size) != size {
    raise ReadFailed(path)
  }
  Bytes::from_array(buffer[:])
}

///|
pub fn read_text(manager : Manager, path : String) -> String raise RawFileError {
  let data = read(manager, path)
  @utf8.decode(data, ignore_bom=true) catch {
    _ => raise InvalidText(path)
  }
}

///|
/// Lists entry names of a resource directory (`""` is the rawfile root).
pub fn list(
  manager : Manager,
  dir : String,
) -> Array[String] raise RawFileError {
  let name = checked_path(dir, allow_root=true)
  let needed = list_raw(manager, name, FixedArray::make(0, b'\x00'), 0)
  if needed == -2 {
    raise TooLarge(dir)
  }
  if needed < 0 {
    raise NotFound(dir)
  }
  let buffer = FixedArray::make(needed, b'\x00')
  if list_raw(manager, name, buffer, needed) != needed {
    raise ReadFailed(dir)
  }
  let text = @utf8.decode(Bytes::from_array(buffer[:])) catch {
    _ => raise InvalidText(dir)
  }
  let names = text
    .split("\n")
    .filter(s => s != "")
    .map(s => s.to_owned())
    .to_array()
  names.sort()
  names
}

///|
/// Host-only manager rooted at a directory, for `moon test` and host checks.
/// It is never released; on HarmonyOS it reads nothing.
pub fn host_manager(root : String) -> Manager {
  host_raw(@utf8.encode(root + "\u{0}"))
}

///|
pub extend RawFileError with Show::{to_string, output}
