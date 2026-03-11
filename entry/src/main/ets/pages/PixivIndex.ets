// entry/src/main/ets/pages/PixivIndex.ets
import { PixivSearchPage } from '../components/Pixiv/PixivSearchPage';
import { PixivFollowingPage } from '../components/Pixiv/PixivFollowingPage';
import { PixivShelfPage } from '../components/Pixiv/PixivShelfPage';
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';
import router from '@ohos.router';

interface ColorConfig {
  pageBg: string;
  tabBarBg: string;
  tabTextActive: string;
  tabTextInactive: string;
}

function getPixivIndexColors(mode: number): ColorConfig {
  const isDark = mode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  return {
    pageBg: isDark ? '#0D0D0D' : '#F9F9F9',
    tabBarBg: isDark ? '#141414' : '#F9F9F9',
    tabTextActive: '#FA8C16',  // Pixiv用橙色主题
    tabTextInactive: isDark ? '#888888' : '#666666'
  };
}

@Entry
@Component
struct PixivIndex {
  @State currentIndex: number = 0;
  @StorageProp('currentColorMode') colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  private controller: TabsController = new TabsController();

  private getColors(): ColorConfig {
    return getPixivIndexColors(this.colorMode);
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
      // 顶部导航
      Row() {
        Button() {
          Text('〈 返回').fontSize(14).fontColor('#FA8C16')
        }
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          router.back();
        })

        Text('Pixiv 小说')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getColors().tabTextActive)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Blank().width(60)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12 + px2vp(AppStorage.get<number>('statusBarHeight') || 0), bottom: 8 })
      .backgroundColor(this.getColors().tabBarBg)

      // Pixiv的3个Tab：搜索、关注、书架（缓存）
      Tabs({ barPosition: BarPosition.End, controller: this.controller, index: this.currentIndex }) {
        TabContent() { PixivSearchPage() }.tabBar(this.TabBuilder('搜索', 0))
        TabContent() { PixivFollowingPage() }.tabBar(this.TabBuilder('关注', 1))
        TabContent() { PixivShelfPage() }.tabBar(this.TabBuilder('缓存', 2))
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