# Offline document search

A MoonBit search library consumed by ArkTS through MoonOHOS.

- `core/`: tokenizer (ASCII words, CJK uni/bi-grams), inverted index, BM25 ranking,
  snippets. `build_index` reads bundled documents with `@rawfile`, logs progress with
  `@hilog` and checks `@task` cancellation; it is exported as `async` + `raises`.
- `moonohos.json`: version 2 manifest with a `SearchIndex` handle and a `Hit` record.
- `harmony/search/`: HAR module; `SearchSession` wraps open, cancel, search and close.

```bash
moon test --target native                                   # 7 unit tests, no SDK
moonohos build --config moonohos.json --sdk "$DEVECO/sdk" --out _build/dist
moonohos har --dist _build/dist --module harmony/search --assemble --deveco "$DEVECO"
```

The consuming app is [../search-app](../search-app).
