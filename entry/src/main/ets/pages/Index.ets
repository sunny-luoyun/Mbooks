// entry/src/main/ets/pages/Index.ets
import { SettingsPage } from './SettingsPage';
import { ShelfPage } from '../components/ShelfPage';
import { UpdateFeedPage } from '../components/UpdateFeedPage';
import { SearchPage } from '../components/SearchPage';

@Entry
@Component
struct Index {
  @StorageLink('mainTabIndex') currentIndex: number = 0
  private controller: TabsController = new TabsController()

  @Builder TabBuilder(title: string, index: number) {
    Column() {
      Text(title)
        .fontSize(16)
        .fontColor(this.currentIndex === index ? '#007DFF' : '#666')
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
      .backgroundColor('#F9F9F9')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }
}