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
