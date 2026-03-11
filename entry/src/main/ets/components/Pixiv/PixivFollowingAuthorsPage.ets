// entry/src/main/ets/components/Pixiv/PixivFollowingAuthorsPage.ets
import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import common from '@ohos.app.ability.common';
import { PixivAuthor } from '../../models/PixivModels';
import { getPixivService } from '../../services/PixivService';
import { pixivCacheDB } from '../../database/PixivCacheDB';

interface FollowingAuthorsColors {
  pageBg: string;
  cardBg: string;
  headerBg: string;
  primaryText: string;
  secondaryText: string;
  tertiaryText: string;
  accentText: string;
  emptyText: string;
  emptySubText: string;
  searchBg: string;
  loadingColor: string;
  cachedBadgeBg: string;
}

function getFollowingAuthorsColors(mode: number): FollowingAuthorsColors {
  const isDark = mode === 0;
  return {
    pageBg: isDark ? '#0D0D0D' : '#F1F3F5',
    cardBg: isDark ? '#1E1E1E' : '#FFFFFF',
    headerBg: isDark ? '#141414' : '#FFFFFF',
    primaryText: isDark ? '#E6E6E6' : '#000000',
    secondaryText: isDark ? '#999999' : '#666666',
    tertiaryText: isDark ? '#666666' : '#999999',
    accentText: '#FA8C16',
    emptyText: isDark ? '#666666' : '#999999',
    emptySubText: isDark ? '#444444' : '#BBBBBB',
    searchBg: isDark ? '#2A2A2A' : '#F5F5F5',
    loadingColor: '#FA8C16',
    cachedBadgeBg: isDark ? '#1A3A1A' : '#F6FFED',
  };
}

@Component
export struct PixivFollowingAuthorsPage {
  @State authors: PixivAuthor[] = [];
  @State isLoading: boolean = false;
  @State errorMsg: string = '';
  @State currentPage: number = 1;
  @State totalPages: number = 1;
  @State hasMore: boolean = false;
  @State total: number = 0;
  private readonly pageSize: number = 48;
  @State colorMode: number = 0;

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

    await this.loadFollowingAuthors(1);
  }


  aboutToDisappear(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    if (this.configCallbackId !== -1) {
      ctx.getApplicationContext().off('environment', this.configCallbackId);
    }
  }

  private getColors(): FollowingAuthorsColors {
    return getFollowingAuthorsColors(this.colorMode);
  }

  private async loadFollowingAuthors(page: number): Promise<void> {
    if (this.isLoading) return;
    this.isLoading = true;
    this.errorMsg = '';

    const result = await this.pixivService.fetchFollowingAuthors(page);

    if (result.success && result.data) {
      // 直接替换，不再追加
      this.authors = result.data.authors;
      this.total = result.data.total;
      this.totalPages = Math.ceil(this.total / this.pageSize) || 1;
      // 更新当前页码（如果成功）
      this.currentPage = page;
    } else {
      this.errorMsg = result.error ?? '加载失败';
      promptAction.showToast({ message: this.errorMsg });
    }

    this.isLoading = false;
  }

  // 计算总页数
  //private get totalPages(): number {
    //return Math.ceil(this.total / this.pageSize) || 1;
  //}

  // 翻页方法
  private goToPrevPage(): void {
    if (this.currentPage > 1) {
      this.loadFollowingAuthors(this.currentPage - 1);
    }
  }

  private goToNextPage(): void {
    if (this.currentPage < this.totalPages) {
      this.loadFollowingAuthors(this.currentPage + 1);
    }
  }

  private loadMore(): void {
    if (!this.hasMore || this.isLoading) return;
    this.loadFollowingAuthors(this.currentPage + 1);
  }

  private openAuthorPage(author: PixivAuthor): void {
    router.pushUrl({
      url: 'pages/PixivAuthorPage',
      params: {
        authorId: author.id,
        authorName: author.name,
        authorAvatar: author.avatarUrl
      }
    });
  }

  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  build() {
    Column() {
      // 标题栏（保持不变）
      Row() {
        Column() {
          Text('关注的作者')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getColors().primaryText)
          if (this.total > 0) {
            Text(`共 ${this.total} 位作者`)
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
          .onClick(() => this.loadFollowingAuthors(1))
      }
      .width('100%')
      .padding({
        left: 16, right: 16,
        top: 16 + px2vp(this.statusBarHeight),
        bottom: 16
      })
      .backgroundColor(this.getColors().headerBg)

      // 内容区
      if (this.isLoading && this.authors.length === 0) {
        // 首次加载中
        Column() {
          LoadingProgress().width(48).height(48).color(this.getColors().loadingColor)
          Text('正在加载关注列表...')
            .fontSize(14).fontColor(this.getColors().secondaryText).margin({ top: 12 })
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.authors.length > 0) {
        // 有数据时：列表 + 分页控件
        Column() {
          // 作者列表（移除了加载更多的 ListItem）
          List({ space: 10 }) {
            ForEach(this.authors, (author: PixivAuthor): void => {
              ListItem() { this.AuthorCard(author) }
              .width('92%')
            }, (author: PixivAuthor): string => author.id)
          }
          .width('100%')
          .layoutWeight(1)                     // 列表占据剩余空间
          .alignListItem(ListItemAlign.Center)
          .edgeEffect(EdgeEffect.Spring)

          // 分页控件（固定在底部）
          Row() {
            Button('上一页')
              .fontSize(14)
              .fontColor(this.getColors().accentText)
              .backgroundColor(this.getColors().cardBg)
              .borderRadius(16)
              .height(36)
              .padding({ left: 16, right: 16 })
              .enabled(this.currentPage > 1 && !this.isLoading)
              .onClick(() => this.goToPrevPage())

            Text(`${this.currentPage} / ${this.totalPages}`)
              .fontSize(14)
              .fontColor(this.getColors().secondaryText)
              .margin({ left: 16, right: 16 })

            Button('下一页')
              .fontSize(14)
              .fontColor(this.getColors().accentText)
              .backgroundColor(this.getColors().cardBg)
              .borderRadius(16)
              .height(36)
              .padding({ left: 16, right: 16 })
              .enabled(this.currentPage < this.totalPages && !this.isLoading)
              .onClick(() => this.goToNextPage())
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 12, bottom: 16 })
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        // 空状态（保持不变）
        Column() {
          Text('👤').fontSize(60).margin({ bottom: 16 })
          Text(this.errorMsg ? (this.errorMsg.includes('Cookie') ? '请先登录 Pixiv' : '加载失败，请重试') : '暂无关注的作者')
            .fontSize(16).fontColor(this.getColors().emptyText)
            .textAlign(TextAlign.Center)
          Text(this.errorMsg ? (this.errorMsg.includes('Cookie') ? '请在设置中填入有效的 PHPSESSID' : this.errorMsg) : '关注喜欢的作者后，将在这里显示')
            .fontSize(12).fontColor(this.getColors().emptySubText)
            .textAlign(TextAlign.Center)
            .margin({ top: 8, bottom: 20 })
          if (this.errorMsg) {
            Button('重新加载')
              .fontSize(14).fontColor('#FFFFFF')
              .backgroundColor(this.getColors().accentText)
              .borderRadius(20).height(40)
              .padding({ left: 24, right: 24 })
              .onClick(() => this.loadFollowingAuthors(1))
          }
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      }
    }
    .width('100%').height('100%')
    .backgroundColor(this.getColors().pageBg)
  }

  @Builder AuthorCard(author: PixivAuthor) {
    Row() {
      // 不再显示头像，只显示作者名
      Text(author.name)
        .fontSize(15)          // 适当缩小字号
        .fontWeight(FontWeight.Medium)
        .fontColor(this.getColors().primaryText)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)       // 占据剩余空间
    }
    .width('100%')
    .padding({ top: 8, bottom: 8, left: 16, right: 16 })  // 减小垂直内边距
    .backgroundColor(this.getColors().cardBg)
    .borderRadius(8)           // 略微减小圆角
    .onClick(() => this.openAuthorPage(author))
  }
}