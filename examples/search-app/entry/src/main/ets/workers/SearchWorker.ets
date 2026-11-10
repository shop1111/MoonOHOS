import { MessageEvents, ThreadWorkerGlobalScope, worker } from '@kit.ArkTS';
import native, { Hit, MoonOHOSDiagnostics, SearchIndex } from '@moonohos/search';
import { SearchJob } from './SearchJob';

// Loads the MoonOHOS module into this Worker's own ArkTS environment, builds
// an index on a background thread (async), queries it and closes it.
const port: ThreadWorkerGlobalScope = worker.workerPort;


async function run(job: SearchJob): Promise<string> {
  const index: SearchIndex = await native.index_texts(job.paths, job.texts);
  const hits: Hit[] = await index.search(job.query, 5);
  const idf: Float64Array = index.term_idf(job.query);
  const diagnostics: MoonOHOSDiagnostics = native.moonohos_diagnostics();
  index.close();
  return `ok hits=${hits.length} top=${hits.length > 0 ? hits[0].path : ''} idf=${idf.length} envs=${diagnostics.liveEnvs}`;
}

port.onmessage = (event: MessageEvents): void => {
  run(event.data as SearchJob)
    .then((reply: string) => port.postMessage(reply))
    .catch((error: Error) => port.postMessage(`fail ${error.name}:${error.message}`));
};
