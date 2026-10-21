import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // `aa start ... --ps scenario auto` runs the scripted device verification.
    const scenario = want.parameters === undefined ? undefined : want.parameters['scenario'];
    AppStorage.setOrCreate<string>('scenario', typeof scenario === 'string' ? scenario : '');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (error) => {
      if (error.code) {
        hilog.error(0x4d4f, 'MoonSearchApp', 'PAGE_LOAD_FAILED %{public}s', error.message);
      }
    });
  }
}
