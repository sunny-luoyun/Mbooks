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

/**
 * 根据模式返回颜色配置
 */
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

  // ✅ 核心修改：使用 @StorageProp 订阅系统的 currentColorMode
  // 当系统深色模式切换时，AppStorage 会自动更新此变量并触发 UI 重绘
  @StorageProp('currentColorMode') colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  private controller: TabsController = new TabsController()

  /**
   * 动态获取颜色（计算属性）
   */
  private getColors(): ColorConfig {
    return getIndexColors(this.colorMode);
  }

  @Builder TabBuilder(title: string, index: number) {
    Column() {
      Text(title)
        .fontSize(16)
        // 使用 getColors() 确保属性联动
        .fontColor(this.currentIndex === index ? this.getColors().tabTextActive : this.getColors().tabTextInactive)
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
      .onChange((index: number): void => {
        this.currentIndex = index
      })
      .barHeight(60)
      // 背景颜色会随 getColors() 实时改变
      .backgroundColor(this.getColors().tabBarBg)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getColors().pageBg)
    // 强制 UI 重新渲染的微调，确保组件感知到 mode 变化
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}