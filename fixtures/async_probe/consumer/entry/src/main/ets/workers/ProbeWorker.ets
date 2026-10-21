import { MessageEvents, worker } from '@kit.ArkTS';
import probe, { ProbeResult } from '@moonohos/asyncprobe';

const port = worker.workerPort;

port.onmessage = (event: MessageEvents) => {
  if (event.data === 'start') {
    const running: Promise<ProbeResult> = probe.startBusy(2000000000);
    const queued: Promise<ProbeResult> = probe.startBusy(1000);
    port.postMessage('started');
    running.then((result: ProbeResult) => {
      port.postMessage(`running-done ${result.value}`);
    });
    queued.then((result: ProbeResult) => {
      port.postMessage(`queued-done ${result.value}`);
    });
  }
};
