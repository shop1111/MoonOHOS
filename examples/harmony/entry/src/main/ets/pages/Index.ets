import native from 'libmoonohos.so';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { runNativeChecks } from '../tests/NativeChecks';
import { sampleBatch } from '../tests/ContainerChecks';

@Entry
@Component
struct Index {
  @State result: string = '—';
  @State checks: string = '等待验证';
  @State textResult: string = '';
  @State bytesResult: string = '';
  @State batchResult: string = '';

  aboutToAppear(): void {
    this.run();
  }

  private run(): void {
    try {
      this.result = native.add(20, 22).toString();
      this.textResult = native.join_text('你好，', 'MoonBit 🌙');
      const bytes: Uint8Array = native.concat_bytes(new Uint8Array([0, 127]), new Uint8Array([255]));
      this.bytesResult = 'Uint8Array [' + bytes[0] + ', ' + bytes[1] + ', ' + bytes[2] + ']';
      const analysis = native.analyze_samples(sampleBatch());
      this.batchResult = 'Sample[] → Analysis：count=' + analysis.count + ', total=' + analysis.total + '\n嵌套数组 ' + JSON.stringify(analysis.groups) + '\n来源 ' + analysis.meta.source;
      this.checks = runNativeChecks();
    } catch (error) {
      const failure = error as Error;
      this.checks = '验证失败：' + failure.message;
      hilog.error(0x0000, 'MoonOHOS', 'MOONOHOS_RUNTIME_FAIL %{public}s', failure.message);
    }
  }

  build() {
    Column({ space: 24 }) {
      Text('MoonOHOS').fontSize(32).fontWeight(FontWeight.Bold).fontColor('#132B47')
      Text('ArkTS UI → MoonBit 核心逻辑').fontSize(16)
      Text('add(20, 22)').fontSize(20)
      Text(this.result).fontSize(72).fontWeight(FontWeight.Bold).fontColor('#087E66')
      Text(this.textResult).fontSize(18).fontColor('#132B47')
      Text(this.bytesResult).fontSize(16).fontColor('#132B47')
      Text(this.batchResult).fontSize(16).textAlign(TextAlign.Center)
      Button('重新调用 MoonBit').onClick(() => { this.run(); })
      Text(this.checks).fontSize(14).textAlign(TextAlign.Center)
    }
    .width('100%').height('100%').justifyContent(FlexAlign.Center).padding(24).backgroundColor('#F5F8FB')
  }
}
