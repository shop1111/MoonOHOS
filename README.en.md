# MoonOHOS: HarmonyOS Native modules in MoonBit

[![Windows](https://github.com/shop1111/MoonOHOS/actions/workflows/windows.yml/badge.svg)](https://github.com/shop1111/MoonOHOS/actions/workflows/windows.yml)
[![Linux and macOS](https://github.com/shop1111/MoonOHOS/actions/workflows/cross-platform.yml/badge.svg)](https://github.com/shop1111/MoonOHOS/actions/workflows/cross-platform.yml)
[![Mooncakes](https://img.shields.io/badge/mooncakes-shop1111%2Fmoonohos-orange)](https://mooncakes.io/docs/shop1111/moonohos)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)

[中文](README.md) | English

Write the reusable core of a HarmonyOS app (search, parsing, computation) in
MoonBit. MoonOHOS generates the Node-API bridge and ArkTS types, cross-compiles
for both device ABIs, links HarmonyOS platform APIs, and packages everything as a
HAR that any Stage app can depend on. ArkTS keeps the UI and system interaction.

```typescript
import textkit, { CancelToken } from '@alice/textkit';

const token: CancelToken = textkit.createCancelToken();
const words: number = await textkit.count_words(longText, token); // runs on a worker thread
token.cancel();                                                    // e.g. when the page closes
```

## What you get

| Layer | What MoonOHOS does | Docs |
|---|---|---|
| Bridge generation | Int/Double/Bool/String/Bytes/Array/struct conversion both ways, `.d.ts` generation, manifest checked against `.mbti` | [Manifest](#manifest-moonohosjson) |
| HarmonyOS runtime | Worker-thread async exports, `CancelToken`, handle lifecycle (close, finalizer, env cleanup), business errors | [ASYNC-THREADING.md](docs/ASYNC-THREADING.md) (Chinese) |
| Platform APIs | `moonohos.native.json` for controlled C dependencies; packages `hilog`, `rawfile`, `task` | [NATIVE-EXTENSIONS.md](docs/NATIVE-EXTENSIONS.md) (Chinese) |
| Distribution | `init`, `build`, `har`, `verify`; SHA-256 and ELF verification of every package | [Commands](#commands) |

How it relates to napi-mbt (desktop Node.js) and ohos-rs (Rust):
[COMPARISON.md](docs/COMPARISON.md). Test evidence:
[VALIDATION-0.4.md](docs/VALIDATION-0.4.md).

## Requirements

| Component | Requirement | Notes |
|---|---|---|
| MoonBit | moonc **≥ 0.10.16** | Tested with Moon `0.1.20261028` and moonc `v0.10.18+6c83a7f62`; newer releases work and `doctor` marks them untested |
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
moonohos har --dist _build/dist --module harmony/textkit --assemble --deveco "$DEVECO"
```

Generated project:

```text
textkit/
  moon.work            # workspace; --ohos adds a local checkout of the platform module
  moonohos.json        # bridge manifest (version 2)
  core/                # MoonBit library: sync greet, async cancellable count_words (logs via HiLog)
  harmony/textkit/     # Hvigor HAR module; Index.ets re-exports the native module
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
  "handles": [{"name": "SearchIndex"}],
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
| `Unit` (result) | `void` | |
| `String` | `string` | UTF-16 code units copied as-is, including NUL and lone surrogates |
| `Bytes` | `Uint8Array` | Views on ordinary, attached ArrayBuffers; copied |
| `Array[T]` | `Array<T>` | Dense, non-Sendable; copied |
| struct | `interface` | `pub(all) struct`; own properties; copied |
| handle (`handles`) | object with `close()` / `isClosed()` | MoonBit value stays native; not nestable in arrays or structs |
| `@pkg.Type` (platform adapter) | e.g. `resourceManager.ResourceManager` | Parameter only; acquired and released by the adapter descriptor |
| `"async": true` | `(..., token?: CancelToken) => Promise<T>` | Runs on a Node-API worker thread |
| `"raises": true` | throws / rejects with `code = ERR_MOONOHOS_BUSINESS` | The MoonBit function must declare `raise` |

Every module also exports `createCancelToken()` and `moonohos_diagnostics()`.
Conversions are limited to depth 32, 1,048,576 elements and 64 MiB; violations
throw `RangeError`, wrong argument types throw `TypeError`. A MoonBit `panic`
terminates the process. Not yet supported: generics, `#value` structs, optional or
labelled parameters, Option, Int64, enums, classes and callbacks (see
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
scripts in [scripts/](scripts); see [VALIDATION-0.4.md](docs/VALIDATION-0.4.md) for
what each layer proves.

## Contributing

Issues and pull requests are welcome in English or Chinese. See
[CONTRIBUTING.md](CONTRIBUTING.md), [CHANGELOG.md](CHANGELOG.md) and
[SECURITY.md](SECURITY.md).

## License

Apache-2.0. Keep both NOTICE files when distributing built libraries and add the
license of your own MoonBit code. Third-party components:
[THIRD_PARTY.md](THIRD_PARTY.md).
