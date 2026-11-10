// Message sent to SearchWorker. Kept apart from the worker script, whose
// top-level code (worker.workerPort) must only run inside the Worker.
export class SearchJob {
  paths: string[] = [];
  texts: string[] = [];
  query: string = '';
}
