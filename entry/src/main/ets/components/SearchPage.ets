// entry/src/main/ets/components/SearchPage.ets
import router from '@ohos.router';
import { CrawlerService } from '../services/CrawlerService';
import { ThreadItemWithMarks } from '../models/SettingsModels';
import common from '@ohos.app.ability.common';
import { Configuration } from '@ohos.app.ability.Configuration';

// 颜色配置接口
interface SearchColors {
  pageBg: string;
  cardBg: string;
  headerBg: string;
  searchBg: string;
  primaryText: string;
  secondaryText: string;
  tertiaryText: string;
  quaternaryText: string;
  accentText: string;
  btnText: string;
  watchedAuthor: string;
  normalAuthor: string;
  emptyText: string;
  emptySubText: string;
  divider: string;
}
// 颜色配置函数 - 根据模式返回对应颜色
function getSearchColors(mode: number): SearchColors {
  const isDark = mode === 0; // ColorMode.Dark = 1
  return {
    // 背景色
    pageBg: isDark ? '#0D0D0D' : '#F1F3F5',
    cardBg: isDark ? '#1E1E1E' : '#FFFFFF',
    headerBg: isDark ? '#141414' : '#FFFFFF',
    searchBg: isDark ? '#2A2A2A' : '#F5F5F5',

    // 文字色
    primaryText: isDark ? '#E6E6E6' : '#000000',
    secondaryText: isDark ? '#999999' : '#666666',
    tertiaryText: isDark ? '#666666' : '#999999',
    quaternaryText: isDark ? '#888888' : '#BBBBBB',
    accentText: '#007DFF',

    // 按钮文字
    btnText: '#007DFF',

    // 关注作者颜色
    watchedAuthor: '#52C41A',
    normalAuthor: isDark ? '#999999' : '#666666',

    // 空状态
    emptyText: isDark ? '#666666' : '#999999',
    emptySubText: isDark ? '#444444' : '#BBBBBB',

    // 其他
    divider: isDark ? '#2A2A2A' : '#E5E5E5'
  };
}

@Component
export struct SearchPage {
  @StorageLink('globalSearchKey') @Watch('onSearchKeyChange') searchKey: string = ""
  @State searchResults: ThreadItemWithMarks[] = []
  @State isSearching: boolean = false
  @State colorMode: number = 0; // 0 = Light, 1 = Dark
  private crawler: CrawlerService | null = null
  private configChangeCallback: () => void = () => {};
  private configCallbackId: number = -1;

  // 监听函数：当 searchKey 发生变化时自动执行
  onSearchKeyChange() {
    if (this.searchKey) {
      this.doSearch(this.searchKey)
    }
  }
  aboutToAppear(): void {
    this.crawler = new CrawlerService(getContext(this) as common.UIAbilityContext)

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

    this.doSearch(this.searchKey || "")
    this.doSearch("");
  }
  aboutToDisappear(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    if (this.configCallbackId !== -1) {
      ctx.getApplicationContext().off('environment', this.configCallbackId);
    }
  }
  // 获取当前颜色配置
  private getColors(): SearchColors {
    return getSearchColors(this.colorMode);
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
              .fontColor(this.getColors().accentText)
              .margin({ right: 6 })
          }

          Text(item.title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.getColors().primaryText)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')

        Row() {
          Text(item.author)
            .fontSize(12)
            .fontColor(this.crawler?.isWatchedAuthor(item.author) ? this.getColors().watchedAuthor : this.getColors().normalAuthor)
            .fontWeight(this.crawler?.isWatchedAuthor(item.author) ? FontWeight.Bold : FontWeight.Normal)

          Text(' · ' + item.lastTime)
            .fontSize(12)
            .fontColor(this.getColors().tertiaryText)
        }
        .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text('查看')
        .fontSize(14)
        .fontColor(this.getColors().btnText)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.getColors().cardBg)
    .borderRadius(12)
    .onClick((): void => {
      router.pushUrl({
        url: 'pages/DetailPage',
        params: { threadId: item.threadId, title: item.title }
      })
    })
  }
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  build() {
    Column() {
      // 标题
      Text('搜索')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.getColors().primaryText)
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          top: 16 + px2vp(this.statusBarHeight),  // ✅ 加上状态栏高度
          bottom: 16
        })

      // 搜索框
      Search({
        value: this.searchKey,
        placeholder: '输入标题、作者或ID搜索已爬取的帖子...'
      })
        .width('92%')
        .backgroundColor(this.getColors().searchBg)
        .placeholderColor(this.getColors().tertiaryText)
        .fontColor(this.getColors().primaryText)
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
            .fontColor(this.getColors().tertiaryText)
          Blank()
          if (this.searchKey) {
            Button('清除')
              .fontSize(12)
              .fontColor(this.getColors().btnText)
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
            .fontColor(this.getColors().emptyText)
          if (this.searchKey) {
            Text('试试搜索其他关键词')
              .fontSize(12)
              .fontColor(this.getColors().emptySubText)
              .margin({ top: 8 })
          }
        }
        .margin({ top: 100 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getColors().pageBg)
  }
}