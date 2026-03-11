// entry/src/main/ets/components/Pixiv/PixivShelfPage.ets
import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import common from '@ohos.app.ability.common';
// import { AlertDialog } from '@ohos.arkui.advanced'; // 模块不存在，删除导入
import { PixivNovel, CacheStatus, formatTextLength } from '../../models/PixivModels';
import { pixivCacheDB } from '../../database/PixivCacheDB';

interface ShelfColors {
  pageBg: string;
  cardBg: string;
  headerBg: string;
  primaryText: string;
  secondaryText: string;
  tertiaryText: string;
  accentText: string;
  emptyText: string;
  emptySubText: string;
  deleteBtnBg: string;
  deleteBtnText: string;
  readBtnBg: string;
  readBtnText: string;
}

function getShelfColors(mode: number): ShelfColors {
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
    deleteBtnBg: isDark ? '#2A1F1F' : '#FFF5F5',
    deleteBtnText: '#FF4D4F',
    readBtnBg: '#FA8C16',
    readBtnText: '#FFFFFF'
  };
}

@Component
export struct PixivShelfPage {
  @State cachedNovels: PixivNovel[] = [];
  @State isLoading: boolean = false;
  @State colorMode: number = 0;
  @State selectedNovels: Set<string> = new Set();
  @State isEditMode: boolean = false;

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
    this.isLoading = false;
  }

  private async deleteCache(novel: PixivNovel): Promise<void> {
    try {
      await pixivCacheDB.deleteCachedText(novel.id);
      promptAction.showToast({ message: `《${novel.title}》已删除` });
      await this.loadCachedNovels();
    } catch (e) {
      promptAction.showToast({ message: '删除失败' });
    }
  }

  private async batchDelete(): Promise<void> {
    if (this.selectedNovels.size === 0) {
      promptAction.showToast({ message: '请先选择要删除的小说' });
      return;
    }
    AlertDialog.show({
      title: '批量删除',
      message: `确定要删除选中的 ${this.selectedNovels.size} 本小说吗？`,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '删除',
        action: async () => {
          for (const id of this.selectedNovels) {
            await pixivCacheDB.deleteCachedText(id);
          }
          promptAction.showToast({ message: `已删除 ${this.selectedNovels.size} 本小说` });
          this.selectedNovels.clear();
          this.isEditMode = false;
          await this.loadCachedNovels();
        },
        fontColor: '#FF4D4F'
      }
    });
  }

  private openReader(novel: PixivNovel): void {
    router.pushUrl({
      url: 'pages/PixivNovelReaderPage',
      params: { novelId: novel.id, title: novel.title, author: novel.author, offline: true }
    });
  }

  private toggleSelect(novel: PixivNovel): void {
    if (this.selectedNovels.has(novel.id)) {
      this.selectedNovels.delete(novel.id);
    } else {
      this.selectedNovels.add(novel.id);
    }
    this.selectedNovels = new Set(this.selectedNovels);
  }

  private selectAll(): void {
    if (this.selectedNovels.size === this.cachedNovels.length) {
      this.selectedNovels.clear();
    } else {
      this.cachedNovels.forEach(n => this.selectedNovels.add(n.id));
    }
    this.selectedNovels = new Set(this.selectedNovels);
  }

  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  build() {
    Column() {
      // 顶部栏
      Row() {
        Text(this.isEditMode ? `已选${this.selectedNovels.size}项` : 'Pixiv 缓存')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getColors().primaryText)
          .layoutWeight(1)

        if (this.isEditMode) {
          Row({ space: 12 }) {
            Button('全选')
              .fontSize(14).fontColor(this.getColors().accentText)
              .backgroundColor(Color.Transparent)
              .onClick(() => this.selectAll())
            Button('取消')
              .fontSize(14).fontColor(this.getColors().secondaryText)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.isEditMode = false;
                this.selectedNovels.clear();
              })
          }
        } else {
          Row({ space: 8 }) {
            Button('管理')
              .fontSize(14).fontColor(this.getColors().accentText)
              .backgroundColor(Color.Transparent)
              .onClick(() => this.isEditMode = true)
            Button('刷新')
              .fontSize(14).fontColor(this.getColors().accentText)
              .backgroundColor(Color.Transparent)
              .onClick(() => this.loadCachedNovels())
          }
        }
      }
      .width('100%')
      .padding({
        left: 16, right: 16,
        top: 16 + px2vp(this.statusBarHeight),
        bottom: 16
      })
      .backgroundColor(this.getColors().headerBg)

      // 内容区
      if (this.isLoading) {
        Column() {
          LoadingProgress().width(40).height(40).color(this.getColors().accentText)
          Text('加载中...').fontSize(14).fontColor(this.getColors().secondaryText).margin({ top: 12 })
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.cachedNovels.length === 0) {
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
          ForEach(this.cachedNovels, (novel: PixivNovel): void => {
            ListItem() {
              this.NovelCard(novel)
            }
          }, (novel: PixivNovel): string => novel.id)
        }
        .width('100%').layoutWeight(1)
        .padding({ left: 16, right: 16 })
        .alignListItem(ListItemAlign.Center)
      }

      // 底部批量操作栏
      if (this.isEditMode && this.selectedNovels.size > 0) {
        Row() {
          Button() {
            Row({ space: 4 }) {
              Text('🗑️').fontSize(16)
              Text(`删除(${this.selectedNovels.size})`)
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
    .width('100%').height('100%')
    .backgroundColor(this.getColors().pageBg)
  }

  @Builder NovelCard(novel: PixivNovel) {
    Row() {
      if (this.isEditMode) {
        Checkbox()
          .select(this.selectedNovels.has(novel.id))
          .selectedColor(this.getColors().accentText)
          .width(20).height(20).margin({ right: 12 })
          .onChange(() => this.toggleSelect(novel))
      }

      Column() {
        Text(novel.title)
          .fontSize(17).fontWeight(FontWeight.Bold)
          .fontColor(this.getColors().primaryText)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Row() {
          Text(novel.author)
            .fontSize(14).fontColor(this.getColors().secondaryText)
            .layoutWeight(1)
          Text(formatTextLength(novel.textLength))
            .fontSize(12).fontColor(this.getColors().tertiaryText)
        }
        .width('100%').margin({ top: 6 })

        if (novel.cachedAt) {
          Text('缓存于: ' + new Date(novel.cachedAt).toLocaleDateString())
            .fontSize(11).fontColor(this.getColors().tertiaryText)
            .margin({ top: 4 })
        }
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start)

      if (!this.isEditMode) {
        Row({ space: 8 }) {
          Button() {
            Text('🗑️').fontSize(16)
          }
          .width(36).height(36)
          .backgroundColor(this.getColors().deleteBtnBg)
          .borderRadius(18)
          .onClick(() => this.deleteCache(novel))

          Button('阅读')
            .fontSize(12).height(32).padding({ left: 12, right: 12 })
            .backgroundColor(this.getColors().readBtnBg)
            .fontColor(this.getColors().readBtnText)
            .borderRadius(16)
            .onClick(() => this.openReader(novel))
        }
      }
    }
    .width('100%').padding(16)
    .backgroundColor(this.getColors().cardBg)
    .borderRadius(12)
    .onClick(() => {
      if (this.isEditMode) {
        this.toggleSelect(novel);
      } else {
        this.openReader(novel);
      }
    })
  }
}