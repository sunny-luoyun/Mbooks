// entry/src/main/ets/components/Pixiv/PixivSearchPage.ets
import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import common from '@ohos.app.ability.common';
import {
  PixivNovel,
  SearchSource,
  CacheStatus,
  PixivSearchParams,
  PixivSortOrder,
  PixivContentMode,
  PixivTag,
  formatTextLength,
  formatPixivDate,
  getCacheStatusDisplay,
  isReadableOffline,
  PixivSearchMode
} from '../../models/PixivModels';
import { getPixivService, SearchThrottle } from '../../services/PixivService';
import { pixivCacheDB } from '../../database/PixivCacheDB';

const HISTORY_KEY = 'pixiv_search_history';
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
  searchBg: string;
  primaryText: string;
  secondaryText: string;
  tertiaryText: string;
  accentText: string;
  tagBg: string;
  tagText: string;
  cachedBadgeBg: string;
  cachingBadgeBg: string;
  failBadgeBg: string;
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
    searchBg: isDark ? '#2A2A2A' : '#F5F5F5',
    primaryText: isDark ? '#E6E6E6' : '#000000',
    secondaryText: isDark ? '#999999' : '#666666',
    tertiaryText: isDark ? '#666666' : '#999999',
    accentText: '#FA8C16',  // Pixiv橙色
    tagBg: isDark ? '#2A2A2A' : '#F0F0F0',
    tagText: isDark ? '#AAAAAA' : '#555555',
    cachedBadgeBg: isDark ? '#1A3A1A' : '#F6FFED',
    cachingBadgeBg: isDark ? '#3A2E00' : '#FFFBE6',
    failBadgeBg: isDark ? '#3A1A1A' : '#FFF2F0',
    emptyText: isDark ? '#666666' : '#999999',
    emptySubText: isDark ? '#444444' : '#BBBBBB',
    divider: isDark ? '#2A2A2A' : '#E5E5E5',
    historyPanelBg: isDark ? '#1E1E1E' : '#FFFFFF',
    historyDeleteText: isDark ? '#666666' : '#BBBBBB',
  };
}

@Component
export struct PixivSearchPage {
  @State searchKey: string = ""
  @State pixivResults: PixivNovel[] = []
  @State isPixivSearching: boolean = false
  @State pixivErrorMsg: string = ''
  @State pixivCurrentPage: number = 1
  @State pixivHasMore: boolean = false
  @State pixivTotal: number = 0
  @State colorMode: number = 0;
  @State cachingIds: Set<string> = new Set()
  @StorageProp('pixivSortOrder') pixivSortOrder: string = PixivSortOrder.DATE_DESC
  @StorageProp('pixivContentMode') pixivContentMode: string = PixivContentMode.ALL

  @State private inputValue: string = ""
  @State private historyList: string[] = []
  @State private showHistory: boolean = false

  private pixivService = getPixivService()
  private throttle: SearchThrottle = new SearchThrottle(800)
  private configChangeCallback: () => void = () => {};
  private configCallbackId: number = -1;

  async aboutToAppear(): Promise<void> {
    const ctx = getContext(this) as common.UIAbilityContext;
    this.colorMode = ctx.config?.colorMode || 0;

    this.configChangeCallback = () => {
      this.colorMode = ctx.config?.colorMode || 0;
    };
    this.configCallbackId = ctx.getApplicationContext().on('environment', {
      onConfigurationUpdated: this.configChangeCallback,
      onMemoryLevel: (_level: number) => {}
    });

    await pixivCacheDB.init(ctx);
    PersistentStorage.persistProp(HISTORY_KEY, '[]');
    this.historyList = SearchHistoryManager.getHistory();

    // 默认加载已缓存的内容
    this.loadCachedNovels();
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
    this.doPixivSearch(keyword, 1);
  }

  private deleteHistoryItem(keyword: string): void {
    SearchHistoryManager.removeHistory(keyword);
    this.refreshHistory();
  }

  private clearAllHistory(): void {
    SearchHistoryManager.clearHistory();
    this.refreshHistory();
  }

  private async loadCachedNovels(): Promise<void> {
    const cached = await pixivCacheDB.getAllCachedNovels()
    this.pixivResults = cached
    this.pixivTotal = cached.length
    this.pixivHasMore = false
  }

  private async doPixivSearch(keyword: string, page: number): Promise<void> {
    if (!keyword.trim()) {
      this.loadCachedNovels();
      return;
    }

    if (!this.throttle.canSearch()) {
      promptAction.showToast({ message: `请稍候 ${this.throttle.remainingMs()}ms 后再搜索` })
      return
    }

    this.isPixivSearching = true
    this.pixivErrorMsg = ''
    if (page === 1) this.pixivResults = []

    if (page === 1) {
      const cached = await pixivCacheDB.getMetaByKeyword(keyword)
      if (cached.length > 0) this.pixivResults = cached
    }

    SearchHistoryManager.addHistory(keyword.trim());
    this.refreshHistory();

    const params: PixivSearchParams = {
      keyword,
      page,
      order: this.pixivSortOrder as PixivSortOrder,
      mode: this.pixivContentMode as PixivContentMode,
      searchMode: PixivSearchMode.TAG_ONLY
    }
    const result = await this.pixivService.searchNovels(params)
    if (result.success && result.data) {
      const merged = await this.mergeCacheStatus(result.data.novels)
      if (page === 1) {
        this.pixivResults = merged
      } else {
        this.pixivResults = this.pixivResults.concat(merged)
      }
      this.pixivTotal = result.data.total
      this.pixivHasMore = result.data.hasMore
      this.pixivCurrentPage = page
      pixivCacheDB.saveNovelMetaBatch(result.data.novels)
    } else {
      this.pixivErrorMsg = result.error ?? '搜索失败'
      if (this.pixivResults.length === 0) {
        promptAction.showToast({ message: this.pixivErrorMsg })
      }
    }
    this.isPixivSearching = false
  }

  private async mergeCacheStatus(novels: PixivNovel[]): Promise<PixivNovel[]> {
    return Promise.all(
      novels.map(async (novel) => {
        const local = await pixivCacheDB.getNovelById(novel.id)
        if (local && local.cacheStatus === CacheStatus.CACHED) {
          novel.cacheStatus = CacheStatus.CACHED;
          novel.cachedAt = local.cachedAt;
          novel.fullText = local.fullText;
        }
        return novel
      })
    )
  }

  private loadMorePixiv(): void {
    if (!this.pixivHasMore || this.isPixivSearching) return
    this.doPixivSearch(this.searchKey, this.pixivCurrentPage + 1)
  }

  private async cacheNovel(novel: PixivNovel): Promise<void> {
    if (this.cachingIds.has(novel.id)) return;
    await pixivCacheDB.saveNovelMeta(novel);

    const newSet = new Set<string>(this.cachingIds);
    newSet.add(novel.id);
    this.cachingIds = newSet;

    this.updateNovelStatus(novel.id, CacheStatus.CACHING);
    await pixivCacheDB.markCaching(novel.id);

    const result = await this.pixivService.fetchNovelText(novel.id);
    if (result.success && result.data) {
      await pixivCacheDB.saveFullText(novel.id, result.data);
      this.updateNovelStatusWithText(novel.id, CacheStatus.CACHED, result.data);
      promptAction.showToast({ message: `《${novel.title}》缓存成功` });
    } else {
      await pixivCacheDB.markCacheFail(novel.id);
      this.updateNovelStatus(novel.id, CacheStatus.CACHE_FAIL);
      promptAction.showToast({ message: result.error ?? '缓存失败' });
    }

    const next = new Set<string>();
    this.cachingIds.forEach(id => { if (id !== novel.id) next.add(id); });
    this.cachingIds = next;
  }

  private async deleteCache(novel: PixivNovel): Promise<void> {
    try {
      await pixivCacheDB.deleteCachedText(novel.id)
      this.updateNovelStatus(novel.id, CacheStatus.NOT_CACHED)
      promptAction.showToast({ message: `《${novel.title}》缓存已删除` })
    } catch (e) {
      promptAction.showToast({ message: '删除失败' })
    }
  }

  private updateNovelStatus(novelId: string, status: CacheStatus): void {
    this.pixivResults = this.pixivResults.map(n => {
      if (n.id === novelId) {
        n.cacheStatus = status;
      }
      return n;
    })
  }

  private updateNovelStatusWithText(novelId: string, status: CacheStatus, fullText: string): void {
    this.pixivResults = this.pixivResults.map(n => {
      if (n.id === novelId) {
        n.cacheStatus = status;
        n.fullText = fullText;
      }
      return n;
    })
  }

  private async openOfflineReader(novel: PixivNovel): Promise<void> {
    const ctx = getContext(this) as common.UIAbilityContext;
    await pixivCacheDB.init(ctx);
    const text = await pixivCacheDB.getFullText(novel.id);
    if (!text) {
      promptAction.showToast({ message: '缓存内容丢失，请重新缓存' });
      return;
    }
    router.pushUrl({
      url: 'pages/PixivNovelReaderPage',
      params: { novelId: novel.id, title: novel.title, author: novel.author, offline: true }
    });
  }

  private openOnlineReader(novel: PixivNovel): void {
    router.pushUrl({
      url: 'pages/PixivNovelReaderPage',
      params: { novelId: novel.id, title: novel.title, author: novel.author, offline: false }
    })
  }

  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Text('Pixiv 搜索')
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
            placeholder: '搜索 Pixiv 小说标题、作者或标签...'
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
              this.searchKey = this.inputValue;
              this.doPixivSearch(this.inputValue, 1);
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
              this.searchKey = this.inputValue;
              this.doPixivSearch(this.inputValue, 1);
            })
        }
        .width('92%')
        .alignSelf(ItemAlign.Center)
        .margin({ left: '4%', right: '4%', bottom: 12 })

        // 统计信息
        if (this.pixivResults.length > 0 || this.pixivTotal > 0) {
          Row() {
            Text(this.searchKey
              ? `共 ${this.pixivTotal} 条结果，已加载 ${this.pixivResults.length} 条`
              : `离线缓存 ${this.pixivResults.length} 本`)
              .fontSize(12).fontColor(this.getColors().tertiaryText)
            Blank()
            if (this.pixivErrorMsg && this.pixivResults.length > 0) {
              Text('⚠️ 网络异常，显示缓存').fontSize(11).fontColor('#FAAD14')
            }
            if (this.searchKey) {
              Button('清除')
                .fontSize(12).fontColor(this.getColors().accentText)
                .backgroundColor(Color.Transparent)
                .onClick((): void => {
                  this.inputValue = ""
                  this.searchKey = ""
                  this.loadCachedNovels()
                })
            }
          }
          .width('92%').padding({ top: 10, bottom: 6 })
        }

        // 内容列表
        if (this.isPixivSearching && this.pixivResults.length === 0) {
          Column() {
            LoadingProgress().width(48).height(48).color(this.getColors().accentText)
            Text('正在搜索 Pixiv...')
              .fontSize(14).fontColor(this.getColors().secondaryText).margin({ top: 12 })
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.pixivResults.length > 0) {
          List({ space: 10 }) {
            ForEach(this.pixivResults, (novel: PixivNovel): void => {
              ListItem() { this.PixivNovelCard(novel) }
              .width('92%')
            }, (novel: PixivNovel): string => `${novel.id}_${novel.cacheStatus}`)

            ListItem() {
              if (this.pixivHasMore) {
                Button(this.isPixivSearching ? '加载中...' : '加载更多')
                  .width('100%').height(44).fontSize(14)
                  .fontColor(this.getColors().accentText)
                  .backgroundColor(this.getColors().cardBg)
                  .borderRadius(12)
                  .enabled(!this.isPixivSearching)
                  .onClick((): void => { this.loadMorePixiv() })
              } else if (this.pixivResults.length > 0) {
                Text('— 已加载全部结果 —')
                  .fontSize(12).fontColor(this.getColors().tertiaryText)
                  .width('100%').textAlign(TextAlign.Center)
                  .padding({ top: 8, bottom: 8 })
              }
            }
            .width('92%')
          }
          .width('100%').layoutWeight(1)
          .alignListItem(ListItemAlign.Center)
          .edgeEffect(EdgeEffect.Spring)
        } else if (!this.isPixivSearching) {
          Column() {
            Text('🎨').fontSize(60).margin({ bottom: 16 })
            Text(this.searchKey
              ? (this.pixivErrorMsg ? '网络错误，无法搜索' : '未找到相关结果')
              : '输入关键词后点击搜索，或查看离线缓存')
              .fontSize(16).fontColor(this.getColors().emptyText)
            Text(this.searchKey
              ? (this.pixivErrorMsg ? '请检查网络或 Cookie 设置' : '试试其他关键词')
              : '已缓存的小说可在无网络时阅读')
              .fontSize(12).fontColor(this.getColors().emptySubText).margin({ top: 8 })
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
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

  @Builder PixivNovelCard(novel: PixivNovel) {
    Column() {
      Row() {
        if (novel.series) {
          Text(`[${novel.series.title}]`)
            .fontSize(11).fontColor(this.getColors().accentText)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '40%' }).margin({ right: 6 })
        }
        Text(novel.hasTitleTranslation && novel.titleTranslated
          ? novel.titleTranslated
          : novel.title)
          .fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor(novel.hasTitleTranslation ? this.getColors().accentText : this.getColors().primaryText)
          .layoutWeight(1).maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (novel.hasTitleTranslation) {
          Text('译')
            .fontSize(9)
            .fontColor('#52C41A')
            .backgroundColor('#F6FFED')
            .borderRadius(2)
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .margin({ left: 4 })
        }

        this.CacheStatusBadge(novel.cacheStatus)
      }
      .width('100%').alignItems(VerticalAlign.Top)

      Row() {
        Text(novel.author)
          .fontSize(12).fontColor(this.getColors().secondaryText)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '50%' })
        Text(' · ' + formatTextLength(novel.textLength))
          .fontSize(12).fontColor(this.getColors().tertiaryText)
        Text(' · ' + formatPixivDate(novel.createDate))
          .fontSize(12).fontColor(this.getColors().tertiaryText)
        Blank()
        Text('♥ ' + novel.bookmarkCount)
          .fontSize(11).fontColor(this.getColors().tertiaryText)
      }
      .width('100%').margin({ top: 6 })

      if (novel.tags.length > 0) {
        Flex({ wrap: FlexWrap.Wrap, direction: FlexDirection.Row }) {
          ForEach(novel.tags.slice(0, 5), (tag: PixivTag): void => {
            Text('#' + (tag.translation ?? tag.name))
              .fontSize(11).fontColor(this.getColors().tagText)
              .backgroundColor(this.getColors().tagBg).borderRadius(4)
              .padding({ left: 6, right: 6, top: 3, bottom: 3 })
              .margin({ right: 6, top: 6 })
          })
        }
        .width('100%')
      }

      Row() {
        Blank()
        if (novel.cacheStatus === CacheStatus.CACHED) {
          Button('删除缓存')
            .fontSize(12).fontColor('#FF4D4F')
            .backgroundColor(this.getColors().searchBg)
            .borderRadius(8).height(32).padding({ left: 12, right: 12 })
            .onClick((): void => { this.deleteCache(novel) })
        }
        if (novel.cacheStatus === CacheStatus.NOT_CACHED ||
          novel.cacheStatus === CacheStatus.CACHE_FAIL) {
          Button(novel.cacheStatus === CacheStatus.CACHE_FAIL ? '重试缓存' : '离线缓存')
            .fontSize(12)
            .fontColor(novel.cacheStatus === CacheStatus.CACHE_FAIL
              ? '#FF4D4F' : this.getColors().accentText)
            .backgroundColor(this.getColors().searchBg)
            .borderRadius(8).height(32).padding({ left: 12, right: 12 })
            .onClick((): void => { this.cacheNovel(novel) })
        }
        if (novel.cacheStatus === CacheStatus.CACHING) {
          Row() {
            LoadingProgress().width(16).height(16).color(this.getColors().accentText)
            Text(' 缓存中').fontSize(12).fontColor(this.getColors().secondaryText)
          }
          .backgroundColor(this.getColors().searchBg)
          .borderRadius(8).height(32).padding({ left: 12, right: 12 })
        }
        if (isReadableOffline(novel)) {
          Button('离线阅读')
            .fontSize(12).fontColor('#52C41A')
            .backgroundColor(this.getColors().cachedBadgeBg)
            .borderRadius(8).height(32).padding({ left: 12, right: 12 })
            .margin({ left: 8 })
            .onClick((): void => { this.openOfflineReader(novel) })
        }
        Button('在线阅读')
          .fontSize(12).fontColor(this.getColors().accentText)
          .backgroundColor(this.getColors().searchBg)
          .borderRadius(8).height(32).padding({ left: 12, right: 12 })
          .margin({ left: 8 })
          .onClick((): void => { this.openOnlineReader(novel) })
      }
      .width('100%').margin({ top: 10 })
    }
    .width('100%').padding(14)
    .backgroundColor(this.getColors().cardBg).borderRadius(12)
  }

  @Builder CacheStatusBadge(status: CacheStatus) {
    if (status !== CacheStatus.NOT_CACHED) {
      Text(getCacheStatusDisplay(status).label)
        .fontSize(10).fontColor(getCacheStatusDisplay(status).color)
        .backgroundColor(
          status === CacheStatus.CACHED ? this.getColors().cachedBadgeBg :
            status === CacheStatus.CACHING ? this.getColors().cachingBadgeBg :
              this.getColors().failBadgeBg
        )
        .borderRadius(4).padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .margin({ left: 6 }).flexShrink(0)
    } else {
      Blank()
    }
  }
}