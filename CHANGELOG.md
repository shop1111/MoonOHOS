# Changelog

All notable changes to MoonOHOS are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/) (pre-1.0: minor versions may break).

## [Unreleased]

### Added
- `Int64` parameters, results, array elements and record fields map to ArkTS
  `bigint` (lossless; out-of-range values throw `RangeError`). Host ASan suite
  `wide_core` / `wide_bridge.cpp`.
- `T?` / `Option[T]` maps to `T | undefined` for parameters, results, array
  elements and record fields (`field?: T`; missing, `undefined` and `null` read
  as `None`). Options cross the C boundary as zero- or one-element arrays built
  by the generated MoonBit wrapper, so no compiler-internal layout is assumed.
  Host ASan suite `option_core` / `option_bridge.cpp`.
- Payload-free enums declared under `"enums"` map to ArkTS string literal
  unions (`export type Level = 'Debug' | 'Info'`), including record fields,
  arrays and Options. Values cross C as `Int` tags converted by a generated
  `match`; unknown names throw `TypeError`; cases are checked against `.mbti`.
  The HAR facade re-exports the type. Host ASan suite `enum_core` /
  `enum_bridge.cpp`.

- Platform packages `deviceinfo` (device and OS properties), `netconn`
  (default network, metered) and `vibrator` (play, cancel), with host
  fallbacks and tests; `libnet_connection.so` and `libohvibrator.z.so` join the
  NDK allow-list. Cross-compiled and ELF-verified for both ABIs.

### Fixed
- Record field types are compared by name during interface verification, so
  enum fields declared in the manifest match the `.mbti`.

## [0.4.1] - 2026-10-31

### Added
- Linux and macOS support for the CLI: executable names, `HOME` fallback for
  the Moon home, DevEco Studio layouts for Windows, macOS (`.app`) and the
  command-line tools, case-sensitive paths on Linux.
- CI on Ubuntu and macOS (format, strict checks, tests, interface diff, CLI
  build, SDK-free `init → check → inspect → plan`) and a non-blocking job on the
  latest MoonBit release.
- `moonohos help`, `moonohos <command> --help`; diagnostics carry a category
  code and next-step hints.
- English README, examples overview, CONTRIBUTING, SECURITY, issue and PR
  templates.

### Changed
- Toolchain requirement is now a floor: **moonc ≥ 0.10.16** (tested with Moon
  `0.1.20261028` / moonc `v0.10.18+6c83a7f62`). `build`, `doctor` and package
  verification share one definition in `environment.mbt`; newer compilers are
  accepted and `doctor` lists them under `untested`.
- HarmonyOS SDK API 26 **or newer** is accepted (was exactly 26).
- Migrated to the current core API: `Json(value)` instead of `.to_json()` on
  standard collections, `StringBuilder()`, `@debug.debug_inspect`.
- CI pins the tested toolchain.

- The README inside each build output describes 0.4 behaviour instead of 0.3.
- Scripts read the DevEco Studio location from `DEVECO_STUDIO`.

### Fixed
- `.mbti` files produced by moonc ≥ 0.10.16 spell `Int` as `Int32`; manifest
  verification and type parsing now accept both spellings (but not `UInt32`).
- `init --ohos` on another Windows drive produced an unusable workspace; it is
  now rejected with an explanation.

## [0.4.0] - 2026-10-21

### Added
- HarmonyOS runtime: `"async": true` exports run MoonBit on a Node-API worker
  thread behind a process gate, with `CancelToken` cancellation.
- Opaque handles (`handles`) with `close()`, finalizers and env-cleanup release.
- Business errors: `"raises": true` maps MoonBit `raise` to `ERR_MOONOHOS_BUSINESS`.
- Controlled native dependencies through `moonohos.native.json`.
- Platform module `shop1111/moonohos_ohos`: `hilog`, `rawfile`, `task`.
- `moonohos init` project template and `moonohos har [--assemble]` HAR packaging.
- Offline document search example (`examples/search`, `examples/search-app`).
- Manifest version 2 (workspace, handles, async, raises).

## [0.3.0] - 2026-10-03

### Added
- Arrays and nested records bridged through compiler-generated accessors.
- Package interface (`.mbti`) parsing and semantic signature verification.
- Content-keyed build cache with verified hits and corruption recovery.
- `verify` command: SHA-256 and ELF64 checks without the SDK.
- Structured diagnostics and bounded external processes with phase logs.

### Fixed
- Bounded shared type analysis; tighter release verification.

## [0.2.0] - 2026-10-03

### Added
- First public release: synchronous scalar, `String` and `Bytes` bridge,
  `.d.ts` generation and dual-ABI (`arm64-v8a`, `x86_64`) builds.

[0.4.1]: https://github.com/shop1111/MoonOHOS/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/shop1111/MoonOHOS/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/shop1111/MoonOHOS/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/shop1111/MoonOHOS/releases/tag/v0.2.0
