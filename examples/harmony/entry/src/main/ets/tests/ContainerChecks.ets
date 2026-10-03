import native, { Sample, SampleMeta, Analysis } from 'libmoonohos.so';

function requireContainer(condition: boolean, message: string): void {
  if (!condition) { throw new Error(message); }
}

function expectContainerType(action: () => void): void {
  let caught: boolean = false;
  try { action(); } catch (error) {
    const failure = error as Error;
    requireContainer(failure.name === 'TypeError', 'container TypeError');
    caught = true;
  }
  requireContainer(caught, 'missing container exception');
}

export function sampleBatch(): Sample[] {
  const meta: SampleMeta = { active: true, source: 'ArkTS' };
  const first: Sample = { label: '中文🌙\u0000样本', values: [20, 22], meta: meta, bytes: new Uint8Array([0, 255]) };
  const second: Sample = { label: 'second', values: [-2, 1.5, 0.5], meta: meta, bytes: new Uint8Array(0) };
  return [first, second];
}

export function runContainerChecks(): number {
  const input: Sample[] = sampleBatch();
  const copied: Sample[] = native.echo_samples(input);
  requireContainer(copied.length === 2 && copied[0].label === input[0].label, 'records and UTF16');
  requireContainer(copied[0].values[1] === 22 && copied[0].meta.source === 'ArkTS', 'nested record');
  requireContainer(copied[0].bytes[1] === 255, 'nested bytes');
  copied[0].values[0] = 999;
  copied[0].meta.source = 'changed';
  copied[0].bytes[0] = 99;
  requireContainer(input[0].values[0] === 20 && input[0].meta.source === 'ArkTS' && input[0].bytes[0] === 0, 'independent output');
  const result: Analysis = native.analyze_samples(input);
  requireContainer(result.count === 2 && result.total === 42, 'batch total');
  requireContainer(result.groups.length === 2 && result.groups[1][1] === 1.5, 'nested array');
  requireContainer(result.labels[0] === input[0].label && result.meta.source === 'MoonBit', 'analysis record');
  const empty: Analysis = native.analyze_samples([]);
  requireContainer(empty.count === 0 && empty.total === 0 && empty.groups.length === 0, 'empty containers');
  input[1].meta.active = false;
  // Both inputs share a non-cyclic record. It is copied separately for each occurrence.
  const repeated: Sample[] = native.echo_samples([input[0], input[0]]);
  repeated[0].meta.source = 'one';
  requireContainer(repeated[1].meta.source === 'ArkTS', 'shared input copies');
  const holes: number[] = new Array<number>(2);
  const invalid: Sample = { label: 'holes', values: holes, meta: { active: true, source: 'test' }, bytes: new Uint8Array(0) };
  expectContainerType(() => { native.echo_samples([invalid]); });
  for (let index: number = 0; index < 1000; index++) {
    requireContainer(native.echo_samples(input)[0].values[1] === 22, 'container repeat');
    requireContainer(native.analyze_samples(input).groups.length === 0, 'shared inactive input');
  }
  return 10;
}
