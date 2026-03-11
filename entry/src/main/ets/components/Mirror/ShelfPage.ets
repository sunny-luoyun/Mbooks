// entry/src/main/ets/components/ShelfPage.ets
import router from '@ohos.router';
import fs from '@ohos.file.fs';
import promptAction from '@ohos.promptAction';
import common from '@ohos.app.ability.common';
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';
import { CrawlerService } from '../../services/CrawlerService';
import { DownloadResult } from '../../models/SettingsModels';
import { ThreadMeta } from '../../services/DownloadService';
import { DownloadService } from '../../services/DownloadService';

interface PostTimeInfo {
  time: string;
}

interface LocalBook {
  threadId: string;
  title: string;
  author: string;
  fileName: string;
  updateTime: number;
  chapterCount: number;
}
interface ReaderParams {
  fileName: string;
  title: string;
  threadId: string;
}

// ✅ 新增：作者分组类型
interface AuthorGroup {
  author: string;
  books: LocalBook[];
}

interface ShelfColors {
  pageBg: string;
  cardBg: string;
  headerBg: string;
  batchBarBg: string;
  primaryText: string;
  secondaryText: string;
  tertiaryText: string;
  accentText: string;
  primaryBtnBg: string;
  secondaryBtnBg: string;
  dangerBtnBg: string;
  primaryBtnText: string;
  secondaryBtnText: string;
  dangerBtnText: string;
  shadow: string;
  chapterTagBg: string;
  checkboxColor: string;
  // ✅ 新增：分组标题背景色
  groupHeaderBg: string;
}

function getShelfColors(mode: number): ShelfColors {
  const isDark = mode === 0;
  return {
    pageBg:           isDark ? '#0D0D0D'    : '#F1F3F5',
    cardBg:           isDark ? '#1E1E1E'    : '#FFFFFF',
    headerBg:         isDark ? '#141414'    : '#FFFFFF',
    batchBarBg:       isDark ? '#141414'    : '#F1F3F5',
    primaryText:      isDark ? '#E6E6E6'    : '#000000',
    secondaryText:    isDark ? '#999999'    : '#666666',
    tertiaryText:     isDark ? '#666666'    : '#999999',
    accentText:       '#007DFF',
    primaryBtnBg:     '#007DFF',
    secondaryBtnBg:   isDark ? '#2A2A2A'    : '#E6F2FF',
    dangerBtnBg:      isDark ? '#2A1F1F'    : '#FFF5F5',
    primaryBtnText:   '#FFFFFF',
    secondaryBtnText: '#007DFF',
    dangerBtnText:    '#FF4D4F',
    shadow:           isDark ? '#000000'    : '#10000000',
    chapterTagBg:     isDark ? '#2A2A2A'    : '#F5F5F5',
    checkboxColor:    '#007DFF',
    // ✅ 新增
    groupHeaderBg:    isDark ? '#1A1A2E'    : '#E8F0FE',
  };
}

// ✅ 新增：排序模式枚举
const enum SortMode {
  ByTime   = 0,
  ByAuthor = 1,
  ByTitle  = 2,
}

@Component
export struct ShelfPage {
  @State localBooks: Array<LocalBook> = [];
  @State isRefreshing: boolean = false;
  @State isEditMode: boolean = false;
  @State selectedBooks: Set<string> = new Set();
  @State colorMode: number = 0;
  // ✅ 新增：排序模式状态
  @State sortMode: number = SortMode.ByTime;

  private crawler: CrawlerService | null = null;
  private readonly THREADS_DIR = 'threads';
  private configChangeCallback: () => void = () => {};
  private configCallbackId: number = -1;

  aboutToAppear(): void {
    this.crawler = new CrawlerService(getContext(this) as common.UIAbilityContext);
    const ctx = getContext(this) as common.UIAbilityContext;
    this.colorMode = ctx.config.colorMode ?? 0;
    this.configChangeCallback = () => {
      this.colorMode = ctx.config.colorMode ?? 0;
    };
    this.configCallbackId = ctx.getApplicationContext().on('environment', {
      onConfigurationUpdated: this.configChangeCallback,
      onMemoryLevel: (level: number) => {}
    });
    this.scanLocalFiles();
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

  // ====================================================
  // ✅ 新增：排序/分组计算属性
  // ====================================================

  /** 当前排序模式的标签文字 */
  private getSortLabel(): string {
    if (this.sortMode === SortMode.ByTime)   return '⏱ 时间';
    if (this.sortMode === SortMode.ByAuthor) return '👤 作者';
    return '🔤 书名';
  }

  /** 切换到下一个排序模式 */
  private cycleSortMode(): void {
    this.sortMode = (this.sortMode + 1) % 3;
  }

  /** 非作者模式下，排序后的书单 */
  private getSortedBooks(): LocalBook[] {
    const arr = this.localBooks.slice();
    if (this.sortMode === SortMode.ByTitle) {
      arr.sort((a, b) => a.title.localeCompare(b.title, 'zh'));
    } else {
      arr.sort((a, b) => b.updateTime - a.updateTime);
    }
    return arr;
  }

  /** 按作者分组（作者内部按更新时间倒序） */
  private getAuthorGroups(): AuthorGroup[] {
    const map = new Map<string, LocalBook[]>();
    for (const book of this.localBooks) {
      const key = book.author || '未知作者';
      if (!map.has(key)) map.set(key, []);
      map.get(key)!.push(book);
    }
    const groups: AuthorGroup[] = [];
    map.forEach((books, author) => {
      books.sort((a, b) => b.updateTime - a.updateTime);
      groups.push({ author, books });
    });
    // 作者按名称排序
    groups.sort((a, b) => a.author.localeCompare(b.author, 'zh'));
    return groups;
  }

  // ====================================================
  // 以下方法与原来完全一致，无改动
  // ====================================================

  private ensureThreadsDir(ctx: common.UIAbilityContext): string {
    const threadsPath = `${ctx.filesDir}/${this.THREADS_DIR}`;
    if (!fs.accessSync(threadsPath)) {
      try { fs.mkdirSync(threadsPath); } catch (e) { console.error('Failed to create threads dir:', e); }
    }
    return threadsPath;
  }

  scanLocalFiles(): void {
    this.isRefreshing = true;
    try {
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const threadsPath = this.ensureThreadsDir(ctx);
      let files: string[] = [];
      try {
        files = fs.listFileSync(threadsPath);
      } catch (e) { console.error('Failed to list threads dir:', e); }

      const books: LocalBook[] = [];
      for (let i = 0; i < files.length; i++) {
        const file: string = files[i];
        if (!file.endsWith('.txt')) continue;
        let tid: string = '';
        let title: string = '';
        const fullMatch = file.match(/^(\d+)_(.+)\.txt$/);
        if (fullMatch) {
          tid = fullMatch[1]; title = fullMatch[2];
        } else {
          const simpleMatch = file.match(/^(\d+)\.txt$/);
          if (simpleMatch) { tid = simpleMatch[1]; title = `帖子${tid}`; }
          else continue;
        }
        let author = "未知作者";
        let updateTime = 0;
        let chapterCount = 0;
        const metaPath = `${threadsPath}/${tid}_meta.json`;
        if (fs.accessSync(metaPath)) {
          try {
            const metaContent = fs.readTextSync(metaPath);
            const meta: ThreadMeta = JSON.parse(metaContent) as ThreadMeta;
            author = meta.author || "未知作者";
            title = meta.title || title;
            updateTime = new Date(meta.lastUpdate).getTime() || 0;
            chapterCount = Object.keys(meta.posts || {} as Record<string, PostTimeInfo>).length;
          } catch (e) { console.error('Parse meta failed for', tid, e); }
        }
        if (chapterCount === 0) chapterCount = this.countChapters(`${threadsPath}/${file}`);
        books.push({ threadId: tid, title, author, fileName: file, updateTime, chapterCount } as LocalBook);
      }
      books.sort((a, b) => b.updateTime - a.updateTime);
      this.localBooks = books;
    } catch (e) {
      console.error('scan files failed', e);
      promptAction.showToast({ message: '扫描文件失败' } as promptAction.ShowToastOptions);
    } finally {
      this.isRefreshing = false;
    }
  }

  private countChapters(filePath: string): number {
    try {
      if (!fs.accessSync(filePath)) return 0;
      const content = fs.readTextSync(filePath);
      const matches = content.match(/【章节 \d+】/g);
      return matches ? matches.length : 0;
    } catch (e) { return 0; }
  }

  private getFullPath(fileName: string): string {
    const ctx = getContext(this) as common.UIAbilityContext;
    return `${ctx.filesDir}/${this.THREADS_DIR}/${fileName}`;
  }

  private getMetaPath(threadId: string): string {
    const ctx = getContext(this) as common.UIAbilityContext;
    return `${ctx.filesDir}/${this.THREADS_DIR}/${threadId}_meta.json`;
  }

  async updateBook(book: LocalBook): Promise<void> {
    this.isRefreshing = true;
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const ds = DownloadService.getInstance(ctx);
      const success = await ds.downloadThread(book.threadId, book.title, book.author, (progress: number) => {});
      if (success) { promptAction.showToast({ message: '更新成功' }); this.scanLocalFiles(); }
      else promptAction.showToast({ message: '更新失败' });
    } catch (e) {
      console.error('Update failed', e);
      promptAction.showToast({ message: '更新失败' });
    } finally { this.isRefreshing = false; }
  }

  private async deleteBook(book: LocalBook): Promise<void> {
    try {
      const txtPath = this.getFullPath(book.fileName);
      const metaPath = this.getMetaPath(book.threadId);
      if (fs.accessSync(txtPath)) fs.unlinkSync(txtPath);
      if (fs.accessSync(metaPath)) fs.unlinkSync(metaPath);
      this.localBooks = this.localBooks.filter(b => b.threadId !== book.threadId);
      promptAction.showToast({ message: `《${book.title}》已删除` });
    } catch (e) {
      console.error('Delete failed', e);
      promptAction.showToast({ message: '删除失败' });
    }
  }
  private showDeleteConfirm(book: LocalBook): void {
    AlertDialog.show({
      title: '确认删除',
      message: `确定要删除《${book.title}》吗？\n此操作不可恢复。`,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '删除', 
        action: () => this.deleteBook(book),
        fontColor: '#FF4D4F'
      }
    });
  }

  private toggleEditMode(): void {
    this.isEditMode = !this.isEditMode;
    if (!this.isEditMode) this.selectedBooks.clear();
  }

  private toggleSelect(book: LocalBook): void {
    if (this.selectedBooks.has(book.threadId)) this.selectedBooks.delete(book.threadId);
    else this.selectedBooks.add(book.threadId);
    this.selectedBooks = new Set(this.selectedBooks);
  }

  private selectAll(): void {
    if (this.selectedBooks.size === this.localBooks.length) this.selectedBooks.clear();
    else this.localBooks.forEach(book => this.selectedBooks.add(book.threadId));
    this.selectedBooks = new Set(this.selectedBooks);
  }
  private async batchDelete(): Promise<void> {
    if (this.selectedBooks.size === 0) {
      promptAction.showToast({ message: '请先选择要删除的书籍' }); return;
    }
    AlertDialog.show({
      title: '批量删除',
      message: `确定要删除选中的 ${this.selectedBooks.size} 本书吗？`,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '删除',
        action: () => this.executeBatchDelete(),
        fontColor: '#FF4D4F'
      }
    });
  }

  private async executeBatchDelete(): Promise<void> {
    let deletedCount = 0;
    for (const threadId of this.selectedBooks) {
      const book = this.localBooks.find(b => b.threadId === threadId);
      if (!book) continue;
      try {
        const txtPath = this.getFullPath(book.fileName);
        const metaPath = this.getMetaPath(threadId);
        if (fs.accessSync(txtPath)) fs.unlinkSync(txtPath);
        if (fs.accessSync(metaPath)) fs.unlinkSync(metaPath);
        deletedCount++;
      } catch (e) { console.error(`Failed to delete ${threadId}`, e); }
    }
    promptAction.showToast({ message: `已删除 ${deletedCount} 本书` });
    this.selectedBooks.clear();
    this.isEditMode = false;
    this.scanLocalFiles();
  }

  private formatTime(timestamp: number): string {
    if (!timestamp || isNaN(timestamp)) return '未知时间';
    const date = new Date(timestamp);
    const now = new Date();
    const diff = now.getTime() - date.getTime();
    if (diff < 0) return '刚刚';
    if (diff < 60 * 60 * 1000) {
      const minutes = Math.floor(diff / (60 * 1000));
      return minutes < 1 ? '刚刚' : `${minutes}分钟前`;
    }
    if (diff < 24 * 60 * 60 * 1000) return `${Math.floor(diff / (60 * 60 * 1000))}小时前`;
    if (diff < 7 * 24 * 60 * 60 * 1000) return `${Math.floor(diff / (24 * 60 * 60 * 1000))}天前`;
    return `${date.getMonth() + 1}月${date.getDate()}日`;
  }

  // ====================================================
  // Builder
  // ====================================================
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  @Builder
  HeaderBar() {
    Row() {
      Text(this.isEditMode ? `已选${this.selectedBooks.size}项` : '我的书架')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.getColors().primaryText)
        .layoutWeight(1)

      if (this.isEditMode) {
        Row({ space: 12 }) {
          Button('全选')
            .fontSize(14).fontColor(this.getColors().accentText)
            .backgroundColor(Color.Transparent).onClick(() => this.selectAll())
          Button('取消')
            .fontSize(14).fontColor(this.getColors().secondaryText)
            .backgroundColor(Color.Transparent).onClick(() => this.toggleEditMode())
        }
      } else {
        Row({ space: 8 }) {
          // ✅ 新增：排序切换按钮
          Button(this.getSortLabel())
            .fontSize(13)
            .fontColor(this.getColors().accentText)
            .backgroundColor(this.getColors().secondaryBtnBg)
            .borderRadius(14)
            .height(28)
            .padding({ left: 10, right: 10 })
            .onClick(() => this.cycleSortMode())
          Button('管理')
            .fontSize(14).fontColor(this.getColors().accentText)
            .backgroundColor(Color.Transparent).onClick(() => this.toggleEditMode())
          Button('刷新')
            .fontSize(14).fontColor(this.getColors().accentText)
            .backgroundColor(Color.Transparent).onClick(() => this.scanLocalFiles())
        }
      }
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      // ✅ 顶部 padding = 原有间距 + 状态栏高度（px 转 vp）
      top: 12 + px2vp(this.statusBarHeight),
      bottom: 12
    })
    .backgroundColor(this.getColors().headerBg)
  }

  @Builder
  EmptyView() {
    Column() {
      Text('📚').fontSize(64).margin({ bottom: 16 })
      Text('书架空空如也').fontSize(16).fontColor(this.getColors().tertiaryText).margin({ bottom: 8 })
      Text('去"发现"页面找书吧').fontSize(14).fontColor(this.getColors().secondaryText)
    }
    .width('100%').height('60%').justifyContent(FlexAlign.Center)
  }

  // ✅ 新增：作者分组标题
  @Builder
  AuthorGroupHeader(author: string, count: number) {
    Row() {
      Text('👤').fontSize(14).margin({ right: 6 })
      Text(author)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.getColors().accentText)
        .layoutWeight(1)
      Text(`${count}本`)
        .fontSize(12)
        .fontColor(this.getColors().tertiaryText)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .backgroundColor(this.getColors().groupHeaderBg)
    .borderRadius({ topLeft: 10, topRight: 10 })
  }

  @Builder
  BookItem(book: LocalBook) {
    Row() {
      if (this.isEditMode) {
        Checkbox()
          .select(this.selectedBooks.has(book.threadId))
          .selectedColor(this.getColors().checkboxColor)
          .width(20).height(20).margin({ right: 12 })
          .onChange(() => this.toggleSelect(book))
      }
      Column() {
        Row() {
          Text(book.title)
            .fontSize(17).fontWeight(FontWeight.Bold)
            .fontColor(this.getColors().primaryText)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (!this.isEditMode && book.chapterCount > 0) {
            Text(`${book.chapterCount}章`)
              .fontSize(11).fontColor(this.getColors().tertiaryText)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor(this.getColors().chapterTagBg).borderRadius(4)
          }
        }.width('100%')

        Row() {
          // ✅ 仅在非作者分组模式下显示作者名，避免冗余
          if (this.sortMode !== SortMode.ByAuthor) {
            Text(book.author)
              .fontSize(14).fontColor(this.getColors().secondaryText)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          } else {
            Blank().layoutWeight(1)
          }
          if (book.updateTime > 0) {
            Text(this.formatTime(book.updateTime))
              .fontSize(12).fontColor(this.getColors().tertiaryText)
          }
        }.width('100%').margin({ top: 6 })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)

      if (!this.isEditMode) {
        Row({ space: 8 }) {
          Button() { Text('🗑️').fontSize(16) }
          .width(36).height(36)
          .backgroundColor(this.getColors().dangerBtnBg).borderRadius(18)
          .onClick(() => this.showDeleteConfirm(book))
          Button('更新')
            .fontSize(12).height(32).padding({ left: 12, right: 12 })
            .backgroundColor(this.getColors().secondaryBtnBg)
            .fontColor(this.getColors().secondaryBtnText).borderRadius(16)
            .onClick(() => this.updateBook(book))
          Button('阅读')
            .fontSize(12).height(32).padding({ left: 12, right: 12 })
            .backgroundColor(this.getColors().primaryBtnBg)
            .fontColor(this.getColors().primaryBtnText).borderRadius(16)
            .onClick(() => {
              router.pushUrl({
                url: 'pages/ReaderPage',
                params: { fileName: book.fileName, title: book.title, threadId: book.threadId } as ReaderParams
              });
            })
        }
      }
    }
    .width('100%').padding(16)
    .backgroundColor(this.getColors().cardBg)
    .borderRadius(12)
    .shadow({ radius: 4, color: this.getColors().shadow })
    .onClick(() => { if (this.isEditMode) this.toggleSelect(book); })
  }

  @Builder
  BatchDeleteBar() {
    if (this.isEditMode && this.selectedBooks.size > 0) {
      Row() {
        Button() {
          Row({ space: 4 }) {
            Text('🗑️').fontSize(16)
            Text(`删除(${this.selectedBooks.size})`).fontSize(14).fontColor(this.getColors().dangerBtnText)
          }
        }
        .width('100%').height(48)
        .backgroundColor(this.getColors().dangerBtnBg).borderRadius(8)
        .onClick(() => this.batchDelete())
      }
      .width('100%').padding({ left: 16, right: 16, bottom: 16 })
      .backgroundColor(this.getColors().batchBarBg)
    }
  }

  build() {
    Column() {
      this.HeaderBar()

      if (this.isRefreshing) {
        LoadingProgress()
          .width(40).height(40).color(this.getColors().accentText).margin(20)
      }

      if (this.localBooks.length === 0 && !this.isRefreshing) {
        this.EmptyView()

        // ✅ 按作者分组视图
      } else if (this.sortMode === SortMode.ByAuthor) {
        List({ space: 16 }) {
          ForEach(this.getAuthorGroups(), (group: AuthorGroup) => {
            ListItemGroup({
              header: this.AuthorGroupHeader(group.author, group.books.length)
            }) {
              ForEach(group.books, (book: LocalBook) => {
                ListItem() { this.BookItem(book) }
              }, (book: LocalBook): string => book.threadId)
            }
          }, (group: AuthorGroup): string => group.author)
        }
        .width('100%').layoutWeight(1)
        .padding({ left: 16, right: 16 })
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Auto)
        .sticky(StickyStyle.Header) // ✅ 分组标题吸顶

        // ✅ 时间/书名排序视图（原逻辑）
      } else {
        List({ space: 12 }) {
          ForEach(this.getSortedBooks(), (book: LocalBook) => {
            ListItem() { this.BookItem(book) }
          }, (book: LocalBook): string => book.threadId)
        }
        .width('100%').layoutWeight(1)
        .padding({ left: 16, right: 16 })
        .alignListItem(ListItemAlign.Center)
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Auto)
      }

      this.BatchDeleteBar()
    }
    .width('100%').height('100%')
    .backgroundColor(this.getColors().pageBg)
  }
}