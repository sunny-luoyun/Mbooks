// entry/src/main/ets/components/Pixiv/PixivSearchPage.ets
import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import common from '@ohos.app.ability.common';
import {
  PixivNovel,
  PixivAuthor,
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
import { getDeepSeekService, DeepSeekService } from '../../services/DeepSeekService';

const HISTORY_KEY_NOVEL = 'pixiv_search_history_novel';
const HISTORY_KEY_AUTHOR = 'pixiv_search_history_author';
const MAX_HISTORY = 20;

class SearchHistoryManager {
  static getHistory(isAuthor: boolean): string[] {
    const key = isAuthor ? HISTORY_KEY_AUTHOR : HISTORY_KEY_NOVEL;
    try {
      const raw = AppStorage.get<string>(key) ?? '[]';
      return JSON.parse(raw) as string[];
    } catch {
      return [];
    }
  }

  static addHistory(keyword: string, isAuthor: boolean): void {
    const key = isAuthor ? HISTORY_KEY_AUTHOR : HISTORY_KEY_NOVEL;
    if (!keyword.trim()) return;
    const list = SearchHistoryManager.getHistory(isAuthor);
    const filtered = list.filter(k => k !== keyword);
    filtered.unshift(keyword);
    const trimmed = filtered.slice(0, MAX_HISTORY);
    AppStorage.setOrCreate(key, JSON.stringify(trimmed));
  }

  static removeHistory(keyword: string, isAuthor: boolean): void {
    const key = isAuthor ? HISTORY_KEY_AUTHOR : HISTORY_KEY_NOVEL;
    const list = SearchHistoryManager.getHistory(isAuthor);
    const filtered = list.filter(k => k !== keyword);
    AppStorage.setOrCreate(key, JSON.stringify(filtered));
  }

  static clearHistory(isAuthor: boolean): void {
    const key = isAuthor ? HISTORY_KEY_AUTHOR : HISTORY_KEY_NOVEL;
    AppStorage.setOrCreate(key, '[]');
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
  toggleBg: string;        // 新增：切换按钮背景
  toggleActive: string;    // 新增：切换按钮激活色
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
    toggleBg: isDark ? '#3A3A3A' : '#E5E5E5',
    toggleActive: '#FA8C16',
  };
}

@Component
export struct PixivSearchPage {
  @State searchKey: string = ""
  @State pixivResults: PixivNovel[] = []
  @State authorResults: PixivAuthor[] = []  // 新增：作者搜索结果
  @State isPixivSearching: boolean = false
  @State pixivErrorMsg: string = ''
  @State pixivCurrentPage: number = 1
  @State pixivHasMore: boolean = false
  @State pixivTotal: number = 0
  @State colorMode: number = 0;
  @State cachingIds: Set<string> = new Set()

  // 记录正在翻译中的小说ID（显示Loading）
  @State translatingIds: Set<string> = new Set()
  // 记录当前显示原文（而非译文）的小说ID，默认显示译文
  @State showingOriginalIds: Set<string> = new Set()

  // 新增：搜索类型切换 0=小说, 1=作者
  @State searchType: number = 0

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

    // 分别持久化两种搜索历史
    PersistentStorage.persistProp(HISTORY_KEY_NOVEL, '[]');
    PersistentStorage.persistProp(HISTORY_KEY_AUTHOR, '[]');

    this.historyList = SearchHistoryManager.getHistory(this.isAuthorSearch());

    // 默认加载已缓存的内容（仅小说模式）
    if (!this.isAuthorSearch()) {
      this.loadCachedNovels();
    }
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

  // 判断当前是否为作者搜索模式
  private isAuthorSearch(): boolean {
    return this.searchType === 1;
  }

  private refreshHistory(): void {
    this.historyList = SearchHistoryManager.getHistory(this.isAuthorSearch());
  }

  private selectHistory(keyword: string): void {
    this.inputValue = keyword;
    this.searchKey = keyword;
    this.showHistory = false;
    if (this.isAuthorSearch()) {
      this.doAuthorSearch(keyword, 1);
    } else {
      this.doPixivSearch(keyword, 1);
    }
  }

  private deleteHistoryItem(keyword: string): void {
    SearchHistoryManager.removeHistory(keyword, this.isAuthorSearch());
    this.refreshHistory();
  }

  private clearAllHistory(): void {
    SearchHistoryManager.clearHistory(this.isAuthorSearch());
    this.refreshHistory();
  }

  // 切换搜索类型
  private switchSearchType(type: number): void {
    if (this.searchType === type) return;
    this.searchType = type;
    this.inputValue = "";
    this.searchKey = "";
    this.pixivResults = [];
    this.authorResults = [];
    this.refreshHistory();

    if (type === 0) {
      this.loadCachedNovels();
    }
  }

  private async loadCachedNovels(): Promise<void> {
    const cached = await pixivCacheDB.getAllCachedNovels()
    this.pixivResults = cached
    this.pixivTotal = cached.length
    this.pixivHasMore = false
  }

  // 搜索小说（原有逻辑）
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

    SearchHistoryManager.addHistory(keyword.trim(), false);
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

  // 新增：搜索作者
  private async doAuthorSearch(keyword: string, page: number): Promise<void> {
    if (!keyword.trim()) {
      this.authorResults = [];
      return;
    }

    if (!this.throttle.canSearch()) {
      promptAction.showToast({ message: `请稍候 ${this.throttle.remainingMs()}ms 后再搜索` })
      return
    }

    this.isPixivSearching = true
    this.pixivErrorMsg = ''
    if (page === 1) this.authorResults = []

    SearchHistoryManager.addHistory(keyword.trim(), true);
    this.refreshHistory();

    const result = await this.pixivService.searchAuthors(keyword, page)

    // 🔍 超详细的调试日志
    console.info(`[SearchPage] ========== 作者搜索调试 ==========`)
    console.info(`[SearchPage] success: ${result.success}`)
    console.info(`[SearchPage] error: ${result.error}`)
    console.info(`[SearchPage] data 是否存在: ${!!result.data}`)

    if (result.data) {
      console.info(`[SearchPage] authors 数组长度: ${result.data.authors?.length || 0}`)
      console.info(`[SearchPage] total: ${result.data.total}`)
      console.info(`[SearchPage] hasMore: ${result.data.hasMore}`)
      console.info(`[SearchPage] 第一个作者: ${JSON.stringify(result.data.authors?.[0]) || '无'}`)
    }

    if (result.success && result.data) {
      if (page === 1) {
        this.authorResults = result.data.authors
      } else {
        this.authorResults = this.authorResults.concat(result.data.authors)
      }
      this.pixivTotal = result.data.total
      this.pixivHasMore = result.data.hasMore
      this.pixivCurrentPage = page

      // 如果结果为空但success为true，提示用户
      if (result.data.authors.length === 0) {
        console.warn(`[SearchPage] API返回成功但作者列表为空`)
        promptAction.showToast({ message: '未找到相关作者' })
      }
    } else {
      this.pixivErrorMsg = result.error ?? '搜索失败'
      console.error(`[SearchPage] 搜索失败: ${this.pixivErrorMsg}`)
      if (this.authorResults.length === 0) {
        promptAction.showToast({ message: this.pixivErrorMsg })
      }
    }
    this.isPixivSearching = false
  }

  private async mergeCacheStatus(novels: PixivNovel[]): Promise<PixivNovel[]> {
    return Promise.all(
      novels.map(async (novel) => {
        const local = await pixivCacheDB.getNovelById(novel.id);
        if (local) {
          // 原有缓存状态合并
          if (local.cacheStatus === CacheStatus.CACHED) {
            novel.cacheStatus = CacheStatus.CACHED;
            novel.cachedAt = local.cachedAt;
            novel.fullText = local.fullText;
          }
          // ✅ 新增：合并标题翻译状态
          if (local.hasTitleTranslation && local.titleTranslated) {
            novel.titleTranslated = local.titleTranslated;
            novel.hasTitleTranslation = true;
          }
        }
        return novel;
      })
    );
  }

  private loadMore(): void {
    if (!this.pixivHasMore || this.isPixivSearching) return;
    if (this.isAuthorSearch()) {
      this.doAuthorSearch(this.searchKey, this.pixivCurrentPage + 1);
    } else {
      this.doPixivSearch(this.searchKey, this.pixivCurrentPage + 1);
    }
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

  private async handleTitleClick(novel: PixivNovel): Promise<void> {
    // 如果正在翻译，忽略点击
    if (this.translatingIds.has(novel.id)) {
      return;
    }

    // 如果已经有翻译，切换原文/译文
    if (novel.hasTitleTranslation && novel.titleTranslated) {
      const newSet = new Set(this.showingOriginalIds);
      if (newSet.has(novel.id)) {
        newSet.delete(novel.id);
        promptAction.showToast({ message: '已切换为译文' });
      } else {
        newSet.add(novel.id);
        promptAction.showToast({ message: '已切换为原文' });
      }
      this.showingOriginalIds = newSet;
      return;
    }

    // ✅ 修复1：加明确类型 DeepSeekService，消除 any/unknown 报错
    const service: DeepSeekService = getDeepSeekService();
    if (!service.hasValidKey()) {
      promptAction.showToast({ message: '请先在设置中填入 DeepSeek API 密钥' });
      return;
    }

    this.translatingIds.add(novel.id);
    this.translatingIds = new Set(this.translatingIds);

    const result = await service.translateText(novel.title, true);

    if (result.success && result.translatedText) {
      await pixivCacheDB.saveTitleTranslation(novel.id, result.translatedText);

      novel.titleTranslated = result.translatedText;
      novel.hasTitleTranslation = true;

      // ✅ 正确代码：把两处 searchResults 都改为 pixivResults
      this.pixivResults = this.pixivResults.map((n: PixivNovel): PixivNovel => {
        if (n.id === novel.id) {
          n.titleTranslated = novel.titleTranslated;
          n.hasTitleTranslation = novel.hasTitleTranslation;
        }
        return n;
      });

      promptAction.showToast({ message: '标题翻译完成' });
    } else {
      promptAction.showToast({ message: result.error || '翻译失败' });
    }

    this.translatingIds.delete(novel.id);
    this.translatingIds = new Set(this.translatingIds);
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

  // 新增：跳转到作者详情页
  private openAuthorPage(author: PixivAuthor): void {
    router.pushUrl({
      url: 'pages/PixivAuthorPage',
      params: {
        authorId: author.id,
        authorName: author.name,
        authorAvatar: author.avatarUrl
      }
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

        // 新增：搜索类型切换开关
        Row() {
          // 搜索小说按钮
          Column() {
            Text('🔍 小说')
              .fontSize(14)
              .fontWeight(this.searchType === 0 ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.searchType === 0 ? '#FFFFFF' : this.getColors().secondaryText)
              .padding({ left: 20, right: 20, top: 8, bottom: 8 })
          }
          .backgroundColor(this.searchType === 0 ? this.getColors().toggleActive : this.getColors().toggleBg)
          .borderRadius(20)
          .onClick(() => this.switchSearchType(0))

          // 搜索作者按钮
          Column() {
            Text('👤 作者')
              .fontSize(14)
              .fontWeight(this.searchType === 1 ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.searchType === 1 ? '#FFFFFF' : this.getColors().secondaryText)
              .padding({ left: 20, right: 20, top: 8, bottom: 8 })
          }
          .backgroundColor(this.searchType === 1 ? this.getColors().toggleActive : this.getColors().toggleBg)
          .borderRadius(20)
          .margin({ left: 12 })
          .onClick(() => this.switchSearchType(1))
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 12 })
        .justifyContent(FlexAlign.Center)

        // 搜索栏
        Row() {
          TextInput({
            text: this.inputValue,
            placeholder: this.isAuthorSearch() ? '搜索 Pixiv 作者...' : '搜索 Pixiv 小说标题、作者或标签...'
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
              this.historyList = SearchHistoryManager.getHistory(this.isAuthorSearch());
              if (this.historyList.length > 0) this.showHistory = true;
            })
            .onSubmit((): void => {
              this.showHistory = false;
              this.searchKey = this.inputValue;
              if (this.isAuthorSearch()) {
                this.doAuthorSearch(this.inputValue, 1);
              } else {
                this.doPixivSearch(this.inputValue, 1);
              }
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
              if (this.isAuthorSearch()) {
                this.doAuthorSearch(this.inputValue, 1);
              } else {
                this.doPixivSearch(this.inputValue, 1);
              }
            })
        }
        .width('92%')
        .alignSelf(ItemAlign.Center)
        .margin({ left: '4%', right: '4%', bottom: 12 })

        // 统计信息
        if ((this.pixivResults.length > 0 || this.authorResults.length > 0) || this.pixivTotal > 0) {
          Row() {
            if (this.isAuthorSearch()) {
              Text(`共找到 ${this.pixivTotal} 位作者，显示 ${this.authorResults.length} 位`)
                .fontSize(12).fontColor(this.getColors().tertiaryText)
            } else {
              Text(this.searchKey
                ? `共 ${this.pixivTotal} 条结果，已加载 ${this.pixivResults.length} 条`
                : `离线缓存 ${this.pixivResults.length} 本`)
                .fontSize(12).fontColor(this.getColors().tertiaryText)
            }
            Blank()
            if (this.pixivErrorMsg && (this.pixivResults.length > 0 || this.authorResults.length > 0)) {
              Text('⚠️ 网络异常，显示缓存').fontSize(11).fontColor('#FAAD14')
            }
            if (this.searchKey) {
              Button('清除')
                .fontSize(12).fontColor(this.getColors().accentText)
                .backgroundColor(Color.Transparent)
                .onClick((): void => {
                  this.inputValue = ""
                  this.searchKey = ""
                  if (this.isAuthorSearch()) {
                    this.authorResults = [];
                  } else {
                    this.loadCachedNovels()
                  }
                })
            }
          }
          .width('92%').padding({ top: 10, bottom: 6 })
        }

        // 内容列表 - 根据搜索类型显示不同内容
        if (this.isPixivSearching &&
          (this.isAuthorSearch() ? this.authorResults.length === 0 : this.pixivResults.length === 0)) {
          Column() {
            LoadingProgress().width(48).height(48).color(this.getColors().accentText)
            Text(this.isAuthorSearch() ? '正在搜索作者...' : '正在搜索 Pixiv...')
              .fontSize(14).fontColor(this.getColors().secondaryText).margin({ top: 12 })
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.isAuthorSearch()) {
          // 作者列表
          this.AuthorListView()
        } else {
          // 小说列表（原有逻辑）
          this.NovelListView()
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

  // 新增：作者列表视图
  @Builder AuthorListView() {
    if (this.authorResults.length > 0) {
      List({ space: 10 }) {
        ForEach(this.authorResults, (author: PixivAuthor): void => {
          ListItem() { this.AuthorCard(author) }
          .width('92%')
        }, (author: PixivAuthor): string => author.id)

        ListItem() {
          if (this.pixivHasMore) {
            Button(this.isPixivSearching ? '加载中...' : '加载更多')
              .width('100%').height(44).fontSize(14)
              .fontColor(this.getColors().accentText)
              .backgroundColor(this.getColors().cardBg)
              .borderRadius(12)
              .enabled(!this.isPixivSearching)
              .onClick((): void => { this.loadMore() })
          } else if (this.authorResults.length > 0) {
            Text('— 已加载全部作者 —')
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
        Text('👤').fontSize(60).margin({ bottom: 16 })
        Text(this.searchKey ? '未找到相关作者' : '输入关键词搜索作者')
          .fontSize(16).fontColor(this.getColors().emptyText)
        Text(this.searchKey ? '试试其他关键词' : '搜索作者查看其所有作品')
          .fontSize(12).fontColor(this.getColors().emptySubText).margin({ top: 8 })
      }
      .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
    }
  }

  // 新增：作者卡片
  @Builder AuthorCard(author: PixivAuthor) {
    Row() {
      // 头像
      Column() {
        if (author.avatarUrl) {
          Image(author.avatarUrl)
            .width(50)
            .height(50)
            .borderRadius(25)
            .objectFit(ImageFit.Cover)
        } else {
          Column() {
            Text('👤').fontSize(24)
          }
          .width(50)
          .height(50)
          .borderRadius(25)
          .backgroundColor(this.getColors().searchBg)
          .justifyContent(FlexAlign.Center)
        }
      }
      .margin({ right: 12 })

      // 信息
      Column() {
        Row() {
          Text(author.name)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getColors().primaryText)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (author.isFollowed) {
            Text('已关注')
              .fontSize(10)
              .fontColor('#52C41A')
              .backgroundColor(this.getColors().cachedBadgeBg)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(4)
              .margin({ left: 8 })
          }
        }
        .width('100%')

        Text(`@${author.account}`)
          .fontSize(12)
          .fontColor(this.getColors().tertiaryText)
          .margin({ top: 4 })
          .width('100%')

        if (author.novelCount !== undefined || author.illustCount !== undefined) {
          Row() {
            if (author.novelCount !== undefined) {
              Text(`${author.novelCount} 部小说`)
                .fontSize(11)
                .fontColor(this.getColors().accentText)
                .backgroundColor(this.getColors().tagBg)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .borderRadius(4)
                .margin({ right: 8 })
            }
            if (author.illustCount !== undefined) {
              Text(`${author.illustCount} 张插画`)
                .fontSize(11)
                .fontColor(this.getColors().tagText)
                .backgroundColor(this.getColors().tagBg)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .borderRadius(4)
            }
          }
          .width('100%')
          .margin({ top: 6 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 箭头
      Text('〉')
        .fontSize(16)
        .fontColor(this.getColors().tertiaryText)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.getColors().cardBg)
    .borderRadius(12)
    .onClick(() => this.openAuthorPage(author))
  }

  // 小说列表视图（原有逻辑提取）
  @Builder NovelListView() {
    if (this.pixivResults.length > 0) {
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
              .onClick((): void => { this.loadMore() })
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
    .position({ x: '4%', y: px2vp(this.statusBarHeight) + 52 + 80 + 8 })
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
            .onClick(() => {
              // 阻止事件冒泡，避免触发卡片的其他点击
              if (novel.series) {
                router.pushUrl({
                  url: 'pages/PixivSeriesPage',
                  params: {
                    seriesId: novel.series.id,
                    seriesTitle: novel.series.title
                  }
                });
              }
            })
            // 添加手势反馈
            .gesture(
              TapGesture({ count: 1 })
                .onAction(() => {
                  // 点击效果已在 onClick 中处理
                })
            )
        }
        Row() {
          // ① 翻译进行中时，显示转圈 Loading
          if (this.translatingIds.has(novel.id)) {
            LoadingProgress()
              .width(14)
              .height(14)
              .color(this.getColors().accentText)
              .margin({ right: 6 })
          }

          // ② 根据 showingOriginalIds 决定显示原文还是译文
          Text(
            this.showingOriginalIds.has(novel.id) || !novel.titleTranslated
              ? novel.title
              : novel.titleTranslated
          )
            .fontSize(15).fontWeight(FontWeight.Medium)
            .fontColor(novel.hasTitleTranslation ? this.getColors().accentText : this.getColors().primaryText)
            .layoutWeight(1).maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)         // ⬅️ 把原来 Text 上的 layoutWeight 移到 Row 上
        .onClick(() => this.handleTitleClick(novel))

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