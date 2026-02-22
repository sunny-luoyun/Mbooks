// entry/src/main/ets/components/reader/ReaderContent.ets
import { Chapter, READER_EVENTS, JumpToPageData, PageData, PageIndex } from '../../pages/ReaderPage';
import { Theme, LayoutConfig } from './ReaderStyles';
import emitter from '@ohos.events.emitter';

/**
 * 懒计算数据源
 * 核心优化：getData() 时才按需计算当前页的 lines，
 * 不在内存中持有全部页面文本，极大降低内存压力
 */
class LazyPageDataSource implements IDataSource {
  private pageIndices: PageIndex[] = [];       // 只存轻量索引
  private chapterContents: string[] = [];       // 各章节原文
  private charsPerLine: number = 30;
  private listeners: DataChangeListener[] = [];

  // 简易 LRU 缓存，避免重复计算（缓存最近 20 页）
  private cache: Map<number, PageData> = new Map();
  private cacheKeys: number[] = [];
  private readonly MAX_CACHE = 20;

  setData(
    pageIndices: PageIndex[],
    chapterContents: string[],
    charsPerLine: number
  ) {
    this.pageIndices = pageIndices;
    this.chapterContents = chapterContents;
    this.charsPerLine = charsPerLine;
    this.cache.clear();
    this.cacheKeys = [];
    this.listeners.forEach(l => l.onDataReloaded());
  }

  totalCount(): number {
    return this.pageIndices.length;
  }

  getData(index: number): PageData {
    if (index < 0 || index >= this.pageIndices.length) {
      return { chapterIndex: 0, pageIndexInChapter: 0, globalPageIndex: index, lines: [] };
    }

    // 命中缓存直接返回
    if (this.cache.has(index)) {
      return this.cache.get(index)!;
    }

    // 按需计算当前页 lines
    const idx = this.pageIndices[index];
    const chapterText = this.chapterContents[idx.chapterIndex] ?? '';
    const slice = chapterText.substring(idx.startOffset, idx.endOffset);
    const lines = this.computeLines(slice, this.charsPerLine);

    const pageData: PageData = {
      chapterIndex: idx.chapterIndex,
      pageIndexInChapter: idx.pageIndexInChapter,
      globalPageIndex: index,
      lines
    };

    // 写入 LRU 缓存
    this.putCache(index, pageData);
    return pageData;
  }

  private putCache(key: number, value: PageData) {
    if (this.cacheKeys.length >= this.MAX_CACHE) {
      const evict = this.cacheKeys.shift()!;
      this.cache.delete(evict);
    }
    this.cache.set(key, value);
    this.cacheKeys.push(key);
  }

  /**
   * 将文本切分为屏幕行（宽度感知，处理中英文混排）
   */
  private computeLines(text: string, maxWidth: number): string[] {
    const lines: string[] = [];
    const paragraphs = text.split('\n');

    for (const para of paragraphs) {
      if (para.length === 0) {
        lines.push('');
        continue;
      }

      let curLine = '';
      let curWidth = 0;

      for (let i = 0; i < para.length; i++) {
        const ch = para[i];
        const w = this.charWidth(ch);

        if (curWidth + w > maxWidth && curLine.length > 0) {
          // 标点不移至行首
          if (this.isTrailingPunct(ch)) {
            lines.push(curLine + ch);
            curLine = '';
            curWidth = 0;
          } else {
            lines.push(curLine);
            curLine = ch;
            curWidth = w;
          }
        } else {
          curLine += ch;
          curWidth += w;
        }
      }

      if (curLine.length > 0) lines.push(curLine);
    }

    return lines;
  }

  private charWidth(ch: string): number {
    const c = ch.charCodeAt(0);
    if (c >= 0x4E00 && c <= 0x9FFF) return 2;
    if (c >= 0xFF01 && c <= 0xFF5E) return 2;
    if (c >= 0x3000 && c <= 0x303F) return 2;
    if (c >= 0x3040 && c <= 0x30FF) return 2;
    return 1;
  }

  private isTrailingPunct(ch: string): boolean {
    return '，。！？；：、.,;:!?）】》'.includes(ch);
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const i = this.listeners.indexOf(listener);
    if (i >= 0) this.listeners.splice(i, 1);
  }
}

@Component
export struct ReaderContent {
  @Prop pages: PageData[] = [];           // 保留兼容，实际不再使用
  @Prop chapters: Chapter[] = [];
  @Prop totalPages: number = 0;
  @Prop screenWidth: number = 360;
  @Prop screenHeight: number = 780;

  // 新增：接收轻量索引 + 章节文本，用于懒计算数据源
  @Prop pageIndices: PageIndex[] = [];
  @Prop chapterContents: string[] = [];
  @Prop charsPerLine: number = 30;

  @StorageProp('currentColorMode') currentColorMode: number = 0;

  onPageChange: (chapterIndex: number, pageIndex: number, globalPage: number) => void = () => {};
  onCenterTap: () => void = () => {};

  @State private dataSource: LazyPageDataSource = new LazyPageDataSource();
  private listScroller: Scroller = new Scroller();
  @State private currentGlobalPage: number = 0;
  private isJumping: boolean = false;
  private tapStartTime: number = 0;
  private tapStartX: number = 0;
  private tapStartY: number = 0;

  aboutToAppear() {
    this.syncDataSource();

    emitter.on(READER_EVENTS.JUMP_TO_PAGE, (eventData) => {
      const data = eventData.data as JumpToPageData;
      this.jumpToPage(data.globalPage);
    });

    emitter.on(READER_EVENTS.UPDATE_PAGINATION, () => {
      this.syncDataSource();
      this.jumpToPage(Math.min(this.currentGlobalPage, this.totalPages - 1));
    });
  }

  aboutToDisappear() {
    emitter.off(READER_EVENTS.JUMP_TO_PAGE);
    emitter.off(READER_EVENTS.UPDATE_PAGINATION);
  }

  private syncDataSource() {
    this.dataSource.setData(this.pageIndices, this.chapterContents, this.charsPerLine);
  }

  jumpToPage(globalPage: number) {
    if (globalPage < 0 || globalPage >= this.totalPages || this.pageIndices.length === 0) return;

    this.isJumping = true;
    this.currentGlobalPage = globalPage;
    this.listScroller.scrollToIndex(globalPage, false, ScrollAlign.START);

    const idx = this.pageIndices[globalPage];
    if (idx) {
      this.onPageChange(idx.chapterIndex, idx.pageIndexInChapter, globalPage);
    }

    setTimeout(() => { this.isJumping = false; }, 350);
  }

  handleTouch(event: TouchEvent) {
    const touch = event.touches[0];
    if (event.type === TouchType.Down) {
      this.tapStartTime = Date.now();
      this.tapStartX = touch.x;
      this.tapStartY = touch.y;
    } else if (event.type === TouchType.Up) {
      const duration = Date.now() - this.tapStartTime;
      const dx = Math.abs(touch.x - this.tapStartX);
      const dy = Math.abs(touch.y - this.tapStartY);
      if (duration < 300 && dx < 10 && dy < 10) {
        this.handleTap(touch.x, touch.y);
      }
    }
  }

  handleTap(x: number, y: number) {
    const cx = this.screenWidth / 2;
    const cy = this.screenHeight / 2;
    if (Math.abs(x - cx) < this.screenWidth * 0.15 &&
      Math.abs(y - cy) < this.screenHeight * 0.15) {
      this.onCenterTap();
    } else if (x < this.screenWidth * 0.2) {
      this.jumpToPage(this.currentGlobalPage - 1);
    } else if (x > this.screenWidth * 0.8) {
      this.jumpToPage(this.currentGlobalPage + 1);
    }
  }

  build() {
    Stack() {
      List({ scroller: this.listScroller }) {
        LazyForEach(this.dataSource, (page: PageData) => {
          ListItem() {
            this.PageBuilder(page)
          }
          .width('100%')
          .height(this.screenHeight)
          .backgroundColor(Theme.BG_COLOR)
        }, (page: PageData) => `${page.globalPageIndex}`)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)   // 关闭弹性，减少渲染开销
      .cachedCount(1)                // 只缓存前后1页（懒计算已很快）
      .onScrollIndex((start: number, end: number) => {
        if (this.isJumping || this.pageIndices.length === 0) return;
        const mid = Math.floor((start + end) / 2);
        if (mid !== this.currentGlobalPage && mid >= 0 && mid < this.totalPages) {
          this.currentGlobalPage = mid;
          const idx = this.pageIndices[mid];
          if (idx) {
            this.onPageChange(idx.chapterIndex, idx.pageIndexInChapter, mid);
          }
        }
      })
      .onTouch((event) => this.handleTouch(event))

      this.PageIndicator()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG_COLOR)
  }

  @Builder PageIndicator() {
    Column() {
      Text(`${this.currentGlobalPage + 1} / ${this.totalPages}`)
        .fontSize(11)
        .fontColor(Theme.TEXT_SECONDARY)
        .opacity(0.6)
    }
    .position({ x: 0, y: '100%' })
    .markAnchor({ x: 0, y: 40 })
    .width('100%')
    .height(30)
    .justifyContent(FlexAlign.Center)
    .hitTestBehavior(HitTestMode.None)
    .zIndex(5)
  }

  @Builder PageBuilder(page: PageData) {
    Column() {
      if (page.pageIndexInChapter === 0) {
        Text(this.chapters[page.chapterIndex]?.title ?? '')
          .fontSize(Theme.FONT_CHAPTER)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT_MAIN)
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: LayoutConfig.TOP_MARGIN, bottom: 20 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      Column() {
        ForEach(page.lines, (line: string, lineIdx: number) => {
          Text(line || ' ')
            .fontSize(Theme.FONT_BODY)
            .fontColor(Theme.TEXT_MAIN)
            .width('100%')
            .height(Theme.LINE_HEIGHT)
            .textAlign(TextAlign.Start)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Clip })
        }, (line: string, lineIdx: number) => lineIdx.toString())
      }
      .width('100%')
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .padding({
      left: Theme.PAGE_PADDING,
      right: Theme.PAGE_PADDING,
      top: page.pageIndexInChapter === 0 ? 0 : LayoutConfig.TOP_MARGIN,
      bottom: LayoutConfig.BOTTOM_MARGIN
    })
    .backgroundColor(Theme.BG_COLOR)
    .alignItems(HorizontalAlign.Start)
  }
}