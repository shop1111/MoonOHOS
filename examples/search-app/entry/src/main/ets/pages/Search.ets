import { hilog } from '@kit.PerformanceAnalysisKit';
import { systemDateTime } from '@kit.BasicServicesKit';
import { resourceManager } from '@kit.LocalizationKit';
import { Hit, IndexStats, SearchSession } from '@moonohos/search';

const TAG: string = 'MoonSearchApp';

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

function errorName(error: Error): string {
  return `${error.name}:${error.message}`;
}

@Entry
@Component
struct SearchPage {
  @State status: string = '尚未建立索引';
  @State query: string = '离线检索';
  @State hits: Hit[] = [];
  @State ticks: number = 0;
  @State building: boolean = false;
  private session: SearchSession = new SearchSession();
  private timer: number = -1;
  private round: number = 0;

  aboutToAppear(): void {
    this.timer = setInterval(() => {
      this.ticks++;
    }, 100);
    const params = this.getUIContext().getRouter().getParams() as Record<string, number>;
    this.round = params === undefined || params['round'] === undefined ? 0 : params['round'];
    if (AppStorage.get<string>('scenario') === 'auto') {
      this.runScenario().catch((error: Error) => log(`MOONSEARCH_FAIL scenario ${errorName(error)}`));
    }
  }

  aboutToDisappear(): void {
    clearInterval(this.timer);
    // Cancels a running build and releases the MoonBit index.
    this.session.close();
    log(`MOONSEARCH_PAGE_CLOSED round=${this.round}`);
  }

  resources(): resourceManager.ResourceManager {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      throw new Error('missing host context');
    }
    return context.resourceManager;
  }

  async buildIndex(dir: string): Promise<IndexStats> {
    this.building = true;
    this.status = `正在建立索引：${dir}`;
    const started: number = now();
    try {
      const stats: IndexStats = await this.session.open(this.resources(), dir);
      this.status = `已索引 ${stats.documents} 篇文档，${stats.terms} 个词项，用时 ${now() - started} ms`;
      return stats;
    } catch (error) {
      this.status = `建立索引中止：${errorName(error as Error)}`;
      throw error as Error;
    } finally {
      this.building = false;
    }
  }

  async runSearch(): Promise<void> {
    if (!this.session.ready) {
      this.status = '请先建立索引';
      return;
    }
    this.hits = await this.session.search(this.query, 20);
    this.status = `“${this.query}” 找到 ${this.hits.length} 条结果`;
  }

  async runScenario(): Promise<void> {
    const small: IndexStats = await this.buildIndex('docs');
    const hits: Hit[] = await this.session.search('离线检索', 5);
    this.hits = hits;
    log(`MOONSEARCH_SMALL round=${this.round} documents=${small.documents} hits=${hits.length} top=${hits.length > 0 ? hits[0].path : ''}`);
    const quick: Hit[] = this.session.searchNow('rawfile', 3);
    log(`MOONSEARCH_SYNC_QUERY hits=${quick.length} top=${quick.length > 0 ? quick[0].path : ''}`);

    const cancelStarted: number = now();
    const cancelled: Promise<IndexStats> = this.buildIndex('docs_large');
    setTimeout(() => this.session.cancel(), 150);
    try {
      await cancelled;
      log('MOONSEARCH_CANCEL_MISSED');
    } catch (error) {
      log(`MOONSEARCH_CANCELLED round=${this.round} error=${errorName(error as Error)} ms=${now() - cancelStarted}`);
    }

    const ticksBefore: number = this.ticks;
    const largeStarted: number = now();
    const large: IndexStats = await this.buildIndex('docs_large');
    log(`MOONSEARCH_LARGE round=${this.round} documents=${large.documents} terms=${large.terms} ms=${now() - largeStarted} ui_ticks=${this.ticks - ticksBefore}`);
    const largeHits: Hit[] = await this.session.search('隐私 privacy 索引', 10);
    this.hits = largeHits;
    log(`MOONSEARCH_LARGE_QUERY hits=${largeHits.length} top=${largeHits.length > 0 ? largeHits[0].path : ''}`);

    this.status = `大型文档集：${large.documents} 篇，“隐私 privacy 索引” ${largeHits.length} 条结果`;
    await sleep(2000);

    // Leave the page while a rebuild is running: aboutToDisappear cancels and closes.
    this.buildIndex('docs_large').catch((error: Error) => {
      log(`MOONSEARCH_EXIT_CANCELLED round=${this.round} error=${errorName(error)}`);
    });
    setTimeout(() => this.getUIContext().getRouter().back(), 200);
  }

  build() {
    Column({ space: 12 }) {
      Text('离线文档检索').fontSize(24).fontWeight(FontWeight.Bold)
      Text(this.status).fontSize(14).fontColor('#444444')
      Text(`界面计时 ${this.ticks}`).fontSize(12).fontColor('#888888')
      Row({ space: 8 }) {
        Button('小型文档集').enabled(!this.building).onClick(() => {
          this.buildIndex('docs').catch((error: Error) => log(`build failed ${errorName(error)}`));
        })
        Button('大型文档集').enabled(!this.building).onClick(() => {
          this.buildIndex('docs_large').catch((error: Error) => log(`build failed ${errorName(error)}`));
        })
        Button('取消').enabled(this.building).onClick(() => this.session.cancel())
      }
      Row({ space: 8 }) {
        TextInput({ text: this.query, placeholder: '输入关键词' })
          .layoutWeight(1)
          .onChange((value: string) => {
            this.query = value;
          })
        Button('搜索').onClick(() => {
          this.runSearch().catch((error: Error) => {
            this.status = `搜索失败：${errorName(error)}`;
          });
        })
      }
      List({ space: 8 }) {
        ForEach(this.hits, (hit: Hit) => {
          ListItem() {
            Column({ space: 4 }) {
              Text(hit.title).fontSize(16).fontWeight(FontWeight.Medium)
              Text(`${hit.path} · ${hit.score.toFixed(3)}`).fontSize(12).fontColor('#2f6fdd')
              Text(hit.snippet).fontSize(13).fontColor('#555555').maxLines(3)
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
          }
        }, (hit: Hit) => hit.path)
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(16)
  }
}
