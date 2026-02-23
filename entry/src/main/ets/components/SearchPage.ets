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
  isReadableOffline
} from '../models/PixivModels';
import { getPixivService, PixivService, SearchThrottle } from '../services/PixivService';
import { pixivCacheDB } from '../database/PixivCacheDB';

// ========================================
// 颜色配置（完全保留原有，追加 Pixiv 所需字段）
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
  // ── 新增 Pixiv 专用 ──
  tagBg: string;
  tagText: string;
  cachedBadgeBg: string;
  cachingBadgeBg: string;
  failBadgeBg: string;
  toggleActiveBg: string;
  toggleInactiveBg: string;
  toggleActiveText: string;
  toggleInactiveText: string;
}

function getSearchColors(mode: number): SearchColors {
  const isDark = mode === 0;
  return {
    // ── 原有字段（完全不变）──
    pageBg:           isDark ? '#0D0D0D' : '#F1F3F5',
    cardBg:           isDark ? '#1E1E1E' : '#FFFFFF',
    headerBg:         isDark ? '#141414' : '#FFFFFF',
    searchBg:         isDark ? '#2A2A2A' : '#F5F5F5',
    primaryText:      isDark ? '#E6E6E6' : '#000000',
    secondaryText:    isDark ? '#999999' : '#666666',
    tertiaryText:     isDark ? '#666666' : '#999999',
    quaternaryText:   isDark ? '#888888' : '#BBBBBB',
    accentText:       '#007DFF',
    btnText:          '#007DFF',
    watchedAuthor:    '#52C41A',
    normalAuthor:     isDark ? '#999999' : '#666666',
    emptyText:        isDark ? '#666666' : '#999999',
    emptySubText:     isDark ? '#444444' : '#BBBBBB',
    divider:          isDark ? '#2A2A2A' : '#E5E5E5',
    // ── 新增字段 ──
    tagBg:              isDark ? '#2A2A2A' : '#F0F0F0',
    tagText:            isDark ? '#AAAAAA' : '#555555',
    cachedBadgeBg:      isDark ? '#1A3A1A' : '#F6FFED',
    cachingBadgeBg:     isDark ? '#3A2E00' : '#FFFBE6',
    failBadgeBg:        isDark ? '#3A1A1A' : '#FFF2F0',
    toggleActiveBg:     '#007DFF',
    toggleInactiveBg:   isDark ? '#2A2A2A' : '#F0F0F0',
    toggleActiveText:   '#FFFFFF',
    toggleInactiveText: isDark ? '#888888' : '#666666',
  };
}

// ========================================
// 主组件
// ========================================

@Component
export struct SearchPage {

  // ── 原有状态（完全不变）──
  @StorageLink('globalSearchKey') @Watch('onSearchKeyChange') searchKey: string = ""
  @State searchResults: ThreadItemWithMarks[] = []
  @State isSearching: boolean = false
  @State colorMode: number = 0;
  private crawler: CrawlerService | null = null
  private configChangeCallback: () => void = () => {};
  private configCallbackId: number = -1;

  // ── 新增：Pixiv 相关状态 ──
  @State searchSource: SearchSource = SearchSource.LOCAL
  @State pixivResults: PixivNovel[] = []
  @State isPixivSearching: boolean = false
  @State pixivErrorMsg: string = ''
  @State pixivCurrentPage: number = 1
  @State pixivHasMore: boolean = false
  @State pixivTotal: number = 0
  @State cachingIds: Set<string> = new Set() // 正在缓存中的 ID 集合
  // Pixiv 搜索配置（可从 AppStorage 读取用户偏好）
  @StorageProp('pixivSortOrder')  pixivSortOrder: string  = PixivSortOrder.DATE_DESC
  @StorageProp('pixivContentMode') pixivContentMode: string = PixivContentMode.ALL
  private pixivService: PixivService = getPixivService()
  private throttle: SearchThrottle = new SearchThrottle(800)

  // ========================================
  // 生命周期（原有逻辑完全保留，追加 DB 初始化）
  // ========================================

  onSearchKeyChange() {
    if (this.searchKey) {
      this.doSearch(this.searchKey)
    }
  }

  aboutToAppear(): void {
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

    // ── 新增：初始化 Pixiv 数据库 ──
    pixivCacheDB.init(ctx);

    this.doSearch(this.searchKey || "")
    this.doSearch("");
  }

  aboutToDisappear(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    if (this.configCallbackId !== -1) {
      ctx.getApplicationContext().off('environment', this.configCallbackId);
    }
  }

  // ========================================
  // 工具方法
  // ========================================

  private getColors(): SearchColors {
    return getSearchColors(this.colorMode);
  }

  // ========================================
  // 搜索逻辑
  // ========================================

  // 统一搜索入口：根据 searchSource 分发
  private doSearch(keyword: string): void {
    if (this.searchSource === SearchSource.LOCAL) {
      this.doLocalSearch(keyword)
    } else {
      this.doPixivSearch(keyword, 1)
    }
  }

  // 原有本地搜索（完全不变）
  private doLocalSearch(keyword: string): void {
    this.isSearching = true
    if (this.crawler) {
      this.searchResults = this.crawler.searchLocal(keyword)
    }
    this.isSearching = false
  }

  // 新增：Pixiv 联网搜索
  private async doPixivSearch(keyword: string, page: number): Promise<void> {
    if (!keyword.trim()) {
      // 关键词为空时显示离线缓存列表
      const cached = await pixivCacheDB.getAllCachedNovels()
      this.pixivResults = cached
      this.pixivTotal   = cached.length
      this.pixivHasMore = false
      return
    }

    if (!this.throttle.canSearch()) {
      promptAction.showToast({
        message: `请稍候 ${this.throttle.remainingMs()}ms 后再搜索`
      })
      return
    }

    this.isPixivSearching = true
    this.pixivErrorMsg    = ''
    if (page === 1) {
      this.pixivResults = []
    }

    // ① 优先展示本地缓存结果（秒显，离线友好）
    if (page === 1) {
      const cached = await pixivCacheDB.getMetaByKeyword(keyword)
      if (cached.length > 0) {
        this.pixivResults = cached
      }
    }

    // ② 联网搜索（更新最新结果）
    const params: PixivSearchParams = {
      keyword,
      page,
      order:  this.pixivSortOrder  as PixivSortOrder,
      mode:   this.pixivContentMode as PixivContentMode
    }
    const result = await this.pixivService.searchNovels(params)
    if (result.success && result.data) {
      const data = result.data
      const novels = data.novels
      const total = data.total
      const hasMore = data.hasMore

      // 合并缓存状态：联网结果里已缓存的条目保持 CACHED 标记
      const merged = await this.mergeCacheStatus(novels)

      if (page === 1) {
        this.pixivResults = merged
      } else {
        // 加载更多：追加
        this.pixivResults = this.pixivResults.concat(merged)
      }
      this.pixivTotal        = total
      this.pixivHasMore      = hasMore
      this.pixivCurrentPage  = page

      // 批量落库元数据（静默，不阻塞 UI）
      pixivCacheDB.saveNovelMetaBatch(novels)
    } else {
      // 联网失败但有本地缓存时不覆盖，仅提示
      this.pixivErrorMsg = result.error ?? '搜索失败'
      if (this.pixivResults.length === 0) {
        // 完全无结果才显示错误态
        promptAction.showToast({ message: this.pixivErrorMsg })
      }
    }

    this.isPixivSearching = false
  }

  // 联网结果与本地缓存状态合并
  private async mergeCacheStatus(novels: PixivNovel[]): Promise<PixivNovel[]> {
    return Promise.all(
      novels.map(async (novel) => {
        const local = await pixivCacheDB.getNovelById(novel.id)
        if (local && local.cacheStatus === CacheStatus.CACHED) {
          return {
            id: novel.id,
            title: novel.title,
            caption: novel.caption,
            author: novel.author,
            authorId: novel.authorId,
            coverUrl: novel.coverUrl,
            tags: novel.tags,
            textLength: novel.textLength,
            pageCount: novel.pageCount,
            createDate: novel.createDate,
            updateDate: novel.updateDate,
            series: novel.series,
            bookmarkCount: novel.bookmarkCount,
            viewCount: novel.viewCount,
            commentCount: novel.commentCount,
            cacheStatus: CacheStatus.CACHED,
            cachedAt: local.cachedAt,
            fullText: local.fullText
          }
        }
        return novel
      })
    )
  }

  // 新增：加载下一页
  private loadMorePixiv(): void {
    if (!this.pixivHasMore || this.isPixivSearching) return
    this.doPixivSearch(this.searchKey, this.pixivCurrentPage + 1)
  }

  // 新增：缓存单本正文
  private async cacheNovel(novel: PixivNovel): Promise<void> {
    if (this.cachingIds.has(novel.id)) return
    // 标记为缓存中（UI 立即反馈）
    const newCachingIds = new Set<string>()
    this.cachingIds.forEach(id => newCachingIds.add(id))
    newCachingIds.add(novel.id)
    this.cachingIds = newCachingIds
    this.updatePixivResultStatus(novel.id, CacheStatus.CACHING)
    await pixivCacheDB.markCaching(novel.id)

    const result = await this.pixivService.fetchNovelText(novel.id)

    if (result.success && result.data) {
      await pixivCacheDB.saveFullText(novel.id, result.data)
      this.updatePixivResultStatusWithText(novel.id, CacheStatus.CACHED, result.data)
      promptAction.showToast({ message: `《${novel.title}》缓存成功` })
    } else {
      await pixivCacheDB.markCacheFail(novel.id)
      this.updatePixivResultStatus(novel.id, CacheStatus.CACHE_FAIL)
      promptAction.showToast({ message: result.error ?? '缓存失败' })
    }
    // 移出进行中集合
    const next = new Set<string>()
    this.cachingIds.forEach(id => {
      if (id !== novel.id) {
        next.add(id)
      }
    })
    this.cachingIds = next
  }

  // 删除单本缓存
  private async deleteCache(novel: PixivNovel): Promise<void> {
    try {
      await pixivCacheDB.deleteCachedText(novel.id);
      // 更新列表状态为未缓存
      this.updatePixivResultStatus(novel.id, CacheStatus.NOT_CACHED);
      promptAction.showToast({ message: `《${novel.title}》缓存已删除` });
    } catch (e) {
      console.error('[SearchPage] deleteCache 失败: ' + JSON.stringify(e));
      promptAction.showToast({ message: '删除失败' });
    }
  }
  // 更新列表中单条的缓存状态（局部刷新，不重新请求）
  private updatePixivResultStatus(novelId: string, status: CacheStatus): void {
    this.pixivResults = this.pixivResults.map(n => {
      if (n.id === novelId) {
        const updated: PixivNovel = {
          id: n.id,
          title: n.title,
          caption: n.caption,
          author: n.author,
          authorId: n.authorId,
          coverUrl: n.coverUrl,
          tags: n.tags,
          textLength: n.textLength,
          pageCount: n.pageCount,
          createDate: n.createDate,
          updateDate: n.updateDate,
          series: n.series,
          bookmarkCount: n.bookmarkCount,
          viewCount: n.viewCount,
          commentCount: n.commentCount,
          cacheStatus: status,
          fullText: n.fullText
        } as PixivNovel
        return updated
      }
      return n
    })
  }

  // 更新缓存状态并设置全文内容
  private updatePixivResultStatusWithText(novelId: string, status: CacheStatus, fullText: string): void {
    this.pixivResults = this.pixivResults.map(n => {
      if (n.id === novelId) {
        const updated: PixivNovel = {
          id: n.id,
          title: n.title,
          caption: n.caption,
          author: n.author,
          authorId: n.authorId,
          coverUrl: n.coverUrl,
          tags: n.tags,
          textLength: n.textLength,
          pageCount: n.pageCount,
          createDate: n.createDate,
          updateDate: n.updateDate,
          series: n.series,
          bookmarkCount: n.bookmarkCount,
          viewCount: n.viewCount,
          commentCount: n.commentCount,
          cacheStatus: status,
          fullText: fullText
        } as PixivNovel
        return updated
      }
      return n
    })
  }

  // 跳转离线阅读页
  private async openOfflineReader(novel: PixivNovel): Promise<void> {
    const ctx = getContext(this) as common.UIAbilityContext;
    await pixivCacheDB.init(ctx);

    // 仅做存在性验证，不把正文放进路由
    const text = await pixivCacheDB.getFullText(novel.id);
    if (!text) {
      promptAction.showToast({ message: '缓存内容丢失，请重新缓存' });
      return;
    }

    // ✅ 只传轻量参数，正文由阅读页自己从 DB 读
    router.pushUrl({
      url: 'pages/PixivNovelReaderPage',
      params: {
        novelId: novel.id,
        title:   novel.title,
        author:  novel.author,
        offline: true
        // 不传 cachedText！
      }
    });
  }

  // 跳转在线阅读页（WebView）
  private openOnlineReader(novel: PixivNovel): void {
    const novelId = String(novel.id);  // ← 强制转字符串，防止数字ID
    if (!novelId) {
      promptAction.showToast({ message: '无效的小说ID' });
      return;
    }
    router.pushUrl({
      url: 'pages/PixivNovelReaderPage',
      params: {
        novelId: novelId,
        title:   novel.title,
        author:  novel.author,
        offline: false
      }
    })
  }

  // ========================================
  // UI Builder
  // ========================================

  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  build() {
    Column() {

      // ── 标题（原有，不变）──
      Text('搜索')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.getColors().primaryText)
        .width('100%')
        .padding({
          left:   16,
          right:  16,
          top:    16 + px2vp(this.statusBarHeight),
          bottom: 16
        })

      // ── 搜索框（原有，仅改 placeholder 适配双模式）──
      Search({
        value:       this.searchKey,
        placeholder: this.searchSource === SearchSource.LOCAL
          ? '输入标题、作者或ID搜索已爬取的帖子...'
          : '搜索 Pixiv 小说标题、作者或标签...'
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

      // ── 新增：搜索源切换 Tab ──
      this.SearchSourceToggle()

      // ── 根据搜索源展示不同内容 ──
      if (this.searchSource === SearchSource.LOCAL) {
        this.LocalSearchContent()
      } else {
        this.PixivSearchContent()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getColors().pageBg)
  }

  // ----------------------------------------
  // 搜索源切换 Tab
  // ----------------------------------------

  @Builder SearchSourceToggle() {
    Row() {
      // 本地书库
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

      // Pixiv 小说
      Text('Pixiv 小说')
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
    }
    .width('92%')
    .padding({ top: 10, bottom: 6 })
    .alignSelf(ItemAlign.Start)
    .margin({ left: '4%' })
  }

  // ----------------------------------------
  // 本地搜索内容区（原有逻辑，完全不变）
  // ----------------------------------------

  @Builder LocalSearchContent() {
    // 统计行
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

  // ----------------------------------------
  // Pixiv 搜索内容区（新增）
  // ----------------------------------------

  @Builder PixivSearchContent() {
    // 统计行
    if (this.pixivResults.length > 0 || this.pixivTotal > 0) {
      Row() {
        Text(this.searchKey
          ? `共 ${this.pixivTotal} 条结果，已加载 ${this.pixivResults.length} 条`
          : `离线缓存 ${this.pixivResults.length} 本`)
          .fontSize(12)
          .fontColor(this.getColors().tertiaryText)

        Blank()

        // 有离线缓存结果时显示错误提示（不遮挡列表）
        if (this.pixivErrorMsg && this.pixivResults.length > 0) {
          Text('⚠️ 网络异常，显示缓存')
            .fontSize(11)
            .fontColor('#FAAD14')
        }

        if (this.searchKey) {
          Button('清除')
            .fontSize(12)
            .fontColor(this.getColors().btnText)
            .backgroundColor(Color.Transparent)
            .onClick((): void => {
              this.searchKey = ""
              this.doPixivSearch("", 1)
            })
        }
      }
      .width('92%')
      .padding({ top: 10, bottom: 6 })
    }

    // 搜索中 Loading
    if (this.isPixivSearching && this.pixivResults.length === 0) {
      Column() {
        LoadingProgress()
          .width(48).height(48)
          .color(this.getColors().accentText)
        Text('正在搜索 Pixiv...')
          .fontSize(14)
          .fontColor(this.getColors().secondaryText)
          .margin({ top: 12 })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    }
    // 结果列表
    else if (this.pixivResults.length > 0) {
      List({ space: 10 }) {
        // 小说卡片列表
        ForEach(this.pixivResults, (novel: PixivNovel): void => {
          ListItem() {
            this.PixivNovelCard(novel)
          }
          .width('92%')
        }, (novel: PixivNovel): string => `${novel.id}_${novel.cacheStatus}`)

        // 加载更多 / 到底了
        ListItem() {
          if (this.pixivHasMore) {
            Button(this.isPixivSearching ? '加载中...' : '加载更多')
              .width('100%')
              .height(44)
              .fontSize(14)
              .fontColor(this.getColors().btnText)
              .backgroundColor(this.getColors().cardBg)
              .borderRadius(12)
              .enabled(!this.isPixivSearching)
              .onClick((): void => { this.loadMorePixiv() })
          } else if (this.pixivResults.length > 0) {
            Text('— 已加载全部结果 —')
              .fontSize(12)
              .fontColor(this.getColors().tertiaryText)
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 8, bottom: 8 })
          }
        }
        .width('92%')
      }
      .width('100%')
      .layoutWeight(1)
      .alignListItem(ListItemAlign.Center)
      .edgeEffect(EdgeEffect.Spring)
    }
    // 空状态
    else if (!this.isPixivSearching) {
      Column() {
        Text('🎌')
          .fontSize(60)
          .margin({ bottom: 16 })
        Text(this.searchKey
          ? (this.pixivErrorMsg ? '网络错误，无法搜索' : '未找到相关结果')
          : '搜索 Pixiv 小说，或查看离线缓存')
          .fontSize(16)
          .fontColor(this.getColors().emptyText)
        Text(this.searchKey
          ? (this.pixivErrorMsg ? '请检查网络或 Cookie 设置' : '试试其他关键词')
          : '已缓存的小说可在无网络时阅读')
          .fontSize(12)
          .fontColor(this.getColors().emptySubText)
          .margin({ top: 8 })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    }
  }

  // ----------------------------------------
  // Pixiv 小说卡片（新增）
  // ----------------------------------------

  @Builder PixivNovelCard(novel: PixivNovel) {
    Column() {
      // 第一行：标题 + 缓存状态徽章
      Row() {
        // 系列标签（有系列时显示）
        if (novel.series) {
          Text(`[${novel.series.title}]`)
            .fontSize(11)
            .fontColor(this.getColors().accentText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '40%' })
            .margin({ right: 6 })
        }

        Text(novel.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.getColors().primaryText)
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        // 缓存状态徽章
        this.CacheStatusBadge(novel.cacheStatus)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      // 第二行：作者 + 字数 + 日期
      Row() {
        Text(novel.author)
          .fontSize(12)
          .fontColor(this.getColors().secondaryText)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '50%' })

        Text(' · ' + formatTextLength(novel.textLength))
          .fontSize(12)
          .fontColor(this.getColors().tertiaryText)

        Text(' · ' + formatPixivDate(novel.createDate))
          .fontSize(12)
          .fontColor(this.getColors().tertiaryText)

        Blank()

        // 收藏数
        Text('♥ ' + novel.bookmarkCount)
          .fontSize(11)
          .fontColor(this.getColors().tertiaryText)
      }
      .width('100%')
      .margin({ top: 6 })

      // 第三行：标签
      if (novel.tags.length > 0) {
        Flex({ wrap: FlexWrap.Wrap, direction: FlexDirection.Row }) {
          ForEach(novel.tags.slice(0, 5), (tag: PixivTag): void => {
            Text('#' + (tag.translation ?? tag.name))
              .fontSize(11)
              .fontColor(this.getColors().tagText)
              .backgroundColor(this.getColors().tagBg)
              .borderRadius(4)
              .padding({ left: 6, right: 6, top: 3, bottom: 3 })
              .margin({ right: 6, top: 6 })
          })
        }
        .width('100%')
      }

      // 第四行：操作按钮
      Row() {
        Blank()

        // ⬇️ 新增：删除缓存按钮（仅已缓存时显示）
        if (novel.cacheStatus === CacheStatus.CACHED) {
          Button('删除缓存')
            .fontSize(12)
            .fontColor('#FF4D4F')
            .backgroundColor(this.getColors().searchBg)
            .borderRadius(8)
            .height(32)
            .padding({ left: 12, right: 12 })
            .onClick((): void => { this.deleteCache(novel) })
        }

        // 缓存/重试按钮
        if (novel.cacheStatus === CacheStatus.NOT_CACHED ||
          novel.cacheStatus === CacheStatus.CACHE_FAIL) {
          Button(novel.cacheStatus === CacheStatus.CACHE_FAIL ? '重试缓存' : '离线缓存')
            .fontSize(12)
            .fontColor(novel.cacheStatus === CacheStatus.CACHE_FAIL ? '#FF4D4F' : this.getColors().btnText)
            .backgroundColor(this.getColors().searchBg)
            .borderRadius(8)
            .height(32)
            .padding({ left: 12, right: 12 })
            .onClick((): void => { this.cacheNovel(novel) })
        }

        // 缓存中：禁用按钮 + 转圈
        if (novel.cacheStatus === CacheStatus.CACHING) {
          Row() {
            LoadingProgress()
              .width(16).height(16)
              .color(this.getColors().accentText)
            Text(' 缓存中')
              .fontSize(12)
              .fontColor(this.getColors().secondaryText)
          }
          .backgroundColor(this.getColors().searchBg)
          .borderRadius(8)
          .height(32)
          .padding({ left: 12, right: 12 })
        }

        // 离线阅读按钮（已缓存时才显示）
        if (isReadableOffline(novel)) {
          Button('离线阅读')
            .fontSize(12)
            .fontColor('#52C41A')
            .backgroundColor(this.getColors().cachedBadgeBg)
            .borderRadius(8)
            .height(32)
            .padding({ left: 12, right: 12 })
            .margin({ left: 8 })
            .onClick((): void => { this.openOfflineReader(novel) })
        }

        // 在线阅读（WebView）
        Button('在线阅读')
          .fontSize(12)
          .fontColor(this.getColors().btnText)
          .backgroundColor(this.getColors().searchBg)
          .borderRadius(8)
          .height(32)
          .padding({ left: 12, right: 12 })
          .margin({ left: 8 })
          .onClick((): void => { this.openOnlineReader(novel) })
      }
      .width('100%')
      .margin({ top: 10 })
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.getColors().cardBg)
    .borderRadius(12)
  }

  // ----------------------------------------
  // 缓存状态徽章（小组件）
  // ----------------------------------------
  @Builder CacheStatusBadge(status: CacheStatus) {
    if (status !== CacheStatus.NOT_CACHED) {
      Text(getCacheStatusDisplay(status).label)
        .fontSize(10)
        .fontColor(getCacheStatusDisplay(status).color)
        .backgroundColor(
          status === CacheStatus.CACHED  ? this.getColors().cachedBadgeBg  :
            status === CacheStatus.CACHING ? this.getColors().cachingBadgeBg :
              this.getColors().failBadgeBg
        )
        .borderRadius(4)
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .margin({ left: 6 })
        .flexShrink(0)
    } else {
      Blank()
    }
  }

  // ----------------------------------------
  // 原有本地搜索卡片（完全不变）
  // ----------------------------------------

  @Builder SearchResultCard(item: ThreadItemWithMarks) {
    Row() {
      Column() {
        Row() {
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
            .fontColor(this.crawler?.isWatchedAuthor(item.author)
              ? this.getColors().watchedAuthor
              : this.getColors().normalAuthor)
            .fontWeight(this.crawler?.isWatchedAuthor(item.author)
              ? FontWeight.Bold
              : FontWeight.Normal)
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
}