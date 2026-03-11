// entry/src/main/ets/pages/PixivAuthorPage.ets
import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import common from '@ohos.app.ability.common';
import {
  PixivNovel,
  CacheStatus,
  PixivTag,
  formatTextLength,
  formatPixivDate,
  getCacheStatusDisplay,
  isReadableOffline,
  PixivSearchResult
} from '../models/PixivModels';
import { getPixivService, PixivService, ServiceResult } from '../services/PixivService';
import { pixivCacheDB } from '../database/PixivCacheDB';

interface AuthorPageColors {
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
  avatarBg: string;
}

function getAuthorPageColors(mode: number): AuthorPageColors {
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
    avatarBg: isDark ? '#2A2A2A' : '#F0F0F0',
  };
}

interface RouterParams {
  authorId: string;
  authorName: string;
  authorAvatar?: string;
}

@Entry
@Component
struct PixivAuthorPage {
  @State authorId: string = '';
  @State authorName: string = '作者详情';
  @State authorAvatar: string = '';
  @State novels: PixivNovel[] = [];
  @State isLoading: boolean = false;
  @State currentPage: number = 1;
  @State hasMore: boolean = false;
  @State colorMode: number = 0;
  @State cachingIds: Set<string> = new Set();
  @State isFollowed: boolean = false;
  @State loadError: string = '';  // 新增：错误信息

  private pixivService: PixivService | null = null;
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

    // ✅ 修复1：先初始化数据库（与 PixivSearchPage 保持一致）
    await pixivCacheDB.init(ctx);

    // ✅ 修复2：在 aboutToAppear 里再获取 service，确保此时 AppStorage
    //          中的 pixivSessionId 已经就绪，Cookie 不会为空
    this.pixivService = getPixivService();

    // 获取路由参数
    const params = router.getParams() as RouterParams;
    if (params?.authorId) {
      this.authorId = params.authorId;
      this.authorName = params.authorName || '作者详情';
      this.authorAvatar = params.authorAvatar || '';
      await this.loadAuthorNovels(1);
    }
  }

  aboutToDisappear(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    if (this.configCallbackId !== -1) {
      ctx.getApplicationContext().off('environment', this.configCallbackId);
    }
  }

  private getColors(): AuthorPageColors {
    return getAuthorPageColors(this.colorMode);
  }

  private async loadAuthorNovels(page: number): Promise<void> {
    if (!this.authorId) return;
    // ✅ 修复3：加 null 守卫防止 service 未初始化时调用
    if (!this.pixivService) return;
    this.isLoading = true;
    this.loadError = '';
    const result: ServiceResult<PixivSearchResult> = await this.pixivService.fetchAuthorNovels(this.authorId, page);

    if (result.success && result.data) {
      const merged = await this.mergeCacheStatus(result.data.novels);
      if (page === 1) {
        this.novels = merged;
      } else {
        this.novels = this.novels.concat(merged);
      }
      this.hasMore = result.data.hasMore;
      this.currentPage = page;
    } else {
      this.loadError = result.error || '加载失败';  // 记录错误
      promptAction.showToast({ message: this.loadError });
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
        return novel;
      })
    );
  }

  private loadMore(): void {
    if (!this.hasMore || this.isLoading) return;
    this.loadAuthorNovels(this.currentPage + 1);
  }
  private async cacheNovel(novel: PixivNovel): Promise<void> {
    if (this.cachingIds.has(novel.id)) return;
    // ✅ 修复：加 null 守卫防止 service 未初始化时调用
    if (!this.pixivService) return;
    await pixivCacheDB.saveNovelMeta(novel);

    const newSet = new Set<string>(this.cachingIds);
    newSet.add(novel.id);
    this.cachingIds = newSet;

    this.updateNovelStatus(novel.id, CacheStatus.CACHING);
    await pixivCacheDB.markCaching(novel.id);
    const result: ServiceResult<string> = await this.pixivService.fetchNovelText(novel.id);
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
    });
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

        Text(this.authorName)
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

      // 作者信息卡片
      Row() {
        // 头像
        if (this.authorAvatar) {
          Image(this.authorAvatar)
            .width(60)
            .height(60)
            .borderRadius(30)
            .objectFit(ImageFit.Cover)
            .margin({ right: 16 })
        } else {
          Column() {
            Text('👤').fontSize(30)
          }
          .width(60)
          .height(60)
          .borderRadius(30)
          .backgroundColor(this.getColors().avatarBg)
          .justifyContent(FlexAlign.Center)
          .margin({ right: 16 })
        }

        Column() {
          Text(this.authorName)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getColors().primaryText)
            .width('100%')

          Text(`ID: ${this.authorId}`)
            .fontSize(12)
            .fontColor(this.getColors().tertiaryText)
            .margin({ top: 4 })
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('92%')
      .padding(16)
      .backgroundColor(this.getColors().cardBg)
      .borderRadius(12)
      .margin({ top: 12, bottom: 12 })
      .alignSelf(ItemAlign.Center)

      // 小说列表
      if (this.isLoading && this.novels.length === 0) {
        Column() {
          LoadingProgress().width(48).height(48).color(this.getColors().accentText)
          Text('正在加载作品...')
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
            } else if (this.novels.length > 0) {
              Text('— 已加载全部作品 —')
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
          Text('暂无公开作品').fontSize(16).fontColor(this.getColors().emptyText)
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
        if (novel.series) {
          Text(`[${novel.series.title}]`)
            .fontSize(11).fontColor(this.getColors().accentText)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '40%' }).margin({ right: 6 })
        }
        Text(novel.title)
          .fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor(this.getColors().primaryText)
          .layoutWeight(1).maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        this.CacheStatusBadge(novel.cacheStatus)
      }
      .width('100%').alignItems(VerticalAlign.Top)

      Row() {
        Text(formatTextLength(novel.textLength))
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
            .onClick((): void => { this.cacheNovel(novel) })
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