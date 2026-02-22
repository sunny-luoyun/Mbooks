// entry/src/main/ets/entryability/EntryAbility.ets
import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { Configuration } from '@kit.AbilityKit';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // ✅ 1. 初始化时，将当前的颜色模式存入 AppStorage
    AppStorage.setOrCreate('currentColorMode', this.context.config.colorMode);
  }

  // ✅ 2. 关键：当系统切换深色/浅色模式时，此回调会被触发
  onConfigurationUpdate(newConfig: Configuration): void {
    // 将变更后的模式同步到 AppStorage，这会触发 Index.ets 中 @StorageProp 的自动刷新
    AppStorage.setOrCreate('currentColorMode', newConfig.colorMode);
    console.info(`[EntryAbility] ColorMode updated to: ${newConfig.colorMode}`);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        console.error('Failed to load the content. Cause: %{public}s', JSON.stringify(err) ?? '');
        return;
      }
    });
  }

  // 其他生命周期函数保持默认即可...
  onWindowStageDestroy(): void {}
  onForeground(): void {}
  onBackground(): void {}
  onDestroy(): void {}
}