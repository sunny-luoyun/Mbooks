// entry/src/main/ets/pages/LauncherPage.ets
import router from '@ohos.router';
import common from '@ohos.app.ability.common';
import promptAction from '@ohos.promptAction';

interface LauncherColors {
  bg: string;
  cardBg: string;
  primaryText: string;
  secondaryText: string;
  mirrorColor: string;
  pixivColor: string;
  settingsColor: string;
  btnText: string;
}

function getLauncherColors(mode: number): LauncherColors {
  const isDark = mode === 0;
  return {
    bg: isDark ? '#0D0D0D' : '#F5F5F5',
    cardBg: isDark ? '#1E1E1E' : '#FFFFFF',
    primaryText: isDark ? '#E6E6E6' : '#000000',
    secondaryText: isDark ? '#999999' : '#666666',
    mirrorColor: '#007DFF',      // 蓝色代表Mirror
    pixivColor: '#FA8C16',       // 橙色代表Pixiv
    settingsColor: '#52C41A',    // 绿色代表设置
    btnText: '#FFFFFF'
  };
}

@Entry
@Component
struct LauncherPage {
  @StorageProp('currentColorMode') colorMode: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  private getColors(): LauncherColors {
    return getLauncherColors(this.colorMode);
  }

  // 检查是否有保存的登录态（可选：自动跳转）
  aboutToAppear() {
    // 可以在这里加逻辑：如果上次选择的是Mirror，自动跳转（可选功能）
  }

  @Builder
  PlatformCard(icon: string, title: string, subtitle: string, color: string, targetUrl: string) {
    Column() {
      Text(icon)
        .fontSize(30)
        .margin({ bottom: 12 })

      Text(title)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.getColors().primaryText)
        .margin({ bottom: 8 })

      Text(subtitle)
        .fontSize(14)
        .fontColor(this.getColors().secondaryText)
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Button('进入')
        .width('80%')
        .height(44)
        .fontSize(16)
        .fontColor(this.getColors().btnText)
        .backgroundColor(color)
        .borderRadius(22)
        .margin({ top: 20 })
        .onClick(() => {
          router.pushUrl({ url: targetUrl });
        })
    }
    .width('90%')
    .padding(24)
    .backgroundColor(this.getColors().cardBg)
    .borderRadius(16)
    .shadow({ radius: 10, color: '#20000000', offsetY: 4 })
    .margin({ bottom: 16 })
  }

  build() {
    Column() {
      // 顶部标题
      Column() {
        Text('📚 小说阅读器')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getColors().primaryText)
          .margin({ top: px2vp(this.statusBarHeight) + 10, bottom: 3 })

        Text('请选择要使用的平台')
          .fontSize(16)
          .fontColor(this.getColors().secondaryText)
      }
      .width('100%')

      // 三个选项
      Scroll() {
        Column() {
          this.PlatformCard(
            'M',
            'Mirror 书库',
            '浏览mirror.chromaso.net的小说更新，关注作者，下载本地阅读',
            this.getColors().mirrorColor,
            'pages/MirrorIndex'
          )

          this.PlatformCard(
            'P',
            'Pixiv 小说',
            '搜索Pixiv小说，关注作者动态，离线缓存，AI翻译',
            this.getColors().pixivColor,
            'pages/PixivIndex'
          )

          this.PlatformCard(
            'S️',
            '设置',
            '全局设置、账号管理、关于应用',
            this.getColors().settingsColor,
            'pages/SettingsPage'
          )

          // 底部留白
          Row().height(10)
        }
        .width('100%')
        .padding({ top: 10 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getColors().bg)
  }
}