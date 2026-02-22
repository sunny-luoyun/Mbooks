// entry/src/main/ets/components/UpdateFeedPage.ets
import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { CrawlerService } from '../services/CrawlerService';
import { ThreadItem, ThreadItemWithMarks } from '../models/SettingsModels';

interface ResumeInfo {
  hasBreakpoint: boolean;
  page: number;
}

@Component
export struct UpdateFeedPage {
  @State newThreads: ThreadItemWithMarks[] = []
  @State updatedThreads: ThreadItemWithMarks[] = []
  @State isLoading: boolean = false
  @State hasBreakpoint: boolean = false
  @State resumePage: number = 1
  @State hasMore: boolean = false
  private crawler: CrawlerService | null = null;

  aboutToAppear(): void {
    this.crawler = new CrawlerService(getContext(this) as Context);
    this.checkBreakpoint();
    this.loadExistingData();
  }

  checkBreakpoint(): void {
    if (this.crawler) {
      const info: ResumeInfo = this.crawler.getResumeInfo() as ResumeInfo;
      this.hasBreakpoint = info.hasBreakpoint;
      this.resumePage = info.page;
    }
  }

  loadExistingData(): void {
    if (this.crawler) {
      this.newThreads = this.crawler.searchLocal("").filter((t: ThreadItemWithMarks): boolean => t.isNew).slice(0, 20);
      this.updatedThreads = this.crawler.searchLocal("").filter((t: ThreadItemWithMarks): boolean => t.isUpdated).slice(0, 20);
    }
  }

  async startCheck(continueFromBreakpoint: boolean): Promise<void> {
    if (!this.crawler) return;

    this.isLoading = true;
    try {
      const result = await this.crawler.syncLatestThreads(continueFromBreakpoint);

      this.newThreads = result.newThreads as ThreadItemWithMarks[];
      this.updatedThreads = result.updatedThreads as ThreadItemWithMarks[];
      this.hasMore = result.hasMore;
      this.hasBreakpoint = result.hasMore;
      this.resumePage = Math.floor(result.resumeOffset / 30) + 1;

      let msg: string = '新帖:' + result.newThreads.length + ' 更新:' + result.updatedThreads.length;
      if (result.hasMore) msg += " (有断点)";
      promptAction.showToast({ message: msg });

    } catch (e) {
      promptAction.showToast({ message: "爬取失败" });
    } finally {
      this.isLoading = false;
    }
  }

  @Builder ThreadCard(thread: ThreadItemWithMarks, isUpdate: boolean) {
    Column() {
      // 标题行
      Row() {
        // 关注标记
        if (thread.watchMarks && thread.watchMarks.length > 0) {
          Text(thread.watchMarks)
            .fontSize(14)
            .margin({ right: 6 })
        }

        if (thread.isNew) {
          Text('新').fontSize(10).fontColor('#FFF').backgroundColor('#52C41A').padding({ left: 4, right: 4 }).borderRadius(4).margin({ right: 6 })
        }
        if (thread.isUpdated) {
          Text('更').fontSize(10).fontColor('#FFF').backgroundColor('#FA8C16').padding({ left: 4, right: 4 }).borderRadius(4).margin({ right: 6 })
        }
        Text(thread.title)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width('100%')

      // 标签
      if (thread.tags && thread.tags.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(thread.tags, (tag: string): void => {
            Text(tag)
              .fontSize(10)
              .fontColor('#007DFF')
              .backgroundColor('#E6F2FF')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(4)
              .margin({ right: 6, top: 4 })
          }, (tag: string): string => tag)
        }.width('100%').margin({ top: 6 })
      }

      // 更新对比信息
      if (isUpdate && thread.prevLastPid) {
        Row() {
          Text('PID: ' + thread.prevLastPid + ' → ' + thread.lastPid)
            .fontSize(11)
            .fontColor('#FA8C16')
            .backgroundColor('#FFF7E6')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
        }.width('100%').margin({ top: 6 })
      }

      // 底部信息
      Row() {
        Text(thread.author)
          .fontSize(12)
          .fontColor(this.crawler?.isWatchedAuthor(thread.author) ? '#52C41A' : '#007DFF')
          .fontWeight(this.crawler?.isWatchedAuthor(thread.author) ? FontWeight.Bold : FontWeight.Normal)
        Blank()
        Text(thread.lastTime).fontSize(12).fontColor('#999')
      }.width('100%').margin({ top: 8 })
    }
    .padding(14)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
    .shadow({ radius: 4, color: '#10000000' })
    .onClick((): void => {
      router.pushUrl({
        url: 'pages/DetailPage',
        params: { threadId: thread.threadId, title: thread.title }
      })
    })
  }

  build() {
    Column() {
      // 顶部控制栏
      Row() {
        Column() {
          Text('最新更新').fontSize(20).fontWeight(FontWeight.Bold)
          if (this.hasBreakpoint) {
            Text('断点: 第' + this.resumePage + '页').fontSize(12).fontColor('#FA8C16')
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)

        if (this.hasBreakpoint) {
          Button('继续爬')
            .fontSize(12)
            .height(32)
            .backgroundColor('#FA8C16')
            .margin({ right: 8 })
            .onClick(() => this.startCheck(true))
        }

        Button(this.isLoading ? '...' : (this.hasBreakpoint ? '重新开始' : '检查更新'))
          .fontSize(12)
          .height(32)
          .enabled(!this.isLoading)
          .onClick(() => this.startCheck(false))
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFF')
      .shadow({ radius: 2, color: '#10000000' })

      if (this.isLoading) {
        LoadingProgress().width(40).height(40).margin(20)
      }

      // 内容列表
      List({ space: 12 }) {
        if (this.updatedThreads.length > 0) {
          ListItemGroup({ header: this.SectionHeader('🔥 更新的帖子 (' + this.updatedThreads.length + ')', '#FA8C16') }) {
            ForEach(this.updatedThreads, (thread: ThreadItemWithMarks): void => {
              ListItem() {
                this.ThreadCard(thread, true)
              }.width('94%').margin({ left: '3%' })
            }, (thread: ThreadItemWithMarks): string => thread.threadId + '_updated')
          }
        }

        if (this.newThreads.length > 0) {
          ListItemGroup({ header: this.SectionHeader('🆕 新帖子 (' + this.newThreads.length + ')', '#52C41A') }) {
            ForEach(this.newThreads, (thread: ThreadItemWithMarks): void => {
              ListItem() {
                this.ThreadCard(thread, false)
              }.width('94%').margin({ left: '3%' })
            }, (thread: ThreadItemWithMarks): string => thread.threadId + '_new')
          }
        }

        if (!this.isLoading && this.newThreads.length === 0 && this.updatedThreads.length === 0) {
          ListItem() {
            Column() {
              Text('暂无更新').fontSize(16).fontColor('#999').margin({ top: 50 })
              Text('点击上方按钮检查').fontSize(12).fontColor('#BBB').margin({ top: 8 })
            }.width('100%')
          }
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }

  @Builder SectionHeader(title: string, color: string) {
    Row() {
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)
    }
    .width('94%')
    .padding({ left: 12, top: 8, bottom: 8 })
    .margin({ left: '3%' })
    .backgroundColor('#FFF')
    .borderRadius(8)
  }
}