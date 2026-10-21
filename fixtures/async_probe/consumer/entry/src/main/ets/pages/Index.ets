import { hilog } from '@kit.PerformanceAnalysisKit';
import { systemDateTime } from '@kit.BasicServicesKit';
import { MessageEvents, worker } from '@kit.ArkTS';
import probe, { ProbeResult } from '@moonohos/asyncprobe';

const TAG: string = 'MoonOHOSProbe';

function log(message: string): void {
  hilog.info(0x4d4f, TAG, '%{public}s', message);
}

function now(): number {
  return systemDateTime.getTime(false);
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, ms);
  });
}

@Entry
@Component
struct Index {
  @State status: string = 'probe running';

  aboutToAppear(): void {
    this.run().catch((error: Error) => {
      log(`PROBE_FAIL ${error.message}`);
      this.status = `failed: ${error.message}`;
    });
  }

  async run(): Promise<void> {
    const mainTid: number = probe.stats().tid;
    let ticks: number = 0;
    let timer: number = setInterval(() => {
      ticks++;
    }, 5);
    let started: number = now();
    const busy: ProbeResult = await probe.startBusy(400000000);
    clearInterval(timer);
    log(`PROBE_ASYNC value=${busy.value} worker=${busy.workerTid} caller=${busy.callerTid} main=${mainTid} ticks=${ticks} ms=${now() - started}`);

    ticks = 0;
    timer = setInterval(() => {
      ticks++;
    }, 5);
    started = now();
    const value: number = probe.syncBusy(40000000);
    const syncMs: number = now() - started;
    const syncTicks: number = ticks;
    clearInterval(timer);
    log(`PROBE_SYNC value=${value} ticks_during_call=${syncTicks} ms=${syncMs}`);

    started = now();
    const cancelling: Promise<ProbeResult> = probe.startBusy(2000000000);
    setTimeout(() => {
      probe.setCancel(1);
    }, 100);
    const cancelled: ProbeResult = await cancelling;
    probe.setCancel(0);
    log(`PROBE_CANCEL value=${cancelled.value} ms=${now() - started}`);

    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      throw new Error('missing host context');
    }
    const raw: ProbeResult = await probe.readRaw(context.resourceManager, 'probe.txt');
    log(`PROBE_RAW sum=${raw.value} worker=${raw.workerTid}`);

    const thread: worker.ThreadWorker = new worker.ThreadWorker('entry/ets/workers/ProbeWorker.ets');
    await new Promise<void>((resolve: () => void) => {
      thread.onmessage = (event: MessageEvents) => {
        log(`PROBE_WORKER_MESSAGE ${event.data as string}`);
        if (event.data === 'started') {
          resolve();
        }
      };
      thread.postMessage('start');
    });
    await sleep(200);
    thread.terminate();
    await sleep(500);
    probe.setCancel(1);
    await sleep(300);
    probe.setCancel(0);
    const after: ProbeResult = await probe.startBusy(1000);
    const stats = probe.stats();
    log(`PROBE_WORKER after=${after.value} pending=${stats.pending} cleanups=${stats.cleanups}`);

    const depths: number[] = [1000, 10000, 50000];
    for (const depth of depths) {
      const result: ProbeResult = await probe.startDepth(depth);
      log(`PROBE_DEPTH n=${depth} value=${result.value}`);
    }
    log('PROBE_DONE');
    this.status = 'probe done';
  }

  build() {
    Column() {
      Text(this.status).fontSize(20)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
