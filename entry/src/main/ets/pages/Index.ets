// entry/src/main/ets/pages/Index.ets
import { SettingsPage } from './SettingsPage';
import { ShelfPage } from '../components/ShelfPage';
import { UpdateFeedPage } from '../components/UpdateFeedPage';
import { SearchPage } from '../components/SearchPage';
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';

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
struct Index {
  @StorageLink('mainTabIndex') currentIndex: number = 0;
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
      Tabs({ barPosition: BarPosition.End, controller: this.controller, index: this.currentIndex }) {
        TabContent() { ShelfPage() }.tabBar(this.TabBuilder('书架', 0))
        TabContent() { UpdateFeedPage() }.tabBar(this.TabBuilder('最新', 1))
        TabContent() { SearchPage() }.tabBar(this.TabBuilder('搜索', 2))
        TabContent() { SettingsPage() }.tabBar(this.TabBuilder('设置', 3))
      }
      .onChange((index: number): void => { this.currentIndex = index })
      .barHeight(60)
      .backgroundColor(this.getColors().tabBarBg)
      .layoutWeight(1)
      // ✅ 关键：让整个 Tabs 组件（含 TabBar）扩展到系统安全区外（底部导航栏区域）
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getColors().pageBg)
    // ✅ 顶部也扩展，让内容能延伸到状态栏后面
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}