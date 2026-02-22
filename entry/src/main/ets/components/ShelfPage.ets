// entry/src/main/ets/components/ShelfPage.ets
import router from '@ohos.router';
import fs from '@ohos.file.fs';
import promptAction from '@ohos.promptAction';
import { CrawlerService } from '../services/CrawlerService';
import { DownloadResult } from '../models/SettingsModels';
import { ThreadMeta } from '../services/DownloadService';

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

@Component
export struct ShelfPage {
  @State localBooks: Array<LocalBook> = [];
  @State isRefreshing: boolean = false;
  @State isEditMode: boolean = false;
  @State selectedBooks: Set<string> = new Set();
  private crawler: CrawlerService | null = null;
  private readonly THREADS_DIR = 'threads';

  aboutToAppear(): void {
    this.crawler = new CrawlerService(getContext(this) as Context);
    this.scanLocalFiles();
  }

  private ensureThreadsDir(ctx: Context): string {
    const threadsPath = `${ctx.filesDir}/${this.THREADS_DIR}`;
    if (!fs.accessSync(threadsPath)) {
      try {
        fs.mkdirSync(threadsPath);
      } catch (e) {
        console.error('Failed to create threads dir:', e);
      }
    }
    return threadsPath;
  }

  scanLocalFiles(): void {
    this.isRefreshing = true;
    try {
      const ctx: Context = getContext(this) as Context;
      const threadsPath = this.ensureThreadsDir(ctx);

      let files: string[] = [];
      try {
        files = fs.listFileSync(threadsPath);
        console.log(`[ShelfPage] Found ${files.length} files: ${JSON.stringify(files)}`);
      } catch (e) {
        console.error('Failed to list threads dir:', e);
      }

      const books: LocalBook[] = [];

      for (let i = 0; i < files.length; i++) {
        const file: string = files[i];
        if (!file.endsWith('.txt')) continue;

        // 关键修复：支持 {id}.txt 和 {id}_{title}.txt 两种格式
        let tid: string = '';
        let title: string = '';

        const fullMatch = file.match(/^(\d+)_(.+)\.txt$/);
        if (fullMatch) {
          tid = fullMatch[1];
          title = fullMatch[2];
        } else {
          const simpleMatch = file.match(/^(\d+)\.txt$/);
          if (simpleMatch) {
            tid = simpleMatch[1];
            title = `帖子${tid}`;
          } else {
            continue;
          }
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
            title = meta.title || title; // 优先使用meta中的title
            updateTime = new Date(meta.lastUpdate).getTime() || 0;
            chapterCount = Object.keys(meta.posts || {} as Record<string, PostTimeInfo>).length;
          } catch (e) {
            console.error('Parse meta failed for', tid, e);
          }
        }

        if (chapterCount === 0) {
          chapterCount = this.countChapters(`${threadsPath}/${file}`);
        }
        books.push({
          threadId: tid,
          title: title,
          author: author,
          fileName: file,
          updateTime: updateTime,
          chapterCount: chapterCount
        } as LocalBook);
      }

      books.sort((a, b) => b.updateTime - a.updateTime);
      this.localBooks = books;
      console.log(`[ShelfPage] Loaded ${books.length} books`);

      if (books.length === 0) {
        console.log('[ShelfPage] No valid books found in:', threadsPath);
      }
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
    } catch (e) {
      return 0;
    }
  }

  private getFullPath(fileName: string): string {
    const ctx = getContext(this) as Context;
    return `${ctx.filesDir}/${this.THREADS_DIR}/${fileName}`;
  }

  private getMetaPath(threadId: string): string {
    const ctx = getContext(this) as Context;
    return `${ctx.filesDir}/${this.THREADS_DIR}/${threadId}_meta.json`;
  }

  async updateBook(book: LocalBook): Promise<void> {
    this.isRefreshing = true;
    try {
      const ctx: Context = getContext(this) as Context;
      const metaPath = this.getMetaPath(book.threadId);
      let existingIds: string[] = [];
      let author: string = book.author;

      if (fs.accessSync(metaPath)) {
        try {
          const metaContent = fs.readTextSync(metaPath);
          const meta: ThreadMeta = JSON.parse(metaContent) as ThreadMeta;
          existingIds = Object.keys(meta.posts || {} as Record<string, PostTimeInfo>);
          author = meta.author || book.author;
        } catch (e) {
          console.error('Read meta failed:', e);
        }
      }

      if (this.crawler) {
        const existingSet = new Set<string>(existingIds);
        const res: DownloadResult = await this.crawler.fetchThreadFullContent(book.threadId, existingSet);

        if (res.newIds.length > 0) {
          const filePath = this.getFullPath(book.fileName);
          const fileExists = fs.accessSync(filePath);

          const file = fs.openSync(filePath,
            fileExists ? fs.OpenMode.READ_WRITE | fs.OpenMode.APPEND
              : fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);

          if (!fileExists) {
            const header = `${book.title}\n作者: ${res.author || author}\n${"=".repeat(60)}\n\n`;
            fs.writeSync(file.fd, header);
          }

          fs.writeSync(file.fd, res.content);
          fs.closeSync(file);

          const newPosts: Record<string, PostTimeInfo> = {};
          existingIds.forEach(id => newPosts[id] = { time: '' });
          res.newIds.forEach(id => newPosts[id] = { time: new Date().toISOString() });

          const newMeta: ThreadMeta = {
            threadId: book.threadId,
            title: book.title,
            author: res.author || author,
            lastUpdate: new Date().toISOString(),
            lastPageOffset: Math.floor(Object.keys(newPosts).length / 20) * 20,
            posts: newPosts
          };

          const mFile = fs.openSync(metaPath,
            fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
          fs.writeSync(mFile.fd, JSON.stringify(newMeta, null, 2));
          fs.closeSync(mFile);

          promptAction.showToast({ message: `更新了 ${res.newIds.length} 章` });
          this.scanLocalFiles();
        } else {
          promptAction.showToast({ message: "已是最新" });
        }
      }
    } catch (e) {
      console.error('Update failed', e);
      promptAction.showToast({ message: "更新失败" });
    } finally {
      this.isRefreshing = false;
    }
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
      primaryButton: { value: '取消', action: () => {} },
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
    if (this.selectedBooks.has(book.threadId)) {
      this.selectedBooks.delete(book.threadId);
    } else {
      this.selectedBooks.add(book.threadId);
    }
    this.selectedBooks = new Set(this.selectedBooks);
  }

  private selectAll(): void {
    if (this.selectedBooks.size === this.localBooks.length) {
      this.selectedBooks.clear();
    } else {
      this.localBooks.forEach(book => this.selectedBooks.add(book.threadId));
    }
    this.selectedBooks = new Set(this.selectedBooks);
  }

  private async batchDelete(): Promise<void> {
    if (this.selectedBooks.size === 0) {
      promptAction.showToast({ message: '请先选择要删除的书籍' });
      return;
    }

    AlertDialog.show({
      title: '批量删除',
      message: `确定要删除选中的 ${this.selectedBooks.size} 本书吗？`,
      primaryButton: { value: '取消', action: () => {} },
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
      } catch (e) {
        console.error(`Failed to delete ${threadId}`, e);
      }
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
    if (diff < 24 * 60 * 60 * 1000) {
      const hours = Math.floor(diff / (60 * 60 * 1000));
      return `${hours}小时前`;
    }
    if (diff < 7 * 24 * 60 * 60 * 1000) {
      const days = Math.floor(diff / (24 * 60 * 60 * 1000));
      return `${days}天前`;
    }
    return `${date.getMonth() + 1}月${date.getDate()}日`;
  }

  @Builder
  HeaderBar() {
    Row() {
      Text(this.isEditMode ? `已选${this.selectedBooks.size}项` : '我的书架')
        .fontSize(20).fontWeight(FontWeight.Bold).layoutWeight(1)

      if (this.isEditMode) {
        Row({ space: 12 }) {
          Button('全选').fontSize(14).fontColor('#007DFF').backgroundColor(Color.Transparent)
            .onClick(() => this.selectAll())
          Button('取消').fontSize(14).fontColor('#666').backgroundColor(Color.Transparent)
            .onClick(() => this.toggleEditMode())
        }
      } else {
        Row({ space: 8 }) {
          Button('管理').fontSize(14).fontColor('#007DFF').backgroundColor(Color.Transparent)
            .onClick(() => this.toggleEditMode())
          Button('刷新').fontSize(14).fontColor('#007DFF').backgroundColor(Color.Transparent)
            .onClick(() => this.scanLocalFiles())
        }
      }
    }
    .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 }).backgroundColor('#FFF')
  }

  @Builder
  EmptyView() {
    Column() {
      Text('📚').fontSize(64).margin({ bottom: 16 })
      Text('书架空空如也').fontSize(16).fontColor('#999').margin({ bottom: 8 })
      Text('去"发现"页面找书吧').fontSize(14).fontColor('#666')
    }
    .width('100%').height('60%').justifyContent(FlexAlign.Center)
  }

  @Builder
  BookItem(book: LocalBook) {
    Row() {
      if (this.isEditMode) {
        Checkbox()
          .select(this.selectedBooks.has(book.threadId))
          .selectedColor('#007DFF')
          .width(20).height(20).margin({ right: 12 })
          .onChange(() => this.toggleSelect(book))
      }

      Column() {
        Row() {
          Text(book.title).fontSize(17).fontWeight(FontWeight.Bold)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          if (!this.isEditMode && book.chapterCount > 0) {
            Text(`${book.chapterCount}章`).fontSize(11).fontColor('#999')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor('#F5F5F5').borderRadius(4)
          }
        }.width('100%')

        Row() {
          Text(book.author).fontSize(14).fontColor('#666')
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          if (book.updateTime > 0) {
            Text(this.formatTime(book.updateTime)).fontSize(12).fontColor('#999')
          }
        }.width('100%').margin({ top: 6 })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)

      if (!this.isEditMode) {
        Row({ space: 8 }) {
          Button() { Text('🗑️').fontSize(16) }
          .width(36).height(36).backgroundColor('#FFF5F5').borderRadius(18)
          .onClick(() => this.showDeleteConfirm(book))

          Button('更新').fontSize(12).height(32).padding({ left: 12, right: 12 })
            .backgroundColor('#E6F2FF').fontColor('#007DFF').borderRadius(16)
            .onClick(() => this.updateBook(book))

          Button('阅读').fontSize(12).height(32).padding({ left: 12, right: 12 })
            .backgroundColor('#007DFF').fontColor('#FFF').borderRadius(16)
            .onClick(() => {
              router.pushUrl({
                url: 'pages/ReaderPage',
                params: { fileName: book.fileName, title: book.title, threadId: book.threadId } as ReaderParams
              });
            })
        }
      }
    }
    .width('100%').padding(16).backgroundColor('#FFF').borderRadius(12)
    .shadow({ radius: 4, color: '#10000000' })
    .onClick(() => { if (this.isEditMode) this.toggleSelect(book); })
  }

  @Builder
  BatchDeleteBar() {
    if (this.isEditMode && this.selectedBooks.size > 0) {
      Row() {
        Button() {
          Row({ space: 4 }) {
            Text('🗑️').fontSize(16)
            Text(`删除(${this.selectedBooks.size})`).fontSize(14).fontColor('#FF4D4F')
          }
        }
        .width('100%').height(48).backgroundColor('#FFF5F5').borderRadius(8)
        .onClick(() => this.batchDelete())
      }
      .width('100%').padding({ left: 16, right: 16, bottom: 16 }).backgroundColor('#F1F3F5')
    }
  }

  build() {
    Column() {
      this.HeaderBar()
      if (this.isRefreshing) {
        LoadingProgress().width(40).height(40).margin(20)
      }
      if (this.localBooks.length === 0 && !this.isRefreshing) {
        this.EmptyView()
      } else {
        List({ space: 12 }) {
          ForEach(this.localBooks, (book: LocalBook) => {
            ListItem() { this.BookItem(book) }
          }, (item: LocalBook): string => item.threadId)
        }
        .width('100%').layoutWeight(1).padding({ left: 16, right: 16 })
        .alignListItem(ListItemAlign.Center)
        .edgeEffect(EdgeEffect.Spring).scrollBar(BarState.Auto)
      }
      this.BatchDeleteBar()
    }
    .width('100%').height('100%').backgroundColor('#F1F3F5')
  }
}