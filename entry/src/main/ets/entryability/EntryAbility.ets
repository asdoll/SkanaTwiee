import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { notificationManager } from '@kit.NotificationKit';
import { Language } from '../common/Language';
import { Prefs } from '../common/Prefs';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    Prefs.init(this.context);
    // Before any UI exists: resources are resolved in the application's
    // preferred language, and that preference has to be published again on every
    // launch because the system keeps it only for the life of the process.
    Language.apply();
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });

    // The media surfaces - the play/pause notification, the status-bar capsule
    // and the lock-screen card - are all notifications of this app, and none of
    // them can appear while notifications are switched off for it. Ask once at
    // start-up (the same order Petrelgram uses): check first, because
    // requestEnableNotification reports an internal error when the system switch
    // is already off and the dialog would then never be shown.
    notificationManager.isNotificationEnabled().then((enabled: boolean): void => {
      if (enabled) {
        return;
      }
      notificationManager.requestEnableNotification(this.context).catch((e: Error): void => {
        hilog.warn(DOMAIN, 'testTag', 'notification request refused: %{public}s', e.message);
      });
    }).catch((e: Error): void => {
      hilog.warn(DOMAIN, 'testTag', 'could not read the notification switch: %{public}s', e.message);
    });

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}