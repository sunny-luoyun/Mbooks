// entry/src/main/ets/components/settings/AboutSettings.ets
import { SettingsService } from '../../services/SettingsService';
import promptAction from '@ohos.promptAction';

@Component
export struct AboutSettings {
  private settingsService: SettingsService | null = null;

  aboutToAppear(): void {
    this.settingsService = SettingsService.getInstance(getContext(this));
  }

  private resetAll(): void {
    // 可以弹出确认对话框
    this.settingsService?.resetToDefault();
    promptAction.showToast({ message: '已重置所有设置' });
  }

  build() {
    Column() {
      Text('📚').fontSize(80).margin({ top: 50, bottom: 20 })

      Text('小说爬虫')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 8 })

      Text('v1.0.0')
        .fontSize(16)
        .fontColor('#999')
        .margin({ bottom: 8 })

      Text('基于 HarmonyOS NEXT 开发')
        .fontSize(14)
        .fontColor('#666')
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
        .backgroundColor('#FF4D4F')
        .onClick((): void => this.resetAll())

      Text('重置后将清除所有关注和配置')
        .fontSize(12)
        .fontColor('#999')
        .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }

  @Builder
  InfoItem(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor('#666')
        .width(80)
      Text(value)
        .fontSize(14)
        .fontColor('#333')
        .layoutWeight(1)
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFF')
    .borderRadius(12)
  }
}