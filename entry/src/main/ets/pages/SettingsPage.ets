// entry/src/main/ets/pages/SettingsPage.ets
import { CrawlerSettings } from '../components/settings/CrawlerSettings';
import { AboutSettings } from '../components/settings/AboutSettings';
import router from '@ohos.router';

interface SettingsPageColors {
  pageBg: string;
  headerBg: string;
  tabTextActive: string;
  tabTextInactive: string;
  dividerColor: string;
  shadowColor: string;
}

function getSettingsPageColors(mode: number): SettingsPageColors {
  const isDark = (mode === 0);
  return {
    pageBg: isDark ? '#0D0D0D' : '#F5F5F5',
    headerBg: isDark ? '#1E1E1E' : '#FFFFFF',
    tabTextActive: '#007DFF',
    tabTextInactive: isDark ? '#888888' : '#666666',
    dividerColor: '#007DFF',
    shadowColor: isDark ? '#000000' : '#10000000'
  };
}

@Entry
@Component
export struct SettingsPage {
  @State currentTab: number = 0;
  @StorageProp('currentColorMode') colorMode: number = 0;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  // ✅ 修改：只保留爬取设置和关于
  private tabs: string[] = ['爬取设置', '关于'];

  private getColors(): SettingsPageColors {
    return getSettingsPageColors(this.colorMode);
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Button() {
          Text('〈 返回').fontSize(14).fontColor('#007DFF')
        }
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          router.back();
        })

        Text('设置')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getColors().tabTextActive)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Blank().width(60)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12 + px2vp(this.statusBarHeight), bottom: 12 })
      .backgroundColor(this.getColors().headerBg)

      // Tab导航
      Row() {
        ForEach(this.tabs, (tab: string, index: number) => {
          Column() {
            Text(tab)
              .fontSize(14)
              .fontWeight(this.currentTab === index ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.currentTab === index ?
                this.getColors().tabTextActive :
                this.getColors().tabTextInactive)

            if (this.currentTab === index) {
              Divider()
                .strokeWidth(2)
                .color(this.getColors().dividerColor)
                .width(20)
                .margin({ top: 4 })
            }
          }
          .layoutWeight(1)
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.currentTab = index;
          })
        }, (tab: string) => tab)
      }
      .width('100%')
      .height(50)
      .backgroundColor(this.getColors().headerBg)
      .shadow({ radius: 2, color: this.getColors().shadowColor })

      // 内容区
      Stack() {
        CrawlerSettings()
          .visibility(this.currentTab === 0 ? Visibility.Visible : Visibility.None)

        AboutSettings()
          .visibility(this.currentTab === 1 ? Visibility.Visible : Visibility.None)
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getColors().pageBg)
    .animation({ duration: 200 })
  }
}