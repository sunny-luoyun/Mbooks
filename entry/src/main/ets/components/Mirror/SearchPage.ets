// entry/src/main/ets/components/Mirror/SearchPage.ets
import router from '@ohos.router';
import { CrawlerService } from '../../services/CrawlerService';
import { ThreadItemWithMarks } from '../../models/SettingsModels';
import common from '@ohos.app.ability.common';

// 只保留Mirror相关的历史管理
const HISTORY_KEY = 'mirror_search_history';
const MAX_HISTORY = 20;

class SearchHistoryManager {
  static getHistory(): string[] {
    try {
      const raw = AppStorage.get<string>(HISTORY_KEY) ?? '[]';
      return JSON.parse(raw) as string[];
    } catch {
      return [];
    }
  }

  static addHistory(keyword: string): void {
    if (!keyword.trim()) return;
    const list = SearchHistoryManager.getHistory();
    const filtered = list.filter(k => k !== keyword);
    filtered.unshift(keyword);
    const trimmed = filtered.slice(0, MAX_HISTORY);
    AppStorage.setOrCreate(HISTORY_KEY, JSON.stringify(trimmed));
  }

  static removeHistory(keyword: string): void {
    const list = SearchHistoryManager.getHistory();
    const filtered = list.filter(k => k !== keyword);
    AppStorage.setOrCreate(HISTORY_KEY, JSON.stringify(filtered));
  }

  static clearHistory(): void {
    AppStorage.setOrCreate(HISTORY_KEY, '[]');
  }
}

interface SearchColors {
  pageBg: string;
  cardBg: string;
  headerBg: string;
  searchBg: string;
  primaryText: string;
  secondaryText: string;
  tertiaryText: string;
  accentText: string;
  emptyText: string;
  emptySubText: string;
  divider: string;
  historyPanelBg: string;
  historyDeleteText: string;
}

function getSearchColors(mode: number): SearchColors {
  const isDark = mode === 0;
  return {
    pageBg: isDark ? '#0D0D0D' : '#F1F3F5',
    cardBg: isDark ? '#1E1E1E' : '#FFFFFF',
    headerBg: isDark ? '#141414' : '#FFFFFF',
    searchBg: isDark ? '#2A2A2A' : '#F5F5F5',
    primaryText: isDark ? '#E6E6E6' : '#000000',
    secondaryText: isDark ? '#999999' : '#666666',
    tertiaryText: isDark ? '#666666' : '#999999',
    accentText: '#007DFF',
    emptyText: isDark ? '#666666' : '#999999',
    emptySubText: isDark ? '#444444' : '#BBBBBB',
    divider: isDark ? '#2A2A2A' : '#E5E5E5',
    historyPanelBg: isDark ? '#1E1E1E' : '#FFFFFF',
    historyDeleteText: isDark ? '#666666' : '#BBBBBB',
  };
}

@Component
export struct SearchPage {
  @StorageLink('globalSearchKey') searchKey: string = ""
  @State searchResults: ThreadItemWithMarks[] = []
  @State isSearching: boolean = false
  @State colorMode: number = 0;
  private crawler: CrawlerService | null = null
  private configChangeCallback: () => void = () => {};
  private configCallbackId: number = -1;

  @State private inputValue: string = ""
  @State private historyList: string[] = []
  @State private showHistory: boolean = false

  async aboutToAppear(): Promise<void> {
    this.crawler = new CrawlerService(getContext(this) as common.UIAbilityContext)
    const ctx = getContext(this) as common.UIAbilityContext;
    this.colorMode = ctx.config?.colorMode || 0;

    this.configChangeCallback = () => {
      this.colorMode = ctx.config?.colorMode || 0;
    };
    this.configCallbackId = ctx.getApplicationContext().on('environment', {
      onConfigurationUpdated: this.configChangeCallback,
      onMemoryLevel: (_level: number) => {}
    });

    PersistentStorage.persistProp(HISTORY_KEY, '[]');
    this.historyList = SearchHistoryManager.getHistory();
    this.inputValue = this.searchKey;
    this.doSearch(this.searchKey || "");
  }

  aboutToDisappear(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    if (this.configCallbackId !== -1) {
      ctx.getApplicationContext().off('environment', this.configCallbackId);
    }
  }

  private getColors(): SearchColors {
    return getSearchColors(this.colorMode);
  }

  private refreshHistory(): void {
    this.historyList = SearchHistoryManager.getHistory();
  }

  private selectHistory(keyword: string): void {
    this.inputValue = keyword;
    this.searchKey = keyword;
    this.showHistory = false;
    this.doSearch(keyword);
  }

  private deleteHistoryItem(keyword: string): void {
    SearchHistoryManager.removeHistory(keyword);
    this.refreshHistory();
  }

  private clearAllHistory(): void {
    SearchHistoryManager.clearHistory();
    this.refreshHistory();
  }

  private doSearch(keyword: string): void {
    if (keyword.trim()) {
      SearchHistoryManager.addHistory(keyword.trim());
      this.refreshHistory();
    }
    this.searchKey = keyword;
    this.isSearching = true;
    if (this.crawler) {
      this.searchResults = this.crawler.searchLocal(keyword)
    }
    this.isSearching = false;
  }

  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Text('搜索 Mirror')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getColors().primaryText)
          .width('100%')
          .padding({
            left: 16, right: 16,
            top: 16 + px2vp(this.statusBarHeight),
            bottom: 16
          })

        // 搜索栏
        Row() {
          TextInput({
            text: this.inputValue,
            placeholder: '输入标题、作者或ID搜索...'
          })
            .layoutWeight(1)
            .height(40)
            .borderRadius(20)
            .backgroundColor(this.getColors().searchBg)
            .placeholderColor(this.getColors().tertiaryText)
            .fontColor(this.getColors().primaryText)
            .fontSize(14)
            .padding({ left: 16, right: 16 })
            .onChange((value: string): void => { this.inputValue = value; })
            .onFocus((): void => {
              this.historyList = SearchHistoryManager.getHistory();
              if (this.historyList.length > 0) this.showHistory = true;
            })
            .onSubmit((): void => {
              this.showHistory = false;
              this.doSearch(this.inputValue);
            })

          Button('搜索')
            .height(40)
            .borderRadius(20)
            .fontSize(14)
            .fontColor('#FFFFFF')
            .backgroundColor(this.getColors().accentText)
            .padding({ left: 20, right: 20 })
            .margin({ left: 8 })
            .onClick((): void => {
              this.showHistory = false;
              this.doSearch(this.inputValue);
            })
        }
        .width('92%')
        .alignSelf(ItemAlign.Center)
        .margin({ left: '4%', right: '4%', bottom: 12 })

        // 结果列表
        if (this.searchResults.length > 0) {
          Row() {
            Text('找到 ' + this.searchResults.length + ' 条结果')
              .fontSize(12).fontColor(this.getColors().tertiaryText)
            Blank()
            if (this.searchKey) {
              Button('清除')
                .fontSize(12).fontColor(this.getColors().accentText)
                .backgroundColor(Color.Transparent)
                .onClick((): void => {
                  this.inputValue = ""
                  this.searchKey = ""
                  this.doSearch("")
                })
            }
          }
          .width('92%').padding({ top: 12, bottom: 8 })
        }

        List({ space: 10 }) {
          ForEach(this.searchResults, (item: ThreadItemWithMarks): void => {
            ListItem() { this.SearchResultCard(item) }
            .width('92%')
          }, (item: ThreadItemWithMarks): string => item.threadId)
        }
        .width('100%').layoutWeight(1).alignListItem(ListItemAlign.Center)

        if (!this.isSearching && this.searchResults.length === 0) {
          Column() {
            Text('🔍').fontSize(60).margin({ bottom: 16 })
            Text(this.searchKey ? '未找到相关结果' : '输入关键词后点击搜索')
              .fontSize(16).fontColor(this.getColors().emptyText)
            if (this.searchKey) {
              Text('试试搜索其他关键词')
                .fontSize(12).fontColor(this.getColors().emptySubText).margin({ top: 8 })
            }
          }
          .margin({ top: 100 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.getColors().pageBg)
      .onClick((): void => {
        if (this.showHistory) this.showHistory = false;
      })

      if (this.showHistory && this.historyList.length > 0) {
        this.HistoryPanel()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder HistoryPanel() {
    Column() {
      Row() {
        Row() {
          Text('🕐').fontSize(13)
          Text(' 搜索历史')
            .fontSize(13).fontWeight(FontWeight.Medium)
            .fontColor(this.getColors().secondaryText)
        }
        Blank()
        Text('清空')
          .fontSize(12).fontColor(this.getColors().historyDeleteText)
          .onClick((): void => {
            this.clearAllHistory();
            this.showHistory = false;
          })
      }
      .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 6 })

      Divider()
        .color(this.getColors().divider).strokeWidth(0.5)
        .margin({ left: 16, right: 16 })

      List() {
        ForEach(this.historyList, (keyword: string): void => {
          ListItem() {
            Row() {
              Text('🔍').fontSize(13).margin({ right: 10 })
              Text(keyword)
                .fontSize(14).fontColor(this.getColors().primaryText)
                .layoutWeight(1).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .onClick((): void => { this.selectHistory(keyword); })
              Text('✕')
                .fontSize(13).fontColor(this.getColors().historyDeleteText)
                .padding({ left: 12, top: 4, bottom: 4 })
                .onClick((): void => {
                  this.deleteHistoryItem(keyword);
                  if (this.historyList.length === 0) this.showHistory = false;
                })
            }
            .width('100%').padding({ left: 16, right: 16, top: 11, bottom: 11 })
            .backgroundColor(this.getColors().historyPanelBg)
          }
        }, (keyword: string): string => keyword)
      }
      .width('100%').constraintSize({ maxHeight: 280 })
      .divider({ strokeWidth: 0.5, color: this.getColors().divider, startMargin: 16, endMargin: 16 })
    }
    .width('92%')
    .backgroundColor(this.getColors().historyPanelBg)
    .borderRadius(12)
    .shadow({ radius: 16, color: '#00000022', offsetY: 4 })
    .position({ x: '4%', y: px2vp(this.statusBarHeight) + 52 + 40 + 8 })
    .zIndex(999)
    .onClick((): void => {})
  }

  @Builder SearchResultCard(item: ThreadItemWithMarks) {
    Row() {
      Column() {
        Row() {
          if (item.watchMarks && item.watchMarks.length > 0) {
            Text(item.watchMarks)
              .fontSize(12).fontColor(this.getColors().accentText).margin({ right: 6 })
          }
          Text(item.title)
            .fontSize(16).fontWeight(FontWeight.Medium)
            .fontColor(this.getColors().primaryText)
            .layoutWeight(1).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')

        Row() {
          Text(item.author)
            .fontSize(12)
            .fontColor(this.crawler?.isWatchedAuthor(item.author) ? '#52C41A' : this.getColors().secondaryText)
            .fontWeight(this.crawler?.isWatchedAuthor(item.author) ? FontWeight.Bold : FontWeight.Normal)
          Text(' · ' + item.lastTime)
            .fontSize(12).fontColor(this.getColors().tertiaryText)
        }
        .margin({ top: 4 })
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start)

      Text('查看').fontSize(14).fontColor(this.getColors().accentText)
    }
    .width('100%').padding(16)
    .backgroundColor(this.getColors().cardBg).borderRadius(12)
    .onClick((): void => {
      router.pushUrl({
        url: 'pages/DetailPage',
        params: { threadId: item.threadId, title: item.title }
      })
    })
  }
}