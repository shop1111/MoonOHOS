# moonohos_ohos

HarmonyOS platform packages for [MoonOHOS](https://github.com/shop1111/MoonOHOS) native modules.

| Package | Purpose | NDK library |
|---|---|---|
| `shop1111/moonohos_ohos/hilog` | `Logger::new(domain, tag)` with `debug/info/warn/error/fatal`; messages are passed as a `%{public}s` argument, never as the format string | `libhilog_ndk.z.so` |
| `shop1111/moonohos_ohos/rawfile` | `read`, `read_text`, `list` for packaged `resources/rawfile` files through a borrowed `Manager` (adapted from ArkTS `resourceManager`) | `librawfile.z.so` |
| `shop1111/moonohos_ohos/task` | `cancelled()` / `check()` observe the `CancelToken` of the running MoonOHOS async task | — |

Each package carries a `moonohos.native.json` descriptor, so the MoonOHOS CLI cross-compiles its C stub for `arm64-v8a` and `x86_64` and records it in the package manifest. Without the bridge (`moon test` on Windows/Linux/macOS) the stubs use host fallbacks: HiLog prints to stderr, `rawfile.host_manager(dir)` reads a directory, and `task.host_set_cancelled` simulates cancellation.

```moonbit
/// Counts packaged documents on a worker thread, logging progress.
pub fn count_documents(resources : @rawfile.Manager, dir : String) -> Int raise {
  let log = @hilog.Logger::new(0x4d4f, "MySearch")
  let mut characters = 0
  for name in @rawfile.list(resources, dir) {
    @task.check()
    characters += @rawfile.read_text(resources, dir + "/" + name).length()
  }
  log.info("indexed " + dir + ": " + characters.to_string() + " characters")
  characters
}
```

Toolchain: moonc >= 0.10.16 (tested with v0.10.18+6c83a7f62), HarmonyOS SDK API 26 or newer. License: Apache-2.0.
