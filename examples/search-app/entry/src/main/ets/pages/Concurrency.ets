import { MessageEvents, taskpool, worker } from '@kit.ArkTS';
import native, { Hit, MoonOHOSDiagnostics, SearchIndex } from '@moonohos/search';
import { SearchJob } from '../workers/SearchJob';

// MoonOHOS in other ArkTS environments (0.7): a Worker and TaskPool threads
// each load the module into their own env, with their own EnvState.

const PATHS: string[] = ['mem/a.md', 'mem/b.md', 'mem/c.md'];
const TEXTS: string[] = [
  '# Worker\nMoonBit runs in a worker thread with its own environment',
  '# TaskPool\nconcurrent functions load the native module again',
  '# UI\nthe main thread keeps its handles while workers come and go'
];

// Starts a Worker, runs one search there, terminates it and waits until the
// Worker env's cleanup hook ran (envCleanups + 1, liveEnvs back).
export function runWorker(): Promise<string> {
  return new Promise<string>((resolve: (value: string) => void) => {
    const before: MoonOHOSDiagnostics = native.moonohos_diagnostics();
    const thread: worker.ThreadWorker = new worker.ThreadWorker('entry/ets/workers/SearchWorker.ets');
    thread.onerror = () => resolve('fail worker error');
    thread.onmessage = (event: MessageEvents): void => {
      const reply: string = event.data as string;
      thread.terminate();
      let tries: number = 0;
      const timer: number = setInterval(() => {
        const after: MoonOHOSDiagnostics = native.moonohos_diagnostics();
        tries++;
        const cleaned: number = after.envCleanups - before.envCleanups;
        if (cleaned > 0 || tries >= 50) {
          clearInterval(timer);
          const pass: boolean = reply.startsWith('ok hits=') && reply.includes(`envs=${before.liveEnvs + 1}`) &&
            cleaned === 1 && after.liveEnvs === before.liveEnvs;
          resolve(`${pass ? 'pass' : 'fail'} ${reply} cleaned=${cleaned} envs_before=${before.liveEnvs} envs_after=${after.liveEnvs} waited_ms=${tries * 100}`);
        }
      }, 100);
    };
    const job: SearchJob = new SearchJob();
    job.paths = PATHS;
    job.texts = TEXTS;
    job.query = 'worker thread';
    thread.postMessage(job);
  });
}

@Concurrent
async function searchInTask(paths: string[], texts: string[], query: string): Promise<string> {
  const index: SearchIndex = await native.index_texts(paths, texts);
  const hits: Hit[] = index.search_now(query, 5);
  const idf: Float64Array = index.term_idf(query);
  const diagnostics: MoonOHOSDiagnostics = native.moonohos_diagnostics();
  index.close();
  return `ok hits=${hits.length} top=${hits.length > 0 ? hits[0].path : ''} idf=${idf.length} envs=${diagnostics.liveEnvs}`;
}

// Runs the same search on TaskPool threads (three tasks in parallel).
export async function runTaskPool(): Promise<string> {
  const tasks: Promise<Object>[] = [];
  for (let i = 0; i < 3; i++) {
    tasks.push(taskpool.execute(new taskpool.Task(searchInTask, PATHS, TEXTS, 'concurrent native')));
  }
  const replies: Object[] = await Promise.all(tasks);
  const texts: string[] = replies.map((reply: Object) => reply as string);
  const pass: boolean = texts.every((reply: string) => reply.startsWith('ok hits=') && reply.includes('top=mem/b.md'));
  return `${pass ? 'pass' : 'fail'} ${texts.join(' | ')}`;
}
