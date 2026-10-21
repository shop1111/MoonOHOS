# Third-party components

MoonOHOS source is licensed under Apache-2.0.

Generated libraries embed the pinned MoonBit runtime (Copyright 2026 International Digital Economy Academy, Apache-2.0) and statically link the DevEco SDK C++ libraries. Each Native package includes the runtime copyright header and the SDK-provided NOTICE.txt, preserving its component licenses and LLVM/libc++ attribution. The SDK headers and compiler binaries are not included.

The CLI depends on moonbitlang/core and moonbitlang/async; Moon resolves these dependencies. Consult their original package licenses when distributing the CLI. Third-party notices do not cover a developer's own MoonBit code: its license remains the developer's responsibility.

The `ohos` platform module (hilog, rawfile, task) is part of MoonOHOS (Apache-2.0). Its stubs include HarmonyOS SDK headers at build time and link `libhilog_ndk.z.so` and `librawfile.z.so` dynamically from the device; no SDK files are redistributed. Packages produced with native dependencies record each stub's source checksum in `manifest.json`.

The offline search example uses documents written for this project (`examples/search/core/testdata`) and a large corpus generated deterministically by `scripts/make_corpus.py` from a fixed vocabulary; neither contains third-party text. The design of `init`/HAR layout and of the resource-manager and HiLog bindings follows public ohos-rs documentation (see `docs/COMPARISON.md`); no ohos-rs code is included.
