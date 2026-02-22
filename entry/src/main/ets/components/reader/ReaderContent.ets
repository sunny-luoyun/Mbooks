// entry/src/main/ets/components/reader/ReaderContent.ets
import { Chapter, READER_EVENTS, JumpToPageData, PageData } from '../../pages/ReaderPage';
import { Theme, LayoutConfig } from './ReaderStyles';
import emitter from '@ohos.events.emitter';

// 构造函数参数接口
interface PageDataConstructorParams {
  chapterIndex: number;
  pageIndexInChapter: number;
  globalPageIndex: number;
  lines: string[];
}

// 内存优化的 PageData 实现类
class PageDataImpl implements PageData {
  chapterIndex: number;
  pageIndexInChapter: number;
  globalPageIndex: number;
  lines: string[];

  constructor(data: PageDataConstructorParams) {
    this.chapterIndex = data.chapterIndex;
    this.pageIndexInChapter = data.pageIndexInChapter;
    this.globalPageIndex = data.globalPageIndex;
    this.lines = data.lines;
  }

  // 计算属性，不存储冗余文本
  get text(): string {
    return this.lines.join('\n');
  }
}

// LazyForEach 数据源
class PageDataSource implements IDataSource {
  private pages: PageData[];
  private listeners: DataChangeListener[] = [];

  constructor(pages: PageData[]) {
    this.pages = pages;
  }

  totalCount(): number {
    return this.pages.length;
  }

  getData(index: number): PageData {
    return this.pages[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const idx = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  // 更新数据时通知
  updateData(newPages: PageData[]) {
    this.pages = newPages;
    this.listeners.forEach(l => l.onDataReloaded());
  }
}

@Component
export struct ReaderContent {
  @Prop pages: PageData[] = [];
  @Prop chapters: Chapter[] = [];
  @Prop totalPages: number = 0;
  @Prop screenWidth: number = 360;
  @Prop screenHeight: number = 780;

  // 监听系统颜色模式变化，触发重新渲染
  @StorageProp('currentColorMode') currentColorMode: number = 0;

  onPageChange: (chapterIndex: number, pageIndex: number, globalPage: number) => void = () => {};
  onCenterTap: () => void = () => {};

  // 使用 LazyForEach 必须的数据源
  @State private pageDataSource: PageDataSource = new PageDataSource([]);
  private listScroller: Scroller = new Scroller();
  private currentGlobalPage: number = 0;
  private isJumping: boolean = false;
  private tapStartTime: number = 0;
  private tapStartX: number = 0;
  private tapStartY: number = 0;

  aboutToAppear() {
    // 初始化数据源
    this.pageDataSource = new PageDataSource(this.pages);

    // 监听跳转事件
    emitter.on(READER_EVENTS.JUMP_TO_PAGE, (eventData) => {
      const data = eventData.data as JumpToPageData;
      this.jumpToPage(data.globalPage);
    });

    emitter.on(READER_EVENTS.UPDATE_PAGINATION, () => {
      // 重新分页后，刷新数据源并跳转回当前页
      this.pageDataSource.updateData(this.pages);
      this.jumpToPage(Math.min(this.currentGlobalPage, this.totalPages - 1));
    });
  }

  aboutToDisappear() {
    emitter.off(READER_EVENTS.JUMP_TO_PAGE);
    emitter.off(READER_EVENTS.UPDATE_PAGINATION);
  }

  // 监听 pages 属性变化（父组件更新时）
  onPagesChange() {
    if (this.pages.length > 0) {
      this.pageDataSource.updateData(this.pages);
    }
  }

  // 监听颜色模式变化，强制刷新列表
  onColorModeChange() {
    // 颜色模式变化时，强制刷新数据源以触发重新渲染
    if (this.pages.length > 0) {
      this.pageDataSource.updateData([...this.pages]);
    }
  }

  jumpToPage(globalPage: number) {
    if (globalPage < 0 || globalPage >= this.totalPages || this.pages.length === 0) return;

    this.isJumping = true;
    this.currentGlobalPage = globalPage;

    // List 的 scrollToIndex 比 Scroll 的 scrollTo 更高效
    this.listScroller.scrollToIndex(globalPage, true, ScrollAlign.START);
    const pageData = this.pages[globalPage];
    if (pageData) {
      this.onPageChange(pageData.chapterIndex, pageData.pageIndexInChapter, globalPage);
    }

    // 动画完成后重置标志
    setTimeout(() => {
      this.isJumping = false;
    }, 350);
  }

  // 处理触摸事件，区分点击和滑动
  handleTouch(event: TouchEvent) {
    const touch = event.touches[0];

    if (event.type === TouchType.Down) {
      this.tapStartTime = Date.now();
      this.tapStartX = touch.x;
      this.tapStartY = touch.y;
    } else if (event.type === TouchType.Up) {
      const duration = Date.now() - this.tapStartTime;
      const deltaX = Math.abs(touch.x - this.tapStartX);
      const deltaY = Math.abs(touch.y - this.tapStartY);

      // 短按且移动距离小，视为点击
      if (duration < 300 && deltaX < 10 && deltaY < 10) {
        this.handleTap(touch.x, touch.y);
      }
    }
  }

  handleTap(x: number, y: number) {
    const centerX = this.screenWidth / 2;
    const centerY = this.screenHeight / 2;
    const tapAreaWidth = this.screenWidth * 0.3;
    const tapAreaHeight = this.screenHeight * 0.3;

    // 中心区域点击
    if (Math.abs(x - centerX) < tapAreaWidth / 2 &&
      Math.abs(y - centerY) < tapAreaHeight / 2) {
      this.onCenterTap();
    }
    // 左侧点击 - 上一页
    else if (x < this.screenWidth * 0.2) {
      this.jumpToPage(this.currentGlobalPage - 1);
    }
    // 右侧点击 - 下一页
    else if (x > this.screenWidth * 0.8) {
      this.jumpToPage(this.currentGlobalPage + 1);
    }
  }

  build() {
    Stack() {
      // 使用 List + LazyForEach 替代 Scroll + ForEach
      List({ scroller: this.listScroller }) {
        LazyForEach(this.pageDataSource, (page: PageData, index: number) => {
          ListItem() {
            this.PageBuilder(page, index)
          }
          .width('100%')
          .height(this.screenHeight) // 固定高度是关键
          .backgroundColor(Theme.BG_COLOR) // 使用动态颜色
        }, (page: PageData, index: number) => page.globalPageIndex.toString())
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
      .cachedCount(2) // 缓存前后2页，平衡内存和流畅度
      .onScrollIndex((start: number, end: number) => {
        // 滚动索引变化时更新当前页
        if (this.isJumping || this.pages.length === 0) return;

        // 取可视区域的中间页作为当前页
        const visiblePage = Math.floor((start + end) / 2);
        if (visiblePage !== this.currentGlobalPage && visiblePage >= 0 && visiblePage < this.totalPages) {
          this.currentGlobalPage = visiblePage;
          const pageData = this.pages[visiblePage];
          if (pageData) {
            this.onPageChange(pageData.chapterIndex, pageData.pageIndexInChapter, visiblePage);
          }
        }
      })
      .onTouch((event) => this.handleTouch(event))

      // 页码指示器
      this.PageIndicator()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG_COLOR) // 使用动态颜色
  }

  @Builder PageIndicator() {
    Column() {
      Text(`${this.currentGlobalPage + 1} / ${this.totalPages}`)
        .fontSize(11)
        .fontColor(Theme.TEXT_SECONDARY) // 使用动态颜色
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

  @Builder PageBuilder(page: PageData, index: number) {
    Column() {
      // 章节标题（仅章节第一页显示）
      if (page.pageIndexInChapter === 0) {
        Text(this.chapters[page.chapterIndex]?.title || '')
          .fontSize(Theme.FONT_CHAPTER)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT_MAIN) // 使用动态颜色
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: LayoutConfig.TOP_MARGIN, bottom: 20 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      // 页面内容 - 修复：使用 Stack 包裹确保撑满宽度，每行 Text 设置 100% 宽度
      Stack({ alignContent: Alignment.TopStart }) {
        Column() {
          ForEach(page.lines, (line: string, lineIdx: number) => {
            Text(line)
              .fontSize(Theme.FONT_BODY)
              .fontColor(Theme.TEXT_MAIN) // 使用动态颜色
              .width('100%') // 确保撑满父容器宽度
              .height(Theme.LINE_HEIGHT) // 固定行高
              .textAlign(TextAlign.Start)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Clip })
          }, (line: string, lineIdx: number) => lineIdx.toString())
        }
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding({
      left: Theme.PAGE_PADDING,
      right: Theme.PAGE_PADDING,
      top: page.pageIndexInChapter === 0 ? 0 : LayoutConfig.TOP_MARGIN,
      bottom: LayoutConfig.BOTTOM_MARGIN
    })
    .backgroundColor(Theme.BG_COLOR) // 使用动态颜色
    .alignItems(HorizontalAlign.Start)
  }
}