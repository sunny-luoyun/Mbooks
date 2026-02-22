// entry/src/main/ets/pages/SettingsPage.ets
import { CrawlerSettings } from '../components/settings/CrawlerSettings';
import { AuthorSettings } from '../components/settings/AuthorSettings';
import { BookSettings } from '../components/settings/BookSettings';
import { AboutSettings } from '../components/settings/AboutSettings';

// 定义颜色配置接口
interface SettingsPageColors {
  pageBg: string;
  headerBg: string;
  tabTextActive: string;
  tabTextInactive: string;
  dividerColor: string;
  shadowColor: string;
}

// 颜色配置函数
function getSettingsPageColors(mode: number): SettingsPageColors {
  // 注意：在 HarmonyOS 中，ColorMode.DARK 通常对应 1，LIGHT 对应 0
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

  // ✅ 修复点：变量名必须与 EntryAbility 中的 'currentColorMode' 保持一致
  @StorageProp('currentColorMode') colorMode: number = 0;

  private tabs: string[] = ['爬取设置', '关注作者', '关注书籍', '关于'];

  build() {
    // 在 build 内部实时获取当前颜色配置，确保 UI 响应
    Column() {
      // 顶部导航
      Row() {
        ForEach(this.tabs, (tab: string, index: number) => {
          Column() {
            Text(tab)
              .fontSize(14)
              .fontWeight(this.currentTab === index ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.currentTab === index ?
                getSettingsPageColors(this.colorMode).tabTextActive :
                getSettingsPageColors(this.colorMode).tabTextInactive)

            if (this.currentTab === index) {
              Divider()
                .strokeWidth(2)
                .color(getSettingsPageColors(this.colorMode).dividerColor)
                .width(20)
                .margin({ top: 4 })
            }
          }
          .layoutWeight(1)
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            console.info('[SettingsPage] 点击 tab: ' + index);
            this.currentTab = index;
          })
        }, (tab: string) => tab)
      }
      .width('100%')
      .height(50)
      .backgroundColor(getSettingsPageColors(this.colorMode).headerBg)
      .shadow({ radius: 2, color: getSettingsPageColors(this.colorMode).shadowColor })

      // 内容区
      Stack() {
        CrawlerSettings()
          .visibility(this.currentTab === 0 ? Visibility.Visible : Visibility.None)

        AuthorSettings()
          .visibility(this.currentTab === 1 ? Visibility.Visible : Visibility.None)

        BookSettings()
          .visibility(this.currentTab === 2 ? Visibility.Visible : Visibility.None)

        AboutSettings()
          .visibility(this.currentTab === 3 ? Visibility.Visible : Visibility.None)
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(getSettingsPageColors(this.colorMode).pageBg)
    // 强制动画过渡，让颜色切换更平滑
    .animation({ duration: 200 })
  }
}