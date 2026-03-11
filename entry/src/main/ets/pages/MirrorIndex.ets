// entry/src/main/ets/pages/MirrorIndex.ets
import { SettingsPage } from './SettingsPage';
import { ShelfPage } from '../components/Mirror/ShelfPage';
import { UpdateFeedPage } from '../components/Mirror/UpdateFeedPage';
import { SearchPage } from '../components/Mirror/SearchPage';
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';
import router from '@ohos.router';

interface ColorConfig {
  pageBg: string;
  tabBarBg: string;
  tabTextActive: string;
  tabTextInactive: string;
  accentColor: string;
}

function getIndexColors(mode: number): ColorConfig {
  const isDark = mode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  return {
    pageBg: isDark ? '#0D0D0D' : '#F9F9F9',
    tabBarBg: isDark ? '#141414' : '#F9F9F9',
    tabTextActive: '#007DFF',
    tabTextInactive: isDark ? '#888888' : '#666666',
    accentColor: '#007DFF'
  };
}

@Entry
@Component
struct MirrorIndex {
  @State currentIndex: number = 0;
  @StorageProp('currentColorMode') colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  private controller: TabsController = new TabsController();

  private getColors(): ColorConfig {
    return getIndexColors(this.colorMode);
  }

  @Builder TabBuilder(title: string, index: number) {
    Column() {
      Text(title)
        .fontSize(16)
        .fontColor(this.currentIndex === index
          ? this.getColors().tabTextActive
          : this.getColors().tabTextInactive)
        .fontWeight(this.currentIndex === index ? FontWeight.Bold : FontWeight.Normal)
    }
    .width('100%')
    .height(50)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Column() {
      // ✅ 顶部添加返回按钮，方便回到Launcher
      Row() {
        Button() {
          Text('〈 返回').fontSize(14).fontColor('#007DFF')
        }
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          router.replaceUrl({ url: 'pages/LauncherPage' });
        })

        Text('Mirror 书库')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getColors().tabTextActive)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Blank().width(60) // 平衡布局
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12 + px2vp(AppStorage.get<number>('statusBarHeight') || 0), bottom: 8 })
      .backgroundColor(this.getColors().tabBarBg)

      Tabs({ barPosition: BarPosition.End, controller: this.controller, index: this.currentIndex }) {
        TabContent() { ShelfPage() }.tabBar(this.TabBuilder('书架', 0))
        TabContent() { UpdateFeedPage() }.tabBar(this.TabBuilder('最新', 1))
        TabContent() { SearchPage() }.tabBar(this.TabBuilder('搜索', 2))
      }
      .onChange((index: number): void => { this.currentIndex = index })
      .barHeight(60)
      .backgroundColor(this.getColors().tabBarBg)
      .layoutWeight(1)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getColors().pageBg)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}