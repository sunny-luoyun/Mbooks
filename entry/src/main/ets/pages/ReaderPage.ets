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
  startPage: number;   // 分页后表示全局页起始
  endPage: number;     // 分页后表示全局页结束（不含）
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

/**
 * 页面偏移量接口
 */
export interface PageOffset {
  start: number;
  end: number;
}

/**
 * 轻量页面索引：只存偏移量，不存文本
 * 相比原来存 lines[]，内存减少约 95%
 */
export interface PageIndex {
  chapterIndex: number;
  pageIndexInChapter: number;
  startOffset: number;   // 在章节内容中的起始字符偏移
  endOffset: number;     // 结束偏移
}
/**
 * 兼容原有 PageData 接口（ReaderContent 展示用）
 */
export interface PageData {
  chapterIndex: number;
  pageIndexInChapter: number;
  globalPageIndex: number;
  lines: string[];
}

/**
 * 分页参数接口
 */
export interface LayoutParams {
  charsPerLine: number;
  linesPerPage: number;
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

const CHAPTER_REGEX =
  /(?:第[一二三四五六七八九十百千零\d]+章|章节\s*\d+|Chapter\s*\d+|^\d+\.)\s*[^\n]*/gmi;
const PREF_KEY_PREFIX = 'reader_';
const MAX_PAGES = 20000;
// 每批处理章节数，控制单次 JS 执行时间 < 16ms（一帧）
const CHUNK_SIZE = 5;

@Entry
@Component
struct ReaderPage {
  @State content: string = '';
  @State title: string = '';
  @State isLoading: boolean = true;
  @State loadingText: string = '正在读取文件...';
  @State loadingProgress: number = 0;   // 0~100，用于进度条
  @State errorMsg: string = '';
  @State fileName: string = '';
  @State chapters: Chapter[] = [];
  @State currentChapterIndex: number = 0;
  @State currentPageIndex: number = 0;
  @State totalPages: number = 0;
  @State bookmarks: Bookmark[] = [];
  @State controllerState: ControllerState = ControllerState.HIDDEN;
  @State screenWidth: number = 360;
  @State screenHeight: number = 780;

  // 新增：轻量索引 + 章节内容数组（替代原来的 pages[]）
  @State pageIndices: PageIndex[] = [];
  @State chapterContents: string[] = [];
  @State charsPerLine: number = 30;
  @State linesPerPage: number = 20;

  // 保留兼容（空数组即可，ReaderContent 已不依赖它展示）
  @State pages: PageData[] = [];

  @StorageProp('currentColorMode') currentColorMode: number = 0;

  private prefManager: preferences.Preferences | null = null;
  private saveTimer: number | null = null;
  private isRestoring: boolean = false;
  private isPaginationCancelled: boolean = false; // 取消旧分页任务标志

  aboutToAppear() {
    const params = router.getParams() as ReaderParams;
    if (params?.fileName) {
      this.fileName = params.fileName;
      this.title = params.title || '未命名';
      this.updateScreenSize().then(() => {
        this.initPreferences().then(() => {
          this.readBookContent(params.fileName);
        });
      });
    } else {
      this.errorMsg = '参数错误：未指定文件名';
      this.isLoading = false;
    }
  }

  aboutToDisappear() {
    this.isPaginationCancelled = true;
    this.saveProgressImmediate();
    if (this.saveTimer !== null) clearTimeout(this.saveTimer);
  }

  async updateScreenSize() {
    try {
      const win = await window.getLastWindow(getContext(this) as common.UIAbilityContext);
      const info = win.getWindowProperties();
      if (info?.windowRect) {
        this.screenWidth = px2vp(info.windowRect.width);
        this.screenHeight = px2vp(info.windowRect.height);
      }
    } catch (e) {
      this.screenWidth = 360;
      this.screenHeight = 780;
    }
  }

  async initPreferences() {
    try {
      this.prefManager = await preferences.getPreferences(getContext(this), 'reader_prefs');
    } catch (e) {
      console.error('Init prefs failed:', e);
    }
  }

  readBookContent(fileName: string) {
    let file: fs.File | null = null;
    try {
      const ctx = getContext(this);
      let filePath = `${ctx.filesDir}/threads/${fileName}`;

      if (!fs.accessSync(filePath)) {
        const old = `${ctx.filesDir}/${fileName}`;
        if (fs.accessSync(old)) filePath = old;
        else throw new Error(`文件不存在: ${filePath}`);
      }

      const stat = fs.statSync(filePath);
      const fileSize = stat.size;
      file = fs.openSync(filePath, fs.OpenMode.READ_ONLY);

      this.loadingText = '正在读取文件...';
      this.loadingProgress = 10;

      const MAX_CHUNK = 4 * 1024 * 1024;
      let content = '';
      const decoder = util.TextDecoder.create('utf-8');

      if (fileSize <= MAX_CHUNK) {
        const buf = new ArrayBuffer(fileSize);
        fs.readSync(file.fd, buf);
        content = decoder.decodeWithStream(new Uint8Array(buf));
      } else {
        let offset = 0;
        while (offset < fileSize) {
          const chunk = Math.min(MAX_CHUNK, fileSize - offset);
          const buf = new ArrayBuffer(chunk);
          fs.readSync(file.fd, buf, { offset, length: chunk });
          content += decoder.decodeWithStream(new Uint8Array(buf));
          offset += chunk;
          this.loadingProgress = 10 + Math.floor((offset / fileSize) * 30);
        }
      }

      this.content = content;
      this.loadingProgress = 40;
      this.loadingText = '正在解析章节...';

      // 同步解析章节（轻量，不阻塞）
      this.parseChapters();
      this.loadingProgress = 50;

      // 异步分块分页（核心优化）
      this.startAsyncPagination().then(() => {
        if (!this.isPaginationCancelled) {
          this.isLoading = false;
          setTimeout(() => this.restorePosition(), 200);
        }
      });

    } catch (e) {
      this.errorMsg = '读取失败: ' + (e as Error).message;
      this.isLoading = false;
    } finally {
      if (file) fs.closeSync(file);
    }
  }
  /**
   * 计算分页参数（屏幕尺寸相关）
   */
  private computeLayoutParams(): LayoutParams {
    const contentWidth = Math.max(100, this.screenWidth - Theme.PAGE_PADDING * 2);
    const charPx = Theme.FONT_BODY * 0.5;
    const charsPerLine = Math.max(20, Math.floor(contentWidth / charPx));

    const availH = Math.max(200,
      this.screenHeight - LayoutConfig.TOP_MARGIN - LayoutConfig.BOTTOM_MARGIN - LayoutConfig.SAFE_BOTTOM_MARGIN
    );
    const linesPerPage = Math.max(5, Math.floor(availH / Theme.LINE_HEIGHT));

    return { charsPerLine, linesPerPage };
  }

  /**
   * 异步分块分页
   * 每次处理 CHUNK_SIZE 个章节后 yield，让渲染线程有机会响应
   */
  private async startAsyncPagination(): Promise<void> {
    this.isPaginationCancelled = false;
    const layoutParams = this.computeLayoutParams();
    this.charsPerLine = layoutParams.charsPerLine;
    this.linesPerPage = layoutParams.linesPerPage;
    console.info(`分页参数: 宽=${this.screenWidth} 每行字符=${this.charsPerLine} 每页行数=${this.linesPerPage}`);

    const newIndices: PageIndex[] = [];
    const newContents: string[] = [];
    const chapters = this.chapters;
    let globalPage = 0;

    for (let ci = 0; ci < chapters.length; ci++) {
      if (this.isPaginationCancelled) return;

      // 每 CHUNK_SIZE 章 yield 一次，让 UI 线程喘气
      if (ci > 0 && ci % CHUNK_SIZE === 0) {
        // 先推送已完成的部分，让用户尽快看到内容
        this.flushPartialResult(newIndices, newContents, chapters, globalPage, ci);
        await this.yieldToUI();
        if (this.isPaginationCancelled) return;
      }

      const ch = chapters[ci];
      const chapterText = this.content.substring(ch.startPage, ch.endPage);
      newContents.push(chapterText);

      // 对当前章节文本做行分割（只计算偏移，不存文本）
      const offsets = this.computePageOffsets(chapterText, this.charsPerLine, this.linesPerPage);
      const chapterStartPage = globalPage;

      ch.pageCount = 0;
      for (const off of offsets) {
        if (globalPage >= MAX_PAGES) break;
        newIndices.push({
          chapterIndex: ci,
          pageIndexInChapter: ch.pageCount,
          startOffset: off.start,
          endOffset: off.end
        });
        ch.pageCount++;
        globalPage++;
      }

      ch.startPage = chapterStartPage;
      ch.endPage = globalPage;

      // 更新进度条
      this.loadingProgress = 50 + Math.floor((ci / chapters.length) * 50);
      this.loadingText = `正在分页... (${ci + 1}/${chapters.length} 章)`;

      if (globalPage >= MAX_PAGES) {
        console.warn(`达到最大页数 ${MAX_PAGES}`);
        break;
      }
    }

    // 最终一次性更新状态
    this.pageIndices = newIndices;
    this.chapterContents = newContents;
    this.totalPages = globalPage;
    this.loadingProgress = 100;
    this.loadingText = '加载完成';

    emitter.emit(READER_EVENTS.UPDATE_PAGINATION, { data: {} });

    // 加载书签（分页完成后才能校验 globalPage 范围）
    await this.loadBookmarks();

    console.info(`分页完成：${globalPage} 页，${chapters.length} 章`);
  }

  /**
   * 中途推送部分结果（让用户提前看到内容）
   */
  private flushPartialResult(
    indices: PageIndex[],
    contents: string[],
    chapters: Chapter[],
    globalPage: number,
    upToChapter: number
  ) {
    // 只有超过一定页数才值得推送（避免频繁触发状态更新）
    if (indices.length > 50) {
      this.pageIndices = [...indices];
      this.chapterContents = [...contents];
      this.totalPages = globalPage;
      //if (this.isLoading && globalPage >= 50) {
        // 有足够内容后提前结束 loading，用户可以开始阅读
        //this.isLoading = false;
        //setTimeout(() => this.restorePosition(), 100);
      //}
    }
  }

  /**
   * 让出 UI 线程（通过 Promise + setTimeout 0 模拟 yield）
   */
  private yieldToUI(): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => resolve(), 0);
    });
  }

  /**
   * 计算章节内各页的字符偏移范围
   * 返回 {start, end} 对数组，不持有文本
   */
  private computePageOffsets(
    text: string,
    charsPerLine: number,
    linesPerPage: number
  ): Array<PageOffset> {
    const result: Array<PageOffset> = [];

    // 先按段落切分，再计算每行占用的字符数
    const lines = this.splitIntoLines(text, charsPerLine);

    // 将 lines 中每行映射回原文偏移（使用累计偏移）
    const lineOffsets = this.buildLineOffsets(text, lines);

    let pageStart = 0;
    let lineIdx = 0;

    while (lineIdx < lines.length) {
      const pageLineEnd = Math.min(lineIdx + linesPerPage, lines.length);
      const startOff = lineOffsets[lineIdx] ?? 0;
      const endOff = lineIdx + linesPerPage < lines.length
        ? lineOffsets[pageLineEnd] ?? text.length
        : text.length;
      result.push({ start: startOff, end: endOff } as PageOffset);
      lineIdx = pageLineEnd;
    }

    return result;
  }

  /**
   * 将文本拆分为屏幕行（返回行字符串数组，用于计算行数）
   */
  private splitIntoLines(text: string, maxWidth: number): string[] {
    const lines: string[] = [];
    const paras = text.split('\n');

    for (const para of paras) {
      if (para.length === 0) {
        lines.push('');
        continue;
      }

      let cur = '';
      let curW = 0;

      for (let i = 0; i < para.length; i++) {
        const ch = para[i];
        const w = this.getCharWidth(ch);

        if (curW + w > maxWidth && cur.length > 0) {
          if (this.isTrailingPunct(ch)) {
            lines.push(cur + ch);
            cur = '';
            curW = 0;
          } else {
            lines.push(cur);
            cur = ch;
            curW = w;
          }
        } else {
          cur += ch;
          curW += w;
        }
      }

      if (cur.length > 0) lines.push(cur);
    }

    return lines;
  }

  /**
   * 建立行 -> 原文偏移的映射表
   * 通过逐行扫描还原每行在原文中的起始位置
   */
  private buildLineOffsets(text: string, lines: string[]): number[] {
    const offsets: number[] = new Array(lines.length + 1).fill(0);
    let pos = 0;
    let lineIdx = 0;

    // 按段落重建偏移
    const paras = text.split('\n');
    for (let pi = 0; pi < paras.length; pi++) {
      const para = paras[pi];

      if (para.length === 0) {
        if (lineIdx < lines.length) {
          offsets[lineIdx] = pos;
          lineIdx++;
        }
        pos++; // '\n'
        continue;
      }

      // 重新模拟断行，记录每行起始偏移
      let curW = 0;
      let lineStart = pos;

      if (lineIdx < lines.length) {
        offsets[lineIdx] = pos;
      }

      for (let i = 0; i < para.length; i++) {
        const ch = para[i];
        const w = this.getCharWidth(ch);

        if (curW + w > this.charsPerLine && curW > 0) {
          lineIdx++;
          if (!this.isTrailingPunct(ch)) {
            if (lineIdx < lines.length) {
              offsets[lineIdx] = pos; // 当前字符位置作为新行起始
            }
            curW = w;
          } else {
            // ✅ 标点归入上一行后，新行起始应该是下一个字符
            if (lineIdx < lines.length) {
              offsets[lineIdx] = pos + 1; // pos+1 才是新行第一个字符
            }
            curW = 0;
          }
        } else {
          curW += w;
        }
        pos++;
      }

      lineIdx++;
      if (lineIdx < lines.length) {
        offsets[lineIdx] = pos;
      }
      pos++; // '\n'
    }

    offsets[lines.length] = text.length;
    return offsets;
  }

  getCharWidth(ch: string): number {
    const c = ch.charCodeAt(0);
    if (c >= 0x4E00 && c <= 0x9FFF) return 2;
    if (c >= 0xFF01 && c <= 0xFF5E) return 2;
    if (c >= 0x3000 && c <= 0x303F) return 2;
    if (c >= 0x3040 && c <= 0x30FF) return 2;
    return 1;
  }

  isTrailingPunct(ch: string): boolean {
    return '，。！？；：、.,;:!?）】》'.includes(ch);
  }

  parseChapters(): void {
    this.chapters = [];
    const matches = Array.from(this.content.matchAll(CHAPTER_REGEX));

    if (matches.length === 0) {
      this.chapters = [{
        title: '正文',
        startPage: 0,
        endPage: this.content.length,
        level: 0,
        pageCount: 0
      }];
    } else {
      this.chapters = matches.map((m, i): Chapter => ({
        title: m[0].trim().substring(0, 50),
        startPage: m.index ?? 0,
        endPage: i + 1 < matches.length ? (matches[i + 1].index ?? this.content.length) : this.content.length,
        level: this.detectLevel(m[0]),
        pageCount: 0
      }));
    }
  }

  detectLevel(title: string): number {
    if (title.match(/^第[一二三四五六七八九十百千零]+章/)) return 0;
    if (title.match(/^[第章节]\d+/)) return 1;
    return 2;
  }

  // ——— 跳转 ———

  jumpToChapter(chapterIndex: number, pageIndex: number = 0): void {
    if (chapterIndex < 0 || chapterIndex >= this.chapters.length) return;
    const ch = this.chapters[chapterIndex];
    const safe = Math.max(0, Math.min(pageIndex, ch.pageCount - 1));
    this.jumpToGlobalPage(ch.startPage + safe);
  }

  jumpToGlobalPage(globalPage: number): void {
    if (this.totalPages === 0) return;
    const safe = Math.max(0, Math.min(globalPage, this.totalPages - 1));
    this.isRestoring = true;

    const idx = this.pageIndices[safe];
    if (idx) {
      this.currentChapterIndex = idx.chapterIndex;
      this.currentPageIndex = idx.pageIndexInChapter;
    }

    emitter.emit(READER_EVENTS.JUMP_TO_PAGE, {
      data: { globalPage: safe, chapterIndex: idx?.chapterIndex ?? 0, pageIndex: idx?.pageIndexInChapter ?? 0 }
    });

    this.saveProgressDelayed();
    setTimeout(() => { this.isRestoring = false; }, 500);
    this.controllerState = ControllerState.HIDDEN;
  }

  onPageChanged(chapterIndex: number, pageIndex: number, globalPage: number) {
    if (this.isRestoring) return;
    this.currentChapterIndex = chapterIndex;
    this.currentPageIndex = pageIndex;
    this.saveProgressDelayed();
  }

  // ——— 进度存储 ———

  private calculateCurrentProgress(): Progress {
    const ch = this.chapters[this.currentChapterIndex];
    return {
      chapterIndex: this.currentChapterIndex,
      pageIndex: this.currentPageIndex,
      globalPage: ch ? ch.startPage + this.currentPageIndex : 0,
      timestamp: Date.now()
    };
  }

  async saveProgressImmediate(): Promise<void> {
    if (!this.prefManager || !this.fileName) return;
    try {
      await this.prefManager.put(
        `${PREF_KEY_PREFIX}progress_${this.fileName}`,
        JSON.stringify(this.calculateCurrentProgress())
      );
      await this.prefManager.flush();
    } catch (e) {}
  }

  saveProgressDelayed(): void {
    if (this.isRestoring) return;
    if (this.saveTimer !== null) clearTimeout(this.saveTimer);
    this.saveTimer = setTimeout(() => this.saveProgressImmediate(), 1500);
  }

  async loadProgress(): Promise<Progress | null> {
    if (!this.prefManager) return null;
    try {
      const raw = await this.prefManager.get(`${PREF_KEY_PREFIX}progress_${this.fileName}`, '');
      return raw ? JSON.parse(raw.toString()) as Progress : null;
    } catch {
      return null;
    }
  }

  async restorePosition(): Promise<void> {
    if (this.totalPages === 0) return;
    const progress = await this.loadProgress();
    if (!progress) return;

    if (progress.globalPage >= 0 && progress.globalPage < this.totalPages) {
      this.jumpToGlobalPage(progress.globalPage);
    } else if (progress.chapterIndex >= 0 && progress.chapterIndex < this.chapters.length) {
      this.jumpToChapter(progress.chapterIndex, progress.pageIndex ?? 0);
    }
  }

  // ——— 书签 ———

  async loadBookmarks() {
    if (!this.prefManager) return;
    try {
      const raw = await this.prefManager.get(`${PREF_KEY_PREFIX}bookmarks_${this.fileName}`, '[]');
      const list = JSON.parse(raw.toString()) as Bookmark[];
      this.bookmarks = list
        .map((bm): Bookmark => ({
          id: bm.id || Date.now().toString(),
          chapterIndex: bm.chapterIndex ?? 0,
          pageIndex: bm.pageIndex ?? 0,
          globalPage: bm.globalPage ?? 0,
          excerpt: bm.excerpt || '书签',
          timestamp: bm.timestamp || Date.now()
        }))
        .filter(bm => this.totalPages === 0 || bm.globalPage < this.totalPages);
    } catch {
      this.bookmarks = [];
    }
  }

  async saveBookmarks() {
    if (!this.prefManager) return;
    try {
      await this.prefManager.put(
        `${PREF_KEY_PREFIX}bookmarks_${this.fileName}`,
        JSON.stringify(this.bookmarks)
      );
      await this.prefManager.flush();
    } catch {}
  }

  addBookmark(): void {
    const ch = this.chapters[this.currentChapterIndex];
    if (!ch) return;

    const globalPage = ch.startPage + this.currentPageIndex;
    const idx = this.pageIndices[globalPage];
    let excerpt = '书签';

    if (idx) {
      const text = this.chapterContents[idx.chapterIndex] ?? '';
      excerpt = text.substring(idx.startOffset, Math.min(idx.startOffset + 60, idx.endOffset))
        .replace(/\n/g, '') + '...';
    }

    const bm: Bookmark = {
      id: Date.now().toString(),
      chapterIndex: this.currentChapterIndex,
      pageIndex: this.currentPageIndex,
      globalPage,
      excerpt,
      timestamp: Date.now()
    };

    const exists = this.bookmarks.some(
      b => b.chapterIndex === bm.chapterIndex && b.pageIndex === bm.pageIndex
    );
    if (!exists) {
      this.bookmarks.unshift(bm);
      this.saveBookmarks();
    }
    this.controllerState = ControllerState.HIDDEN;
  }

  deleteBookmark(id: string): void {
    this.bookmarks = this.bookmarks.filter(b => b.id !== id);
    this.saveBookmarks();
  }

  jumpToBookmark(bm: Bookmark): void {
    if (bm.globalPage >= 0 && bm.globalPage < this.totalPages) {
      this.jumpToGlobalPage(bm.globalPage);
    } else {
      this.jumpToChapter(bm.chapterIndex, bm.pageIndex ?? 0);
    }
  }

  // ——— UI ———

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.isLoading) {
        this.LoadingView()
      } else if (this.errorMsg) {
        this.ErrorView()
      } else {
        ReaderContent({
          pages: this.pages,            // 兼容空数组
          pageIndices: this.pageIndices,
          chapterContents: this.chapterContents,
          charsPerLine: this.charsPerLine,
          chapters: this.chapters,
          totalPages: this.totalPages,
          screenWidth: this.screenWidth,
          screenHeight: this.screenHeight,
          onPageChange: (ci: number, pi: number, gp: number): void => this.onPageChanged(ci, pi, gp),
          onCenterTap: () => {
            this.controllerState = this.controllerState === ControllerState.HIDDEN
              ? ControllerState.VISIBLE
              : ControllerState.HIDDEN;
          }
        })

        ReaderController({
          controllerState: this.controllerState,
          title: this.title,
          currentChapterIndex: this.currentChapterIndex,
          currentPageIndex: this.currentPageIndex,
          totalChapters: this.chapters.length,
          chapters: this.chapters,
          bookmarks: this.bookmarks,
          onBack: () => this.saveProgressImmediate().then(() => router.back()),
          onAddBookmark: () => this.addBookmark(),
          onJumpToChapter: (i: number, pi: number) => this.jumpToChapter(i, pi),
          onJumpToBookmark: (bm: Bookmark) => this.jumpToBookmark(bm),
          onDeleteBookmark: (id: string) => this.deleteBookmark(id)
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.BG_COLOR)
  }
  @Builder LoadingView(): void {
    Column() {
      LoadingProgress()
        .width(48)
        .height(48)
        .color(Theme.TEXT_MAIN)

      Text(this.loadingText)
        .fontSize(14)
        .fontColor(Theme.TEXT_MAIN)
        .margin({ top: 16 })

      // 进度条
      Column() {
        Row()
          .width(`${this.loadingProgress}%`)
          .height(4)
          .backgroundColor(Theme.TEXT_ACCENT)
          .borderRadius(2)
          .animation({ duration: 300, curve: Curve.EaseOut })
      }
      .width('60%')
      .height(4)
      .backgroundColor(Theme.isDarkMode() ? '#333' : '#e0e0e0')
      .borderRadius(2)
      .margin({ top: 20 })

      Text(`${this.loadingProgress}%`)
        .fontSize(12)
        .fontColor(Theme.TEXT_SECONDARY)
        .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Theme.BG_COLOR)
  }
  @Builder ErrorView(): void {
    Column() {
      Text(this.errorMsg)
        .fontSize(14)
        .fontColor('#FF4D4F')
        .textAlign(TextAlign.Center)
        .padding(20)
      Button('返回')
        .margin({ top: 20 })
        .onClick(() => router.back())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Theme.BG_COLOR)
  }
}