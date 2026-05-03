// entry/src/main/ets/components/Pixiv/PixivShelfPage.ets
// ============================================================
//  三层堆栈导航：作者列表 → 作者详情（独立小说+系列） → 系列小说列表
//  使用 Navigation + NavPathStack，系统返回键自动回退
// ============================================================

import promptAction from '@ohos.promptAction';
import common from '@ohos.app.ability.common';
import router from '@ohos.router';
import { PixivNovel, PixivSeries, formatTextLength, formatPixivDate } from '../../models/PixivModels';
import { pixivCacheDB } from '../../database/PixivCacheDB';

// ────────────────────────────────────────────────────────────
//  主题色工具
// ────────────────────────────────────────────────────────────
interface ShelfColors {
  pageBg: string;
  cardBg: string;
  cardBg2: string;       // 嵌套卡片背景（稍深/稍浅）
  headerBg: string;
  primaryText: string;
  secondaryText: string;
  tertiaryText: string;
  accentText: string;
  accentBg: string;
  emptyText: string;
  emptySubText: string;
  deleteBtnBg: string;
  deleteBtnText: string;
  readBtnBg: string;
  readBtnText: string;
  divider: string;
  seriesBadgeBg: string;
  seriesBadgeText: string;
}

function getShelfColors(mode: number): ShelfColors {
  const isDark = mode === 0;
  return {
    pageBg: isDark ? '#0D0D0D' : '#F1F3F5',
    cardBg: isDark ? '#1E1E1E' : '#FFFFFF',
    cardBg2: isDark ? '#252525' : '#F8F8F8',
    headerBg: isDark ? '#141414' : '#FFFFFF',
    primaryText: isDark ? '#E6E6E6' : '#1A1A1A',
    secondaryText: isDark ? '#999999' : '#666666',
    tertiaryText: isDark ? '#666666' : '#999999',
    accentText: '#FA8C16',
    accentBg: isDark ? '#2A1E0A' : '#FFF7E6',
    emptyText: isDark ? '#666666' : '#999999',
    emptySubText: isDark ? '#444444' : '#BBBBBB',
    deleteBtnBg: isDark ? '#2A1F1F' : '#FFF5F5',
    deleteBtnText: '#FF4D4F',
    readBtnBg: '#FA8C16',
    readBtnText: '#FFFFFF',
    divider: isDark ? '#2A2A2A' : '#EEEEEE',
    seriesBadgeBg: isDark ? '#1A2E1A' : '#F6FFED',
    seriesBadgeText: '#52C41A',
  };
}

// ────────────────────────────────────────────────────────────
//  数据聚合类型
// ────────────────────────────────────────────────────────────

/** 作者卡片信息（聚合后） */
interface AuthorGroup {
  authorId: string;
  authorName: string;
  /** 不属于任何系列的独立小说 */
  standaloneNovels: PixivNovel[];
  /** key = seriesId */
  seriesMap: Map<string, SeriesGroup>;
  /** 总缓存数（独立 + 系列内） */
  totalCount: number;
}

/** 系列卡片信息 */
interface SeriesGroup {
  seriesId: string;
  seriesTitle: string;
  novels: PixivNovel[];
}

/** 将小说列表聚合成 AuthorGroup[] */
function groupNovels(novels: PixivNovel[]): AuthorGroup[] {
  const authorMap = new Map<string, AuthorGroup>();

  for (const novel of novels) {
    let group = authorMap.get(novel.authorId);
    if (!group) {
      group = {
        authorId: novel.authorId,
        authorName: novel.author,
        standaloneNovels: [],
        seriesMap: new Map(),
        totalCount: 0,
      };
      authorMap.set(novel.authorId, group);
    }

    if (novel.series) {
      const sid = novel.series.id;
      let sg = group.seriesMap.get(sid);
      if (!sg) {
        sg = { seriesId: sid, seriesTitle: novel.series.title, novels: [] };
        group.seriesMap.set(sid, sg);
      }
      // 系列内按 series.order 排序
      sg.novels.push(novel);
    } else {
      group.standaloneNovels.push(novel);
    }
    group.totalCount++;
  }

  // 系列内小说排序
  for (const ag of authorMap.values()) {
    for (const sg of ag.seriesMap.values()) {
      sg.novels.sort((a, b) => (a.series?.order ?? 0) - (b.series?.order ?? 0));
    }
  }

  // 作者按名字排序
  return Array.from(authorMap.values()).sort((a, b) =>
  a.authorName.localeCompare(b.authorName)
  );
}

// ────────────────────────────────────────────────────────────
//  NavPath 参数类型
// ────────────────────────────────────────────────────────────
interface AuthorDetailParam {
  authorGroup: AuthorGroup;
  colorMode: number;
}

interface SeriesDetailParam {
  seriesGroup: SeriesGroup;
  authorName: string;
  colorMode: number;
}

// ====================================================================
//  页面一：作者详情页（系列 + 独立小说）
//  路径名："AuthorDetailPage"
// ====================================================================
@Component
struct AuthorDetailPage {
  @Consume('shelfNavStack') navStack: NavPathStack;
  @State colorMode: number = 0;

  private authorGroup: AuthorGroup = {
    authorId: '',
    authorName: '',
    standaloneNovels: [],
    seriesMap: new Map(),
    totalCount: 0,
  };

  private getColors(): ShelfColors {
    return getShelfColors(this.colorMode);
  }

  private openReader(novel: PixivNovel): void {
    router.pushUrl({
      url: 'pages/PixivNovelReaderPage',
      params: { novelId: novel.id, title: novel.title, author: novel.author, offline: true }
    });
  }

  private openSeries(sg: SeriesGroup): void {
    const param: SeriesDetailParam = {
      seriesGroup: sg,
      authorName: this.authorGroup.authorName,
      colorMode: this.colorMode,
    };
    this.navStack.pushPathByName('SeriesDetailPage', param);
  }

  build() {
    NavDestination() {
      Column() {
        // ── 作者信息头部 ──
        Row() {
          // 头像占位
          Column() {
            Text(this.authorGroup.authorName.charAt(0).toUpperCase())
              .fontSize(22)
              .fontColor('#FFFFFF')
              .fontWeight(FontWeight.Bold)
          }
          .width(52).height(52)
          .borderRadius(26)
          .backgroundColor(this.getColors().accentText)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .margin({ right: 14 })

          Column() {
            Text(this.authorGroup.authorName)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.getColors().primaryText)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .onClick(() => {
                router.pushUrl({
                  url: 'pages/PixivAuthorPage',
                  params: {
                    authorId: this.authorGroup.authorId,
                    authorName: this.authorGroup.authorName,
                    authorAvatar: ''   // 本地缓存没有头像，传空即可
                  }
                });
              })

            Text(`${this.authorGroup.totalCount} 本缓存  ·  ${this.authorGroup.seriesMap.size} 个系列`)
              .fontSize(13)
              .fontColor(this.getColors().secondaryText)
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        .backgroundColor(this.getColors().cardBg)

        // 分割线
        Divider().color(this.getColors().divider).strokeWidth(1)

        // ── 内容列表 ──
        List({ space: 10 }) {
          // 1. 系列卡片
          if (this.authorGroup.seriesMap.size > 0) {
            ListItem() {
              Text('📚 系列')
                .fontSize(13)
                .fontColor(this.getColors().tertiaryText)
                .fontWeight(FontWeight.Medium)
                .padding({ left: 4, bottom: 4 })
                .width('100%')
            }
          }

          ForEach(
            Array.from(this.authorGroup.seriesMap.values()),
            (sg: SeriesGroup): void => {
              ListItem() {
                this.SeriesCard(sg)
              }
            },
            (sg: SeriesGroup): string => sg.seriesId
          )

          // 2. 独立小说
          if (this.authorGroup.standaloneNovels.length > 0) {
            ListItem() {
              Text('📄 独立小说')
                .fontSize(13)
                .fontColor(this.getColors().tertiaryText)
                .fontWeight(FontWeight.Medium)
                .padding({ left: 4, bottom: 4, top: this.authorGroup.seriesMap.size > 0 ? 8 : 0 })
                .width('100%')
            }
          }

          ForEach(
            this.authorGroup.standaloneNovels,
            (novel: PixivNovel): void => {
              ListItem() {
                this.NovelCard(novel)
              }
            },
            (novel: PixivNovel): string => novel.id
          )
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 12, bottom: 16 })
        .backgroundColor(this.getColors().pageBg)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.getColors().pageBg)
    }
    .title(this.authorGroup.authorName)
    .backgroundColor(this.getColors().headerBg)
    .onReady((ctx: NavDestinationContext) => {
      const param = ctx.pathInfo.param as AuthorDetailParam;
      this.authorGroup = param.authorGroup;
      this.colorMode = param.colorMode;
    })
  }

  @Builder SeriesCard(sg: SeriesGroup) {
    Row() {
      Column() {
        Row() {
          // 系列徽章
          Text('系列')
            .fontSize(10)
            .fontColor(this.getColors().seriesBadgeText)
            .backgroundColor(this.getColors().seriesBadgeBg)
            .borderRadius(4)
            .padding({ left: 5, right: 5, top: 2, bottom: 2 })
            .margin({ right: 8 })

          Text(sg.seriesTitle)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getColors().primaryText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')

        Text(`共 ${sg.novels.length} 话已缓存`)
          .fontSize(13)
          .fontColor(this.getColors().secondaryText)
          .margin({ top: 6 })

        // 预览前两本标题
        if (sg.novels.length > 0) {
          Column() {
            ForEach(
              sg.novels.slice(0, 2),
              (n: PixivNovel): void => {
                Text(`第${n.series?.order ?? '-'}话  ${(n.hasTitleTranslation && n.titleTranslated) ? n.titleTranslated : n.title}`)
                  .fontSize(12)
                  .fontColor(this.getColors().tertiaryText)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                  .margin({ top: 3 })
              },
              (n: PixivNovel): string => n.id
            )
            if (sg.novels.length > 2) {
              Text(`…还有 ${sg.novels.length - 2} 话`)
                .fontSize(11)
                .fontColor(this.getColors().tertiaryText)
                .margin({ top: 3 })
            }
          }
          .width('100%')
          .margin({ top: 6 })
          .padding({ left: 8, top: 6, bottom: 6, right: 8 })
          .backgroundColor(this.getColors().cardBg2)
          .borderRadius(6)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 箭头
      Text('›')
        .fontSize(22)
        .fontColor(this.getColors().tertiaryText)
        .margin({ left: 8 })
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.getColors().cardBg)
    .borderRadius(12)
    .onClick(() => this.openSeries(sg))
  }

  @Builder NovelCard(novel: PixivNovel) {
    Row() {
      Column() {
        Text((novel.hasTitleTranslation && novel.titleTranslated) ? novel.titleTranslated : novel.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor((novel.hasTitleTranslation && novel.titleTranslated) ? this.getColors().accentText : this.getColors().primaryText)
          .width('100%')

        Row() {
          Text(formatTextLength(novel.textLength))
            .fontSize(12)
            .fontColor(this.getColors().tertiaryText)
          if (novel.cachedAt) {
            Text(' · ' + formatPixivDate(novel.cachedAt))
              .fontSize(12)
              .fontColor(this.getColors().tertiaryText)
          }
        }
        .width('100%')
        .margin({ top: 5 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button('阅读')
        .fontSize(12)
        .height(30)
        .padding({ left: 14, right: 14 })
        .backgroundColor(this.getColors().readBtnBg)
        .fontColor(this.getColors().readBtnText)
        .borderRadius(15)
        .margin({ left: 10 })
        .onClick(() => this.openReader(novel))
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.getColors().cardBg)
    .borderRadius(10)
    .onClick(() => this.openReader(novel))
  }
}

// ====================================================================
//  页面二：系列详情页（展示该系列缓存的所有小说）
//  路径名："SeriesDetailPage"
// ====================================================================
@Component
struct SeriesDetailPage {
  @Consume('shelfNavStack') navStack: NavPathStack;
  @State colorMode: number = 0;

  private seriesGroup: SeriesGroup = { seriesId: '', seriesTitle: '', novels: [] };
  private authorName: string = '';

  private getColors(): ShelfColors {
    return getShelfColors(this.colorMode);
  }

  private openReader(novel: PixivNovel): void {
    router.pushUrl({
      url: 'pages/PixivNovelReaderPage',
      params: { novelId: novel.id, title: novel.title, author: novel.author, offline: true }
    });
  }

  build() {
    NavDestination() {
      Column() {
        // 系列信息头部
        Column() {
          Row() {
            Text('📚')
              .fontSize(28)
              .margin({ right: 12 })
            Column() {
              Text(this.seriesGroup.seriesTitle)
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.getColors().primaryText)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .onClick(() => {
                  router.pushUrl({
                    url: 'pages/PixivSeriesPage',
                    params: {
                      seriesId: this.seriesGroup.seriesId,
                      seriesTitle: this.seriesGroup.seriesTitle
                    }
                  });
                })
              Text(`${this.authorName}  ·  共 ${this.seriesGroup.novels.length} 话已缓存`)
                .fontSize(13)
                .fontColor(this.getColors().secondaryText)
                .margin({ top: 5 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .backgroundColor(this.getColors().cardBg)

        Divider().color(this.getColors().divider).strokeWidth(1)

        // 小说列表
        List({ space: 10 }) {
          ForEach(
            this.seriesGroup.novels,
            (novel: PixivNovel): void => {
              ListItem() {
                this.SeriesNovelCard(novel)
              }
            },
            (novel: PixivNovel): string => novel.id
          )
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 12, bottom: 16 })
        .backgroundColor(this.getColors().pageBg)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.getColors().pageBg)
    }
    .title(this.seriesGroup.seriesTitle)
    .backgroundColor(this.getColors().headerBg)
    .onReady((ctx: NavDestinationContext) => {
      const param = ctx.pathInfo.param as SeriesDetailParam;
      this.seriesGroup = param.seriesGroup;
      this.authorName = param.authorName;
      this.colorMode = param.colorMode;
    })
  }

  @Builder SeriesNovelCard(novel: PixivNovel) {
    Row() {
      // 话数徽章
      Column() {
        Text(`${novel.series?.order ?? '?'}`)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getColors().accentText)
      }
      .width(40)
      .height(40)
      .borderRadius(8)
      .backgroundColor(this.getColors().accentBg)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .margin({ right: 12 })

      Column() {
        Text((novel.hasTitleTranslation && novel.titleTranslated) ? novel.titleTranslated : novel.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor((novel.hasTitleTranslation && novel.titleTranslated) ? this.getColors().accentText : this.getColors().primaryText)
          .width('100%')

        Row() {
          Text(formatTextLength(novel.textLength))
            .fontSize(12)
            .fontColor(this.getColors().tertiaryText)
          if (novel.cachedAt) {
            Text(' · 缓存于 ' + formatPixivDate(novel.cachedAt))
              .fontSize(12)
              .fontColor(this.getColors().tertiaryText)
          }
        }
        .width('100%')
        .margin({ top: 5 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Button('阅读')
        .fontSize(12)
        .height(30)
        .padding({ left: 14, right: 14 })
        .backgroundColor(this.getColors().readBtnBg)
        .fontColor(this.getColors().readBtnText)
        .borderRadius(15)
        .margin({ left: 10 })
        .onClick(() => this.openReader(novel))
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.getColors().cardBg)
    .borderRadius(10)
    .onClick(() => this.openReader(novel))
  }
}

// ====================================================================
//  主入口：PixivShelfPage — 作者卡片列表（第一层）
// ====================================================================
@Component
export struct PixivShelfPage {
  @State private cachedNovels: PixivNovel[] = [];
  @State private authorGroups: AuthorGroup[] = [];
  @State private isLoading: boolean = false;
  @State private colorMode: number = 0;
  @State private selectedAuthors: Set<string> = new Set();
  @State private isEditMode: boolean = false;

  // NavPathStack 通过 @Provide 向子组件（AuthorDetailPage / SeriesDetailPage）注入
  @Provide('shelfNavStack') private navStack: NavPathStack = new NavPathStack();

  private configChangeCallback: () => void = () => {};
  private configCallbackId: number = -1;

  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  async aboutToAppear(): Promise<void> {
    const ctx = getContext(this) as common.UIAbilityContext;
    this.colorMode = ctx.config?.colorMode ?? 0;

    this.configChangeCallback = () => {
      this.colorMode = ctx.config?.colorMode ?? 0;
    };
    this.configCallbackId = ctx.getApplicationContext().on('environment', {
      onConfigurationUpdated: this.configChangeCallback,
      onMemoryLevel: (_level: number) => {},
    });

    await this.loadCachedNovels();
  }

  aboutToDisappear(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    if (this.configCallbackId !== -1) {
      ctx.getApplicationContext().off('environment', this.configCallbackId);
    }
  }

  private getColors(): ShelfColors {
    return getShelfColors(this.colorMode);
  }

  private async loadCachedNovels(): Promise<void> {
    this.isLoading = true;
    const novels = await pixivCacheDB.getAllCachedNovels();
    this.cachedNovels = novels;
    this.authorGroups = groupNovels(novels);
    this.isLoading = false;
  }

  /** 删除某作者下所有缓存 */
  private async deleteAuthorCache(ag: AuthorGroup): Promise<void> {
    AlertDialog.show({
      title: '删除作者缓存',
      message: `确定删除「${ag.authorName}」的全部 ${ag.totalCount} 本缓存？`,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '删除',
        fontColor: '#FF4D4F',
        action: async () => {
          const all: PixivNovel[] = [
            ...ag.standaloneNovels,
            ...Array.from(ag.seriesMap.values()).flatMap(sg => sg.novels),
          ];
          for (const n of all) {
            await pixivCacheDB.deleteCachedText(n.id);
          }
          promptAction.showToast({ message: `已删除「${ag.authorName}」全部缓存` });
          await this.loadCachedNovels();
        },
      },
    });
  }

  /** 批量删除选中作者 */
  private async batchDelete(): Promise<void> {
    if (this.selectedAuthors.size === 0) {
      promptAction.showToast({ message: '请先选择要删除的作者' });
      return;
    }
    const count = this.authorGroups
      .filter(ag => this.selectedAuthors.has(ag.authorId))
      .reduce((sum, ag) => sum + ag.totalCount, 0);

    AlertDialog.show({
      title: '批量删除',
      message: `确定删除 ${this.selectedAuthors.size} 位作者共 ${count} 本缓存？`,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '删除',
        fontColor: '#FF4D4F',
        action: async () => {
          for (const ag of this.authorGroups) {
            if (!this.selectedAuthors.has(ag.authorId)) continue;
            const all: PixivNovel[] = [
              ...ag.standaloneNovels,
              ...Array.from(ag.seriesMap.values()).flatMap(sg => sg.novels),
            ];
            for (const n of all) {
              await pixivCacheDB.deleteCachedText(n.id);
            }
          }
          promptAction.showToast({ message: `已删除 ${this.selectedAuthors.size} 位作者的缓存` });
          this.selectedAuthors.clear();
          this.isEditMode = false;
          await this.loadCachedNovels();
        },
      },
    });
  }

  private toggleSelect(ag: AuthorGroup): void {
    if (this.selectedAuthors.has(ag.authorId)) {
      this.selectedAuthors.delete(ag.authorId);
    } else {
      this.selectedAuthors.add(ag.authorId);
    }
    this.selectedAuthors = new Set(this.selectedAuthors);
  }

  private selectAll(): void {
    if (this.selectedAuthors.size === this.authorGroups.length) {
      this.selectedAuthors.clear();
    } else {
      this.authorGroups.forEach(ag => this.selectedAuthors.add(ag.authorId));
    }
    this.selectedAuthors = new Set(this.selectedAuthors);
  }

  private openAuthor(ag: AuthorGroup): void {
    const param: AuthorDetailParam = { authorGroup: ag, colorMode: this.colorMode };
    this.navStack.pushPathByName('AuthorDetailPage', param);
  }

  // ── NavPathBuilder：路由表 ──
  @Builder
  navDestBuilder(name: string) {
    if (name === 'AuthorDetailPage') {
      AuthorDetailPage()
    } else if (name === 'SeriesDetailPage') {
      SeriesDetailPage()
    }
  }

  build() {
    // Navigation 组件：堆栈式导航容器
    Navigation(this.navStack) {
      Column() {
        // ── 顶部栏 ──
        Row() {
          Text(this.isEditMode ? `已选 ${this.selectedAuthors.size} 位作者` : 'Pixiv 缓存')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getColors().primaryText)
            .layoutWeight(1)

          if (this.isEditMode) {
            Row({ space: 12 }) {
              Button('全选')
                .fontSize(14)
                .fontColor(this.getColors().accentText)
                .backgroundColor(Color.Transparent)
                .onClick(() => this.selectAll())
              Button('取消')
                .fontSize(14)
                .fontColor(this.getColors().secondaryText)
                .backgroundColor(Color.Transparent)
                .onClick(() => {
                  this.isEditMode = false;
                  this.selectedAuthors.clear();
                })
            }
          } else {
            Row({ space: 8 }) {
              Button('管理')
                .fontSize(14)
                .fontColor(this.getColors().accentText)
                .backgroundColor(Color.Transparent)
                .onClick(() => this.isEditMode = true)
              Button('刷新')
                .fontSize(14)
                .fontColor(this.getColors().accentText)
                .backgroundColor(Color.Transparent)
                .onClick(() => this.loadCachedNovels())
            }
          }
        }
        .width('100%')
        .padding({
          left: 16, right: 16,
          top: 16 + px2vp(this.statusBarHeight),
          bottom: 16,
        })
        .backgroundColor(this.getColors().headerBg)

        // ── 统计栏 ──
        if (!this.isLoading && this.authorGroups.length > 0) {
          Row() {
            Text(`${this.authorGroups.length} 位作者`)
              .fontSize(12).fontColor(this.getColors().tertiaryText)
            Text(' · ')
              .fontSize(12).fontColor(this.getColors().tertiaryText)
            Text(`${this.cachedNovels.length} 本缓存`)
              .fontSize(12).fontColor(this.getColors().tertiaryText)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 4 })
          .backgroundColor(this.getColors().pageBg)
        }

        // ── 内容区 ──
        if (this.isLoading) {
          Column() {
            LoadingProgress().width(40).height(40).color(this.getColors().accentText)
            Text('加载中...').fontSize(14).fontColor(this.getColors().secondaryText).margin({ top: 12 })
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.authorGroups.length === 0) {
          Column() {
            Text('📚').fontSize(64).margin({ bottom: 16 })
            Text('暂无缓存小说').fontSize(16).fontColor(this.getColors().emptyText)
            Text('在搜索页或关注页缓存小说后，可在此离线阅读')
              .fontSize(12).fontColor(this.getColors().emptySubText)
              .textAlign(TextAlign.Center)
              .padding({ left: 32, right: 32 })
              .margin({ top: 8 })
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          List({ space: 12 }) {
            ForEach(
              this.authorGroups,
              (ag: AuthorGroup): void => {
                ListItem() {
                  this.AuthorCard(ag)
                }
              },
              (ag: AuthorGroup): string => ag.authorId
            )
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 16, right: 16, top: 4, bottom: 16 })
          .backgroundColor(this.getColors().pageBg)
        }

        // ── 底部批量操作栏 ──
        if (this.isEditMode && this.selectedAuthors.size > 0) {
          Row() {
            Button() {
              Row({ space: 4 }) {
                Text('🗑️').fontSize(16)
                Text(`删除选中作者(${this.selectedAuthors.size})`)
                  .fontSize(14).fontColor(this.getColors().deleteBtnText)
              }
            }
            .width('100%').height(48)
            .backgroundColor(this.getColors().deleteBtnBg)
            .borderRadius(8)
            .onClick(() => this.batchDelete())
          }
          .width('100%').padding({ left: 16, right: 16, bottom: 16 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.getColors().pageBg)
    }
    .navDestination(this.navDestBuilder)
    .hideTitleBar(true)            // 用自定义顶部栏
    .hideBackButton(false)         // 子页面显示返回按钮
    .mode(NavigationMode.Stack)    // 纯堆栈模式
    .width('100%')
    .height('100%')
    .backgroundColor(this.getColors().pageBg)
  }

  // ── 作者卡片 ──
  @Builder AuthorCard(ag: AuthorGroup) {
    Row() {
      // 编辑模式复选框
      if (this.isEditMode) {
        Checkbox()
          .select(this.selectedAuthors.has(ag.authorId))
          .selectedColor(this.getColors().accentText)
          .width(22).height(22)
          .margin({ right: 12 })
          .onChange(() => this.toggleSelect(ag))
      }

      // 头像
      Column() {
        Text(ag.authorName.charAt(0).toUpperCase())
          .fontSize(18)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Bold)
      }
      .width(46).height(46)
      .borderRadius(23)
      .backgroundColor(this.getColors().accentText)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .margin({ right: 12 })

      // 信息区
      Column() {
        Text(ag.authorName)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getColors().primaryText)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        // 摘要标签行
        Row({ space: 6 }) {
          if (ag.seriesMap.size > 0) {
            Text(`📚 ${ag.seriesMap.size} 系列`)
              .fontSize(11)
              .fontColor(this.getColors().seriesBadgeText)
              .backgroundColor(this.getColors().seriesBadgeBg)
              .borderRadius(4)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          }
          if (ag.standaloneNovels.length > 0) {
            Text(`📄 ${ag.standaloneNovels.length} 独立`)
              .fontSize(11)
              .fontColor(this.getColors().accentText)
              .backgroundColor(this.getColors().accentBg)
              .borderRadius(4)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          }
          Text(`共 ${ag.totalCount} 本`)
            .fontSize(11)
            .fontColor(this.getColors().tertiaryText)
        }
        .width('100%')
        .margin({ top: 6 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (!this.isEditMode) {
        Row({ space: 8 }) {
          // 快速删除
          Button() {
            Text('🗑️').fontSize(15)
          }
          .width(34).height(34)
          .backgroundColor(this.getColors().deleteBtnBg)
          .borderRadius(17)
          .onClick(() => this.deleteAuthorCache(ag))

          // 进入箭头
          Text('›')
            .fontSize(24)
            .fontColor(this.getColors().tertiaryText)
        }
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.getColors().cardBg)
    .borderRadius(12)
    .onClick(() => {
      if (this.isEditMode) {
        this.toggleSelect(ag);
      } else {
        this.openAuthor(ag);
      }
    })
  }
}