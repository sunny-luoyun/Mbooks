// entry/src/main/ets/components/SearchPage.ets
import router from '@ohos.router';
import { CrawlerService } from '../services/CrawlerService';
import { ThreadItemWithMarks } from '../models/SettingsModels';
import common from '@ohos.app.ability.common';
import promptAction from '@ohos.promptAction';
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
} from '../models/PixivModels';
import { getPixivService, PixivService, SearchThrottle } from '../services/PixivService';
import { pixivCacheDB } from '../database/PixivCacheDB';

// ========================================
// 搜索历史管理器
// ========================================

const HISTORY_KEY = 'searchHistory';
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
    const list     = SearchHistoryManager.getHistory();
    const filtered = list.filter(k => k !== keyword);
    filtered.unshift(keyword);
    const trimmed  = filtered.slice(0, MAX_HISTORY);
    AppStorage.setOrCreate(HISTORY_KEY, JSON.stringify(trimmed));
  }

  static removeHistory(keyword: string): void {
    const list     = SearchHistoryManager.getHistory();
    const filtered = list.filter(k => k !== keyword);
    AppStorage.setOrCreate(HISTORY_KEY, JSON.stringify(filtered));
  }

  static clearHistory(): void {
    AppStorage.setOrCreate(HISTORY_KEY, '[]');
  }
}

// ========================================
// 颜色配置
// ========================================

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
  tagBg: string;
  tagText: string;
  cachedBadgeBg: string;
  cachingBadgeBg: string;
  failBadgeBg: string;
  toggleActiveBg: string;
  toggleInactiveBg: string;
  toggleActiveText: string;
  toggleInactiveText: string;
  historyPanelBg: string;
  historyItemHoverBg: string;
  historyDeleteText: string;
}

function getSearchColors(mode: number): SearchColors {
  const isDark = mode === 0;
  return {
    pageBg:             isDark ? '#0D0D0D' : '#F1F3F5',
    cardBg:             isDark ? '#1E1E1E' : '#FFFFFF',
    headerBg:           isDark ? '#141414' : '#FFFFFF',
    searchBg:           isDark ? '#2A2A2A' : '#F5F5F5',
    primaryText:        isDark ? '#E6E6E6' : '#000000',
    secondaryText:      isDark ? '#999999' : '#666666',
    tertiaryText:       isDark ? '#666666' : '#999999',
    quaternaryText:     isDark ? '#888888' : '#BBBBBB',
    accentText:         '#007DFF',
    btnText:            '#007DFF',
    watchedAuthor:      '#52C41A',
    normalAuthor:       isDark ? '#999999' : '#666666',
    emptyText:          isDark ? '#666666' : '#999999',
    emptySubText:       isDark ? '#444444' : '#BBBBBB',
    divider:            isDark ? '#2A2A2A' : '#E5E5E5',
    tagBg:              isDark ? '#2A2A2A' : '#F0F0F0',
    tagText:            isDark ? '#AAAAAA' : '#555555',
    cachedBadgeBg:      isDark ? '#1A3A1A' : '#F6FFED',
    cachingBadgeBg:     isDark ? '#3A2E00' : '#FFFBE6',
    failBadgeBg:        isDark ? '#3A1A1A' : '#FFF2F0',
    toggleActiveBg:     '#007DFF',
    toggleInactiveBg:   isDark ? '#2A2A2A' : '#F0F0F0',
    toggleActiveText:   '#FFFFFF',
    toggleInactiveText: isDark ? '#888888' : '#666666',
    historyPanelBg:     isDark ? '#1E1E1E' : '#FFFFFF',
    historyItemHoverBg: isDark ? '#2A2A2A' : '#F5F5F5',
    historyDeleteText:  isDark ? '#666666' : '#BBBBBB',
  };
}

// ========================================
// 主组件
// ========================================

@Component
export struct SearchPage {

  // ── 原有状态 ──
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

  // ── Pixiv 搜索（第二 Tab）──
  @State searchSource: SearchSource = SearchSource.LOCAL
  @State pixivResults: PixivNovel[] = []
  @State isPixivSearching: boolean = false
  @State pixivErrorMsg: string = ''
  @State pixivCurrentPage: number = 1
  @State pixivHasMore: boolean = false
  @State pixivTotal: number = 0

  // ── ★ 新增：Pixiv 关注（第三 Tab）──
  @State followingResults: PixivNovel[] = []
  @State isFollowingLoading: boolean = false
  @State followingErrorMsg: string = ''
  @State followingCurrentPage: number = 1
  @State followingHasMore: boolean = false
  @State followingTotal: number = 0

  // ── 共用 ──
  @State cachingIds: Set<string> = new Set()
  @StorageProp('pixivSortOrder')  pixivSortOrder: string  = PixivSortOrder.DATE_DESC
  @StorageProp('pixivContentMode') pixivContentMode: string = PixivContentMode.ALL
  private pixivService: PixivService = getPixivService()
  private throttle: SearchThrottle = new SearchThrottle(800)

  // ========================================
  // 生命周期
  // ========================================
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

    await pixivCacheDB.init(ctx);
    PersistentStorage.persistProp(HISTORY_KEY, '[]');
    this.historyList = SearchHistoryManager.getHistory();
    this.inputValue  = this.searchKey;
    this.doLocalSearch(this.searchKey || "");
  }

  aboutToDisappear(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    if (this.configCallbackId !== -1) {
      ctx.getApplicationContext().off('environment', this.configCallbackId);
    }
  }

  // ========================================
  // 工具
  // ========================================

  private getColors(): SearchColors {
    return getSearchColors(this.colorMode);
  }

  // ========================================
  // 历史记录操作
  // ========================================

  private refreshHistory(): void {
    this.historyList = SearchHistoryManager.getHistory();
  }

  private selectHistory(keyword: string): void {
    this.inputValue  = keyword;
    this.searchKey   = keyword;
    this.showHistory = false;
    this.triggerSearch(keyword);
  }

  private deleteHistoryItem(keyword: string): void {
    SearchHistoryManager.removeHistory(keyword);
    this.refreshHistory();
  }

  private clearAllHistory(): void {
    SearchHistoryManager.clearHistory();
    this.refreshHistory();
  }

  // ========================================
  // 搜索逻辑
  // ========================================

  private triggerSearch(keyword: string): void {
    if (keyword.trim()) {
      SearchHistoryManager.addHistory(keyword.trim());
      this.refreshHistory();
    }
    this.searchKey = keyword;

    if (this.searchSource === SearchSource.LOCAL) {
      this.doLocalSearch(keyword);
    } else if (this.searchSource === SearchSource.PIXIV) {
      this.doPixivSearch(keyword, 1);
    }
    // 关注 Tab 没有关键词搜索，忽略
  }

  private doLocalSearch(keyword: string): void {
    this.isSearching = true
    if (this.crawler) {
      this.searchResults = this.crawler.searchLocal(keyword)
    }
    this.isSearching = false
  }

  private doSearch(keyword: string): void {
    if (this.searchSource === SearchSource.LOCAL) {
      this.doLocalSearch(keyword)
    } else if (this.searchSource === SearchSource.PIXIV) {
      this.doPixivSearch(keyword, 1)
    }
  }

  private async doPixivSearch(keyword: string, page: number): Promise<void> {
    if (!keyword.trim()) {
      const cached = await pixivCacheDB.getAllCachedNovels()
      this.pixivResults = cached
      this.pixivTotal   = cached.length
      this.pixivHasMore = false
      return
    }

    if (!this.throttle.canSearch()) {
      promptAction.showToast({ message: `请稍候 ${this.throttle.remainingMs()}ms 后再搜索` })
      return
    }

    this.isPixivSearching = true
    this.pixivErrorMsg    = ''
    if (page === 1) this.pixivResults = []

    if (page === 1) {
      const cached = await pixivCacheDB.getMetaByKeyword(keyword)
      if (cached.length > 0) this.pixivResults = cached
    }

    const params: PixivSearchParams = {
      keyword,
      page,
      order:      this.pixivSortOrder   as PixivSortOrder,
      mode:       this.pixivContentMode as PixivContentMode,
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
      this.pixivTotal       = result.data.total
      this.pixivHasMore     = result.data.hasMore
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

  // ★ 新增：加载关注用户最新小说
  private async doFollowingLoad(page: number): Promise<void> {
    if (this.isFollowingLoading) return

    this.isFollowingLoading = true
    this.followingErrorMsg  = ''
    if (page === 1) this.followingResults = []

    const result = await this.pixivService.fetchFollowingNovels(page)

    if (result.success && result.data) {
      const merged = await this.mergeCacheStatus(result.data.novels)
      if (page === 1) {
        this.followingResults = merged
      } else {
        this.followingResults = this.followingResults.concat(merged)
      }
      this.followingTotal       = result.data.total
      this.followingHasMore     = result.data.hasMore
      this.followingCurrentPage = page
      // 同步落库，方便离线使用
      pixivCacheDB.saveNovelMetaBatch(result.data.novels)
    } else {
      this.followingErrorMsg = result.error ?? '加载失败'
      promptAction.showToast({ message: this.followingErrorMsg })
    }

    this.isFollowingLoading = false
  }

  private loadMoreFollowing(): void {
    if (!this.followingHasMore || this.isFollowingLoading) return
    this.doFollowingLoad(this.followingCurrentPage + 1)
  }

  // ── 通用：合并缓存状态 ──
  private async mergeCacheStatus(novels: PixivNovel[]): Promise<PixivNovel[]> {
    return Promise.all(
      novels.map(async (novel) => {
        const local = await pixivCacheDB.getNovelById(novel.id)
        if (local && local.cacheStatus === CacheStatus.CACHED) {
          return {
            id: novel.id, title: novel.title, caption: novel.caption,
            author: novel.author, authorId: novel.authorId, coverUrl: novel.coverUrl,
            tags: novel.tags, textLength: novel.textLength, pageCount: novel.pageCount,
            createDate: novel.createDate, updateDate: novel.updateDate,
            series: novel.series, bookmarkCount: novel.bookmarkCount,
            viewCount: novel.viewCount, commentCount: novel.commentCount,
            cacheStatus: CacheStatus.CACHED, cachedAt: local.cachedAt, fullText: local.fullText
          }
        }
        return novel
      })
    )
  }

  private loadMorePixiv(): void {
    if (!this.pixivHasMore || this.isPixivSearching) return
    this.doPixivSearch(this.searchKey, this.pixivCurrentPage + 1)
  }

  // ── 缓存操作（供两个 Pixiv Tab 共用）──
  private async cacheNovel(novel: PixivNovel): Promise<void> {
    if (this.cachingIds.has(novel.id)) return;

    // ★ 确保元数据已存在（幂等操作）
    await pixivCacheDB.saveNovelMeta(novel);

    const newSet = new Set<string>();
    this.cachingIds.forEach(id => newSet.add(id));
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

  /**
   * 同时更新两个列表（pixivResults / followingResults）中对应项的缓存状态
   * 这样无论从哪个 Tab 触发缓存操作，两边状态都保持同步
   */
  private updateNovelStatus(novelId: string, status: CacheStatus): void {
    const update = (list: PixivNovel[]): PixivNovel[] =>
    list.map(n => n.id === novelId
      ? { id: n.id, title: n.title, caption: n.caption, author: n.author,
        authorId: n.authorId, coverUrl: n.coverUrl, tags: n.tags,
        textLength: n.textLength, pageCount: n.pageCount,
        createDate: n.createDate, updateDate: n.updateDate, series: n.series,
        bookmarkCount: n.bookmarkCount, viewCount: n.viewCount,
        commentCount: n.commentCount, cacheStatus: status, fullText: n.fullText } as PixivNovel
      : n)
    this.pixivResults     = update(this.pixivResults)
    this.followingResults = update(this.followingResults)
  }

  private updateNovelStatusWithText(novelId: string, status: CacheStatus, fullText: string): void {
    const update = (list: PixivNovel[]): PixivNovel[] =>
    list.map(n => n.id === novelId
      ? { id: n.id, title: n.title, caption: n.caption, author: n.author,
        authorId: n.authorId, coverUrl: n.coverUrl, tags: n.tags,
        textLength: n.textLength, pageCount: n.pageCount,
        createDate: n.createDate, updateDate: n.updateDate, series: n.series,
        bookmarkCount: n.bookmarkCount, viewCount: n.viewCount,
        commentCount: n.commentCount, cacheStatus: status, fullText: fullText } as PixivNovel
      : n)
    this.pixivResults     = update(this.pixivResults)
    this.followingResults = update(this.followingResults)
  }

  // ── 阅读器 ──
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
    const novelId = String(novel.id);
    if (!novelId) {
      promptAction.showToast({ message: '无效的小说ID' });
      return;
    }
    router.pushUrl({
      url: 'pages/PixivNovelReaderPage',
      params: { novelId, title: novel.title, author: novel.author, offline: false }
    })
  }

  // ========================================
  // UI Builder
  // ========================================

  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {

      Column() {
        Text('搜索')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getColors().primaryText)
          .width('100%')
          .padding({
            left: 16, right: 16,
            top: 16 + px2vp(this.statusBarHeight),
            bottom: 16
          })

        this.SearchBar()
        this.SearchSourceToggle()

        if (this.searchSource === SearchSource.LOCAL) {
          this.LocalSearchContent()
        } else if (this.searchSource === SearchSource.PIXIV) {
          this.PixivSearchContent()
        } else {
          // ★ 新增：关注用户最新小说内容区
          this.FollowingContent()
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

  // ----------------------------------------
  // 搜索栏
  // ----------------------------------------

  @Builder SearchBar() {
    Row() {
      TextInput({
        text: this.inputValue,
        // 关注 Tab 不需要搜索，提示语不同
        placeholder: this.searchSource === SearchSource.LOCAL
          ? '输入标题、作者或ID搜索...'
          : this.searchSource === SearchSource.PIXIV
            ? '搜索 Pixiv 小说标题、作者或标签...'
            : '关注用户最新作品，无需关键词'
      })
        .layoutWeight(1)
        .height(40)
        .borderRadius(20)
        .backgroundColor(this.getColors().searchBg)
        .placeholderColor(this.getColors().tertiaryText)
        .fontColor(this.getColors().primaryText)
        .fontSize(14)
        .padding({ left: 16, right: 16 })
        // 关注 Tab 输入框只读（无搜索功能，展示提示即可）
        .enabled(this.searchSource !== SearchSource.PIXIV_FOLLOWING)
        .onChange((value: string): void => { this.inputValue = value; })
        .onFocus((): void => {
          if (this.searchSource === SearchSource.PIXIV_FOLLOWING) return;
          this.historyList = SearchHistoryManager.getHistory();
          if (this.historyList.length > 0) this.showHistory = true;
        })
        .onSubmit((): void => {
          this.showHistory = false;
          this.triggerSearch(this.inputValue);
        })

      Button(this.searchSource === SearchSource.PIXIV_FOLLOWING ? '刷新' : '搜索')
        .height(40)
        .borderRadius(20)
        .fontSize(14)
        .fontColor('#FFFFFF')
        .backgroundColor(this.getColors().accentText)
        .padding({ left: 20, right: 20 })
        .margin({ left: 8 })
        .onClick((): void => {
          this.showHistory = false;
          if (this.searchSource === SearchSource.PIXIV_FOLLOWING) {
            // 关注 Tab：刷新（从第一页重新加载）
            this.doFollowingLoad(1);
          } else {
            this.triggerSearch(this.inputValue);
          }
        })
    }
    .width('92%')
    .alignSelf(ItemAlign.Center)
    .margin({ left: '4%', right: '4%' })
  }

  // ----------------------------------------
  // 历史记录浮动面板（不变）
  // ----------------------------------------

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

  // ----------------------------------------
  // ★ 修改：搜索源切换 Tab（新增第三个）
  // ----------------------------------------

  @Builder SearchSourceToggle() {
    Scroll() {
      Row() {
        // Tab 1：本地书库
        Text('📚 本地书库')
          .fontSize(13)
          .fontWeight(this.searchSource === SearchSource.LOCAL
            ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.searchSource === SearchSource.LOCAL
            ? this.getColors().toggleActiveText
            : this.getColors().toggleInactiveText)
          .padding({ left: 16, right: 16, top: 7, bottom: 7 })
          .borderRadius(20)
          .backgroundColor(this.searchSource === SearchSource.LOCAL
            ? this.getColors().toggleActiveBg
            : this.getColors().toggleInactiveBg)
          .onClick((): void => {
            if (this.searchSource !== SearchSource.LOCAL) {
              this.searchSource = SearchSource.LOCAL
              this.doLocalSearch(this.searchKey)
            }
          })

        // Tab 2：Pixiv 小说
        Text('✨ Pixiv 小说')
          .fontSize(13)
          .fontWeight(this.searchSource === SearchSource.PIXIV
            ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.searchSource === SearchSource.PIXIV
            ? this.getColors().toggleActiveText
            : this.getColors().toggleInactiveText)
          .padding({ left: 16, right: 16, top: 7, bottom: 7 })
          .borderRadius(20)
          .backgroundColor(this.searchSource === SearchSource.PIXIV
            ? this.getColors().toggleActiveBg
            : this.getColors().toggleInactiveBg)
          .margin({ left: 10 })
          .onClick((): void => {
            if (this.searchSource !== SearchSource.PIXIV) {
              this.searchSource = SearchSource.PIXIV
              this.doPixivSearch(this.searchKey, 1)
            }
          })

        // ★ Tab 3：Pixiv 关注
        Text('💞 Pixiv 关注')
          .fontSize(13)
          .fontWeight(this.searchSource === SearchSource.PIXIV_FOLLOWING
            ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.searchSource === SearchSource.PIXIV_FOLLOWING
            ? this.getColors().toggleActiveText
            : this.getColors().toggleInactiveText)
          .padding({ left: 16, right: 16, top: 7, bottom: 7 })
          .borderRadius(20)
          .backgroundColor(this.searchSource === SearchSource.PIXIV_FOLLOWING
            ? this.getColors().toggleActiveBg
            : this.getColors().toggleInactiveBg)
          .margin({ left: 10 })
          .onClick((): void => {
            if (this.searchSource !== SearchSource.PIXIV_FOLLOWING) {
              this.searchSource = SearchSource.PIXIV_FOLLOWING
              // 切换时若列表为空则自动加载第一页
              if (this.followingResults.length === 0) {
                this.doFollowingLoad(1)
              }
            }
          })
      }
      .padding({ left: '4%', right: '4%' })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .padding({ top: 10, bottom: 6 })
  }

  // ----------------------------------------
  // 本地搜索内容区（原有，不变）
  // ----------------------------------------

  @Builder LocalSearchContent() {
    if (this.searchResults.length > 0) {
      Row() {
        Text('找到 ' + this.searchResults.length + ' 条结果')
          .fontSize(12).fontColor(this.getColors().tertiaryText)
        Blank()
        if (this.searchKey) {
          Button('清除')
            .fontSize(12).fontColor(this.getColors().btnText)
            .backgroundColor(Color.Transparent)
            .onClick((): void => {
              this.inputValue = ""
              this.searchKey  = ""
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

  // ----------------------------------------
  // Pixiv 搜索内容区（原有，不变）
  // ----------------------------------------

  @Builder PixivSearchContent() {
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
            .fontSize(12).fontColor(this.getColors().btnText)
            .backgroundColor(Color.Transparent)
            .onClick((): void => {
              this.inputValue = ""
              this.searchKey  = ""
              this.doPixivSearch("", 1)
            })
        }
      }
      .width('92%').padding({ top: 10, bottom: 6 })
    }

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
              .fontColor(this.getColors().btnText)
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
        Text('🥲🈚️').fontSize(60).margin({ bottom: 16 })
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

  // ----------------------------------------
  // ★ 新增：Pixiv 关注内容区
  // ----------------------------------------

  @Builder FollowingContent() {
    // 统计行
    if (this.followingResults.length > 0 || this.followingTotal > 0) {
      Row() {
        Text(`关注动态：共 ${this.followingTotal} 篇，已加载 ${this.followingResults.length} 篇`)
          .fontSize(12).fontColor(this.getColors().tertiaryText)
        Blank()
        if (this.followingErrorMsg && this.followingResults.length > 0) {
          Text('⚠️ 网络异常').fontSize(11).fontColor('#FAAD14')
        }
      }
      .width('92%').padding({ top: 10, bottom: 6 })
    }

    // 首次加载中
    if (this.isFollowingLoading && this.followingResults.length === 0) {
      Column() {
        LoadingProgress().width(48).height(48).color(this.getColors().accentText)
        Text('正在加载关注动态...')
          .fontSize(14).fontColor(this.getColors().secondaryText).margin({ top: 12 })
      }
      .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)

    } else if (this.followingResults.length > 0) {
      // 结果列表（复用 PixivNovelCard，完全相同的卡片样式）
      List({ space: 10 }) {
        ForEach(this.followingResults, (novel: PixivNovel): void => {
          ListItem() { this.PixivNovelCard(novel) }
          .width('92%')
        }, (novel: PixivNovel): string => `following_${novel.id}_${novel.cacheStatus}`)

        // 加载更多 / 到底了
        ListItem() {
          if (this.followingHasMore) {
            Button(this.isFollowingLoading ? '加载中...' : '加载更多')
              .width('100%').height(44).fontSize(14)
              .fontColor(this.getColors().btnText)
              .backgroundColor(this.getColors().cardBg)
              .borderRadius(12)
              .enabled(!this.isFollowingLoading)
              .onClick((): void => { this.loadMoreFollowing() })
          } else if (this.followingResults.length > 0) {
            Text('— 已加载全部关注动态 —')
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

    } else if (!this.isFollowingLoading) {
      // 空状态
      Column() {
        Text('💞').fontSize(60).margin({ bottom: 16 })
        Text(this.followingErrorMsg
          ? (this.followingErrorMsg.includes('Cookie') || this.followingErrorMsg.includes('登录')
            ? '请先登录 Pixiv'
            : '加载失败，请重试')
          : '点击右上角「刷新」加载关注动态')
          .fontSize(16).fontColor(this.getColors().emptyText)
          .textAlign(TextAlign.Center).padding({ left: 24, right: 24 })
        Text(this.followingErrorMsg
          ? (this.followingErrorMsg.includes('Cookie') || this.followingErrorMsg.includes('登录')
            ? '请在设置中填入有效的 PHPSESSID'
            : this.followingErrorMsg)
          : '将显示您在 Pixiv 关注用户的最新小说')
          .fontSize(12).fontColor(this.getColors().emptySubText)
          .textAlign(TextAlign.Center).padding({ left: 24, right: 24 })
          .margin({ top: 8 })
        // 快捷刷新按钮
        Button('立即加载')
          .fontSize(14).fontColor('#FFFFFF')
          .backgroundColor(this.getColors().accentText)
          .borderRadius(20).height(40)
          .padding({ left: 24, right: 24 })
          .margin({ top: 20 })
          .onClick((): void => { this.doFollowingLoad(1) })
      }
      .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
    }
  }

  // ----------------------------------------
  // Pixiv 小说卡片（两个 Pixiv Tab 共用）
  // ----------------------------------------

  @Builder PixivNovelCard(novel: PixivNovel) {
    Column() {
      Row() {
        if (novel.series) {
          Text(`[${novel.series.title}]`)
            .fontSize(11).fontColor(this.getColors().accentText)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '40%' }).margin({ right: 6 })
        }
        // 标题：如果有翻译，显示翻译后的标题
        Text(novel.hasTitleTranslation && novel.titleTranslated
          ? novel.titleTranslated
          : novel.title)
          .fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor(novel.hasTitleTranslation
            ? this.getColors().accentText
            : this.getColors().primaryText)
          .layoutWeight(1).maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        // 翻译标记
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

      // 操作按钮行
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
              ? '#FF4D4F' : this.getColors().btnText)
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
          .fontSize(12).fontColor(this.getColors().btnText)
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

  // ----------------------------------------
  // 缓存状态徽章（不变）
  // ----------------------------------------

  @Builder CacheStatusBadge(status: CacheStatus) {
    if (status !== CacheStatus.NOT_CACHED) {
      Text(getCacheStatusDisplay(status).label)
        .fontSize(10).fontColor(getCacheStatusDisplay(status).color)
        .backgroundColor(
          status === CacheStatus.CACHED  ? this.getColors().cachedBadgeBg  :
            status === CacheStatus.CACHING ? this.getColors().cachingBadgeBg :
              this.getColors().failBadgeBg
        )
        .borderRadius(4).padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .margin({ left: 6 }).flexShrink(0)
    } else {
      Blank()
    }
  }

  // ----------------------------------------
  // 原有本地搜索卡片（不变）
  // ----------------------------------------

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
            .fontColor(this.crawler?.isWatchedAuthor(item.author)
              ? this.getColors().watchedAuthor : this.getColors().normalAuthor)
            .fontWeight(this.crawler?.isWatchedAuthor(item.author)
              ? FontWeight.Bold : FontWeight.Normal)
          Text(' · ' + item.lastTime)
            .fontSize(12).fontColor(this.getColors().tertiaryText)
        }
        .margin({ top: 4 })
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start)

      Text('查看').fontSize(14).fontColor(this.getColors().btnText)
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