// entry/src/main/ets/pages/ReaderPage.ets
import router from '@ohos.router';
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import preferences from '@ohos.data.preferences';
import window from '@ohos.window';
import common from '@ohos.app.ability.common';
import { ReaderContent } from '../components/reader/ReaderContent';
import { ReaderController, ControllerState } from '../components/reader/ReaderController';
import { Theme, LayoutConfig } from '../components/reader/ReaderStyles';
import emitter from '@ohos.events.emitter';

interface ReaderParams {
  fileName: string;
  title: string;
  threadId?: string;
}

export interface Chapter {
  title: string;
  startPage: number;
  endPage: number;
  level: number;
  pageCount: number;
}

export interface Bookmark {
  id: string;
  chapterIndex: number;
  pageIndex: number;
  globalPage: number;
  excerpt: string;
  timestamp: number;
}

export interface Progress {
  chapterIndex: number;
  pageIndex: number;
  globalPage: number;
  timestamp: number;
}

export interface JumpToPageData {
  globalPage: number;
  chapterIndex: number;
  pageIndex: number;
}

interface ReaderEvents {
  JUMP_TO_PAGE: string;
  JUMP_TO_GLOBAL_PAGE: string;
  GET_CURRENT_PAGE: string;
  PAGE_RESULT: string;
  UPDATE_PAGINATION: string;
}

export const READER_EVENTS: ReaderEvents = {
  JUMP_TO_PAGE: 'jump_to_page',
  JUMP_TO_GLOBAL_PAGE: 'jump_to_global_page',
  GET_CURRENT_PAGE: 'get_current_page',
  PAGE_RESULT: 'page_result',
  UPDATE_PAGINATION: 'update_pagination'
};

const CHAPTER_REGEX = /(?:第[一二三四五六七八九十百千零\d]+章|章节\s*\d+|Chapter\s*\d+|^\d+\.)\s*[^\n]*/gmi;
const PREF_KEY_PREFIX = 'reader_';
// 内存优化的 PageData 接口
export interface PageData {
  chapterIndex: number;
  pageIndexInChapter: number;
  globalPageIndex: number;
  lines: string[];
  // 不再存储 text，由组件计算
}

@Entry
@Component
struct ReaderPage {
  @State content: string = "";
  @State title: string = "";
  @State isLoading: boolean = true;
  @State errorMsg: string = "";
  @State fileName: string = "";
  @State chapters: Chapter[] = [];
  @State currentChapterIndex: number = 0;
  @State currentPageIndex: number = 0;
  @State totalPages: number = 0;
  @State bookmarks: Bookmark[] = [];
  @State controllerState: ControllerState = ControllerState.HIDDEN;
  @State screenWidth: number = 360;
  @State screenHeight: number = 780;

  // 使用 @State 让 ReaderContent 能监听变化
  @State pages: PageData[] = [];

  private prefManager: preferences.Preferences | null = null;
  private saveTimer: number | null = null;
  private isRestoring: boolean = false;

  aboutToAppear() {
    const params = router.getParams() as ReaderParams;
    if (params?.fileName) {
      this.fileName = params.fileName;
      this.title = params.title || '未命名';
      this.updateScreenSize();
      this.initPreferences().then(() => {
        this.readBookContent(params.fileName);
      });
    } else {
      this.errorMsg = "参数错误：未指定文件名";
      this.isLoading = false;
    }
  }

  aboutToDisappear() {
    this.saveProgressImmediate();
    if (this.saveTimer !== null) clearTimeout(this.saveTimer);
  }

  async updateScreenSize() {
    try {
      let windowClass = await window.getLastWindow(getContext(this) as common.UIAbilityContext);
      let windowInfo = windowClass.getWindowProperties();
      if (windowInfo?.windowRect) {
        this.screenWidth = px2vp(windowInfo.windowRect.width);
        this.screenHeight = px2vp(windowInfo.windowRect.height);
      }
    } catch (e) {
      console.error('Get window size failed:', e);
      // 使用默认值
      this.screenWidth = 360;
      this.screenHeight = 780;
    }
  }

  async initPreferences() {
    try {
      this.prefManager = await preferences.getPreferences(getContext(this), 'reader_prefs');
      await this.loadBookmarks();
    } catch (e) {
      console.error('Init prefs failed:', e);
    }
  }

  readBookContent(fileName: string) {
    let file: fs.File | null = null;
    try {
      let context = getContext(this);
      let filePath = `${context.filesDir}/threads/${fileName}`;

      // 检查文件存在性
      if (!fs.accessSync(filePath)) {
        const oldPath = `${context.filesDir}/${fileName}`;
        if (fs.accessSync(oldPath)) {
          filePath = oldPath;
        } else {
          throw new Error(`文件不存在: ${filePath}`);
        }
      }

      // 获取文件信息
      const stat = fs.statSync(filePath);
      const fileSize = stat.size;

      // 大文件警告（超过 10MB）
      if (fileSize > 10 * 1024 * 1024) {
        console.warn(`大文件警告: ${fileSize / 1024 / 1024}MB，加载可能需要时间`);
      }

      file = fs.openSync(filePath, fs.OpenMode.READ_ONLY);

      // 分块读取大文件，避免一次性分配超大 ArrayBuffer
      const MAX_CHUNK = 5 * 1024 * 1024; // 5MB 分块
      let content = '';

      if (fileSize <= MAX_CHUNK) {
        // 小文件直接读
        let buf = new ArrayBuffer(fileSize);
        fs.readSync(file.fd, buf);
        let textDecoder = util.TextDecoder.create('utf-8');
        content = textDecoder.decodeWithStream(new Uint8Array(buf));
      } else {
        // 大文件分块读（简化版，实际可能需要更复杂的拼接逻辑处理编码边界）
        let textDecoder = util.TextDecoder.create('utf-8');
        let offset = 0;
        while (offset < fileSize) {
          const chunkSize = Math.min(MAX_CHUNK, fileSize - offset);
          let buf = new ArrayBuffer(chunkSize);
          fs.readSync(file.fd, buf, { offset: offset, length: chunkSize });
          content += textDecoder.decodeWithStream(new Uint8Array(buf));
          offset += chunkSize;
        }
      }

      this.content = content;

      // 解析章节
      this.parseChapters();

      // 执行分页（优化版）
      this.performPagination();

      this.isLoading = false;

      // 延迟恢复位置，确保 ReaderContent 已渲染
      setTimeout(() => this.restorePosition(), 200);

    } catch (e) {
      this.errorMsg = "读取失败: " + (e as Error).message;
      this.isLoading = false;
      console.error('Read book failed:', e);
    } finally {
      if (file) fs.closeSync(file);
    }
  }

  // 优化版分页：限制最大页数，使用内存友好的数据结构
  performPagination() {
    if (!this.content || this.chapters.length === 0) {
      this.pages = [];
      this.totalPages = 0;
      return;
    }

    const newPages: PageData[] = [];
    let globalPageIndex = 0;

    const contentWidth = Math.max(100, this.screenWidth - Theme.PAGE_PADDING * 2);
    const charsPerLine = Math.floor(contentWidth / LayoutConfig.CHAR_WIDTH);
    const availableHeight = Math.max(200, this.screenHeight - LayoutConfig.TOP_MARGIN - LayoutConfig.BOTTOM_MARGIN);
    const linesPerPage = Math.floor(availableHeight / Theme.LINE_HEIGHT);

    // 限制最大页数，防止内存爆炸（约 5000 页，约 2-3MB 文本）
    const MAX_PAGES = 5000;

    for (let chapterIdx = 0; chapterIdx < this.chapters.length; chapterIdx++) {
      const chapter = this.chapters[chapterIdx];
      const startIdx = chapter.startPage; // 此时还是字符索引
      const endIdx = chapter.endPage;
      const chapterContent = this.content.substring(startIdx, endIdx);

      // 文本断行
      const lines = this.breakTextIntoLines(chapterContent, charsPerLine);

      chapter.startPage = globalPageIndex; // 改为页码索引

      let pageLines: string[] = [];
      for (let line of lines) {
        pageLines.push(line);

        if (pageLines.length >= linesPerPage) {
          // 只存储 lines，不存储 text
          newPages.push({
            chapterIndex: chapterIdx,
            pageIndexInChapter: chapter.pageCount,
            globalPageIndex: globalPageIndex,
            lines: pageLines.slice() // 复制数组
          });

          pageLines = [];
          chapter.pageCount++;
          globalPageIndex++;

          // 检查最大页数限制
          if (globalPageIndex >= MAX_PAGES) {
            console.warn(`达到最大页数限制 ${MAX_PAGES}，后续内容将被截断`);
            break;
          }
        }
      }

      // 处理剩余行
      if (pageLines.length > 0 && globalPageIndex < MAX_PAGES) {
        newPages.push({
          chapterIndex: chapterIdx,
          pageIndexInChapter: chapter.pageCount,
          globalPageIndex: globalPageIndex,
          lines: pageLines
        });
        chapter.pageCount++;
        globalPageIndex++;
      }

      chapter.endPage = globalPageIndex;

      // 提前退出检查
      if (globalPageIndex >= MAX_PAGES) break;
    }

    // 更新状态（触发 ReaderContent 重新渲染）
    this.pages = newPages;
    this.totalPages = globalPageIndex;

    console.info(`分页完成：共 ${this.totalPages} 页，${this.chapters.length} 章，内存页数 ${newPages.length}`);
  }

  breakTextIntoLines(text: string, charsPerLine: number): string[] {
    const lines: string[] = [];
    let currentLine = '';
    let currentWidth = 0;

    for (let i = 0; i < text.length; i++) {
      const char = text[i];
      const charWidth = this.getCharWidth(char);

      if (char === '\n') {
        if (currentLine) lines.push(currentLine);
        currentLine = '';
        currentWidth = 0;
      } else if (currentWidth + charWidth > charsPerLine) {
        // 行尾标点处理
        if (this.isPunctuation(char) && currentLine.length > 0) {
          currentLine += char;
          lines.push(currentLine);
          currentLine = '';
          currentWidth = 0;
        } else {
          if (currentLine) lines.push(currentLine);
          currentLine = char;
          currentWidth = charWidth;
        }
      } else {
        currentLine += char;
        currentWidth += charWidth;
      }
    }

    if (currentLine) {
      lines.push(currentLine);
    }

    return lines;
  }

  getCharWidth(char: string): number {
    // 中文字符和全角字符占2，英文占1
    const code = char.charCodeAt(0);
    return (code > 127 || (code >= 0xFF01 && code <= 0xFF5E)) ? 2 : 1;
  }

  isPunctuation(char: string): boolean {
    return '，。！？；：""\'\'（）【】、'.includes(char);
  }

  parseChapters(): void {
    // 重置章节数组
    this.chapters = [];

    const matches = Array.from(this.content.matchAll(CHAPTER_REGEX));

    if (matches.length === 0) {
      // 无章节，整本书作为一章
      this.chapters = [{
        title: "正文",
        startPage: 0,
        endPage: this.content.length,
        level: 0,
        pageCount: 0
      }];
    } else {
      this.chapters = matches.map((match, idx): Chapter => ({
        title: match[0].trim().substring(0, 50),
        startPage: match.index || 0,
        endPage: idx + 1 < matches.length ? (matches[idx + 1].index ?? this.content.length) : this.content.length,
        level: this.detectLevel(match[0]),
        pageCount: 0
      }));
    }
  }

  detectLevel(title: string): number {
    if (title.match(/^第[一二三四五六七八九十百千零]+章/)) return 0;
    if (title.match(/^[第章节]\d+/)) return 1;
    return 2;
  }

  jumpToChapter(chapterIndex: number, pageIndex: number = 0): void {
    if (chapterIndex < 0 || chapterIndex >= this.chapters.length) return;

    const chapter = this.chapters[chapterIndex];
    const safePageIndex = Math.max(0, Math.min(pageIndex, chapter.pageCount - 1));
    const globalPage = chapter.startPage + safePageIndex;

    this.jumpToGlobalPage(globalPage);
  }

  jumpToGlobalPage(globalPage: number): void {
    if (this.totalPages === 0) return;

    const safePage = Math.max(0, Math.min(globalPage, this.totalPages - 1));

    this.isRestoring = true;

    const pageData = this.pages[safePage];
    if (pageData) {
      this.currentChapterIndex = pageData.chapterIndex;
      this.currentPageIndex = pageData.pageIndexInChapter;
    }

    // 发送事件到 ReaderContent
    emitter.emit(READER_EVENTS.JUMP_TO_PAGE, {
      data: {
        globalPage: safePage,
        chapterIndex: pageData?.chapterIndex ?? 0,
        pageIndex: pageData?.pageIndexInChapter ?? 0
      }
    });

    this.saveProgressDelayed();

    setTimeout(() => {
      this.isRestoring = false;
    }, 500);

    this.controllerState = ControllerState.HIDDEN;
  }

  onPageChanged(chapterIndex: number, pageIndex: number, globalPage: number) {
    if (this.isRestoring) return;

    this.currentChapterIndex = chapterIndex;
    this.currentPageIndex = pageIndex;
    this.saveProgressDelayed();
  }

  private calculateCurrentProgress(): Progress {
    const chapter = this.chapters[this.currentChapterIndex];
    const currentGlobalPage = chapter ? chapter.startPage + this.currentPageIndex : 0;

    return {
      chapterIndex: this.currentChapterIndex,
      pageIndex: this.currentPageIndex,
      globalPage: currentGlobalPage,
      timestamp: Date.now()
    };
  }

  async saveProgressImmediate(): Promise<void> {
    if (!this.prefManager || this.fileName === "") return;

    const progress = this.calculateCurrentProgress();
    try {
      await this.prefManager.put(`${PREF_KEY_PREFIX}progress_${this.fileName}`, JSON.stringify(progress));
      await this.prefManager.flush();
    } catch (e) {
      console.error('Save progress failed:', e);
    }
  }

  saveProgressDelayed(): void {
    if (this.isRestoring) return;
    if (this.saveTimer !== null) clearTimeout(this.saveTimer);
    this.saveTimer = setTimeout(() => this.saveProgressImmediate(), 1500);
  }

  async loadProgress(): Promise<Progress | null> {
    if (!this.prefManager) return null;
    try {
      const data = await this.prefManager.get(`${PREF_KEY_PREFIX}progress_${this.fileName}`, '');
      return data ? JSON.parse(data.toString()) as Progress : null;
    } catch (e) {
      return null;
    }
  }

  async restorePosition(): Promise<void> {
    if (this.totalPages === 0) return;

    const progress = await this.loadProgress();
    if (!progress) return;

    // 优先使用全局页码
    if (progress.globalPage !== undefined && progress.globalPage >= 0 && progress.globalPage < this.totalPages) {
      this.jumpToGlobalPage(progress.globalPage);
    } else if (progress.chapterIndex >= 0 && progress.chapterIndex < this.chapters.length) {
      this.jumpToChapter(progress.chapterIndex, progress.pageIndex || 0);
    }
  }

  async loadBookmarks() {
    if (!this.prefManager) return;
    try {
      const data = await this.prefManager.get(`${PREF_KEY_PREFIX}bookmarks_${this.fileName}`, '[]');
      const rawBookmarks = JSON.parse(data.toString()) as Bookmark[];
      this.bookmarks = rawBookmarks.map((bm: Bookmark): Bookmark => ({
        id: bm.id || Date.now().toString(),
        chapterIndex: bm.chapterIndex ?? 0,
        pageIndex: bm.pageIndex ?? 0,
        globalPage: bm.globalPage ?? 0,
        excerpt: bm.excerpt || '书签',
        timestamp: bm.timestamp || Date.now()
      })).filter((bm: Bookmark) => bm.globalPage < this.totalPages || this.totalPages === 0);
    } catch (e) {
      this.bookmarks = [];
    }
  }

  async saveBookmarks() {
    if (!this.prefManager) return;
    try {
      await this.prefManager.put(`${PREF_KEY_PREFIX}bookmarks_${this.fileName}`, JSON.stringify(this.bookmarks));
      await this.prefManager.flush();
    } catch (e) {}
  }

  addBookmark(): void {
    const chapter = this.chapters[this.currentChapterIndex];
    if (!chapter) return;

    const globalPage = chapter.startPage + this.currentPageIndex;
    const pageData = this.pages[globalPage];

    // 生成摘录
    let excerpt = '书签';
    if (pageData && pageData.lines.length > 0) {
      excerpt = pageData.lines.slice(0, 2).join('').substring(0, 40) + '...';
    }

    const bookmark: Bookmark = {
      id: Date.now().toString(),
      chapterIndex: this.currentChapterIndex,
      pageIndex: this.currentPageIndex,
      globalPage: globalPage,
      excerpt: excerpt,
      timestamp: Date.now()
    };

    // 检查重复
    const exists = this.bookmarks.some(b =>
    b.chapterIndex === bookmark.chapterIndex && b.pageIndex === bookmark.pageIndex
    );

    if (!exists) {
      this.bookmarks.unshift(bookmark);
      this.saveBookmarks();
    }

    this.controllerState = ControllerState.HIDDEN;
  }

  deleteBookmark(id: string): void {
    this.bookmarks = this.bookmarks.filter(b => b.id !== id);
    this.saveBookmarks();
  }

  jumpToBookmark(bm: Bookmark): void {
    if (bm.globalPage !== undefined && bm.globalPage >= 0 && bm.globalPage < this.totalPages) {
      this.jumpToGlobalPage(bm.globalPage);
    } else {
      this.jumpToChapter(bm.chapterIndex, bm.pageIndex || 0);
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.isLoading) {
        this.LoadingView()
      } else if (this.errorMsg) {
        this.ErrorView()
      } else {
        // 阅读内容层 - 传递 pages 给 ReaderContent
        ReaderContent({
          pages: this.pages,
          chapters: this.chapters,
          totalPages: this.totalPages,
          screenWidth: this.screenWidth,
          screenHeight: this.screenHeight,
          onPageChange: (chapterIdx: number, pageIdx: number, globalPage: number) => {
            this.onPageChanged(chapterIdx, pageIdx, globalPage);
          },
          onCenterTap: () => {
            this.controllerState = this.controllerState === ControllerState.HIDDEN
              ? ControllerState.VISIBLE
              : ControllerState.HIDDEN;
          }
        })

        // 控制层
        ReaderController({
          controllerState: this.controllerState,
          title: this.title,
          currentChapterIndex: this.currentChapterIndex,
          currentPageIndex: this.currentPageIndex,
          totalChapters: this.chapters.length,
          chapters: this.chapters,
          bookmarks: this.bookmarks,
          onBack: () => {
            this.saveProgressImmediate().then(() => router.back());
          },
          onAddBookmark: () => this.addBookmark(),
          onJumpToChapter: (idx: number, pageIdx: number) => this.jumpToChapter(idx, pageIdx),
          onJumpToBookmark: (bm: Bookmark) => this.jumpToBookmark(bm),
          onDeleteBookmark: (id: string) => this.deleteBookmark(id)
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG_COLOR)
  }

  @Builder LoadingView() {
    Column() {
      LoadingProgress().width(40).height(40)
      Text('正在加载书籍...').fontSize(14).margin({ top: 12 })
      Text('大文件可能需要一些时间').fontSize(12).fontColor('#999').margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder ErrorView() {
    Column() {
      Text(this.errorMsg).fontSize(14).fontColor('#FF4D4F')
      Button('返回').margin({ top: 20 }).onClick(() => router.back())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}