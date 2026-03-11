// entry/src/main/ets/entryability/EntryAbility.ets
import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { Configuration } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { initPreferences } from '../utils/PreferencesUtil';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppStorage.setOrCreate('currentColorMode', this.context.config.colorMode);
    AppStorage.setOrCreate('pixivSessionId', '');
    initPreferences(this.context);
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    AppStorage.setOrCreate('currentColorMode', newConfig.colorMode);
    console.info(`[EntryAbility] ColorMode updated to: ${newConfig.colorMode}`);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.getMainWindow((err: BusinessError, windowClass: window.Window) => {
      if (err.code) {
        console.error('获取主窗口失败: ' + JSON.stringify(err));
        return;
      }

      windowClass.setWindowLayoutFullScreen(true).then(() => {
        console.info('全屏布局设置成功');

        const sysBarProps: window.SystemBarProperties = {
          statusBarColor: '#00000000',
          navigationBarColor: '#00000000',
          statusBarContentColor: '#FFFFFF',
          navigationBarContentColor: '#FFFFFF'
        };
        return windowClass.setWindowSystemBarProperties(sysBarProps);
      }).then(() => {
        console.info('状态栏/导航栏透明化成功');

        const avoidArea = windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        const statusBarHeight = avoidArea.topRect.height;
        AppStorage.setOrCreate('statusBarHeight', statusBarHeight);
        console.info(`状态栏高度: ${statusBarHeight}px`);

      }).catch((e: BusinessError) => {
        console.error('沉浸式设置失败: ' + JSON.stringify(e));
      });
    });

    // ✅ 修改这里：改为加载 LauncherPage
    windowStage.loadContent('pages/LauncherPage', (err) => {
      if (err.code) {
        console.error('Failed to load the content. Cause: %{public}s', JSON.stringify(err) ?? '');
        return;
      }
    });
  }

  onWindowStageDestroy(): void {}
  onForeground(): void {}
  onBackground(): void {}
  onDestroy(): void {}
}