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
    // ✅ 第一步：获取主窗口
    windowStage.getMainWindow((err: BusinessError, windowClass: window.Window) => {
      if (err.code) {
        console.error('获取主窗口失败: ' + JSON.stringify(err));
        return;
      }

      // ✅ 第二步：设置全屏布局（内容延伸到状态栏/导航栏区域下方）
      windowClass.setWindowLayoutFullScreen(true).then(() => {
        console.info('全屏布局设置成功');

        // ✅ 第三步：将状态栏和导航栏背景设为透明
        const sysBarProps: window.SystemBarProperties = {
          statusBarColor: '#00000000',        // 完全透明
          navigationBarColor: '#00000000',    // 完全透明
          statusBarContentColor: '#FFFFFF',   // 状态栏图标颜色（亮色主题可改为 #000000）
          navigationBarContentColor: '#FFFFFF'
        };
        return windowClass.setWindowSystemBarProperties(sysBarProps);
      }).then(() => {
        console.info('状态栏/导航栏透明化成功');

        // ✅ 第四步：将状态栏高度存入 AppStorage，供各页面 Header 使用
        // 避免内容被状态栏遮住
        const avoidArea = windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        const statusBarHeight = avoidArea.topRect.height;
        AppStorage.setOrCreate('statusBarHeight', statusBarHeight);
        console.info(`状态栏高度: ${statusBarHeight}px`);

      }).catch((e: BusinessError) => {
        console.error('沉浸式设置失败: ' + JSON.stringify(e));
      });
    });

    // ✅ 加载页面（与窗口配置并行，无依赖关系）
    windowStage.loadContent('pages/Index', (err) => {
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