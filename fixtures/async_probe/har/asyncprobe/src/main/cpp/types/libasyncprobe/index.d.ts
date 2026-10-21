import { resourceManager } from '@kit.LocalizationKit';
export interface ProbeResult { value: number; workerTid: number; callerTid: number; }
export interface ProbeStats { pending: number; cleanups: number; tid: number; }
export const startBusy: (rounds: number) => Promise<ProbeResult>;
export const startDepth: (depth: number) => Promise<ProbeResult>;
export const readRaw: (resources: resourceManager.ResourceManager, path: string) => Promise<ProbeResult>;
export const syncBusy: (rounds: number) => number;
export const setCancel: (value: number) => void;
export const stats: () => ProbeStats;
