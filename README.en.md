# MoonOHOS: HarmonyOS Native modules in MoonBit

[![Windows](https://github.com/shop1111/MoonOHOS/actions/workflows/windows.yml/badge.svg)](https://github.com/shop1111/MoonOHOS/actions/workflows/windows.yml)
[![Linux and macOS](https://github.com/shop1111/MoonOHOS/actions/workflows/cross-platform.yml/badge.svg)](https://github.com/shop1111/MoonOHOS/actions/workflows/cross-platform.yml)
[![Mooncakes](https://img.shields.io/badge/mooncakes-shop1111%2Fmoonohos-orange)](https://mooncakes.io/docs/shop1111/moonohos)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)

[中文](README.md) | English

Write the native part of a HarmonyOS app in MoonBit. Heavy computation runs on a
background thread so the UI stays responsive, MoonBit code can call HarmonyOS
system APIs directly, and the result is packaged as a HAR that ArkTS imports.

```typescript
import textkit, { CancelToken } from '@alice/textkit';

const token: CancelToken = textkit.createCancelToken();
const words: number = await textkit.count_words(longText, token); // runs on a worker thread
token.cancel();                                                    // e.g. when the page closes
```

## Why use it

Most HarmonyOS apps need nothing but ArkTS. Moving part of an app to native
code pays off for:

- **CPU-heavy work**: search, parsing, compression, cryptography, image and audio processing.
- **Shared core logic**: the same code also serves other platforms.
- **NDK access**: system capabilities that only have a C interface.

The official native option is C/C++. MoonOHOS lets you use MoonBit instead: memory
safe, close to TypeScript in syntax, fast to compile, small binaries, and MoonBit
code that does not use the platform packages also compiles to Wasm and JavaScript.

It is not a good fit for:

- ordinary UI and business logic: use ArkTS;
- projects built mainly on existing C++ libraries: use C++ directly;
- projects that need a mature ecosystem: MoonBit has few libraries and the compiler is still evolving;
- code that must never take the process down: a MoonBit `panic` ends the app process.

## Architecture and status

| Layer | Purpose | Status |
|---|---|---|
| HarmonyOS runtime | ArkTS ↔ MoonBit: conversions, `.d.ts` generation, background-thread tasks, cancellation, ArkTS callbacks, handle lifecycle | **Done.** Host ASan covers everything. **Run on the x86_64 emulator** (built with moonc 0.10.20, 2026-11-11): background-thread tasks, cancellation, ArkTS progress callbacks, handle methods, handle type tags, handle lifecycle, and the 0.7 additions `Float64Array`, native size reporting and loading the module in a Worker and in TaskPool. **Not yet run on a device**: Int64, Option, enums, the other three typed arrays |
| System APIs | MoonBit calls the HarmonyOS NDK directly | **Partial**: six platform packages (`hilog`, `rawfile`, `task`, `deviceinfo`, `netconn`, `vibrator`) and a mechanism for third-party C dependencies. **Planned**: bindings generated from SDK headers to cover many more modules |
| Graphics | MoonBit renders through XComponent and handles touch | **Planned** |
| Project integration | Init, cross-compilation, HAR packaging, artifact verification | **Done**: the CLI (`init`, `build`, `har`, `verify`). **Planned**: a Hvigor plugin to build from DevEco; publishing to ohpm |

| Document | Contents |
|---|---|
| [ASYNC-THREADING.md](docs/ASYNC-THREADING.md) (Chinese) | Threading, cancellation, callbacks, lifecycle |
| [NATIVE-EXTENSIONS.md](docs/NATIVE-EXTENSIONS.md) (Chinese) | Platform packages and native dependencies |
| [COMPARISON.md](docs/COMPARISON.md) (Chinese) | Point-by-point comparison with napi-mbt and ohos-rs |
| [VALIDATION-0.7.md](docs/VALIDATION-0.7.md) (Chinese) | Emulator runs with moonc 0.10.20: async, cancellation, callbacks, type tags, typed arrays, native size, Worker/TaskPool |
| [VALIDATION-0.5.md](docs/VALIDATION-0.5.md) (Chinese) | What each test level proves |

### Relation to napi-mbt

[napi-mbt](https://github.com/unmbt/napi-mbt) is a MoonBit binding tool for
Node.js with broader general-purpose coverage than MoonOHOS. Its MoonBit code
runs only on the JS thread, background work relies on spawning Node child
processes, it does not cross-compile, and it ships npm packages. None of that
works on HarmonyOS. The MoonOHOS bridge is designed for mobile UI apps and runs
MoonBit on background threads. MoonOHOS does not aim for the breadth of a
general binding tool; its effort goes into system APIs, graphics and project
integration. See [COMPARISON.md](docs/COMPARISON.md) for the evidence.

## Requirements

| Component | Requirement | Notes |
|---|---|---|
| MoonBit | moonc **≥ 0.10.20** | Tested with Moon `0.1.20261104` and moonc `v0.10.20+65efd5b93`; newer releases work and `doctor` marks them untested. 0.10.18 and older cannot parse `#derive(...)` |
| Host | Windows x64 (fully validated); Linux and macOS (CLI and library covered by CI) | The CLI is a native MoonBit program: MSVC Build Tools on Windows, cc/clang elsewhere |
| HarmonyOS SDK | API **≥ 26** | From DevEco Studio or the command-line tools; needed by `build` and `har`, not by `init`, `check`, `inspect`, `plan` or `verify` |
| Target ABIs | `arm64-v8a`, `x86_64` | Run on the x86_64 emulator (API 26); ARM64 hardware not yet validated |

`moonohos doctor --sdk <SDK> --json` checks every item and explains what to fix.

## Quick start

`DEVECO` below is your DevEco Studio installation (`C:\Program Files\Huawei\DevEco Studio`
on Windows, `/Applications/DevEco-Studio.app` on macOS, the command-line-tools
directory on Linux).

```bash
moon install shop1111/moonohos/cmd/moonohos        # or, in this repo: moon build --target native --release cmd/moonohos
moonohos init textkit --package alice/textkit       # MoonBit module + manifest + HAR project
cd textkit
moonohos check                                      # no SDK needed: strict compile of the generated wrapper
moonohos build --sdk "$DEVECO/sdk" --out _build/dist
moonohos har --dist _build/dist --module harmony/textkit --assemble --app --deveco "$DEVECO"
```

`--app` also builds the demo app in `harmony/entry` (an unsigned debug HAP) whose page calls the synchronous `greet` and the cancellable async `count_words`; open `harmony/` in DevEco Studio to sign and run it.

Generated project:

```text
textkit/
  moon.work            # workspace; --ohos adds a local checkout of the platform module
  moonohos.json        # bridge manifest (version 2)
  core/                # MoonBit library: sync greet, async cancellable count_words (logs via HiLog)
  harmony/textkit/     # Hvigor HAR module; Index.ets re-exports the native module
  harmony/entry/       # demo Stage app depending on the HAR module
```

Use the HAR from an app's `oh-package.json5`:

```json
{"dependencies": {"@alice/textkit": "file:../textkit/harmony/textkit/build/default/outputs/default/textkit.har"}}
```

## Manifest (moonohos.json)

```json
{
  "version": 2,
  "module": "core",
  "package": "moonohos/search",
  "nativeModule": "moonsearch",
  "workspace": "moon.work",
  "handles": [{"name": "SearchIndex", "methods": ["search"]}],
  "enums": [{"name": "Mode", "cases": ["Exact", "Prefix"]}],
  "types": [{"name": "Hit", "fields": [{"name": "path", "type": "String"}, {"name": "score", "type": "Double"}]}],
  "functions": [
    {"name": "build_index", "params": [{"name": "resources", "type": "@rawfile.Manager"}, {"name": "dir", "type": "String"}],
     "return": "SearchIndex", "async": true, "raises": true},
    {"name": "search", "params": [{"name": "index", "type": "SearchIndex"}, {"name": "query", "type": "String"}, {"name": "limit", "type": "Int"}],
     "return": "Array[Hit]", "async": true}
  ]
}
```

| MoonBit | ArkTS | Notes |
|---|---|---|
| `Int` / `Double` / `Bool` | `number` / `number` / `boolean` | Int is a finite 32-bit integer (`.mbti` may spell it `Int32`); Double must be finite |
| `Int64` | `bigint` | Signed 64-bit; out-of-range bigint throws RangeError, a number throws TypeError (0.5) |
| `T?` / `Option[T]` | `T \| undefined` | Parameters, results, array elements and struct fields (declared `field?: T`; missing, `undefined` and `null` all read as `None`); no nested Option (0.5) |
| payload-free enum (`"enums"`) | string literal union, e.g. `'Debug' \| 'Info'` | Unknown names throw TypeError; cases are checked against `.mbti` (0.5) |
| `Unit` (result) | `void` | |
| `String` | `string` | UTF-16 code units copied as-is, including NUL and lone surrogates |
| `Bytes` | `Uint8Array` | Views on ordinary, attached ArrayBuffers; copied |
| `FixedArray[Double]` / `FixedArray[Float]` / `FixedArray[Int]` / `FixedArray[Int64]` | `Float64Array` / `Float32Array` / `Int32Array` / `BigInt64Array` | Element storage is copied in one block (memcpy); views at an offset are fine; another element type, plain arrays, Sendable or detached buffers throw TypeError. NaN and Infinity cross unchanged. Allowed as parameters, results, struct fields, array elements, Option, async results and callback arguments (0.7). Packages using `FixedArray[Float]` import `moonbitlang/core/float` in `moon.pkg` |
| `Array[T]` | `Array<T>` | Dense, non-Sendable; copied |
| struct | `interface` | `pub(all) struct`; own properties; copied |
| handle (`handles`) | object with `close()` / `isClosed()` | MoonBit value stays native; not nestable in arrays or structs. Functions listed in `"methods"` (handle as first parameter) also become methods: `index.search(q)` is `search(index, q)` (0.5). Objects carry a per-module type tag; objects wrapped by other native modules are rejected before their pointer is read (0.7). `"size"` names a `(Handle) -> Int` function called once when the handle is created; the bytes are reported to the ArkTS GC through `napi_wrap_enhance` (0.7) |
| `@pkg.Type` (platform adapter) | e.g. `resourceManager.ResourceManager` | Parameter only; acquired and released by the adapter descriptor |
| callback `(T1, T2) -> Unit` (parameter only) | `(arg0: T1, arg1: T2) => void` | Sync functions call it on the UI thread during the call, and it may call the module again. Async functions copy the arguments into a queue on the worker; calls run on the UI thread in order, and the Promise settles after the last one. If a callback throws, later calls are skipped, `@task.check()` sees cancellation and the call fails with that error. A closure kept after its call returns is ignored. Arguments must be copyable values (not handles, platform objects or callbacks), at most 16 (0.6) |
| `"async": true` | `(..., token?: CancelToken) => Promise<T>` | Runs on a Node-API worker thread |
| `"raises": true` | throws / rejects with `code = ERR_MOONOHOS_BUSINESS` | The MoonBit function must declare `raise` |

Every module also exports `createCancelToken()` and `moonohos_diagnostics()`
(live handles, task counters, `liveEnvs`, `nativeBytes`, ...).

A module can be loaded on the UI thread, in Workers and in TaskPool tasks (0.7):
each ArkTS environment gets its own module state, handles and tasks belong to
the environment that created them, and a terminated Worker closes only its own
handles and cancels only its own tasks. All environments share one MoonBit
runtime and enter it one at a time (see
[ASYNC-THREADING.md](docs/ASYNC-THREADING.md)).

In calls whose parameters or result contain arrays, structs or Option,
conversions are limited to depth 32, 1,048,576 elements and 64 MiB; in other
calls String, Bytes and typed arrays are limited by their 32-bit length only.
Violations throw `RangeError`, wrong argument types throw `TypeError`. A MoonBit `panic`
terminates the process. Not yet supported: generics, `#value` structs, optional or
labelled parameters, enums with payloads and callbacks that return values (see
[CHANGELOG](CHANGELOG.md) for progress).

## Commands

```text
moonohos init <dir> [--name <module>] [--package owner/name] [--ohos <path>] [--json]
moonohos build --sdk <SDK> [--config moonohos.json] [--abi arm64-v8a,x86_64] [--out <dir>] [--dry-run] [--cache] [--json]
moonohos har --dist <package> --module <HAR module> [--assemble --deveco <DevEco Studio>] [--json]
moonohos doctor [--sdk <SDK>] [--json]
moonohos check | inspect | plan [--config moonohos.json] [--json]
moonohos verify --out <package> [--json]
moonohos <command> --help
```

- `build` compiles both ABIs into a new output directory. `--dry-run` validates the
  manifest and toolchain only. `--cache` reuses a verified build whose content key
  (sources, dependencies, manifest, compiler, runtime, SDK, generator) matches.
- `har` verifies the package, then writes libraries, type package, NOTICE files,
  provenance (`moonohos-har.json`) and an ArkTS facade into the HAR module;
  `--assemble` runs ohpm and hvigor `assembleHar` and reports the HAR's SHA-256.
- Exit codes: 0 success, 2 invalid arguments, 3 failure. With `--json`, failures
  carry `diagnostics[].code` (e.g. `toolchain`, `interface`, `config`, `io`) and
  next-step hints in `context`.

## Example: offline document search

- [examples/search/core](examples/search/core): MoonBit search library. Tokenizes
  ASCII words and CJK uni/bi-grams, builds an inverted index, ranks with BM25, reads
  bundled documents through `@rawfile`, logs with `@hilog`, and checks `@task`
  cancellation while indexing.
- [examples/search/harmony/search](examples/search/harmony/search): HAR module with a
  `SearchSession` that opens, cancels, searches and closes.
- [examples/search-app](examples/search-app): standalone Stage app that only depends
  on `search.har`.

## Validation

| CI | Coverage |
|---|---|
| Windows (pinned toolchain) | Format, strict checks, tests, interface diff, CLI build, packaging, production-code gate, host AddressSanitizer runs of generated bridges |
| Linux, macOS | Format, strict checks, framework/platform/example tests, interface diff, CLI build, SDK-free `init → check → inspect → plan` |
| Latest MoonBit | Check and test against the newest toolchain as an early warning (non-blocking) |

SDK builds, HAR/HAP assembly and emulator runs are executed locally with the
scripts in [scripts/](scripts); see [VALIDATION-0.7.md](docs/VALIDATION-0.7.md) for
the emulator run and [VALIDATION-0.5.md](docs/VALIDATION-0.5.md) for what each
layer proves.

## Roadmap

Done: 0.4 HarmonyOS runtime, platform packages and HAR distribution; 0.5 Int64, Option, payload-free enums, handle methods, `deviceinfo` / `netconn` / `vibrator`, the `init` demo app and the CLI on Linux/macOS; 0.6 ArkTS callbacks; 0.7 (in progress) handle type tags, typed arrays, native size reporting, Worker/TaskPool loading.

Next, layer by layer (priorities are open for discussion in issues):

1. **HarmonyOS runtime**: run Int64, Option, enums and the platform packages on the emulator. The four additions borrowed from napi-mbt's designs (handle type tags, native size reporting, per-environment state, typed arrays) are done and ran on the emulator (0.7). Full general-purpose binding coverage is not a goal.
2. **System APIs**: a binding generator driven by SDK headers that emits MoonBit declarations and C shims, topped by hand-written safe wrappers (resource release, error codes as `raise`). The first batch targets 8–10 modules that need no special permission, such as files, cryptography, pasteboard and HiTrace.
3. **Graphics**: XComponent and Native Drawing, so MoonBit draws 2D content and handles touch events, with an example app.
4. **Project integration**: a Hvigor plugin that builds MoonBit modules from DevEco; publishing HARs to ohpm; turning pure-MoonBit Mooncakes packages into HARs in one step.
5. **Other**: ARM64 hardware validation and a bilingual docs site.

## Contributing

Issues and pull requests are welcome in English or Chinese. See
[CONTRIBUTING.md](CONTRIBUTING.md), [CHANGELOG.md](CHANGELOG.md) and
[SECURITY.md](SECURITY.md).

## License

Apache-2.0. Keep both NOTICE files when distributing built libraries and add the
license of your own MoonBit code. Third-party components:
[THIRD_PARTY.md](THIRD_PARTY.md).
