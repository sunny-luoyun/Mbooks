// entry/src/main/ets/components/SearchPage.ets
import router from '@ohos.router';
import { CrawlerService } from '../services/CrawlerService';
import { ThreadItemWithMarks } from '../models/SettingsModels';

@Component
export struct SearchPage {
  @StorageLink('globalSearchKey') @Watch('onSearchKeyChange') searchKey: string = ""
  @State searchResults: ThreadItemWithMarks[] = []
  @State isSearching: boolean = false
  private crawler: CrawlerService | null = null

  // 监听函数：当 searchKey 发生变化时自动执行
  onSearchKeyChange() {
    if (this.searchKey) {
      this.doSearch(this.searchKey)
    }
  }

  aboutToAppear(): void {
    this.crawler = new CrawlerService(getContext(this) as Context)
    this.doSearch(this.searchKey || "")


    this.doSearch("");
  }


  private doSearch(keyword: string): void {
    this.isSearching = true
    if (this.crawler) {
      this.searchResults = this.crawler.searchLocal(keyword)
    }
    this.isSearching = false
  }

  @Builder
  SearchResultCard(item: ThreadItemWithMarks) {
    Row() {
      Column() {
        Row() {
          // 关注标记
          if (item.watchMarks && item.watchMarks.length > 0) {
            Text(item.watchMarks)
              .fontSize(12)
              .margin({ right: 6 })
          }

          Text(item.title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')

        Row() {
          Text(item.author)
            .fontSize(12)
            .fontColor(this.crawler?.isWatchedAuthor(item.author) ? '#52C41A' : '#666')
            .fontWeight(this.crawler?.isWatchedAuthor(item.author) ? FontWeight.Bold : FontWeight.Normal)

          Text(' · ' + item.lastTime)
            .fontSize(12)
            .fontColor('#999')
        }
        .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text('查看')
        .fontSize(14)
        .fontColor('#007DFF')
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFF')
    .borderRadius(12)
    .onClick((): void => {
      router.pushUrl({
        url: 'pages/DetailPage',
        params: { threadId: item.threadId, title: item.title }
      })
    })
  }

  build() {
    Column() {
      // 标题
      Text('搜索')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding(16)

      // 搜索框
      Search({
        value: this.searchKey,
        placeholder: '输入标题、作者或ID搜索已爬取的帖子...'
      })
        .width('92%')
        .backgroundColor('#F5F5F5')
        .onChange((value: string): void => {
          this.searchKey = value
        })
        .onSubmit((value: string): void => {
          this.doSearch(value)
        })

      // 统计
      if (this.searchResults.length > 0) {
        Row() {
          Text('找到 ' + this.searchResults.length + ' 条结果')
            .fontSize(12)
            .fontColor('#999')
          Blank()
          if (this.searchKey) {
            Button('清除')
              .fontSize(12)
              .fontColor('#007DFF')
              .backgroundColor(Color.Transparent)
              .onClick((): void => {
                this.searchKey = ""
                this.doSearch("")
              })
          }
        }
        .width('92%')
        .padding({ top: 12, bottom: 8 })
      }

      // 结果列表
      List({ space: 10 }) {
        ForEach(this.searchResults, (item: ThreadItemWithMarks): void => {
          ListItem() {
            this.SearchResultCard(item)
          }
          .width('92%')
        }, (item: ThreadItemWithMarks): string => item.threadId)
      }
      .width('100%')
      .layoutWeight(1)
      .alignListItem(ListItemAlign.Center)

      // 空状态
      if (!this.isSearching && this.searchResults.length === 0) {
        Column() {
          Text('🔍')
            .fontSize(60)
            .margin({ bottom: 16 })
          Text(this.searchKey ? '未找到相关结果' : '输入关键词开始搜索')
            .fontSize(16)
            .fontColor('#999')
          if (this.searchKey) {
            Text('试试搜索其他关键词')
              .fontSize(12)
              .fontColor('#BBB')
              .margin({ top: 8 })
          }
        }
        .margin({ top: 100 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F1F3F5')
  }
}