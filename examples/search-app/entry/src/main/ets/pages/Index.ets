import { hilog } from '@kit.PerformanceAnalysisKit';
import search, { MoonOHOSDiagnostics } from '@moonohos/search';

const TAG: string = 'MoonSearchApp';

function log(message: string): void {
  hilog.info(0x4d4f, TAG, '%{public}s', message);
}

function describe(diagnostics: MoonOHOSDiagnostics): string {
  return `live_handles=${diagnostics.liveHandles} released=${diagnostics.releasedHandles} ` +
    `pending_tasks=${diagnostics.pendingTasks} completed=${diagnostics.completedTasks} ` +
    `cancelled=${diagnostics.cancelledTasks}`;
}

@Entry
@Component
struct Index {
  @State diagnostics: string = '';
  private rounds: number = 0;

  aboutToAppear(): void {
    this.refresh();
    if (AppStorage.get<string>('scenario') === 'auto') {
      log('MOONSEARCH_SCENARIO_BEGIN');
      setTimeout(() => this.openSearch(), 300);
    }
  }

  onPageShow(): void {
    this.refresh();
    if (AppStorage.get<string>('scenario') !== 'auto' || this.rounds === 0) {
      return;
    }
    // Give closed handles and cancelled tasks time to settle, then re-enter once.
    setTimeout(() => {
      const current: MoonOHOSDiagnostics = search.moonohos_diagnostics();
      log(`MOONSEARCH_RETURNED round=${this.rounds} ${describe(current)}`);
      if (this.rounds < 2) {
        this.openSearch();
        return;
      }
      const ok: boolean = current.liveHandles === 0 && current.pendingTasks === 0 && current.cancelledTasks >= 2;
      log(`${ok ? 'MOONSEARCH_PASS' : 'MOONSEARCH_FAIL'} ${describe(current)}`);
      AppStorage.setOrCreate<string>('scenario', '');
    }, 1500);
  }

  refresh(): void {
    this.diagnostics = describe(search.moonohos_diagnostics());
  }

  openSearch(): void {
    this.rounds++;
    this.getUIContext().getRouter().pushUrl({ url: 'pages/Search', params: { round: this.rounds } });
  }

  build() {
    Column({ space: 16 }) {
      Text('离线文档检索').fontSize(28).fontWeight(FontWeight.Bold)
      Text('文档随应用打包，MoonBit 在工作线程建立索引并排序，ArkTS 只负责界面。')
        .fontSize(15).fontColor('#555555').textAlign(TextAlign.Center)
      Button('打开检索').width('60%').onClick(() => this.openSearch())
      Text(`MoonOHOS 诊断：${this.diagnostics}`).fontSize(12).fontColor('#888888').textAlign(TextAlign.Center)
    }
    .width('100%')
    .height('100%')
    .padding(24)
    .justifyContent(FlexAlign.Center)
  }
}
