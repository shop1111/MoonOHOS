// Device check for MoonOHOS handle type tags (0.7). Plain TypeScript so the
// probe can pass deliberately wrong objects, which ArkTS typing would reject.
//
// - own:     a SearchIndex created by this module is accepted (via its method).
// - foreign: the system ResourceManager is a native object wrapped by another
//            module; it must be rejected before its pointer is unwrapped.
// - kind:    a CancelToken from this module is not a SearchIndex.
// - plain:   an ordinary object is not a MoonOHOS object.
// - method:  a declared SearchIndex method invoked with a foreign `this`.
// - close:   the built-in `close()` invoked with a foreign `this`.

function outcome(run: () => unknown, needle: string): string {
  try {
    run();
    return 'accepted';
  } catch (error) {
    const e = error as Error;
    return e.message.includes(needle) ? e.name : `${e.name}(${e.message})`;
  }
}

export async function typeTagProbe(native: any, resources: object): Promise<string> {
  const index = await native.build_index(resources, 'docs', native.createCancelToken());
  const token = native.createCancelToken();
  // Handle method (0.5) on this module's own object.
  const own: string = index.stats().documents > 0 ? 'ok' : 'empty';
  const foreign = outcome(() => native.search_now(resources, 'x', 1), 'of this module required');
  const kind = outcome(() => native.search_now(token, 'x', 1), 'of another kind');
  const plain = outcome(() => native.search_now({}, 'x', 1), 'of this module required');
  // Declared methods unwrap `this` as their handle parameter (`stats.index`).
  const method = outcome(() => index.stats.call(resources), 'stats.index: MoonOHOS object of this module required');
  const close = outcome(() => index.close.call(resources), 'called on another object');
  const after: string = native.stats(index).documents > 0 ? 'ok' : 'empty';
  index.close();
  const pass = own === 'ok' && after === 'ok' &&
    [foreign, kind, plain, method, close].every((r: string) => r === 'TypeError');
  return `${pass ? 'pass' : 'fail'} own=${own} foreign=${foreign} kind=${kind} plain=${plain} method=${method} close=${close} after=${after}`;
}

// Typed arrays (0.7): `term_idf` returns FixedArray[Double] as a Float64Array.
export async function typedArrayProbe(native: any, resources: object): Promise<string> {
  const index = await native.build_index(resources, 'docs', native.createCancelToken());
  const idf = index.term_idf('rawfile 离线 absentterm');
  index.close();
  const typed = idf instanceof Float64Array;
  const values = Array.from(idf as Float64Array).map((x: number) => x.toFixed(3)).join(',');
  const pass = typed && idf.length === 3 && idf[0] > 0 && idf[1] > 0 && idf[2] === 0;
  return `${pass ? 'pass' : 'fail'} type=${Object.prototype.toString.call(idf)} length=${idf.length} values=${values}`;
}

// Native size (0.7): the size declared for SearchIndex is reported when the
// handle is wrapped (napi_wrap_enhance) and counted until close().
export async function memoryProbe(native: any, resources: object): Promise<string> {
  const before: number = native.moonohos_diagnostics().nativeBytes;
  const index = await native.build_index(resources, 'docs_large', native.createCancelToken());
  const declared: number = native.index_bytes(index);
  const during: number = native.moonohos_diagnostics().nativeBytes;
  index.close();
  const after: number = native.moonohos_diagnostics().nativeBytes;
  const pass = declared > 0 && during - before === declared && after === before;
  return `${pass ? 'pass' : 'fail'} declared=${declared} delta=${during - before} after_close_delta=${after - before}`;
}
