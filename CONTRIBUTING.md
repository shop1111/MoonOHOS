# Contributing to MoonOHOS

Thanks for helping MoonBit run well on HarmonyOS. Issues and pull requests are
welcome in Chinese or English.

## Ways to help

- **Report a bug**: use the bug template and include `moonohos doctor --json`
  output, your OS, and the smallest `moonohos.json` that reproduces it.
- **Request a type or platform API**: use the feature template. Platform
  packages live in [`ohos/`](ohos) and follow the pattern of `hilog` and
  `rawfile` (see [docs/NATIVE-EXTENSIONS.md](docs/NATIVE-EXTENSIONS.md)).
- **Improve docs and examples**: anything that shortens the path from
  `moonohos init` to a running app is valuable.

## Development setup

| Need | Version |
|---|---|
| MoonBit toolchain | moonc ≥ 0.10.20 (CI uses `v0.10.20+65efd5b93`) |
| Python | 3.10+ (verification scripts) |
| C/C++ compiler | MSVC on Windows (host ASan), clang or gcc elsewhere |
| DevEco Studio | 26+, only for SDK builds, HAR/HAP and device checks |

```bash
moon update
moon fmt
moon check --target native --deny-warn
moon test --target native --deny-warn
moon info --target native        # commit any pkg.generated.mbti changes
```

Also run the same `check`/`test` in `ohos/` and `examples/search/`.

With the HarmonyOS SDK available, run the end-to-end checks before touching
code generation or the CLI:

```bash
moon build --target native --release cmd/moonohos
python scripts/verify_cli.py --sdk "<DevEco>/sdk"
python scripts/verify_integration.py "<DevEco>/sdk"
python scripts/verify_containers.py async_core async_bridge.cpp
```

## Pull request checklist

- One topic per PR; commit messages follow `type: summary`
  (`feat`, `fix`, `docs`, `test`, `ci`, `chore`, `refactor`).
- New behaviour comes with tests. Generated C/C++ changes need a host ASan
  case in `tests/*_bridge.cpp` or a fixture under `fixtures/`.
- `moon fmt` leaves no diff and `pkg.generated.mbti` is up to date.
- User-visible changes get a line under *Unreleased* in
  [CHANGELOG.md](CHANGELOG.md).
- Do not commit build output (`_build/`, `.mooncakes/`, `oh_modules/`).

## Code layout

| Path | What lives there |
|---|---|
| `*.mbt` (root) | Library: manifest parsing, type graph, code generation, package policy |
| `cmd/moonohos/` | CLI (`init`, `build`, `har`, `doctor`, `check`, `inspect`, `plan`, `verify`) |
| `ohos/` | Platform module `shop1111/moonohos_ohos` (HiLog, RawFile, task) |
| `fixtures/` | Small MoonBit projects used by host verification |
| `tests/` | Node-API test doubles and ASan harnesses |
| `examples/` | Runnable examples and HarmonyOS apps |
| `scripts/` | End-to-end verification and example build scripts |

## License

By contributing you agree that your contribution is licensed under the
[Apache License 2.0](LICENSE).
