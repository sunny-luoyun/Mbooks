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

  // 监听系统颜色模式变化
  @StorageProp('currentColorMode') currentColorMode: number = 0;

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

    // 计算可用宽度和每行字符数
    const contentWidth = Math.max(100, this.screenWidth - Theme.PAGE_PADDING * 2);

    // 修复：调整字符宽度系数，中文18sp字体实际宽度约为18px
    const charWidth = Theme.FONT_BODY * 0.5;

    // 考虑不同设备的屏幕密度，设置一个最小字符数保证可读性
    const minCharsPerLine = 20;
    let charsPerLine = Math.floor(contentWidth / charWidth);
    if (charsPerLine < minCharsPerLine) {
      charsPerLine = minCharsPerLine;
    }

    // 计算可用高度和每页行数
    const availableHeight = Math.max(200, this.screenHeight - LayoutConfig.TOP_MARGIN - LayoutConfig.BOTTOM_MARGIN);
    // 修复：给每页底部留出安全边距，避免最后一行被截断
    const safeAvailableHeight = availableHeight - LayoutConfig.SAFE_BOTTOM_MARGIN;
    const linesPerPage = Math.floor(safeAvailableHeight / Theme.LINE_HEIGHT);

    console.info(`分页参数: 屏幕宽=${this.screenWidth}, 内容宽=${contentWidth}, 每行字符=${charsPerLine}, 每页行数=${linesPerPage}`);

    // 限制最大页数，防止内存爆炸（约 5000 页，约 2-3MB 文本）
    const MAX_PAGES = 5000;

    for (let chapterIdx = 0; chapterIdx < this.chapters.length; chapterIdx++) {
      const chapter = this.chapters[chapterIdx];
      const startIdx = chapter.startPage;
      const endIdx = chapter.endPage;
      const chapterContent = this.content.substring(startIdx, endIdx);

      // 文本断行
      const lines = this.breakTextIntoLines(chapterContent, charsPerLine);

      // 记录章节起始页码（全局页码索引）
      const chapterStartPage = globalPageIndex;

      let pageLines: string[] = [];
      let lineIndex = 0;

      while (lineIndex < lines.length && globalPageIndex < MAX_PAGES) {
        pageLines.push(lines[lineIndex]);
        lineIndex++;

        // 当达到每页行数限制时，创建新页面
        if (pageLines.length >= linesPerPage) {
          newPages.push({
            chapterIndex: chapterIdx,
            pageIndexInChapter: chapter.pageCount,
            globalPageIndex: globalPageIndex,
            lines: pageLines.slice()
          });

          pageLines = [];
          chapter.pageCount++;
          globalPageIndex++;
        }
      }

      // 处理剩余行（最后一页可能不满）
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

      // 更新章节的页码信息
      chapter.startPage = chapterStartPage;
      chapter.endPage = globalPageIndex;

      // 提前退出检查
      if (globalPageIndex >= MAX_PAGES) {
        console.warn(`达到最大页数限制 ${MAX_PAGES}，后续内容将被截断`);
        break;
      }
    }

    // 更新状态（触发 ReaderContent 重新渲染）
    this.pages = newPages;
    this.totalPages = globalPageIndex;

    console.info(`分页完成：共 ${this.totalPages} 页，${this.chapters.length} 章，内存页数 ${newPages.length}`);
  }

  // 修复后的文本断行逻辑：避免字符被截断，处理英文单词边界
  breakTextIntoLines(text: string, maxCharsPerLine: number): string[] {
    const lines: string[] = [];
    const paragraphs = text.split('\n');

    for (const paragraph of paragraphs) {
      if (paragraph.length === 0) {
        lines.push('');
        continue;
      }

      let currentLine = '';
      let currentWidth = 0;
      let i = 0;

      while (i < paragraph.length) {
        const char = paragraph[i];
        const charWidth = this.getCharWidth(char);

        // 检查是否超出宽度限制
        if (currentWidth + charWidth > maxCharsPerLine && currentLine.length > 0) {
          // 处理行尾：避免标点符号在行首
          if (this.isPunctuation(char) && !this.isStartPunctuation(char)) {
            currentLine += char;
            lines.push(currentLine);
            currentLine = '';
            currentWidth = 0;
            i++;
          } else {
            const lastChar = currentLine[currentLine.length - 1];
            if (this.isPunctuation(lastChar) && !this.isStartPunctuation(lastChar)) {
              lines.push(currentLine);
              currentLine = char;
              currentWidth = charWidth;
              i++;
            } else {
              const breakPoint = this.findWordBreak(currentLine);
              if (breakPoint > 0 && breakPoint < currentLine.length - 3) {
                const remaining = currentLine.substring(breakPoint);
                currentLine = currentLine.substring(0, breakPoint);
                lines.push(currentLine);
                currentLine = remaining + char;
                currentWidth = this.calculateWidth(currentLine);
              } else {
                lines.push(currentLine);
                currentLine = char;
                currentWidth = charWidth;
              }
              i++;
            }
          }
        } else {
          currentLine += char;
          currentWidth += charWidth;
          i++;
        }
      }

      if (currentLine.length > 0) {
        lines.push(currentLine);
      }
    }

    return lines;
  }

  private findWordBreak(line: string): number {
    for (let i = line.length - 1; i > 0; i--) {
      if (line[i] === ' ' || line[i] === '\t') {
        return i;
      }
    }
    return -1;
  }

  private calculateWidth(str: string): number {
    let width = 0;
    for (const char of str) {
      width += this.getCharWidth(char);
    }
    return width;
  }

  getCharWidth(char: string): number {
    const code = char.charCodeAt(0);
    if (code >= 0x4E00 && code <= 0x9FFF) return 2;
    if (code >= 0xFF01 && code <= 0xFF5E) return 2;
    if (code >= 0x3000 && code <= 0x303F) return 2;
    if (code >= 0x3040 && code <= 0x309F) return 2;
    if (code >= 0x30A0 && code <= 0x30FF) return 2;
    return 1;
  }

  isPunctuation(char: string): boolean {
    return '，。！？；：、.,;:!?"\'()[]'.includes(char);
  }

  isStartPunctuation(char: string): boolean {
    return '，。！？；：、.,;:!?）】》'.includes(char);
  }

  parseChapters(): void {
    this.chapters = [];
    const matches = Array.from(this.content.matchAll(CHAPTER_REGEX));

    if (matches.length === 0) {
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
        // 阅读内容层
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
    .backgroundColor(Theme.BG_COLOR) // 使用动态颜色
  }

  @Builder LoadingView() {
    Column() {
      LoadingProgress()
        .width(40)
        .height(40)
        .color(Theme.TEXT_MAIN) // 加载动画颜色适配
      Text('正在加载书籍...')
        .fontSize(14)
        .fontColor(Theme.TEXT_MAIN) // 使用动态颜色
        .margin({ top: 12 })
      Text('大文件可能需要一些时间')
        .fontSize(12)
        .fontColor(Theme.TEXT_SECONDARY) // 使用动态颜色
        .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Theme.BG_COLOR) // 使用动态颜色
  }

  @Builder ErrorView() {
    Column() {
      Text(this.errorMsg)
        .fontSize(14)
        .fontColor('#FF4D4F')
      Button('返回')
        .margin({ top: 20 })
        .onClick(() => router.back())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Theme.BG_COLOR) // 使用动态颜色
  }
}