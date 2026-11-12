# Changelog

All notable changes to MoonOHOS are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/) (pre-1.0: minor versions may break).

## [Unreleased]

## [0.9.0] - 2026-11-12

### Added
- `shop1111/moonohos_ohos/surface` (0.9 phase 1, docs/XCOMPONENT.md): opens
  the NativeWindow of an ArkUI XComponent from the surface id ArkTS receives
  in `onSurfaceCreated`, sets CPU usage and RGBA 8888, and presents MoonBit
  pixel arrays (`present`, `present_canvas`; rows copied by stride, fence
  awaited, requested buffer size re-applied after ArkUI resets it on surface
  changes). `VSync::request_frame` runs a MoonBit closure on the VSync
  thread through the MoonOHOS gate. `Canvas` (clear, rect, circle) and
  `rgba` are pure MoonBit. `libnative_window.so` and `libnative_vsync.so`
  join the allowlist; `verify_bindings.py` now also checks `ohos/surface`.
- Search example: an XComponent animated from MoonBit (bouncing ball, touch
  markers, frame bar) that follows rotation; the emulator scenario taps it
  and checks frame rate, buffer size, touch delivery and release
  (docs/VALIDATION-0.9.md).
- `sys/drawing` (0.9 phase 2): Native Drawing generated from 16
  `native_drawing/` headers, 322 functions (canvas, bitmap, brush, pen,
  path, rect, round rect, point, color, matrix, font, typeface, text blob,
  shader effects); `libnative_drawing.so` allowlisted.
- `Surface::draw(render)`: binds a Native Drawing canvas directly to the
  window buffer (no copy), runs `render` and queues the buffer; the canvas
  handle is invalidated when `render` returns. The search example draws its
  frames this way (gradient shader, anti-aliased shapes, text) and switches
  to the CPU canvas during the probe so both paths run on the emulator.
- bindgen: consecutive `const E *` inputs (32/64-bit integers, float,
  double) followed by a size/count/len parameter become `FixedArray[E]`
  parameters sharing that length (gradients, glyph widths).

- OpenGL ES (0.9 phase 3): `shop1111/moonohos_ohos/gl` creates an EGL
  window surface and an ES 3 context from an XComponent surface id;
  `GlSurface::frame` makes it current on the calling thread, sets the
  viewport, runs the callback, swaps and releases it. Helpers cover the GL
  calls that take pointers (shader source, program linking with info logs,
  buffer/vertex array/texture/framebuffer names, float buffer data, vertex
  attribute offsets, matrix uniforms, `read_pixels`, `get_integers`) plus
  common `GL_*` constants. `sys/gles` is generated from `GLES3/gl3.h`
  (135 functions); `libEGL.so` and `libGLESv3.so` are allowlisted. The
  search example renders a rotating triangle in a second XComponent and
  checks the read-back center pixel on the emulator.
- bindgen spec field `libraries`: only these system libraries are searched
  for exports (GL symbols are also exported by internal libraries).

### Fixed
- bindgen: a non-const scalar pointer after a length-like integer parameter
  (`glGenBuffers(GLsizei n, GLuint *)`) was bound as a single output and
  would have been written past; it is now reported as an output array. `n`
  counts as a length name.
- bindgen: MoonBit's reserved words (`ref`, ...) are escaped like keywords.
- bindgen: a parameter named like a local of the generated C stub (`r`,
  `object`) redefined it and failed to compile
  (`OH_Drawing_BrushSetColor4f(..., float r, ...)`); such parameters now get
  a trailing `_` (`sys/hidebug`'s `destroy_backtrace_object(object_)`).

### Known issues
- Exported functions become C symbols `moonohos_<name>`, which can collide
  with hand-written platform stubs (`moonohos_rawfile_read`, ...). The new
  surface package uses `moonohos_ohos_*`; the bridge does not detect
  collisions yet.

## [0.8.0] - 2026-11-12

### Added
- `moonohos bindgen --spec <moonohos.bindgen.json> --sdk <SDK>`: generates a
  MoonBit package, C stub, native descriptor and coverage report from
  HarmonyOS SDK headers. Declarations come from the SDK clang's JSON AST;
  each function is matched to the system library that exports it on both
  ABIs. Values, enums (with `Other(Int)`), flat structs, `const char *`,
  byte inputs, scalar and string outputs and error-code results (`SysError`)
  are generated, plus handles and callbacks (below); variadic functions and
  buffers of unknown length are skipped with a reason. See docs/BINDGEN.md.
- 14 generated packages under `shop1111/moonohos_ohos/sys/`: accesstoken,
  battery, bluetooth, deviceinfo, display, hidebug, hitrace, osaccount, qos,
  sensor, syscap, timeservice, vibrator, wifi (160 functions, 15 skipped).
  Their libraries join the system library allowlist.
- `scripts/generate_bindings.py` regenerates them; `scripts/verify_bindings.py`
  compiles every stub with `-Werror` against the SDK headers and links it with
  `--no-undefined` for both ABIs.
- Search example: `platform_report()` calls 19 generated functions; the
  emulator scenario checks the results (docs/VALIDATION-0.8.md).
- bindgen handles: structs passed as `T **`, returned as `T *`, given to
  callbacks or used opaquely become MoonBit external objects. Handles from
  Create functions with a paired Destroy are owned (explicit destroy or
  finalizer); use after destroy raises `SysError::Closed`; complete structs
  get field getters; `E **data, <int> *length` outputs become `FixedArray[E]`.
- bindgen callbacks: function-pointer parameters take MoonBit closures,
  dispatched through eight C trampolines per site and released by the
  matching Unregister or with the handle they were set on. SDK threads enter
  the MoonOHOS gate (`moonohos_gate_enter/leave`, now exported by the bridge).
- Display handles, the display listener and an ambient-light sensor
  subscription ran on the emulator (docs/VALIDATION-0.8.md).

### Fixed
- `moonohos build` dropped moonc's `-all-pkgs` table when replaying the
  dry-run plan, so MoonBit code calling methods of prelude aliases such as
  `Float` failed with "package moonbitlang/core/float is not imported" while
  `moon check` passed. The CLI (and the host-test emit tool) now writes the
  table Moon would have written. The 0.7 advice to import
  `moonbitlang/core/float` for `FixedArray[Float]` is no longer needed.

## [0.7.0] - 2026-11-11

Breaking: `build` and `doctor` require moonc >= 0.10.20, and the public
`ValueType` enum gains four typed-array cases (exhaustive matches need new arms).

### Added
- Typed arrays: `FixedArray[Double]`, `FixedArray[Float]`, `FixedArray[Int]`
  and `FixedArray[Int64]` map to `Float64Array`, `Float32Array`, `Int32Array`
  and `BigInt64Array`. Element storage is copied in one block; views at an
  offset are accepted, other element types, plain arrays, Sendable and
  detached buffers are TypeErrors, and NaN/Infinity cross unchanged. They work
  as parameters, results, record fields, array elements, Option, async results
  and callback arguments (`typed_bridge.cpp`).
- Native size reporting: a handle entry may name `"size"`, a synchronous
  `(Handle) -> Int` function. It is called once, under the gate, when the
  handle is created, and the bytes are reported to the ArkTS GC with
  `napi_wrap_enhance`. HarmonyOS does not export `napi_adjust_external_memory`,
  which napi-mbt exposes on Node.
- Several ArkTS environments: the module can be loaded on the UI thread, in
  Workers and in TaskPool tasks; each env keeps its own state, handles and
  tasks (`env_bridge.cpp`: separate state, Worker teardown while tasks are
  pending, four envs calling concurrently).
- `moonohos_diagnostics()` reports `liveEnvs` and `nativeBytes`.
- Search example: `index_texts` (in-memory documents, used from a Worker and
  TaskPool), `term_idf` (a `Float64Array` method) and a declared size for
  `SearchIndex`.

### Changed
- README, README.en and COMPARISON describe the new direction: the bridge stays
  focused on mobile UI apps (MoonBit on background threads), and new work goes
  to system APIs, XComponent graphics and project integration. COMPARISON is
  rewritten against napi-mbt v0.3.7 with source references.
- Toolchain: CI and `doctor` now use moonc `v0.10.20+65efd5b93` (Moon
  `0.1.20261104`). Types use the `#derive(...)` attribute instead of the
  deprecated trailing `derive(...)`, which moonc 0.10.18 and older cannot parse,
  so `build` and `doctor` now require moonc >= 0.10.20. Package verification
  keeps its own floor (moonc >= 0.10.16), so HARs built by 0.4.1 to 0.6.x stay
  verifiable.

### Verified
- The search example, rebuilt with moonc 0.10.20, ran twice on the x86_64
  emulator (API 26): background indexing, cancellation, ArkTS progress
  callbacks, handle methods and the new type tags (the system ResourceManager
  passed as a SearchIndex is rejected). See docs/VALIDATION-0.7.md.
- On the same emulator: `term_idf` returns a real `Float64Array`; the 20 MB
  index size reaches `nativeBytes` and is released on close; the module loads
  and runs async work in a Worker (its env is cleaned up within 100 ms of
  `terminate()`) and in three parallel TaskPool tasks.

### Fixed
- A handle released from one thread while another thread was draining the
  release queue could stay unreleased until the next MoonBit call (the gate's
  retry did not re-check the queue after unlocking). Found by `env_bridge.cpp`
  with four concurrent envs (2 of 25 runs); 60 of 60 runs pass after the fix.
- Package manifests record only the first line of `moon version` /
  `moonc -v`; Moon 0.1.20261104 appends feature-flag lines.
- Handles and `CancelToken` objects carry a per-module type tag
  (`napi_type_tag_object`, derived from the package and `nativeModule`). Objects
  wrapped by another native module, including another MoonOHOS module, are now
  rejected with a TypeError before their native pointer is read; previously
  such an object could be mistaken for one of this module's handles. The design
  follows napi-mbt.
- The callback ASan fixture no longer builds a `Ref` from a record literal,
  which moonc 0.10.20 rejects outside `moonbitlang/core/ref`; the suite
  previously stopped at code generation without a pass or fail line.

## [0.6.0] - 2026-11-01

### Added
- ArkTS callbacks: a parameter typed `(T1, T2) -> Unit` becomes
  `(arg0: T1, arg1: T2) => void`. The business function receives a generated
  MoonBit closure; arguments are copied under the gate and may be any copyable
  type (scalars, String, Bytes, arrays, records, Options, enums). Sync
  functions invoke the callback on the JS thread during the call (the callback
  may call the module again); async functions queue each call through a
  threadsafe function, deliver in order on the JS thread and settle the
  Promise after the last one. A throwing callback skips later calls, is seen
  by `@task.check()` as cancellation and becomes the call's error. Closures
  kept after their call are ignored. Host ASan suite `callback_core` /
  `callback_bridge.cpp`; the search example adds `build_index_reporting` and
  `SearchSession.open(..., onProgress)`.

### Changed
- The process gate is re-entrant on its owning thread, and cancellation scopes
  restore the previous scope, so nested calls from callbacks are safe.

## [0.5.0] - 2026-11-01

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
- Handle methods: `"handles": [{"name": "Index", "methods": ["search"]}]`
  attaches the listed functions (whose first parameter is the handle) to every
  handle object, so ArkTS can call `index.search(q)`; sync, async and raising
  functions are supported and the module functions remain. The generated
  bridge now has one `Impl_` per export behind `Call_` and `Method_` entry
  points. Host ASan suite `async_core` / `method_bridge.cpp`; the search
  example uses methods.
- `moonohos init` also generates `harmony/entry`, a demo Stage app that
  depends on the HAR module and calls `greet` and a cancellable `count_words`;
  `moonohos har --assemble --app` builds its HAP. `verify_init_flow.ps1` now
  checks the HAP contains both ABI libraries.
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

[Unreleased]: https://github.com/shop1111/MoonOHOS/compare/v0.9.0...HEAD
[0.9.0]: https://github.com/shop1111/MoonOHOS/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/shop1111/MoonOHOS/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/shop1111/MoonOHOS/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/shop1111/MoonOHOS/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/shop1111/MoonOHOS/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/shop1111/MoonOHOS/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/shop1111/MoonOHOS/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/shop1111/MoonOHOS/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/shop1111/MoonOHOS/releases/tag/v0.2.0
