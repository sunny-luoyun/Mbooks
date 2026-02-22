// entry/src/main/ets/services/SettingsService.ets
import fs from '@ohos.file.fs';
import { Context } from '@ohos.abilityAccessCtrl';
import {
  AppSettings,
  WatchedAuthor,
  WatchedBook,
  CrawlerConfig,
  NotificationConfig,
  UIConfig
} from '../models/SettingsModels';

export class SettingsService {
  private static instance: SettingsService | null = null;
  private context: Context;
  private settingsPath: string;
  private cache: AppSettings | null = null;
  private listeners: Set<(settings: AppSettings) => void> = new Set();

  // 默认配置
  private readonly DEFAULT_SETTINGS: AppSettings = {
    version: 1,
    authors: [],
    books: [],
    crawler: {
      maxPagesPerRun: 5,
      stopAfterOldPages: 2,
      requestDelay: 800,
      enableBreakpoint: true,
      autoCheckOnStartup: false,
      checkIntervalHours: 0
    },
    notification: {
      enablePush: true,
      notifyNewThread: true,
      notifyUpdate: true,
      notifyWatchedOnly: false
    },
    ui: {
      theme: 'auto',
      fontSize: 16,
      lineSpacing: 1.5
    }
  };

  private constructor(context: Context) {
    this.context = context;
    this.settingsPath = context.filesDir + '/app_settings.json';
    this.loadSettings();
  }

  static getInstance(context: Context): SettingsService {
    if (!SettingsService.instance) {
      SettingsService.instance = new SettingsService(context);
    }
    return SettingsService.instance;
  }

  // 订阅设置变更
  subscribe(callback: (settings: AppSettings) => void): () => void {
    this.listeners.add(callback);
    // 立即返回当前值
    if (this.cache) callback(this.deepCloneSettings(this.cache));
    // 返回取消订阅函数
    return (): void => {
      this.listeners.delete(callback);
    };
  }

  private notifyListeners(): void {
    if (this.cache) {
      this.listeners.forEach((cb: (settings: AppSettings) => void): void => {
        cb(this.deepCloneSettings(this.cache!));
      });
    }
  }

  // 加载设置
  private loadSettings(): void {
    try {
      if (fs.accessSync(this.settingsPath)) {
        const content: string = fs.readTextSync(this.settingsPath);
        const loaded: AppSettings = JSON.parse(content) as AppSettings;
        // 版本迁移处理
        this.cache = this.migrateSettings(loaded);
      } else {
        this.cache = this.deepCloneSettings(this.DEFAULT_SETTINGS);
        this.saveSettings();
      }
    } catch (e) {
      console.error('Settings load failed:', e);
      this.cache = this.deepCloneSettings(this.DEFAULT_SETTINGS);
    }
  }

  // 设置版本迁移逻辑
  private migrateSettings(old: AppSettings): AppSettings {
    if (!old.version || old.version < 1) {
      // 手动合并对象，避免使用Object.assign
      const merged: AppSettings = {
        version: 1,
        authors: old.authors || [],
        books: old.books || [],
        crawler: old.crawler || {
          maxPagesPerRun: 5,
          stopAfterOldPages: 2,
          requestDelay: 800,
          enableBreakpoint: true,
          autoCheckOnStartup: false,
          checkIntervalHours: 0
        },
        notification: old.notification || {
          enablePush: true,
          notifyNewThread: true,
          notifyUpdate: true,
          notifyWatchedOnly: false
        },
        ui: old.ui || {
          theme: 'auto',
          fontSize: 16,
          lineSpacing: 1.5
        }
      };
      return merged;
    }
    return old;
  }

  // 保存设置
  private saveSettings(): void {
    if (!this.cache) return;
    let file: fs.File | null = null;
    try {
      file = fs.openSync(
        this.settingsPath,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC
      );
      fs.writeSync(file.fd, JSON.stringify(this.cache, null, 2));
      this.notifyListeners();
    } catch (e) {
      console.error('Settings save failed:', e);
    } finally {
      if (file) {
        try {
          fs.closeSync(file);
        } catch (e) {
          console.error('Failed to close file:', e);
        }
      }
    }
  }

  // 深拷贝辅助方法
  private deepCloneSettings(settings: AppSettings): AppSettings {
    const clonedAuthors: WatchedAuthor[] = [];
    for (let i: number = 0; i < settings.authors.length; i++) {
      const a: WatchedAuthor = settings.authors[i];
      clonedAuthors.push({
        name: a.name,
        addTime: a.addTime,
        notifyOnUpdate: a.notifyOnUpdate
      });
    }

    const clonedBooks: WatchedBook[] = [];
    for (let i: number = 0; i < settings.books.length; i++) {
      const b: WatchedBook = settings.books[i];
      clonedBooks.push({
        threadId: b.threadId,
        title: b.title,
        addTime: b.addTime,
        notifyOnUpdate: b.notifyOnUpdate,
        autoDownload: b.autoDownload
      });
    }

    return {
      version: settings.version,
      authors: clonedAuthors,
      books: clonedBooks,
      crawler: {
        maxPagesPerRun: settings.crawler.maxPagesPerRun,
        stopAfterOldPages: settings.crawler.stopAfterOldPages,
        requestDelay: settings.crawler.requestDelay,
        enableBreakpoint: settings.crawler.enableBreakpoint,
        autoCheckOnStartup: settings.crawler.autoCheckOnStartup,
        checkIntervalHours: settings.crawler.checkIntervalHours
      },
      notification: {
        enablePush: settings.notification.enablePush,
        notifyNewThread: settings.notification.notifyNewThread,
        notifyUpdate: settings.notification.notifyUpdate,
        notifyWatchedOnly: settings.notification.notifyWatchedOnly
      },
      ui: {
        theme: settings.ui.theme,
        fontSize: settings.ui.fontSize,
        lineSpacing: settings.ui.lineSpacing
      }
    };
  }

  // ==================== 获取配置 ====================

  getSettings(): AppSettings {
    if (this.cache) {
      return this.deepCloneSettings(this.cache);
    }
    return this.deepCloneSettings(this.DEFAULT_SETTINGS);
  }

  getCrawlerConfig(): CrawlerConfig {
    const settings: AppSettings = this.getSettings();
    return {
      maxPagesPerRun: settings.crawler.maxPagesPerRun,
      stopAfterOldPages: settings.crawler.stopAfterOldPages,
      requestDelay: settings.crawler.requestDelay,
      enableBreakpoint: settings.crawler.enableBreakpoint,
      autoCheckOnStartup: settings.crawler.autoCheckOnStartup,
      checkIntervalHours: settings.crawler.checkIntervalHours
    };
  }

  getNotificationConfig(): NotificationConfig {
    const settings: AppSettings = this.getSettings();
    return {
      enablePush: settings.notification.enablePush,
      notifyNewThread: settings.notification.notifyNewThread,
      notifyUpdate: settings.notification.notifyUpdate,
      notifyWatchedOnly: settings.notification.notifyWatchedOnly
    };
  }

  // ==================== 关注作者管理 ====================

  addWatchedAuthor(author: string, notify: boolean = true): boolean {
    if (!this.cache) return false;
    if (this.cache.authors.some((a: WatchedAuthor): boolean => a.name === author)) return false;

    const newAuthor: WatchedAuthor = {
      name: author,
      addTime: Date.now(),
      notifyOnUpdate: notify
    };
    this.cache.authors.push(newAuthor);
    this.saveSettings();
    return true;
  }

  removeWatchedAuthor(author: string): void {
    if (!this.cache) return;
    this.cache.authors = this.cache.authors.filter((a: WatchedAuthor): boolean => a.name !== author);
    this.saveSettings();
  }

  isWatchedAuthor(author: string): boolean {
    if (!this.cache) return false;
    return this.cache.authors.some((a: WatchedAuthor): boolean => a.name === author);
  }

  getWatchedAuthors(): WatchedAuthor[] {
    if (!this.cache) return [];
    const authors: WatchedAuthor[] = this.cache.authors;
    const result: WatchedAuthor[] = [];
    for (let i: number = 0; i < authors.length; i++) {
      result.push({
        name: authors[i].name,
        addTime: authors[i].addTime,
        notifyOnUpdate: authors[i].notifyOnUpdate
      });
    }
    return result;
  }

  updateWatchedAuthorNotify(authorName: string, notifyOnUpdate: boolean): boolean {
    if (!this.cache) return false;

    const authorIndex = this.cache.authors.findIndex((a: WatchedAuthor): boolean => a.name === authorName);
    if (authorIndex === -1) return false;

    // 更新通知设置
    this.cache.authors[authorIndex] = {
      name: this.cache.authors[authorIndex].name,
      addTime: this.cache.authors[authorIndex].addTime,
      notifyOnUpdate: notifyOnUpdate
    };

    this.saveSettings();
    return true;
  }

  // ==================== 关注书籍管理 ====================

  addWatchedBook(threadId: string, title: string, autoDownload: boolean = false): boolean {
    if (!this.cache) return false;
    if (this.cache.books.some((b: WatchedBook): boolean => b.threadId === threadId)) return false;

    const newBook: WatchedBook = {
      threadId: threadId,
      title: title,
      addTime: Date.now(),
      notifyOnUpdate: true,
      autoDownload: autoDownload
    };
    this.cache.books.push(newBook);
    this.saveSettings();
    return true;
  }

  removeWatchedBook(threadId: string): void {
    if (!this.cache) return;
    this.cache.books = this.cache.books.filter((b: WatchedBook): boolean => b.threadId !== threadId);
    this.saveSettings();
  }

  isWatchedBook(threadId: string): boolean {
    if (!this.cache) return false;
    return this.cache.books.some((b: WatchedBook): boolean => b.threadId === threadId);
  }

  getWatchedBooks(): WatchedBook[] {
    if (!this.cache) return [];
    const books: WatchedBook[] = this.cache.books;
    const result: WatchedBook[] = [];
    for (let i: number = 0; i < books.length; i++) {
      result.push({
        threadId: books[i].threadId,
        title: books[i].title,
        addTime: books[i].addTime,
        notifyOnUpdate: books[i].notifyOnUpdate,
        autoDownload: books[i].autoDownload
      });
    }
    return result;
  }

  updateWatchedBooks(books: WatchedBook[]): void {
    if (!this.cache) return;
    this.cache.books = [];
    for (let i: number = 0; i < books.length; i++) {
      this.cache.books.push({
        threadId: books[i].threadId,
        title: books[i].title,
        addTime: books[i].addTime,
        notifyOnUpdate: books[i].notifyOnUpdate,
        autoDownload: books[i].autoDownload
      });
    }
    this.saveSettings();
  }

  updateWatchedBookAutoDownload(threadId: string, autoDownload: boolean): boolean {
    if (!this.cache) return false;

    const bookIndex = this.cache.books.findIndex((b: WatchedBook): boolean => b.threadId === threadId);
    if (bookIndex === -1) return false;

    this.cache.books[bookIndex] = {
      threadId: this.cache.books[bookIndex].threadId,
      title: this.cache.books[bookIndex].title,
      addTime: this.cache.books[bookIndex].addTime,
      notifyOnUpdate: this.cache.books[bookIndex].notifyOnUpdate,
      autoDownload: autoDownload
    };

    this.saveSettings();
    return true;
  }

  updateWatchedBookNotify(threadId: string, notifyOnUpdate: boolean): boolean {
    if (!this.cache) return false;

    const bookIndex = this.cache.books.findIndex((b: WatchedBook): boolean => b.threadId === threadId);
    if (bookIndex === -1) return false;

    this.cache.books[bookIndex] = {
      threadId: this.cache.books[bookIndex].threadId,
      title: this.cache.books[bookIndex].title,
      addTime: this.cache.books[bookIndex].addTime,
      notifyOnUpdate: notifyOnUpdate,
      autoDownload: this.cache.books[bookIndex].autoDownload
    };

    this.saveSettings();
    return true;
  }

  // ==================== 爬取配置更新 ====================

  updateCrawlerConfig(config: Partial<CrawlerConfig>): void {
    if (!this.cache) return;
    const newConfig: CrawlerConfig = {
      maxPagesPerRun: config.maxPagesPerRun !== undefined ? config.maxPagesPerRun : this.cache.crawler.maxPagesPerRun,
      stopAfterOldPages: config.stopAfterOldPages !== undefined ? config.stopAfterOldPages : this.cache.crawler.stopAfterOldPages,
      requestDelay: config.requestDelay !== undefined ? config.requestDelay : this.cache.crawler.requestDelay,
      enableBreakpoint: config.enableBreakpoint !== undefined ? config.enableBreakpoint : this.cache.crawler.enableBreakpoint,
      autoCheckOnStartup: config.autoCheckOnStartup !== undefined ? config.autoCheckOnStartup : this.cache.crawler.autoCheckOnStartup,
      checkIntervalHours: config.checkIntervalHours !== undefined ? config.checkIntervalHours : this.cache.crawler.checkIntervalHours
    };
    this.cache.crawler = newConfig;
    this.saveSettings();
  }

  // ==================== 通知配置更新 ====================

  updateNotificationConfig(config: Partial<NotificationConfig>): void {
    if (!this.cache) return;
    const newConfig: NotificationConfig = {
      enablePush: config.enablePush !== undefined ? config.enablePush : this.cache.notification.enablePush,
      notifyNewThread: config.notifyNewThread !== undefined ? config.notifyNewThread : this.cache.notification.notifyNewThread,
      notifyUpdate: config.notifyUpdate !== undefined ? config.notifyUpdate : this.cache.notification.notifyUpdate,
      notifyWatchedOnly: config.notifyWatchedOnly !== undefined ? config.notifyWatchedOnly : this.cache.notification.notifyWatchedOnly
    };
    this.cache.notification = newConfig;
    this.saveSettings();
  }

  // ==================== UI配置更新 ====================

  updateUIConfig(ui: Partial<UIConfig>): void {
    if (!this.cache) return;
    const newConfig: UIConfig = {
      theme: ui.theme !== undefined ? ui.theme : this.cache.ui.theme,
      fontSize: ui.fontSize !== undefined ? ui.fontSize : this.cache.ui.fontSize,
      lineSpacing: ui.lineSpacing !== undefined ? ui.lineSpacing : this.cache.ui.lineSpacing
    };
    this.cache.ui = newConfig;
    this.saveSettings();
  }

  // 重置为默认
  resetToDefault(): void {
    this.cache = this.deepCloneSettings(this.DEFAULT_SETTINGS);
    this.cache.authors = [];
    this.cache.books = [];
    this.saveSettings();
  }
}