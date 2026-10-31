# Examples / 示例

| Example | What it shows | Needs SDK |
|---|---|---|
| [core](core) | Smallest bridge: scalars, `String`, `Bytes`, arrays and nested structs (`moonohos.json` at the repo root points here) | `check`/`inspect`: no; `build`: yes |
| [search](search) | Real module: offline document search with async indexing, cancellation, HiLog and RawFile; packaged as a HAR | `build`/`har`: yes |
| [search-app](search-app) | Standalone Stage app that depends only on `search.har` | DevEco |
| [harmony](harmony) | Type-conversion regression app for the `core` package (0.3 manual integration) | DevEco |

## Run without the SDK

```bash
moon build --target native --release cmd/moonohos
cli=_build/native/release/build/cmd/moonohos/moonohos      # .exe on Windows
(cd examples/core && moon test --target native)
(cd examples/search && moon test --target native)
$cli inspect --json                                          # reads ./moonohos.json -> examples/core
$cli check --config examples/search/moonohos.json --json
```

## Build and run on HarmonyOS

```powershell
.\scripts\build_search.ps1 -DevEco '<DevEco Studio>'        # CLI build -> HAR -> 2000 synthetic docs -> HAP
.\scripts\verify_search_device.ps1                           # install and run twice on the emulator
.\scripts\build_example.ps1 -DevEco '<DevEco Studio>'        # regression app for examples/core
```
