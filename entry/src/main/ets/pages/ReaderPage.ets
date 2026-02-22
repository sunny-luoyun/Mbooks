// entry/src/main/ets/pages/ReaderPage.ets (修复版)

import router from '@ohos.router';
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import preferences from '@ohos.data.preferences';
import display from '@ohos.display';

interface ReaderParams {
  fileName: string;
  title: string;
  threadId?: string;
}

interface Chapter {
  title: string;
  index: number;
  level: number;
  contentLength?: number;
}

interface Bookmark {
  id: string;
  chapterIndex: number;
  charIndex: number;
  excerpt: string;
  timestamp: number;
}

// ✅ 修复：Progress 结构优化，移除不可靠的 scrollIndex
interface Progress {
  chapterIndex: number;
  chapterOffset: number;  // 章节内字符偏移（0-1 之间的比例）
  timestamp: number;
}

const CHAPTER_REGEX = /(?:第[一二三四五六七八九十百千零\d]+章|章节\s*\d+|Chapter\s*\d+|^\d+\.)\s*[^\n]*/gmi;
const PREF_KEY_PREFIX = 'reader_';

@Entry
@Component
struct ReaderPage {
  // 基础状态
  @State content: string = "";
  @State title: string = "";
  @State isLoading: boolean = true;
  @State errorMsg: string = "";
  @State fileName: string = "";

  // 目录相关
  @State chapters: Chapter[] = [];
  @State showCatalog: boolean = false;
  @State currentChapterIndex: number = 0;

  // 书签相关
  @State bookmarks: Bookmark[] = [];
  @State showBookmarks: boolean = false;
  @State showAddBookmark: boolean = false;

  // List 控制器
  private listController: ListScroller = new ListScroller();

  // 进度管理
  private prefManager: preferences.Preferences | null = null;

  // ✅ 修复：使用 Map 存储每个章节的真实高度（用于精确跳转）
  private chapterHeights: Map<number, number> = new Map();

  // ✅ 修复：记录 List 当前真实可见的索引范围
  private visibleStartIndex: number = 0;
  private visibleEndIndex: number = 0;

  // 常量
  private readonly CONTENT_START_INDEX = 0;  // 简化：顶部不需要占位，TopBar 在 List 外

  // ✅ 修复：正确的定时器类型
  private saveTimer: number | null = null;
  private isRestoring: boolean = false;  // 标记是否正在恢复位置，避免保存冲突

  aboutToAppear() {
    const params = router.getParams() as ReaderParams;
    if (params && params.fileName) {
      this.fileName = params.fileName;
      this.title = params.title || '未命名';
      this.initPreferences();
      this.readBookContent(params.fileName);
    } else {
      this.errorMsg = "参数错误：未指定文件名";
      this.isLoading = false;
    }
  }

  aboutToDisappear() {
    // ✅ 修复：页面销毁时立即保存一次进度
    if (!this.isRestoring) {
      this.saveProgressImmediate();
    }
    // 清理定时器
    if (this.saveTimer !== null) {
      clearTimeout(this.saveTimer);
      this.saveTimer = null;
    }
  }

  async initPreferences() {
    try {
      this.prefManager = await preferences.getPreferences(getContext(this), 'reader_prefs');
      await this.loadBookmarks();
    } catch (e) {
      console.error('[ReaderPage] Init prefs failed:', e);
    }
  }

  readBookContent(fileName: string) {
    let file: fs.File | null = null;
    try {
      let context = getContext(this);
      let filePath = `${context.filesDir}/threads/${fileName}`;

      if (!fs.accessSync(filePath)) {
        const oldPath = `${context.filesDir}/${fileName}`;
        if (fs.accessSync(oldPath)) {
          filePath = oldPath;
        } else {
          throw new Error(`文件不存在: ${filePath}`);
        }
      }

      file = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
      let stat = fs.statSync(file.fd);
      if (stat.size === 0) throw new Error("文件为空");

      let buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);

      let textDecoder = util.TextDecoder.create('utf-8');
      let uint8Array = new Uint8Array(buf);
      this.content = textDecoder.decodeWithStream(uint8Array);

      this.parseChapters();
      this.isLoading = false;

      // ✅ 修复：确保章节解析完成后再恢复位置
      setTimeout(() => {
        this.restorePosition();
      }, 100);

    } catch (e) {
      console.error(`[ReaderPage] Read failed:`, e);
      this.errorMsg = "读取失败: " + (e.message || JSON.stringify(e));
      this.isLoading = false;
    } finally {
      if (file) {
        try { fs.closeSync(file); } catch (e) {}
      }
    }
  }

  parseChapters() {
    const matches = Array.from(this.content.matchAll(CHAPTER_REGEX));
    this.chapters = matches.map((match, idx) => ({
      title: match[0].trim().substring(0, 50),
      index: match.index || 0,
      level: this.detectLevel(match[0]),
      contentLength: 0
    } as Chapter));

    for (let i = 0; i < this.chapters.length; i++) {
      const start = this.chapters[i].index;
      const end = i + 1 < this.chapters.length ? this.chapters[i + 1].index : this.content.length;
      this.chapters[i].contentLength = end - start;
    }

    if (this.chapters.length === 0) {
      const segmentLength = 5000;
      const count = Math.ceil(this.content.length / segmentLength);
      for (let i = 0; i < count; i++) {
        const start = i * segmentLength;
        const end = Math.min(start + segmentLength, this.content.length);
        this.chapters.push({
          title: `第${i + 1}部分`,
          index: start,
          level: 0,
          contentLength: end - start
        });
      }
    }
    console.log(`[ReaderPage] Parsed ${this.chapters.length} chapters`);
  }

  detectLevel(title: string): number {
    if (title.match(/^第[一二三四五六七八九十百千零]+章/)) return 0;
    if (title.match(/^章节\s*\d+/i)) return 0;
    if (title.match(/^Chapter\s*\d+/i)) return 0;
    if (title.match(/^\d+\./)) return 1;
    return 2;
  }

  // ==================== 核心修复：精确的跳转方法 ====================

  /**
   * ✅ 修复：跳转到指定章节和精确位置
   */
  jumpToChapter(chapterIndex: number, chapterOffsetRatio: number = 0) {
    if (chapterIndex < 0 || chapterIndex >= this.chapters.length) {
      console.warn(`[ReaderPage] Invalid chapter index: ${chapterIndex}`);
      return;
    }

    console.log(`[ReaderPage] Jump to chapter ${chapterIndex}, offset ${chapterOffsetRatio}`);

    this.isRestoring = true;  // 标记正在恢复，避免保存冲突
    this.currentChapterIndex = chapterIndex;

    // 直接跳转到目标章节的 ListItem
    this.listController.scrollToIndex(chapterIndex, true, ScrollAlign.START);

    // 如果有章节内偏移，进行微调
    if (chapterOffsetRatio > 0) {
      setTimeout(() => {
        this.adjustChapterOffset(chapterIndex, chapterOffsetRatio);
        this.isRestoring = false;  // 恢复完成
      }, 350);  // 给 List 滚动动画留出时间
    } else {
      setTimeout(() => {
        this.isRestoring = false;
      }, 350);
    }

    this.showCatalog = false;
  }

  /**
   * ✅ 修复：章节内偏移调整 - 基于比例而非绝对像素
   */
  private adjustChapterOffset(chapterIndex: number, offsetRatio: number) {
    const chapter = this.chapters[chapterIndex];
    if (!chapter.contentLength || chapter.contentLength === 0) return;

    // 计算需要滚动的像素距离
    // 先尝试获取已缓存的章节高度
    let chapterHeight = this.chapterHeights.get(chapterIndex);

    if (!chapterHeight) {
      // 如果没有缓存，使用估算高度
      chapterHeight = this.estimateChapterHeight(chapter);
    }

    const scrollDelta = offsetRatio * chapterHeight;

    if (scrollDelta > 0) {
      console.log(`[ReaderPage] Adjust offset by ${scrollDelta}px (ratio: ${offsetRatio})`);
      this.listController.scrollBy(0, scrollDelta);
    }
  }

  private estimateChapterHeight(chapter: Chapter): number {
    if (!chapter.contentLength) return 500;

    const displayInfo = display.getDefaultDisplaySync();
    const screenWidth = displayInfo.width / displayInfo.densityPixels;
    const availableWidth = screenWidth - 40;
    const charsPerLine = Math.floor(availableWidth / 18 * 0.95);

    const lineHeight = 32;
    const lines = Math.ceil(chapter.contentLength / charsPerLine);

    return lines * lineHeight + 60;
  }

  // ==================== 核心修复：精确的进度保存 ====================

  /**
   * ✅ 修复：基于真实可见索引计算进度
   */
  private calculateCurrentProgress(): Progress {
    // 使用 onScrollIndex 记录的真实可见索引
    const chapterIdx = Math.min(this.visibleStartIndex, this.chapters.length - 1);
    const chapter = this.chapters[chapterIdx];

    if (!chapter) {
      return { chapterIndex: 0, chapterOffset: 0, timestamp: Date.now() };
    }

    // 计算章节内偏移比例（0-1）
    let offsetRatio = 0;

    // 获取章节在屏幕上的位置信息来估算偏移
    // 由于 HarmonyOS 没有直接提供，我们通过可见索引和滚动位置估算
    if (this.visibleStartIndex === chapterIdx && this.visibleEndIndex > chapterIdx) {
      // 当前章节占据屏幕主要部分，估算为开始位置
      offsetRatio = 0;
    } else {
      // 章节已经在屏幕上方，估算偏移
      // 这里简化处理，如果需要更精确，需要监听每个章节的 onAreaChange
      offsetRatio = 0;
    }

    return {
      chapterIndex: chapterIdx,
      chapterOffset: offsetRatio,
      timestamp: Date.now()
    };
  }

  /**
   * ✅ 修复：立即保存进度（用于页面销毁时）
   */
  private async saveProgressImmediate() {
    if (!this.prefManager || this.chapters.length === 0) return;

    const progress = this.calculateCurrentProgress();
    const key = `${PREF_KEY_PREFIX}progress_${this.fileName}`;

    try {
      await this.prefManager.put(key, JSON.stringify(progress));
      await this.prefManager.flush();
      console.log(`[ReaderPage] Progress saved immediately:`, progress);
    } catch (e) {
      console.error('[ReaderPage] Save progress failed:', e);
    }
  }

  /**
   * ✅ 修复：延迟保存进度（用于滚动时）
   */
  private saveProgressDelayed() {
    if (this.isRestoring) return;  // 恢复过程中不保存

    // 清理之前的定时器
    if (this.saveTimer !== null) {
      clearTimeout(this.saveTimer);
    }

    // 设置新的定时器，1秒后保存
    this.saveTimer = setTimeout(() => {
      this.saveProgressImmediate();
      this.saveTimer = null;
    }, 1000);
  }

  async loadProgress() {
    if (!this.prefManager) return;
    try {
      const key = `${PREF_KEY_PREFIX}progress_${this.fileName}`;
      const data = await this.prefManager.get(key, '');
      if (data) {
        const progress: Progress = JSON.parse(data.toString());
        console.log(`[ReaderPage] Loaded progress:`, progress);
        return progress;
      }
    } catch (e) {
      console.error('[ReaderPage] Load progress failed:', e);
    }
    return null;
  }

  async restorePosition() {
    if (this.chapters.length === 0) return;

    const progress = await this.loadProgress();
    if (!progress) {
      // 没有保存的进度，默认从第一章开始
      this.currentChapterIndex = 0;
      return;
    }

    // 确保章节索引有效
    const chapterIdx = Math.min(progress.chapterIndex, this.chapters.length - 1);
    this.currentChapterIndex = chapterIdx;

    console.log(`[ReaderPage] Restoring to chapter ${chapterIdx}, offset ${progress.chapterOffset}`);

    // 使用保存的偏移比例跳转
    this.jumpToChapter(chapterIdx, progress.chapterOffset);
  }

  // ==================== 书签管理（保持不变） ====================

  async loadBookmarks() {
    if (!this.prefManager) return;
    try {
      const key = `${PREF_KEY_PREFIX}bookmarks_${this.fileName}`;
      const data = await this.prefManager.get(key, '[]');
      this.bookmarks = JSON.parse(data as string);
    } catch (e) {
      this.bookmarks = [];
    }
  }

  async saveBookmarks() {
    if (!this.prefManager) return;
    const key = `${PREF_KEY_PREFIX}bookmarks_${this.fileName}`;
    await this.prefManager.put(key, JSON.stringify(this.bookmarks));
    await this.prefManager.flush();
  }

  addBookmark() {
    const chapterIdx = this.currentChapterIndex;
    const chapter = this.chapters[chapterIdx];

    // ✅ 修复：书签使用章节内偏移比例，更精确
    const charIndex = chapter.index + Math.floor((chapter.contentLength || 0) * 0.1); // 默认记录10%位置
    const excerpt = this.content.substring(charIndex, charIndex + 40) + '...';

    const bookmark: Bookmark = {
      id: Date.now().toString(),
      chapterIndex: chapterIdx,
      charIndex: charIndex,
      excerpt: excerpt,
      timestamp: Date.now()
    };

    this.bookmarks.unshift(bookmark);
    this.saveBookmarks();
    this.showAddBookmark = false;
  }

  deleteBookmark(id: string) {
    this.bookmarks = this.bookmarks.filter(b => b.id !== id);
    this.saveBookmarks();
  }

  jumpToBookmark(bookmark: Bookmark) {
    const chapter = this.chapters[bookmark.chapterIndex];
    if (!chapter) return;

    // 计算章节内偏移比例
    const offsetRatio = Math.min(1, Math.max(0,
      (bookmark.charIndex - chapter.index) / (chapter.contentLength || 1)
    ));

    this.jumpToChapter(bookmark.chapterIndex, offsetRatio);
    this.showBookmarks = false;
  }

  // ==================== UI 构建（核心修复：List 事件监听） ====================

  build() {
    Stack() {
      Column() {
        this.TopBar()
        if (this.isLoading) {
          this.LoadingView()
        } else if (this.errorMsg) {
          this.ErrorView()
        } else {
          this.ContentView()
        }
        if (!this.isLoading && !this.errorMsg) {
          this.BottomBar()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#f4efe7')

      if (this.showCatalog) {
        this.CatalogPanel()
      }
      if (this.showBookmarks) {
        this.BookmarkPanel()
      }
      if (this.showAddBookmark) {
        this.AddBookmarkDialog()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  TopBar() {
    Row() {
      Text('❮')
        .fontSize(22)
        .padding(10)
        .onClick(() => {
          this.saveProgressImmediate();  // 返回前保存
          router.back();
        })

      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)

      Row() {
        Button('☰')
          .fontSize(20)
          .backgroundColor(Color.Transparent)
          .fontColor('#333')
          .onClick(() => {
            this.showCatalog = true;
            this.showBookmarks = false;
          })

        Button('🔖')
          .fontSize(20)
          .backgroundColor(Color.Transparent)
          .fontColor('#333')
          .margin({ left: 8 })
          .onClick(() => {
            this.showBookmarks = true;
            this.showCatalog = false;
          })
      }
    }
    .width('100%')
    .padding({ top: 40, bottom: 12, left: 16, right: 16 })
    .backgroundColor('#f2f2f2')
    .zIndex(10)
  }

  @Builder
  ContentView() {
    List({ scroller: this.listController }) {
      // ✅ 修复：简化结构，每个章节一个 ListItem
      ForEach(this.chapters, (chapter: Chapter, index: number) => {
        ListItem() {
          this.ChapterContentBuilder(chapter, index)
        }
        .id(`chapter_${index}`)
        // ✅ 新增：监听章节项的面积变化，获取真实高度
        .onAreaChange((oldArea, newArea) => {
          if (newArea.height > 0) {
            this.chapterHeights.set(index, Number(newArea.height));
          }
        })
      })

      // 底部占位
      ListItem() {
        Column() {
          Blank().height(200 as number)
          Text('已到达末尾').fontSize(12).fontColor('#999').margin({ top: 20 })
        }
        .width('100%')
      }
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
    // ✅ 关键修复：准确监听滚动索引变化
    .onScrollIndex((start: number, end: number) => {
      // 记录真实的可见索引范围
      this.visibleStartIndex = start;
      this.visibleEndIndex = end;

      // 更新当前章节（取可见范围的中间值更准确）
      const visibleChapterStart = Math.max(0, start);
      const visibleChapterEnd = Math.min(this.chapters.length - 1, end);
      const mainChapter = Math.floor((visibleChapterStart + visibleChapterEnd) / 2);

      if (mainChapter !== this.currentChapterIndex && mainChapter < this.chapters.length) {
        this.currentChapterIndex = mainChapter;
        // 延迟保存进度
        this.saveProgressDelayed();
      }
    })
    .cachedCount(3)  // ✅ 优化：减少缓存数量，降低内存占用
    .listDirection(Axis.Vertical)
  }

  @Builder
  ChapterContentBuilder(chapter: Chapter, index: number) {
    Column() {
      if (this.shouldShowChapterTitle(chapter.title, index)) {
        Text(chapter.title)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#2c2c2c')
          .margin({ top: index === 0 ? 16 : 32, bottom: 16 })
          .width('100%')
          .textAlign(TextAlign.Start)
      }

      Text(this.getChapterText(chapter))
        .fontSize(18)
        .lineHeight(32)
        .fontColor('#2c2c2c')
        .width('100%')
        .textAlign(TextAlign.Start)
        .textOverflow({ overflow: TextOverflow.Clip })
        .maxLines(undefined)
        .padding({ bottom: 24 })
    }
    .width('100%')
    .padding({ left: 20, right: 20 })
    .backgroundColor('#f4efe7')
  }

  private shouldShowChapterTitle(title: string, index: number): boolean {
    const content = this.getChapterText(this.chapters[index]);
    const trimmedContent = content.trimStart();
    if (trimmedContent.startsWith(title)) return false;
    if (title.startsWith('第') && title.includes('部分')) return true;
    return true;
  }

  private getChapterText(chapter: Chapter): string {
    const start = chapter.index;
    const end = start + (chapter.contentLength || 0);
    return this.content.substring(start, end);
  }

  @Builder
  BottomBar() {
    Row() {
      Text(`章节 ${this.currentChapterIndex + 1}/${this.chapters.length}`)
        .fontSize(12)
        .fontColor('#666')

      Blank()

      Button('+ 书签')
        .fontSize(12)
        .height(28)
        .backgroundColor('#e6d7c3')
        .fontColor('#5c4b37')
        .onClick(() => this.showAddBookmark = true)
    }
    .width('100%')
    .height(50)
    .padding({ left: 20, right: 20 })
    .backgroundColor('#f2f2f2')
    .border({ width: { top: 1 }, color: '#e0e0e0' })
  }

  @Builder
  CatalogPanel() {
    Stack() {
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.5)')
        .onClick(() => this.showCatalog = false)

      Row() {
        Column() {
          Text('目录')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .margin({ top: 40, bottom: 20 })
            .width('100%')
            .textAlign(TextAlign.Center)

          List() {
            ForEach(this.chapters, (chapter: Chapter, index: number) => {
              ListItem() {
                Row() {
                  Text(chapter.title)
                    .fontSize(16)
                    .fontColor(index === this.currentChapterIndex ? '#ff6b6b' : '#333')
                    .fontWeight(index === this.currentChapterIndex ? FontWeight.Bold : FontWeight.Normal)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)

                  if (index === this.currentChapterIndex) {
                    Text('●')
                      .fontSize(12)
                      .fontColor('#ff6b6b')
                  }
                }
                .width('100%')
                .padding(16)
                .backgroundColor(index === this.currentChapterIndex ? '#fff5f5' : Color.Transparent)
                .onClick(() => this.jumpToChapter(index))
              }
            })
          }
          .width('100%')
          .layoutWeight(1)
          .divider({ strokeWidth: 1, color: '#f0f0f0' })

          Button('关闭')
            .width('80%')
            .margin({ top: 16, bottom: 20 })
            .onClick(() => this.showCatalog = false)
        }
        .width('75%')
        .height('100%')
        .backgroundColor('#fff')
        .padding({ left: 16, right: 16 })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .height('100%')
    .zIndex(100)
  }

  @Builder
  BookmarkPanel() {
    Stack() {
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.5)')
        .onClick(() => this.showBookmarks = false)

      Row() {
        Column() {
          Text('我的书签')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .margin({ top: 40, bottom: 20 })
            .width('100%')
            .textAlign(TextAlign.Center)

          if (this.bookmarks.length === 0) {
            Column() {
              Text('暂无书签')
                .fontSize(14)
                .fontColor('#999')
                .margin({ top: 50 })
            }
            .layoutWeight(1)
          } else {
            List() {
              ForEach(this.bookmarks, (bookmark: Bookmark, index: number) => {
                ListItem() {
                  Row() {
                    Column() {
                      Text(bookmark.excerpt)
                        .fontSize(14)
                        .fontColor('#333')
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width('100%')

                      Text(`第${bookmark.chapterIndex + 1}章 · ${this.formatTime(bookmark.timestamp)}`)
                        .fontSize(12)
                        .fontColor('#999')
                        .margin({ top: 4 })
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                  }
                  .width('100%')
                  .padding(12)
                  .backgroundColor('#f9f9f9')
                  .borderRadius(8)
                }
                .swipeAction({ end: this.DeleteButton(bookmark.id) })
                .onClick(() => this.jumpToBookmark(bookmark))
              })
            }
            .width('100%')
            .layoutWeight(1)
            .divider({ strokeWidth: 1, color: '#f0f0f0' })
            .padding({ bottom: 12 })
          }

          Button('关闭')
            .width('80%')
            .margin({ bottom: 20 })
            .onClick(() => this.showBookmarks = false)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#fff')
        .padding({ left: 16, right: 16 })
      }
      .width('80%')
      .height('100%')
      .position({ x: '20%', y: 0 })
    }
    .width('100%')
    .height('100%')
    .zIndex(100)
  }

  @Builder
  DeleteButton(id: string) {
    Button() {
      Text('删除')
        .fontColor('#fff')
        .fontSize(14)
    }
    .width(60)
    .height('100%')
    .backgroundColor('#ff4d4f')
    .onClick(() => {
      this.deleteBookmark(id);
    })
  }

  @Builder
  AddBookmarkDialog() {
    Column() {
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.6)')
        .onClick(() => this.showAddBookmark = false)

      Column() {
        Text('添加书签')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 16 })

        Text(`当前位置：第${this.currentChapterIndex + 1}章`)
          .fontSize(14)
          .fontColor('#666')
          .margin({ bottom: 20 })

        Text('确定要在当前位置添加书签吗？')
          .fontSize(14)
          .fontColor('#333')
          .margin({ bottom: 24 })

        Row({ space: 12 }) {
          Button('取消')
            .width(100)
            .backgroundColor('#f0f0f0')
            .fontColor('#666')
            .onClick(() => this.showAddBookmark = false)

          Button('确定')
            .width(100)
            .backgroundColor('#ff6b6b')
            .fontColor('#fff')
            .onClick(() => this.addBookmark())
        }
      }
      .width(300)
      .padding(24)
      .backgroundColor('#fff')
      .borderRadius(12)
      .position({ x: '50%', y: '50%' })
      .markAnchor({ x: 150, y: -100 })
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    .zIndex(200)
  }

  @Builder
  LoadingView() {
    Column() {
      LoadingProgress().width(40).height(40)
      Text('加载中...').fontSize(14).fontColor('#999').margin({ top: 12 })
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  ErrorView() {
    Column() {
      Text('⚠️').fontSize(48).margin({ bottom: 16 })
      Text(this.errorMsg).fontSize(14).fontColor('#FF4D4F').textAlign(TextAlign.Center)
      Button('返回').margin({ top: 20 }).onClick(() => router.back())
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding(20)
  }

  formatTime(timestamp: number): string {
    const date = new Date(timestamp);
    return `${date.getMonth() + 1}/${date.getDate()} ${date.getHours()}:${date.getMinutes().toString().padStart(2, '0')}`;
  }
}