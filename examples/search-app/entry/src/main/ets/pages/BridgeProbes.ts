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

// System bindings (0.8): generated `sys/*` packages called from MoonBit.
// Calls that need permissions this app lacks may report `!error`; they only
// have to return instead of crashing.
export function platformProbe(native: any, log: (line: string) => void): string {
  const lines: string[] = native.platform_report();
  const values = new Map<string, string>();
  for (const line of lines) {
    log(`MOONSEARCH_SYS ${line}`);
    const ok = line.indexOf('=');
    const bad = line.indexOf('!');
    if (ok > 0 && (bad < 0 || ok < bad)) {
      values.set(line.substring(0, ok), line.substring(ok + 1));
    }
  }
  const capacity = Number(values.get('battery.capacity'));
  const size = (values.get('display.size') ?? '0x0').split('x').map((x: string) => Number(x));
  const checks: [string, boolean][] = [
    ['battery', capacity >= 0 && capacity <= 100],
    ['display', size[0] > 0 && size[1] > 0],
    ['deviceinfo', (values.get('deviceinfo.os') ?? '') !== '' && Number(values.get('deviceinfo.api')) >= 26],
    ['syscap', values.get('syscap.hitrace') === 'true' && values.get('syscap.fake') === 'false'],
    ['timezone', (values.get('timeservice.zone') ?? '') !== ''],
    // The x86_64 emulator kernel rejects thread QoS for every process
    // (system services log "apply qos failed"); then all three calls return -1.
    ['qos', /^set=0,get=0:QOS_USER_INITIATED,reset=0$/.test(values.get('qos.roundtrip') ?? '') ||
      /^set=-1,get=-1:.*,reset=-1$/.test(values.get('qos.roundtrip') ?? '')],
    ['hitrace', (values.get('hitrace.chain') ?? '').includes('valid=true')],
    ['hidebug', /total_kb=[1-9]/.test(values.get('hidebug.memory') ?? '')],
    ['all_returned', lines.length === 19],
  ];
  const failed = checks.filter((c: [string, boolean]) => !c[1]).map((c: [string, boolean]) => c[0]);
  return `${failed.length === 0 ? 'pass' : 'fail'} calls=${lines.length} checks=${checks.length}${failed.length ? ' failed=' + failed.join(',') : ''}`;
}

// Handles and callbacks (0.8). The display listener must have fired and the
// destroyed display handle must refuse use; the light sensor result is
// recorded either way (the emulator may not provide one), but if it was
// subscribed it must also unsubscribe and destroy cleanly.
export function callbacksVerdict(handles: string[], started: string[], stopped: string[]): string {
  const value = (lines: string[], key: string): string => {
    const line = lines.find((l: string) => l.startsWith(key + '='));
    return line === undefined ? '' : line.substring(key.length + 1);
  };
  const displayEvents = Number(value(stopped, 'events.display'));
  const light = started.find((l: string) => l.startsWith('listen.light')) ?? '';
  const subscribed = light.includes('subscribed=true');
  const checks: [string, boolean][] = [
    ['primary', /^id=\d+,name=.*,size=\d+x\d+,alive=true,after_destroy=closed,live=false$/.test(value(handles, 'handle.primary'))],
    ['finalized', value(handles, 'handle.subscriber') === 'created_and_dropped=50'],
    ['listener', /^index=\d+$/.test(value(started, 'listen.display'))],
    ['display_events', displayEvents >= 1],
    ['unregister', value(stopped, 'unlisten.display') === 'ok'],
    ['light_cleanup', !subscribed || value(stopped, 'unlisten.light') === 'destroyed=0'],
  ];
  const failed = checks.filter((c: [string, boolean]) => !c[1]).map((c: [string, boolean]) => c[0]);
  return `${failed.length === 0 ? 'pass' : 'fail'} display_events=${displayEvents} light_events=${value(stopped, 'events.light')} light_subscribed=${subscribed}${failed.length ? ' failed=' + failed.join(',') : ''}`;
}
