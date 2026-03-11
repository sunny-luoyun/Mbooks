// entry/src/main/ets/components/Pixiv/PixivFollowingPage.ets
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
  isReadableOffline
} from '../../models/PixivModels';
import { getPixivService } from '../../services/PixivService';
import { pixivCacheDB } from '../../database/PixivCacheDB';

interface FollowingColors {
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
  loadingColor: string;
}

function getFollowingColors(mode: number): FollowingColors {
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
    loadingColor: '#FA8C16'
  };
}

@Component
export struct PixivFollowingPage {
  @State followingResults: PixivNovel[] = []
  @State isLoading: boolean = false
  @State errorMsg: string = ''
  @State currentPage: number = 1
  @State hasMore: boolean = false
  @State total: number = 0
  @State colorMode: number = 0;
  @State cachingIds: Set<string> = new Set()

  private pixivService = getPixivService()
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
    // 自动加载第一页
    this.loadFollowing(1);
  }

  aboutToDisappear(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    if (this.configCallbackId !== -1) {
      ctx.getApplicationContext().off('environment', this.configCallbackId);
    }
  }

  private getColors(): FollowingColors {
    return getFollowingColors(this.colorMode);
  }

  private async loadFollowing(page: number): Promise<void> {
    if (this.isLoading) return;

    this.isLoading = true;
    this.errorMsg = '';
    if (page === 1) this.followingResults = [];

    const result = await this.pixivService.fetchFollowingNovels(page);

    if (result.success && result.data) {
      const merged = await this.mergeCacheStatus(result.data.novels);
      if (page === 1) {
        this.followingResults = merged;
      } else {
        this.followingResults = this.followingResults.concat(merged);
      }
      this.total = result.data.total;
      this.hasMore = result.data.hasMore;
      this.currentPage = page;
      // 同步落库
      pixivCacheDB.saveNovelMetaBatch(result.data.novels);
    } else {
      this.errorMsg = result.error ?? '加载失败';
      promptAction.showToast({ message: this.errorMsg });
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
    this.loadFollowing(this.currentPage + 1);
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
      await pixivCacheDB.deleteCachedText(novel.id);
      this.updateNovelStatus(novel.id, CacheStatus.NOT_CACHED);
      promptAction.showToast({ message: `《${novel.title}》缓存已删除` });
    } catch (e) {
      promptAction.showToast({ message: '删除失败' });
    }
  }

  private updateNovelStatus(novelId: string, status: CacheStatus): void {
    this.followingResults = this.followingResults.map(n => {
      if (n.id === novelId) {
        n.cacheStatus = status;
      }
      return n;
    });
  }

  private updateNovelStatusWithText(novelId: string, status: CacheStatus, fullText: string): void {
    this.followingResults = this.followingResults.map(n => {
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
      // 标题栏
      Row() {
        Column() {
          Text('Pixiv 关注')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getColors().primaryText)
          if (this.total > 0) {
            Text(`共 ${this.total} 篇，已加载 ${this.followingResults.length} 篇`)
              .fontSize(12).fontColor(this.getColors().tertiaryText)
              .margin({ top: 4 })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button('刷新')
          .fontSize(14)
          .fontColor(this.getColors().accentText)
          .backgroundColor(Color.Transparent)
          .enabled(!this.isLoading)
          .onClick(() => this.loadFollowing(1))
      }
      .width('100%')
      .padding({
        left: 16, right: 16,
        top: 16 + px2vp(this.statusBarHeight),
        bottom: 16
      })
      .backgroundColor(this.getColors().headerBg)

      // 内容区
      if (this.isLoading && this.followingResults.length === 0) {
        Column() {
          LoadingProgress().width(48).height(48).color(this.getColors().loadingColor)
          Text('正在加载关注动态...')
            .fontSize(14).fontColor(this.getColors().secondaryText).margin({ top: 12 })
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)

      } else if (this.followingResults.length > 0) {
        List({ space: 10 }) {
          ForEach(this.followingResults, (novel: PixivNovel): void => {
            ListItem() { this.NovelCard(novel) }
            .width('92%')
          }, (novel: PixivNovel): string => `following_${novel.id}_${novel.cacheStatus}`)

          // 加载更多
          ListItem() {
            if (this.hasMore) {
              Button(this.isLoading ? '加载中...' : '加载更多')
                .width('100%').height(44).fontSize(14)
                .fontColor(this.getColors().accentText)
                .backgroundColor(this.getColors().cardBg)
                .borderRadius(12)
                .enabled(!this.isLoading)
                .onClick(() => this.loadMore())
            } else {
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

      } else {
        // 空状态
        Column() {
          Text('💞').fontSize(60).margin({ bottom: 16 })
          Text(this.errorMsg
            ? (this.errorMsg.includes('Cookie') || this.errorMsg.includes('登录')
              ? '请先登录 Pixiv'
              : '加载失败，请重试')
            : '暂无关注动态')
            .fontSize(16).fontColor(this.getColors().emptyText)
            .textAlign(TextAlign.Center)

          Text(this.errorMsg
            ? (this.errorMsg.includes('Cookie') || this.errorMsg.includes('登录')
              ? '请在设置中填入有效的 PHPSESSID'
              : this.errorMsg)
            : '将显示您在 Pixiv 关注用户的最新小说')
            .fontSize(12).fontColor(this.getColors().emptySubText)
            .textAlign(TextAlign.Center)
            .margin({ top: 8, bottom: 20 })

          Button('重新加载')
            .fontSize(14).fontColor('#FFFFFF')
            .backgroundColor(this.getColors().accentText)
            .borderRadius(20).height(40)
            .padding({ left: 24, right: 24 })
            .onClick(() => this.loadFollowing(1))
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
            .backgroundColor(this.getColors().tagBg)
            .borderRadius(8).height(32).padding({ left: 12, right: 12 })
            .onClick(() => this.deleteCache(novel))
        }
        if (novel.cacheStatus === CacheStatus.NOT_CACHED ||
          novel.cacheStatus === CacheStatus.CACHE_FAIL) {
          Button(novel.cacheStatus === CacheStatus.CACHE_FAIL ? '重试缓存' : '离线缓存')
            .fontSize(12)
            .fontColor(novel.cacheStatus === CacheStatus.CACHE_FAIL
              ? '#FF4D4F' : this.getColors().accentText)
            .backgroundColor(this.getColors().tagBg)
            .borderRadius(8).height(32).padding({ left: 12, right: 12 })
            .onClick(() => this.cacheNovel(novel))
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
            .onClick(() => this.openOfflineReader(novel))
        }
        Button('在线阅读')
          .fontSize(12).fontColor(this.getColors().accentText)
          .backgroundColor(this.getColors().tagBg)
          .borderRadius(8).height(32).padding({ left: 12, right: 12 })
          .margin({ left: 8 })
          .onClick(() => this.openOnlineReader(novel))
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