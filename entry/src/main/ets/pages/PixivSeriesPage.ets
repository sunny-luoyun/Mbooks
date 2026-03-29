// entry/src/main/ets/pages/PixivSeriesPage.ets
import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import common from '@ohos.app.ability.common';
import {
  PixivNovel,
  CacheStatus,
  PixivTag,
  formatTextLength,
  formatPixivDate,
  isReadableOffline,
  getCacheStatusDisplay
} from '../models/PixivModels';
import { getPixivService } from '../services/PixivService';
import { pixivCacheDB } from '../database/PixivCacheDB';

interface SeriesPageColors {
  pageBg: string;
  cardBg: string;
  headerBg: string;
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
  seriesInfoBg: string;
}

function getSeriesPageColors(mode: number): SeriesPageColors {
  const isDark = mode === 0;
  return {
    pageBg: isDark ? '#0D0D0D' : '#F1F3F5',
    cardBg: isDark ? '#1E1E1E' : '#FFFFFF',
    headerBg: isDark ? '#141414' : '#FFFFFF',
    primaryText: isDark ? '#E6E6E6' : '#000000',
    secondaryText: isDark ? '#999999' : '#666666',
    tertiaryText: isDark ? '#666666' : '#999999',
    accentText: '#FA8C16',
    tagBg: isDark ? '#2A2A2A' : '#F0F0F0',
    tagText: isDark ? '#AAAAAA' : '#555555',
    cachedBadgeBg: isDark ? '#1A3A1A' : '#F6FFED',
    cachingBadgeBg: isDark ? '#3A2E00' : '#FFFBE6',
    failBadgeBg: isDark ? '#3A1A1A' : '#FFF2F0',
    emptyText: isDark ? '#666666' : '#999999',
    emptySubText: isDark ? '#444444' : '#BBBBBB',
    seriesInfoBg: isDark ? '#1A1A2E' : '#E8F0FE'
  };
}

interface RouterParams {
  seriesId: string;
  seriesTitle?: string;
}

@Entry
@Component
struct PixivSeriesPage {
  @State seriesId: string = '';
  @State seriesTitle: string = '系列详情';
  @State seriesCaption: string = '';
  @State authorName: string = '';
  @State novels: PixivNovel[] = [];
  @State isLoading: boolean = false;
  @State currentPage: number = 1;
  @State hasMore: boolean = false;
  @State colorMode: number = 0;
  @State cachingIds: Set<string> = new Set();

  // ✅ 新增：离线模式标志
  @State isOfflineMode: boolean = false;
  // ✅ 新增：离线模式下缓存的小说总数（用于显示）
  @State offlineCachedCount: number = 0;

  private pixivService = getPixivService();
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

    // 获取路由参数
    const params = router.getParams() as RouterParams;
    if (params?.seriesId) {
      this.seriesId = params.seriesId;
      if (params.seriesTitle) {
        this.seriesTitle = params.seriesTitle;
      }
      await pixivCacheDB.init(ctx);
    }

    await this.loadSeriesNovels(1);
  }

  aboutToDisappear(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    if (this.configCallbackId !== -1) {
      ctx.getApplicationContext().off('environment', this.configCallbackId);
    }
  }

  private getColors(): SeriesPageColors {
    return getSeriesPageColors(this.colorMode);
  }

  // ✅ 新增：从本地缓存数据库中查找属于本系列的所有已缓存小说
  private async loadCachedSeriesNovels(): Promise<void> {
    this.isOfflineMode = true;

    // 从 DB 取出所有缓存的小说，再按 series.id 过滤
    const allCached = await pixivCacheDB.getAllCachedNovels();
    const seriesNovels = allCached.filter((novel: PixivNovel): boolean => {
      return novel.series?.id === this.seriesId;
    });

    // 按系列序号升序排列（如果没有序号，按 id 升序兜底）
    seriesNovels.sort((a: PixivNovel, b: PixivNovel): number => {
      const orderA = a.series?.order ?? parseInt(a.id, 10);
      const orderB = b.series?.order ?? parseInt(b.id, 10);
      return orderA - orderB;
    });

    this.novels = seriesNovels;
    this.offlineCachedCount = seriesNovels.length;
    this.hasMore = false; // 离线模式下不支持加载更多
  }

  private async loadSeriesNovels(page: number): Promise<void> {
    if (!this.seriesId) return;

    this.isLoading = true;
    const result = await this.pixivService.fetchSeriesNovels(this.seriesId, page);

    if (result.success && result.data) {
      this.isOfflineMode = false;

      // ✅ 【修改点】先提取顶层信息
      const apiSeriesTitle = result.data?.seriesTitle || '';
      const apiAuthorName  = result.data?.authorName  || '';

      // ✅ 【修改点】在 mergeCacheStatus / saveNovelMetaBatch 之前，
      //    先把 author 和 series.title 补全到每个 novel 上
      //    这样存入数据库的数据就是完整的，书架展示时不会有空白
      result.data.novels.forEach((novel: PixivNovel) => {
        if (!novel.author && apiAuthorName) {
          novel.author = apiAuthorName;
        }
        if (!novel.series) {
          // 只有真的没有系列信息时才新建（但 order 为 0）
          novel.series = { id: this.seriesId, title: apiSeriesTitle || this.seriesTitle, order: 0 };
        } else {
          // 已有 series，仅补全缺失的 id 和 title
          if (!novel.series.id) novel.series.id = this.seriesId;
          if (!novel.series.title && (apiSeriesTitle || this.seriesTitle)) {
            novel.series.title = apiSeriesTitle || this.seriesTitle;
          }
          // 保留已有的 order（已在 parsePixivNovelFromRaw 中正确设置）
        }
      });

      const merged = await this.mergeCacheStatus(result.data?.novels || []);

      if (page === 1) {
        this.novels = merged;
        if (apiSeriesTitle && this.seriesTitle === '系列详情') {
          this.seriesTitle = apiSeriesTitle;
        }
        this.seriesCaption = result.data?.seriesCaption || '';
        this.authorName = apiAuthorName;
      } else {
        this.novels = this.novels.concat(merged);
      }
      this.hasMore = result.data?.hasMore;
      this.currentPage = page;

      // ✅ 此时 novels 里每个对象的 author 和 series.title 都已补全，存库数据完整
      pixivCacheDB.saveNovelMetaBatch(result.data.novels);

    } else {
      console.warn(`[SeriesPage] 网络请求失败: ${result.error}，尝试加载本地缓存`);
      await this.loadCachedSeriesNovels();

      if (this.novels.length === 0) {
        promptAction.showToast({ message: '无网络且暂无缓存，请联网后重试' });
      }
    }

    this.isLoading = false;
  }

  private async mergeCacheStatus(novels: PixivNovel[]): Promise<PixivNovel[]> {
    return Promise.all(
      novels.map(async (novel) => {
        const local = await pixivCacheDB.getNovelById(novel.id);
        if (local && local.cacheStatus === CacheStatus.CACHED) {
          novel.cacheStatus = CacheStatus.CACHED;
          novel.cachedAt = local.cachedAt;
          novel.fullText = local.fullText;
        }
        // 合并标题翻译
        if (local && local.hasTitleTranslation && local.titleTranslated) {
          novel.titleTranslated = local.titleTranslated;
          novel.hasTitleTranslation = true;
        }
        return novel;
      })
    );
  }

  private loadMore(): void {
    if (!this.hasMore || this.isLoading) return;
    this.loadSeriesNovels(this.currentPage + 1);
  }

  private async cacheNovel(novel: PixivNovel): Promise<void> {
    if (this.cachingIds.has(novel.id)) return;

    // 缓存前再次确保 series / author 信息完整，避免 shelf 按单篇分组
    if (!novel.author && this.authorName) {
      novel.author = this.authorName;
    }
    if (!novel.series) {
      novel.series = { id: this.seriesId, title: this.seriesTitle, order: 0 };
    } else {
      if (!novel.series.id) novel.series.id = this.seriesId;
      if (!novel.series.title && this.seriesTitle) {
        novel.series.title = this.seriesTitle;
      }
    }
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
      await pixivCacheDB.deleteCachedText(novel.id);
      this.updateNovelStatus(novel.id, CacheStatus.NOT_CACHED);
      promptAction.showToast({ message: `《${novel.title}》缓存已删除` });
    } catch (e) {
      promptAction.showToast({ message: '删除失败' });
    }
  }

  private updateNovelStatus(novelId: string, status: CacheStatus): void {
    this.novels = this.novels.map(n => {
      if (n.id === novelId) {
        n.cacheStatus = status;
      }
      return n;
    });
  }

  private updateNovelStatusWithText(novelId: string, status: CacheStatus, fullText: string): void {
    this.novels = this.novels.map(n => {
      if (n.id === novelId) {
        n.cacheStatus = status;
        n.fullText = fullText;
      }
      return n;
    });
  }

  private async openOfflineReader(novel: PixivNovel): Promise<void> {
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
    });
  }

  private openAuthorPage(): void {
    if (!this.novels.length) return;
    const authorId = this.novels[0]?.authorId;
    if (authorId) {
      router.pushUrl({
        url: 'pages/PixivAuthorPage',
        params: {
          authorId: authorId,
          authorName: this.authorName || this.novels[0].author
        }
      });
    }
  }

  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Button() {
          Text('〈 返回').fontSize(14).fontColor('#FA8C16')
        }
        .backgroundColor(Color.Transparent)
        .onClick(() => router.back())

        Text(this.seriesTitle)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getColors().primaryText)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Blank().width(60)
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 12 + px2vp(this.statusBarHeight),
        bottom: 12
      })
      .backgroundColor(this.getColors().headerBg)

      // ✅ 新增：离线模式提示横幅
      if (this.isOfflineMode) {
        Row() {
          Text('📴').fontSize(14)
          Text(this.offlineCachedCount > 0
            ? `  离线模式 · 显示本系列 ${this.offlineCachedCount} 部已缓存作品`
            : '  离线模式 · 本系列暂无缓存作品')
            .fontSize(13)
            .fontColor('#D48806')
            .layoutWeight(1)
          // 重试按钮：点击后重新尝试联网加载
          Text('重试')
            .fontSize(13)
            .fontColor('#FA8C16')
            .padding({ left: 12, top: 4, bottom: 4 })
            .onClick((): void => {
              this.isOfflineMode = false;
              this.loadSeriesNovels(1);
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor(this.colorMode === 0 ? '#2D2200' : '#FFFBE6')
      }

      // 系列信息卡片
      Column() {
        Text(this.seriesTitle)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getColors().accentText)
          .width('100%')
          .textAlign(TextAlign.Center)

        if (this.authorName) {
          Text(`作者: ${this.authorName}`)
            .fontSize(14)
            .fontColor(this.getColors().secondaryText)
            .margin({ top: 8 })
            .onClick(() => this.openAuthorPage())
        }

        if (this.seriesCaption) {
          Text(this.seriesCaption)
            .fontSize(12)
            .fontColor(this.getColors().tertiaryText)
            .margin({ top: 8 })
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        Text(`共 ${this.novels.length} 部作品${this.isOfflineMode ? '（已缓存）' : ''}`)
          .fontSize(12)
          .fontColor(this.getColors().tertiaryText)
          .margin({ top: 8 })
      }
      .width('92%')
      .padding(16)
      .backgroundColor(this.getColors().seriesInfoBg)
      .borderRadius(12)
      .margin({ top: 12, bottom: 12 })
      .alignSelf(ItemAlign.Center)

      // 小说列表
      if (this.isLoading && this.novels.length === 0) {
        Column() {
          LoadingProgress().width(48).height(48).color(this.getColors().accentText)
          Text('正在加载系列作品...')
            .fontSize(14).fontColor(this.getColors().secondaryText).margin({ top: 12 })
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.novels.length > 0) {
        List({ space: 10 }) {
          ForEach(this.novels, (novel: PixivNovel): void => {
            ListItem() { this.NovelCard(novel) }
            .width('92%')
          }, (novel: PixivNovel): string => `${novel.id}_${novel.cacheStatus}`)

          ListItem() {
            if (this.hasMore) {
              Button(this.isLoading ? '加载中...' : '加载更多')
                .width('100%').height(44).fontSize(14)
                .fontColor(this.getColors().accentText)
                .backgroundColor(this.getColors().cardBg)
                .borderRadius(12)
                .enabled(!this.isLoading)
                .onClick((): void => { this.loadMore() })
            } else {
              Text(this.isOfflineMode ? '— 以上为本系列所有缓存作品 —' : '— 已加载全部作品 —')
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
      } else {
        Column() {
          Text('📚').fontSize(60).margin({ bottom: 16 })
          Text(this.isOfflineMode ? '本系列暂无缓存作品' : '暂无作品')
            .fontSize(16).fontColor(this.getColors().emptyText)
          Text(this.isOfflineMode ? '请联网后访问以加载完整列表' : '')
            .fontSize(12).fontColor(this.getColors().emptySubText).margin({ top: 8 })
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getColors().pageBg)
  }

  @Builder NovelCard(novel: PixivNovel) {
    Column() {
      Row() {
        // 系列序号标记
        if (novel.series?.order) {
          Text(`#${novel.series.order}`)
            .fontSize(11).fontColor(this.getColors().accentText)
            .margin({ right: 6 })
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .backgroundColor(this.getColors().tagBg)
            .borderRadius(4)
        }

        // ✅ 新增：系列标题标签（当序号无法代表系列名时补充显示）
        if (novel.series?.title) {
          Text(`[${novel.series.title}]`)
            .fontSize(11).fontColor(this.getColors().accentText)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '40%' }).margin({ right: 6 })
        }

        Text(
          novel.hasTitleTranslation && novel.titleTranslated
            ? novel.titleTranslated
            : novel.title
        )
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.getColors().primaryText)
          .layoutWeight(1)
          .maxLines(2)
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
        if (novel.author) {
          Text(novel.author)
            .fontSize(12).fontColor(this.getColors().secondaryText)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '40%' })
        }
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
            .backgroundColor(this.getColors().tagBg)
            .borderRadius(8).height(32).padding({ left: 12, right: 12 })
            .onClick((): void => { this.deleteCache(novel) })
        }
        if (novel.cacheStatus === CacheStatus.NOT_CACHED ||
          novel.cacheStatus === CacheStatus.CACHE_FAIL) {
          Button(novel.cacheStatus === CacheStatus.CACHE_FAIL ? '重试缓存' : '离线缓存')
            .fontSize(12)
            .fontColor(novel.cacheStatus === CacheStatus.CACHE_FAIL
              ? '#FF4D4F' : this.getColors().accentText)
            .backgroundColor(this.getColors().tagBg)
            .borderRadius(8).height(32).padding({ left: 12, right: 12 })
          // ✅ 离线模式下缓存按钮置灰（无法联网）
            .enabled(!this.isOfflineMode)
            .onClick((): void => {
              if (this.isOfflineMode) {
                promptAction.showToast({ message: '离线状态下无法缓存，请开启代理后重试' });
                return;
              }
              this.cacheNovel(novel);
            })
        }
        if (novel.cacheStatus === CacheStatus.CACHING) {
          Row() {
            LoadingProgress().width(16).height(16).color(this.getColors().accentText)
            Text(' 缓存中').fontSize(12).fontColor(this.getColors().secondaryText)
          }
          .backgroundColor(this.getColors().tagBg)
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
          .backgroundColor(this.getColors().tagBg)
          .borderRadius(8).height(32).padding({ left: 12, right: 12 })
          .margin({ left: 8 })
          // ✅ 离线模式下在线阅读按钮置灰
          .enabled(!this.isOfflineMode)
          .onClick((): void => {
            if (this.isOfflineMode) {
              promptAction.showToast({ message: '离线状态下请使用离线阅读' });
              return;
            }
            this.openOnlineReader(novel);
          })
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