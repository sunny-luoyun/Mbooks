// entry/src/main/ets/pages/MirrorIndex.ets
import { ShelfPage } from '../components/Mirror/ShelfPage';
import { UpdateFeedPage } from '../components/Mirror/UpdateFeedPage';
import { SearchPage } from '../components/Mirror/SearchPage';
// ✅ 新增：导入两个设置组件
import { AuthorSettings } from '../components/settings/AuthorSettings';
import { BookSettings } from '../components/settings/BookSettings';
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

// ✅ 设置页内部颜色配置
interface SettingColors {
  headerBg: string;
  cardBg: string;
  primaryText: string;
  secondaryText: string;
  accentText: string;
  divider: string;
}

function getSettingColors(mode: number): SettingColors {
  const isDark = mode === 0;
  return {
    headerBg: isDark ? '#1E1E1E' : '#FFFFFF',
    cardBg: isDark ? '#1E1E1E' : '#FFFFFF',
    primaryText: isDark ? '#E6E6E6' : '#000000',
    secondaryText: isDark ? '#999999' : '#666666',
    accentText: '#007DFF',
    divider: isDark ? '#2A2A2A' : '#E5E5E5'
  };
}

@Entry
@Component
struct MirrorIndex {
  @State currentIndex: number = 0;
  @StorageProp('currentColorMode') colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  // ✅ 新增：监听设置页传来的 Tab 跳转指令
  @StorageLink('mainTabIndex') @Watch('onMainTabIndexChange') mainTabIndex: number = -1;

  // ✅ 新增：当前选中的设置子tab（0=关注作者，1=关注书籍）
  @State currentSettingTab: number = 0;

  private controller: TabsController = new TabsController();

  private getColors(): ColorConfig {
    return getIndexColors(this.colorMode);
  }

  // ✅ 新增：处理 Tab 跳转
  onMainTabIndexChange() {
    if (this.mainTabIndex >= 0 && this.mainTabIndex < 4 && this.mainTabIndex !== this.currentIndex) {
      this.currentIndex = this.mainTabIndex;
      this.controller.changeIndex(this.mainTabIndex);
      // 消费掉这次跳转指令，防止重复触发
      AppStorage.setOrCreate('mainTabIndex', -1);
    }
  }

  aboutToAppear() {
    // ✅ 新增：初始化时检查是否有待处理的跳转（冷启动情况）
    const pendingTab = AppStorage.get<number>('mainTabIndex');
    if (pendingTab !== undefined && pendingTab >= 0 && pendingTab !== this.currentIndex) {
      this.currentIndex = pendingTab;
      this.controller.changeIndex(pendingTab);
      AppStorage.setOrCreate('mainTabIndex', -1);
    }
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

  // 设置页内容构建器（保持不变）
  @Builder MirrorSettingsContent() {
    Column() {
      // 内部分段控制器
      Row() {
        // 关注作者按钮
        Column() {
          Text('关注作者')
            .fontSize(16)
            .fontWeight(this.currentSettingTab === 0 ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.currentSettingTab === 0 ? getSettingColors(this.colorMode).accentText : getSettingColors(this.colorMode).secondaryText)

          if (this.currentSettingTab === 0) {
            Divider()
              .strokeWidth(2)
              .color(getSettingColors(this.colorMode).accentText)
              .width(20)
              .margin({ top: 4 })
          }
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.currentSettingTab = 0;
        })

        // 分隔线
        Divider()
          .vertical(true)
          .height(20)
          .color(getSettingColors(this.colorMode).divider)

        // 关注书籍按钮
        Column() {
          Text('关注书籍')
            .fontSize(16)
            .fontWeight(this.currentSettingTab === 1 ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.currentSettingTab === 1 ? getSettingColors(this.colorMode).accentText : getSettingColors(this.colorMode).secondaryText)

          if (this.currentSettingTab === 1) {
            Divider()
              .strokeWidth(2)
              .color(getSettingColors(this.colorMode).accentText)
              .width(20)
              .margin({ top: 4 })
          }
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.currentSettingTab = 1;
        })
      }
      .width('100%')
      .height(50)
      .backgroundColor(getSettingColors(this.colorMode).headerBg)

      // 内容区：根据currentSettingTab显示不同组件
      Stack() {
        // 关注作者
        Column() {
          AuthorSettings()
        }
        .visibility(this.currentSettingTab === 0 ? Visibility.Visible : Visibility.None)
        .width('100%')
        .height('100%')

        // 关注书籍
        Column() {
          BookSettings()
        }
        .visibility(this.currentSettingTab === 1 ? Visibility.Visible : Visibility.None)
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Column() {
      // 顶部导航
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

        Blank().width(60)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12 + px2vp(AppStorage.get<number>('statusBarHeight') || 0), bottom: 8 })
      .backgroundColor(this.getColors().tabBarBg)

      // Tabs
      Tabs({ barPosition: BarPosition.End, controller: this.controller, index: this.currentIndex }) {
        TabContent() { ShelfPage() }.tabBar(this.TabBuilder('书架', 0))
        TabContent() { UpdateFeedPage() }.tabBar(this.TabBuilder('最新', 1))
        TabContent() { SearchPage() }.tabBar(this.TabBuilder('搜索', 2))

        // 第4个Tab：设置（内部分段切换）
        TabContent() {
          this.MirrorSettingsContent()
        }.tabBar(this.TabBuilder('设置', 3))
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