import native from '@moonohos/search';

// MoonBit draws buffers of a third of the component's resolution (360 x 200
// until the first onSurfaceChanged); the compositor scales them up.
export const SURFACE_SCALE: number = 3;

// XComponent surface lifecycle (API 12+): the surface id goes to MoonBit,
// which opens the window and animates it from VSync callbacks.
export class MoonSurfaceController extends XComponentController {
  private log: (message: string) => void;
  // Buffer size requested on the last onSurfaceChanged.
  bufferSize: string = '360x200';

  constructor(log: (message: string) => void) {
    super();
    this.log = log;
  }

  onSurfaceCreated(surfaceId: string): void {
    const attached: string = native.surface_attach(surfaceId, 360, 200);
    this.log(`MOONSEARCH_SURFACE_ATTACH ${attached}`);
  }

  onSurfaceChanged(surfaceId: string, rect: SurfaceRect): void {
    const width: number = Math.max(1, Math.round(rect.surfaceWidth / SURFACE_SCALE));
    const height: number = Math.max(1, Math.round(rect.surfaceHeight / SURFACE_SCALE));
    this.bufferSize = `${width}x${height}`;
    const resized: string = native.surface_resize(width, height);
    this.log(`MOONSEARCH_SURFACE_CHANGED ${rect.surfaceWidth}x${rect.surfaceHeight} ${resized}`);
  }

  onSurfaceDestroyed(surfaceId: string): void {
    this.log(`MOONSEARCH_SURFACE_DETACH ${native.surface_detach()}`);
  }
}

function field(report: string, name: string): string {
  for (const part of report.split(',')) {
    if (part.startsWith(`${name}=`)) {
      return part.substring(name.length + 1);
    }
  }
  return '';
}

// Two reports `seconds` apart: frames advanced at a plausible rate on both
// paths (Native Drawing, then the CPU canvas), the buffer has the requested
// size and the injected tap reached MoonBit.
export function surfaceVerdict(before: string, after: string, seconds: number, expected: string): string {
  const frames: number = Number(field(after, 'frames')) - Number(field(before, 'frames'));
  const fps: number = frames / seconds;
  const buffer: string = field(after, 'buffer');
  const touches: number = Number(field(after, 'touches'));
  const drawing: number = Number(field(after, 'drawing_frames')) - Number(field(before, 'drawing_frames'));
  const cpu: number = Number(field(after, 'cpu_frames')) - Number(field(before, 'cpu_frames'));
  const ok: boolean = field(after, 'running') === 'true' && field(after, 'error') === '' &&
    fps >= 20 && buffer === expected && touches >= 1 && drawing > 0 && cpu > 0;
  return `${ok ? 'pass' : 'fail'} frames=${frames} fps=${fps.toFixed(1)} drawing=${drawing} cpu=${cpu} ` +
    `buffer=${buffer} touches=${touches}`;
}
