// entry/src/main/ets/pages/SettingsPage.ets
import { CrawlerSettings } from '../components/settings/CrawlerSettings';
import { AuthorSettings } from '../components/settings/AuthorSettings';
import { BookSettings } from '../components/settings/BookSettings';
import { AboutSettings } from '../components/settings/AboutSettings';

@Entry
@Component
export struct SettingsPage {
  @State currentTab: number = 0;
  private tabs: string[] = ['爬取设置', '关注作者', '关注书籍', '关于'];

  // 使用 @Builder 但传递 key 强制重新创建
  @Builder TabContent(index: number) {
    if (index === 0) {
      CrawlerSettings()
    } else if (index === 1) {
      AuthorSettings()
    } else if (index === 2) {
      BookSettings()
    } else {
      AboutSettings()
    }
  }

  build() {
    Column() {
      // 顶部导航
      Row() {
        ForEach(this.tabs, (tab: string, index: number): void => {
          Column() {
            Text(tab)
              .fontSize(14)
              .fontWeight(this.currentTab === index ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.currentTab === index ? '#007DFF' : '#666')
            if (this.currentTab === index) {
              Divider()
                .strokeWidth(2)
                .color('#007DFF')
                .width(20)
                .margin({ top: 4 })
            }
          }
          .layoutWeight(1)
          .onClick((): void => {
            console.log('[SettingsPage] 点击 tab: ' + index);
            this.currentTab = index;
          })
        }, (tab: string): string => tab)
      }
      .width('100%')
      .height(50)
      .backgroundColor('#FFF')
      .shadow({ radius: 2, color: '#10000000' })

      // 内容区 - 使用 Stack 和 visibility 控制，或直接用条件渲染
      Stack() {
        // 所有组件都创建，但只显示当前 tab
        CrawlerSettings()
          .visibility(this.currentTab === 0 ? Visibility.Visible : Visibility.Hidden)

        AuthorSettings()
          .visibility(this.currentTab === 1 ? Visibility.Visible : Visibility.Hidden)

        BookSettings()
          .visibility(this.currentTab === 2 ? Visibility.Visible : Visibility.Hidden)

        AboutSettings()
          .visibility(this.currentTab === 3 ? Visibility.Visible : Visibility.Hidden)
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}