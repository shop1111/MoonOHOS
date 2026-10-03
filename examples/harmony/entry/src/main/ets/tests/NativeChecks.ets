import native from 'libmoonohos.so';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { runContainerChecks } from './ContainerChecks';

function requireValue(condition: boolean, name: string): void {
  if (!condition) {
    throw new Error(name);
  }
}

function expectRange(name: string, action: () => void): void {
  let caught: boolean = false;
  try {
    action();
  } catch (error) {
    const failure = error as Error;
    requireValue(failure.name === 'RangeError', name + ': exception type');
    caught = true;
  }
  requireValue(caught, name + ': exception missing');
}

export function runNativeChecks(): string {
  requireValue(native.add(20, 22) === 42, 'add');
  requireValue(native.add(-2, 1) === -1, 'negative');
  requireValue(native.add(-2147483648, 0) === -2147483648, 'Int minimum');
  requireValue(native.add(2147483647, 0) === 2147483647, 'Int maximum');
  requireValue(native.add(2147483647, 1) === -2147483648, 'Int wrapping');
  requireValue(native.scale(1.5, 2) === 3, 'Double');
  requireValue(native.negate(true) === false && native.negate(false) === true, 'Bool');
  native.ping();
  expectRange('fraction', () => { native.add(0.5, 1); });
  expectRange('overflow', () => { native.add(2147483648, 0); });
  expectRange('NaN', () => { native.add(Number.NaN, 0); });
  expectRange('Infinity', () => { native.scale(Number.POSITIVE_INFINITY, 1); });
  expectRange('non-finite result', () => { native.scale(1e308, 1e308); });
  const references: number = runReferenceChecks();
  const containers: number = runContainerChecks();
  const repeatedText: string = '中文😀\u0000尾';
  const repeatedBytes: Uint8Array = new Uint8Array([0, 127, 255]);
  for (let index: number = 0; index < 1000; index++) {
    requireValue(native.add(index, 1) === index + 1, 'repeat');
    requireValue(native.echo_text(repeatedText) === repeatedText, 'text repeat');
    requireBytes(native.echo_bytes(repeatedBytes), repeatedBytes, 'bytes repeat');
    requireValue(native.describe_bytes('bytes=', repeatedBytes) === 'bytes=3', 'mixed repeat');
  }
  // Emit after startup traffic settles; device HiLog can throttle a busy process.
  setTimeout(() => {
    hilog.info(0x0000, 'MoonOHOS', 'MOONOHOS_RUNTIME_PASS version=0.3.0 add=42 scalar_checks=13 reference_checks=%{public}d container_checks=%{public}d repeated_calls=1000', references, containers);
  }, 1500);
  return '13 项标量 + ' + references + ' 项引用 + ' + containers + ' 项容器检查通过\n连续调用 1000 次';
}

function requireBytes(left: Uint8Array, right: Uint8Array, name: string): void {
  requireValue(left.length === right.length, name + ': length');
  for (let index: number = 0; index < right.length; index++) {
    requireValue(left[index] === right[index], name + ': byte ' + index);
  }
}

function runReferenceChecks(): number {
  let checks: number = 0;
  const textCases: string[] = ['', '中文', '😀🚀', 'A\u0000B', '\uD800X', 'X\uDC00', '文'.repeat(65536)];
  for (let index: number = 0; index < textCases.length; index++) {
    requireValue(native.echo_text(textCases[index]) === textCases[index], 'UTF16 ' + index);
    checks++;
  }
  requireValue(native.join_text('中文', '😀\u0000尾') === '中文😀\u0000尾', 'join text'); checks++;
  const empty: Uint8Array = new Uint8Array(0);
  requireBytes(native.echo_bytes(empty), empty, 'empty bytes'); checks++;
  const all: Uint8Array = new Uint8Array(256);
  for (let index: number = 0; index < all.length; index++) { all[index] = index; }
  requireBytes(native.echo_bytes(all), all, 'all byte values'); checks++;
  const partial: Uint8Array = all.subarray(17, 48);
  const copied: Uint8Array = native.echo_bytes(partial);
  requireBytes(copied, partial, 'offset view'); checks++;
  copied[0] = 99;
  requireValue(partial[0] === 17 && all[17] === 17, 'independent return'); checks++;
  requireBytes(native.concat_bytes(new Uint8Array([0, 255]), new Uint8Array([127])), new Uint8Array([0, 255, 127]), 'concat bytes'); checks++;
  requireValue(native.describe_bytes('bytes=', partial) === 'bytes=31', 'mixed references'); checks++;
  return checks;
}
