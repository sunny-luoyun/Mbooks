
// entry/src/main/ets/components/UpdateFeedPage.ets
import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import common from '@ohos.app.ability.common';
import { CrawlerService } from '../../services/CrawlerService';
import { ThreadItem, ThreadItemWithMarks } from '../../models/SettingsModels';
// import { Configuration } from '@ohos.arkui'; // 模块不存在，删除导入
interface ResumeInfo {
  hasBreakpoint: boolean;
  page: number;
}
interface ColorConfig {
  pageBg: string;
  cardBg: string;
  headerBg: string;
  primaryText: string;
  secondaryText: string;
  tertiaryText: string;
  quaternaryText: string;
  accentText: string;
  newTagBg: string;
  updateTagBg: string;
  newTagText: string;
  updateTagText: string;
  primaryBtnBg: string;
  secondaryBtnBg: string;
  secondaryBtnText: string;
  tagBg: string;
  tagText: string;
  compareBg: string;
  compareText: string;
  watchedAuthor: string;
  normalAuthor: string;
  shadow: string;
  sectionHeaderBg: string;
  emptyText: string;
  emptySubText: string;
}

interface ConfigUpdateEvent {
  colorMode: number;
}
// 颜色配置函数 - 根据模式返回对应颜色
function getUpdateFeedColors(mode: number): ColorConfig {
  const isDark = mode === 0; // ColorMode.Dark = 1
  return {
    // 背景色
    pageBg: isDark ? '#0D0D0D' : '#F5F5F5',
    cardBg: isDark ? '#1E1E1E' : '#FFFFFF',
    headerBg: isDark ? '#141414' : '#FFFFFF',

    // 文字色
    primaryText: isDark ? '#E6E6E6' : '#000000',
    secondaryText: isDark ? '#999999' : '#666666',
    tertiaryText: isDark ? '#666666' : '#999999',
    quaternaryText: isDark ? '#BBBBBB' : '#999999',
    accentText: '#007DFF',

    // 强调色
    newTagBg: '#52C41A',
    updateTagBg: '#FA8C16',
    newTagText: '#FFFFFF',
    updateTagText: '#FFFFFF',

    // 按钮背景
    primaryBtnBg: '#007DFF',
    secondaryBtnBg: '#FA8C16',
    secondaryBtnText: '#FFFFFF',

    // 标签背景
    tagBg: isDark ? '#1A3A5C' : '#E6F2FF',
    tagText: '#007DFF',

    // 对比信息背景
    compareBg: isDark ? '#3D2E1F' : '#FFF7E6',
    compareText: '#FA8C16',

    // 关注作者颜色
    watchedAuthor: '#52C41A',
    normalAuthor: '#007DFF',

    // 其他
    shadow: isDark ? '#000000' : '#10000000',
    sectionHeaderBg: isDark ? '#1E1E1E' : '#FFFFFF',
    emptyText: isDark ? '#666666' : '#999999',
    emptySubText: isDark ? '#444444' : '#BBBBBB'
  };
}

@Component
export struct UpdateFeedPage {
  @State newThreads: ThreadItemWithMarks[] = []
  @State updatedThreads: ThreadItemWithMarks[] = []
  @State isLoading: boolean = false
  @State hasBreakpoint: boolean = false
  @State resumePage: number = 1
  @State hasMore: boolean = false
  @State colorMode: number = 0; // 0 = Light, 1 = Dark
  private crawler: CrawlerService | null = null;
  private configChangeCallback: () => void = () => {};
  private configCallbackId: number = -1;
  aboutToAppear(): void {
    this.crawler = new CrawlerService(getContext(this) as common.UIAbilityContext);
    // 初始化颜色模式
    const ctx = getContext(this) as common.UIAbilityContext;
    this.colorMode = ctx.config?.colorMode || 0;
    // 监听系统颜色模式变化 - 使用ApplicationContext的配置监听
    this.configChangeCallback = () => {
      this.colorMode = ctx.config?.colorMode || 0;
    };
    // 使用正确的EnvironmentCallback类型
    this.configCallbackId = ctx.getApplicationContext().on('environment', {
      onConfigurationUpdated: this.configChangeCallback,
      onMemoryLevel: (level: number) => {
        // 内存级别变化的处理
      }
    });

    this.checkBreakpoint();
    this.loadExistingData();
  }
  aboutToDisappear(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    if (this.configCallbackId !== -1) {
      ctx.getApplicationContext().off('environment', this.configCallbackId);
    }
  }
  // 获取当前颜色配置
  private getColors(): ColorConfig {
    return getUpdateFeedColors(this.colorMode);
  }
  checkBreakpoint(): void {
    if (this.crawler) {
      const info = this.crawler.getResumeInfo();
      if (info && typeof info === 'object' && info.hasBreakpoint !== undefined && info.page !== undefined) {
        this.hasBreakpoint = info.hasBreakpoint;
        this.resumePage = info.page;
      }
    }
  }

  // 标记所有新帖/更新帖为已读
  private markAllAsRead(): void {
    if (!this.crawler) return;

    // 清除标记
    this.crawler.clearAllMarks();

    // 清空当前显示的列表
    this.newThreads = [];
    this.updatedThreads = [];

    // 可选：重新加载本地数据（此时应无新帖/更新帖）
    // this.loadExistingData(); // 如果上面清空后不需要显示，可以不调用

    // 提示用户
    promptAction.showToast({ message: '已清除所有新帖标记' });

    // 如果存在断点，也可以选择不清除断点，保持原样
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
            .fontColor(this.getColors().accentText)
            .margin({ right: 6 })
        }

        if (thread.isNew) {
          Text('新')
            .fontSize(10)
            .fontColor(this.getColors().newTagText)
            .backgroundColor(this.getColors().newTagBg)
            .padding({ left: 4, right: 4 })
            .borderRadius(4)
            .margin({ right: 6 })
        }
        if (thread.isUpdated) {
          Text('更')
            .fontSize(10)
            .fontColor(this.getColors().updateTagText)
            .backgroundColor(this.getColors().updateTagBg)
            .padding({ left: 4, right: 4 })
            .borderRadius(4)
            .margin({ right: 6 })
        }
        Text(thread.title)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getColors().primaryText)
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
              .fontColor(this.getColors().tagText)
              .backgroundColor(this.getColors().tagBg)
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
            .fontColor(this.getColors().compareText)
            .backgroundColor(this.getColors().compareBg)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
        }.width('100%').margin({ top: 6 })
      }

      // 底部信息
      Row() {
        Text(thread.author)
          .fontSize(12)
          .fontColor(this.crawler?.isWatchedAuthor(thread.author) ? this.getColors().watchedAuthor : this.getColors().normalAuthor)
          .fontWeight(this.crawler?.isWatchedAuthor(thread.author) ? FontWeight.Bold : FontWeight.Normal)
        Blank()
        Text(thread.lastTime).fontSize(12).fontColor(this.getColors().tertiaryText)
      }.width('100%').margin({ top: 8 })
    }
    .padding(14)
    .backgroundColor(this.getColors().cardBg)
    .borderRadius(12)
    .shadow({ radius: 4, color: this.getColors().shadow })
    .onClick((): void => {
      router.pushUrl({
        url: 'pages/DetailPage',
        params: { threadId: thread.threadId, title: thread.title }
      })
    })
  }
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;


  build() {
    Column() {
      // 顶部控制栏
      Row() {
        Column() {
          Text('最新更新')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getColors().primaryText)
          if (this.hasBreakpoint) {
            Text('断点: 第' + this.resumePage + '页')
              .fontSize(12)
              .fontColor(this.getColors().updateTagBg)
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)

        // 新增：标记为已读按钮
        if (this.newThreads.length > 0 || this.updatedThreads.length > 0) {
          Button('标记为已读')
            .fontSize(12)
            .height(32)
            .fontColor(this.getColors().primaryText)
            .backgroundColor('#CCCCCC')   // 灰色背景，可根据设计调整
            .margin({ right: 8 })
            .onClick(() => this.markAllAsRead())
        }

        if (this.hasBreakpoint) {
          Button('继续爬')
            .fontSize(12)
            .height(32)
            .fontColor(this.getColors().secondaryBtnText)
            .backgroundColor(this.getColors().secondaryBtnBg)
            .margin({ right: 8 })
            .onClick(() => this.startCheck(true))
        }

        Button(this.isLoading ? '...' : (this.hasBreakpoint ? '重新开始' : '检查更新'))
          .fontSize(12)
          .height(32)
          .enabled(!this.isLoading)
          .fontColor(this.getColors().primaryText)
          .backgroundColor(this.getColors().primaryBtnBg)
          .onClick(() => this.startCheck(false))
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 16 + px2vp(this.statusBarHeight),  // ✅ 加上状态栏高度
        bottom: 16
      })

      if (this.isLoading) {
        LoadingProgress()
          .width(40)
          .height(40)
          .color(this.getColors().accentText)
          .margin(20)
      }

      // 内容列表
      List({ space: 12 }) {
        if (this.updatedThreads.length > 0) {
          ListItemGroup({ header: this.SectionHeader('🔥 更新的帖子 (' + this.updatedThreads.length + ')', this.getColors().updateTagBg) }) {
            ForEach(this.updatedThreads, (thread: ThreadItemWithMarks): void => {
              ListItem() {
                this.ThreadCard(thread, true)
              }.width('94%').margin({ left: '3%' })
            }, (thread: ThreadItemWithMarks): string => thread.threadId + '_updated')
          }
        }

        if (this.newThreads.length > 0) {
          ListItemGroup({ header: this.SectionHeader('🆕 新帖子 (' + this.newThreads.length + ')', this.getColors().newTagBg) }) {
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
              Text('暂无更新')
                .fontSize(16)
                .fontColor(this.getColors().emptyText)
                .margin({ top: 50 })
              Text('点击上方按钮检查')
                .fontSize(12)
                .fontColor(this.getColors().emptySubText)
                .margin({ top: 8 })
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
    .backgroundColor(this.getColors().pageBg)
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
    .backgroundColor(this.getColors().sectionHeaderBg)
    .borderRadius(8)
  }
}