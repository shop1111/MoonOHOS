import { resourceManager } from '@kit.LocalizationKit';
import native, { CancelToken, Hit, IndexStats, SearchIndex } from './generated/Native';

/**
 * One searchable index owned by a page. `open` builds the index on a worker
 * thread, `cancel` stops a running build, and `close` cancels and releases the
 * MoonBit index. Close is idempotent; call it when the page disappears.
 */
export class SearchSession {
  private index: SearchIndex | undefined = undefined;
  private token: CancelToken | undefined = undefined;

  get ready(): boolean {
    return this.index !== undefined;
  }

  async open(resources: resourceManager.ResourceManager, dir: string): Promise<IndexStats> {
    this.close();
    const token: CancelToken = native.createCancelToken();
    this.token = token;
    const index: SearchIndex = await native.build_index(resources, dir, token);
    if (this.token !== token) {
      // Cancelled or superseded after the worker finished: do not keep it.
      index.close();
      throw new Error('index build superseded');
    }
    this.token = undefined;
    this.index = index;
    return native.stats(index);
  }

  cancel(): void {
    if (this.token !== undefined) {
      this.token.cancel();
      this.token = undefined;
    }
  }

  search(query: string, limit: number): Promise<Hit[]> {
    if (this.index === undefined) {
      return Promise.reject(new Error('index not ready'));
    }
    return native.search(this.index, query, limit);
  }

  searchNow(query: string, limit: number): Hit[] {
    if (this.index === undefined) {
      return [];
    }
    return native.search_now(this.index, query, limit);
  }

  close(): void {
    this.cancel();
    if (this.index !== undefined) {
      this.index.close();
      this.index = undefined;
    }
  }
}
