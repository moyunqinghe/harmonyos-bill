import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { retireLegacyReminders } from '../common/ReminderScheduler';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'MyHello', '%{public}s', 'Ability onCreate');
    retireLegacyReminders(this.context);
  }

  onDestroy(): void {
    hilog.info(0x0000, 'MyHello', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(0x0000, 'MyHello', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/LaunchPage', (err) => {
      if (err.code) {
        hilog.error(0x0000, 'MyHello', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err) ?? '');
        return;
      }
      hilog.info(0x0000, 'MyHello', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(0x0000, 'MyHello', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(0x0000, 'MyHello', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(0x0000, 'MyHello', '%{public}s', 'Ability onBackground');
  }
}
