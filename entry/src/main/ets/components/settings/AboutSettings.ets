// entry/src/main/ets/components/settings/AboutSettings.ets
import { SettingsService } from '../../services/SettingsService';
import promptAction from '@ohos.promptAction';
import { Configuration } from '@ohos.app.ability.Configuration';
import { Context } from '@ohos.abilityAccessCtrl';
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';
import common from '@ohos.app.ability.common';

interface AboutSettingsColors {
  pageBg: string;
  cardBg: string;
  primaryText: string;
  secondaryText: string;
  tertiaryText: string;
  accentText: string;
  iconColor: string;
  dangerBtnBg: string;
  dangerBtnText: string;
  versionText: string;
  infoLabel: string;
  infoValue: string;
}
// 颜色配置函数 - 根据模式返回对应颜色
function getAboutSettingsColors(mode: number): AboutSettingsColors {
  const isDark = mode === 0; // 1 表示暗色模式
  return {
    // 背景色
    pageBg: isDark ? '#0D0D0D' : '#F5F5F5',
    cardBg: isDark ? '#1E1E1E' : '#FFFFFF',

    // 文字色
    primaryText: isDark ? '#E6E6E6' : '#000000',
    secondaryText: isDark ? '#999999' : '#666666',
    tertiaryText: isDark ? '#666666' : '#999999',
    accentText: '#007DFF',

    // 图标颜色
    iconColor: isDark ? '#555555' : '#CCCCCC',

    // 按钮颜色
    dangerBtnBg: '#FF4D4F',
    dangerBtnText: '#FFFFFF',

    // 版本号颜色
    versionText: isDark ? '#888888' : '#999999',

    // 信息项标签颜色
    infoLabel: isDark ? '#888888' : '#666666',
    infoValue: isDark ? '#CCCCCC' : '#333333'
  };
}
@Component
export struct AboutSettings {
  @State colorMode: number = 0; // 0 表示亮色模式
  private configChangeCallback: () => void = () => {};
  private configCallbackId: number = -1;
  private settingsService: SettingsService | null = null;

  aboutToAppear(): void {

    this.settingsService = SettingsService.getInstance(getContext(this));
    // 1. 初始化获取当前真实的颜色模式
    const ctx = getContext(this) as common.UIAbilityContext;
    this.colorMode = ctx.config?.colorMode || 0;

    // 2. 注册监听函数
    this.configChangeCallback = () => {
      // 当系统配置变化时，重新给 colorMode 赋值触发 UI 刷新
      this.colorMode = ctx.config?.colorMode || 0;
    };

    this.configCallbackId = ctx.getApplicationContext().on('environment', {
      onConfigurationUpdated: this.configChangeCallback,
      onMemoryLevel: (level: number) => {}
    });
  }
  aboutToDisappear(): void {
    // 3. 别忘了在组件销毁时移除监听，防止内存泄漏
    const ctx = getContext(this) as common.UIAbilityContext;
    if (this.configCallbackId !== -1) {
      ctx.getApplicationContext().off('environment', this.configCallbackId);
    }
  }
  // 获取当前颜色配置
  private getColors(): AboutSettingsColors {
    return getAboutSettingsColors(this.colorMode);
  }

  private resetAll(): void {
    // 可以弹出确认对话框
    this.settingsService?.resetToDefault();
    promptAction.showToast({ message: '已重置所有设置' });
  }

  build() {
    Column() {
      Text('📚')
        .fontSize(80)
        .fontColor(this.getColors().iconColor)
        .margin({ top: 50, bottom: 20 })

      Text('小说爬虫')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.getColors().primaryText)
        .margin({ bottom: 8 })

      Text('v1.0.0')
        .fontSize(16)
        .fontColor(this.getColors().versionText)
        .margin({ bottom: 8 })

      Text('基于 HarmonyOS NEXT 开发')
        .fontSize(14)
        .fontColor(this.getColors().secondaryText)
        .margin({ bottom: 40 })

      // 功能列表
      Column({ space: 12 }) {
        this.InfoItem('功能特点', '自动爬取、断点续传、关注提醒')
        this.InfoItem('数据存储', '本地JSON文件，隐私安全')
        this.InfoItem('开源协议', 'MIT License')
      }
      .width('92%')
      .margin({ bottom: 40 })

      // 重置按钮
      Button('重置所有设置')
        .width('80%')
        .height(44)
        .fontColor(this.getColors().dangerBtnText)
        .backgroundColor(this.getColors().dangerBtnBg)
        .onClick((): void => this.resetAll())

      Text('重置后将清除所有关注和配置')
        .fontSize(12)
        .fontColor(this.getColors().tertiaryText)
        .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getColors().pageBg)
  }

  @Builder
  InfoItem(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor(this.getColors().infoLabel)
        .width(80)
      Text(value)
        .fontSize(14)
        .fontColor(this.getColors().infoValue)
        .layoutWeight(1)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.getColors().cardBg)
    .borderRadius(12)
  }
}