# Third-party components

MoonOHOS source is licensed under Apache-2.0.

Generated libraries embed the pinned MoonBit runtime (Copyright 2026 International Digital Economy Academy, Apache-2.0) and statically link the DevEco SDK C++ libraries. Each Native package includes the runtime copyright header and the SDK-provided NOTICE.txt, preserving its component licenses and LLVM/libc++ attribution. The SDK headers and compiler binaries are not included.

The CLI depends on moonbitlang/core and moonbitlang/async; Moon resolves these dependencies. Consult their original package licenses when distributing the CLI. Third-party notices do not cover a developer's own MoonBit code: its license remains the developer's responsibility.
