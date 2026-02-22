// entry/src/main/ets/services/CrawlerService.ets
import http from '@ohos.net.http';
import fs from '@ohos.file.fs';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@ohos.base';
import { ThreadItem, DownloadResult, SyncResult } from '../models/SettingsModels';
import { SettingsService } from './SettingsService';

export { ThreadItem, DownloadResult, SyncResult };

interface CrawlerConfig {
  maxPagesPerRun: number;
  stopAfterOldPages: number;
  requestDelay: number;
  enableBreakpoint: boolean;
}

interface ResumeInfo {
  hasBreakpoint: boolean;
  offset: number;
  page: number;
}

interface SpiderState {
  maxSeenPid: number;
  resumeOffset: number;
  threads: Record<string, ThreadItem>;
  lastSyncTime?: number;
}
// 带关注标记的线程类型
interface ThreadItemWithMarks extends ThreadItem {
  watchMarks: string;
}

export class CrawlerService {
  private readonly BASE_URL = "https://mirror.chromaso.net";
  private readonly PAGE_SIZE = 30;

  private stateFilePath: string = "";
  private context: common.Context;
  private settingsService: SettingsService;
  private currentConfig: CrawlerConfig | null = null;

  constructor(context: common.Context) {
    this.context = context;
    this.stateFilePath = `${context.filesDir}/spider_state.json`;
    this.settingsService = SettingsService.getInstance(context);

    this.refreshConfig();

    this.settingsService.subscribe(() => {
      this.refreshConfig();
      console.log('[CrawlerService] 配置已更新');
    });
  }

  private refreshConfig(): void {
    const crawlerConfig = this.settingsService.getCrawlerConfig();
    this.currentConfig = {
      maxPagesPerRun: crawlerConfig.maxPagesPerRun,
      stopAfterOldPages: crawlerConfig.stopAfterOldPages,
      requestDelay: crawlerConfig.requestDelay,
      enableBreakpoint: crawlerConfig.enableBreakpoint
    };
  }

  private get MAX_PAGES(): number {
    return this.currentConfig?.maxPagesPerRun || 5;
  }

  private get STOP_AFTER_OLD_PAGES(): number {
    return this.currentConfig?.stopAfterOldPages || 2;
  }

  private get REQUEST_DELAY(): number {
    return this.currentConfig?.requestDelay || 800;
  }

  private get ENABLE_BREAKPOINT(): boolean {
    return this.currentConfig?.enableBreakpoint !== false;
  }

  private loadState(): SpiderState {
    try {
      if (fs.accessSync(this.stateFilePath)) {
        let content = fs.readTextSync(this.stateFilePath);
        let data = JSON.parse(content) as SpiderState;
        return {
          maxSeenPid: data.maxSeenPid || 0,
          resumeOffset: data.resumeOffset || 0,
          threads: data.threads || {},
          lastSyncTime: data.lastSyncTime || 0
        };
      }
    } catch (e) {
      console.error('loadState error', e);
    }
    return { maxSeenPid: 0, resumeOffset: 0, threads: {} };
  }

  private saveState(state: SpiderState): void {
    if (!this.ENABLE_BREAKPOINT) {
      state.resumeOffset = 0;
    }

    let file: fs.File | null = null;
    try {
      file = fs.openSync(this.stateFilePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, JSON.stringify(state, null, 2));
    } catch (e) {
      console.error('saveState error', e);
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

  getResumeInfo(): ResumeInfo {
    let state = this.loadState();
    return {
      hasBreakpoint: this.ENABLE_BREAKPOINT && state.resumeOffset > 0,
      offset: state.resumeOffset,
      page: Math.floor(state.resumeOffset / this.PAGE_SIZE) + 1
    };
  }



  clearBreakpoint(): void {
    let state = this.loadState();
    state.resumeOffset = 0;
    this.saveState(state);
  }

  async syncLatestThreads(continueFromBreakpoint: boolean = true): Promise<SyncResult> {
    let state = this.loadState();

    if (!continueFromBreakpoint) {
      state.resumeOffset = 0;
    }

    let known = state.threads;
    let maxSeenPid = state.maxSeenPid;
    let startPage = Math.floor(state.resumeOffset / this.PAGE_SIZE);

    if (state.resumeOffset % this.PAGE_SIZE !== 0 && state.resumeOffset > 0) {
      startPage += 1;
    }

    let newThreads: ThreadItem[] = [];
    let updatedThreads: ThreadItem[] = [];
    let seenNewIds = new Set<string>();
    let seenUpdatedIds = new Set<string>();

    let newestPidThisRun = maxSeenPid;
    let oldPageStreak = 0;
    let lastSuccessfulOffset = state.resumeOffset;

    console.log(`[Spider] 开始爬取，startPage=${startPage}, maxSeenPid=${maxSeenPid}, resumeOffset=${state.resumeOffset}`);
    console.log(`[Spider] 配置: MAX_PAGES=${this.MAX_PAGES}, STOP_AFTER_OLD_PAGES=${this.STOP_AFTER_OLD_PAGES}, ENABLE_BREAKPOINT=${this.ENABLE_BREAKPOINT}`);

    if (startPage > 0) {
      console.log('[Spider] 先扫首页防漏...');
      let firstPage = await this.fetchSinglePage(0);
      if (firstPage && firstPage.length > 0) {
        let firstMaxPid = Math.max(...firstPage.map(t => Number(t.lastPid)));
        newestPidThisRun = Math.max(newestPidThisRun, firstMaxPid);
        this.processPageResults(firstPage, known, newThreads, updatedThreads, seenNewIds, seenUpdatedIds);
      }
      await this.sleep(Math.floor(this.REQUEST_DELAY / 2));
    }

    for (let pageIdx = startPage; pageIdx < startPage + this.MAX_PAGES; pageIdx++) {
      let offset = pageIdx * this.PAGE_SIZE;
      console.log(`[Spider] 抓取页 ${pageIdx + 1}, offset=${offset}`);

      let threads = await this.fetchSinglePage(offset);

      if (threads === null) {
        console.warn(`[Spider] 页 ${pageIdx + 1} 请求失败，记录断点 offset=${offset}`);
        if (this.ENABLE_BREAKPOINT) {
          state.resumeOffset = offset;
          this.saveState(state);
        }
        return {
          newThreads: this.addWatchMarks(newThreads),
          updatedThreads: this.addWatchMarks(updatedThreads),
          hasMore: this.ENABLE_BREAKPOINT,
          resumeOffset: offset
        };
      }

      if (threads.length === 0) {
        console.log(`[Spider] 页 ${pageIdx + 1} 无数据，到底部`);
        state.resumeOffset = 0;
        break;
      }

      lastSuccessfulOffset = offset + this.PAGE_SIZE;
      let pageMaxPid = Math.max(...threads.map(t => Number(t.lastPid)));
      newestPidThisRun = Math.max(newestPidThisRun, pageMaxPid);

      this.processPageResults(threads, known, newThreads, updatedThreads, seenNewIds, seenUpdatedIds);

      if (pageMaxPid <= maxSeenPid) {
        oldPageStreak++;
        console.log(`[Spider] 本页无新pid，连续${oldPageStreak}页`);
      } else {
        oldPageStreak = 0;
      }

      if (oldPageStreak >= this.STOP_AFTER_OLD_PAGES) {
        console.log(`[Spider] 连续${this.STOP_AFTER_OLD_PAGES}页无新内容，智能停止`);
        state.resumeOffset = 0;
        break;
      }

      let delay = this.REQUEST_DELAY + Math.random() * 400;
      await this.sleep(Math.floor(delay));
    }

    state.maxSeenPid = newestPidThisRun;
    state.resumeOffset = (oldPageStreak >= this.STOP_AFTER_OLD_PAGES) ? 0 : lastSuccessfulOffset;
    state.lastSyncTime = Date.now();
    this.saveState(state);

    console.log(`[Spider] 完成，新帖:${newThreads.length}, 更新:${updatedThreads.length}, maxSeenPid:${newestPidThisRun}`);

    return {
      newThreads: this.addWatchMarks(newThreads.sort((a, b) => Number(b.lastPid) - Number(a.lastPid))),
      updatedThreads: this.addWatchMarks(updatedThreads.sort((a, b) => Number(b.lastPid) - Number(a.lastPid))),
      hasMore: this.ENABLE_BREAKPOINT && state.resumeOffset > 0,
      resumeOffset: state.resumeOffset
    };
  }

  private processPageResults(
    threads: ThreadItem[],
    known: Record<string, ThreadItem>,
    newThreads: ThreadItem[],
    updatedThreads: ThreadItem[],
    seenNewIds: Set<string>,
    seenUpdatedIds: Set<string>
  ): void {
    for (let t of threads) {
      let prev = known[t.threadId];

      if (!prev) {
        if (!seenNewIds.has(t.threadId)) {
          t.isNew = true;
          newThreads.push(t);
          seenNewIds.add(t.threadId);
        }
      } else if (Number(t.lastPid) > Number(prev.lastPid)) {
        if (!seenUpdatedIds.has(t.threadId)) {
          t.isUpdated = true;
          t.prevLastPid = prev.lastPid;
          t.prevLastTime = prev.lastTime;
          updatedThreads.push(t);
          seenUpdatedIds.add(t.threadId);
        }
      }

      known[t.threadId] = {
        threadId: t.threadId,
        title: t.title,
        author: t.author,
        lastPid: t.lastPid,
        lastTime: t.lastTime,
        tags: t.tags,
        createTime: t.createTime,
        lastUser: t.lastUser,
        isNew: t.isNew,
        isUpdated: t.isUpdated,
        prevLastPid: t.prevLastPid,
        prevLastTime: t.prevLastTime
      };
    }
  }

  private async fetchSinglePage(offset: number): Promise<ThreadItem[] | null> {
    let url = offset === 0 ? `${this.BASE_URL}/forum/18/` : `${this.BASE_URL}/forum/18/+${offset}`;
    let httpRequest = http.createHttp();

    try {
      let response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.0.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9',
        },
        expectDataType: http.HttpDataType.STRING
      });

      if (response.responseCode === 200) {
        return this.parseHtmlByString(response.result as string);
      } else if (response.responseCode === 404) {
        return [];
      }
    } catch (err) {
      console.error(`fetchSinglePage failed offset=${offset}`, err);
      return null;
    } finally {
      httpRequest.destroy();
    }
    return null;
  }

  // ==================== 关注功能接口（已实现） ====================

  isWatchedAuthor(author: string): boolean {
    return this.settingsService.isWatchedAuthor(author);
  }

  isWatchedBook(threadId: string): boolean {
    return this.settingsService.isWatchedBook(threadId);
  }

  getWatchMarks(item: ThreadItem): string {
    let marks: string[] = [];
    if (this.isWatchedAuthor(item.author)) marks.push("⭐");
    if (this.isWatchedBook(item.threadId)) marks.push("📚");
    return marks.join("");
  }


  // 关键修复：正确添加关注标记
  private addWatchMarks(threads: ThreadItem[]): ThreadItemWithMarks[] {
    return threads.map(t => {
      const marks: string[] = [];
      if (this.isWatchedAuthor(t.author)) marks.push("⭐");
      if (this.isWatchedBook(t.threadId)) marks.push("📚");
      const result: ThreadItemWithMarks = {
        threadId: t.threadId,
        title: t.title,
        author: t.author,
        lastPid: t.lastPid,
        lastTime: t.lastTime,
        tags: t.tags,
        createTime: t.createTime,
        lastUser: t.lastUser,
        isNew: t.isNew,
        isUpdated: t.isUpdated,
        prevLastPid: t.prevLastPid,
        prevLastTime: t.prevLastTime,
        watchMarks: marks.join("")  // 添加标记字段
      };
      return result;
    });
  }

  private stateToArray(state: Record<string, ThreadItem>): ThreadItem[] {
    return Object.values(state).sort((a, b) => Number(b.lastPid) - Number(a.lastPid));
  }

  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  searchLocal(keyword: string): ThreadItemWithMarks[] {
    let state = this.loadState();
    let results: ThreadItem[] = [];
    let k = keyword.toLowerCase();

    Object.values(state.threads).forEach(item => {
      if (item.title.toLowerCase().includes(k) ||
      item.author.toLowerCase().includes(k) ||
        item.threadId === keyword) {
        results.push(item);
      }
    });

    return this.addWatchMarks(results.sort((a, b) => Number(b.lastPid) - Number(a.lastPid)));
  }

  async fetchThreadDetail(threadId: string): Promise<string> {
    let res = await this.fetchThreadFullContent(threadId, new Set<string>());
    return res.content;
  }

  async fetchThreadFullContent(threadId: string, existingIds: Set<string>): Promise<DownloadResult> {
    let url = `${this.BASE_URL}/thread/${threadId}`;
    let req = http.createHttp();
    try {
      let res = await req.request(url, { expectDataType: http.HttpDataType.STRING });
      let html = res.result as string;
      let authorMatch = html.match(/class="ui-link"[^>]*>([^<]+)</);
      let author = "未知";
      if (authorMatch) {
        author = authorMatch[1].trim();
      }

      let bodyStart = html.indexOf('class="card-body"');
      let content = "";
      if (bodyStart !== -1) {
        let bodyEnd = html.indexOf('</div>', bodyStart);
        content = html.substring(bodyStart, bodyEnd).replace(/<[^>]+>/g, "").trim();
      }
      return { content, newIds: ["1"], author };
    } catch (e) {
      return { content: "下载失败", newIds: [], author: "未知" };
    } finally {
      req.destroy();
    }
  }

  private parseHtmlByString(html: string): ThreadItem[] {
    let items: ThreadItem[] = [];
    let tbodyMatch = html.match(/<tbody[^>]*>([\s\S]*?)<\/tbody>/i);
    let content: string = tbodyMatch ? tbodyMatch[1] : html;
    let rowRegex = /<tr[^>]*>([\s\S]*?)<\/tr>/gi;
    let rowMatch: RegExpExecArray | null;

    while ((rowMatch = rowRegex.exec(content)) !== null) {
      let tr: string = rowMatch[1];
      let idMatch = tr.match(/href="\/thread\/(\d+)"/);
      let titleMatch = tr.match(/<a href="\/thread\/\d+"[^>]*class="ui-link"[^>]*>([\s\S]*?)<\/a>/);

      if (!idMatch || !titleMatch) continue;
      let tid: string = idMatch[1];
      let titleText: string = titleMatch[1];
      let title: string = titleText.replace(/<[^>]+>/g, "").trim();

      let author: string = "匿名";
      let authorMatch = tr.match(/href="\/author\/\d+"[^>]*class="ui-link"[^>]*>([^<]+)<\/a>/);
      if (authorMatch) {
        author = authorMatch[1].trim();
      }

      let tags: string[] = [];
      let tagMatches = tr.matchAll(/href="\/tag\/\d+"[^>]*>(?:<span[^>]*>#<\/span>)?([^<]+)<\/a>/g);
      for (let m of tagMatches) {
        let tag: string = m[1].trim();
        if (tag && !tag.includes('report_problem')) tags.push(tag);
      }

      let createTime: string = "未知";
      let timeMatch1 = tr.match(/datetime="(\d{4}-\d{2}-\d{2})/);
      if (timeMatch1) {
        createTime = timeMatch1[1];
      }

      let lastUser: string = "无回复";
      let authorRegex = /href="\/author\/\d+"[^>]*class="ui-link"[^>]*>([^<]+)<\/a>/g;
      let lastAuthorMatch: RegExpExecArray | null = null;
      let tempMatch: RegExpExecArray | null;
      while ((tempMatch = authorRegex.exec(tr)) !== null) {
        lastAuthorMatch = tempMatch;
      }
      if (lastAuthorMatch) {
        lastUser = lastAuthorMatch[1].trim();
      }

      let lastTime: string = "刚刚";
      let timeRegex = /<time[^>]*>([^<]+)<\/time>/g;
      let lastTimeMatch: RegExpExecArray | null = null;
      let tempTimeMatch: RegExpExecArray | null;
      while ((tempTimeMatch = timeRegex.exec(tr)) !== null) {
        lastTimeMatch = tempTimeMatch;
      }
      if (lastTimeMatch) {
        lastTime = lastTimeMatch[1].trim();
      }

      let lastPid: number = 0;
      let pidMatch = tr.match(/href="\/thread\/\d+\/last#p(\d+)"/);
      if (pidMatch) {
        lastPid = parseInt(pidMatch[1]);
      }
      items.push({
        threadId: tid,
        title: title,
        author: author,
        lastPid: lastPid.toString(),
        lastTime: lastTime,
        tags: tags,
        createTime: createTime,
        lastUser: lastUser,
        isNew: false,
        isUpdated: false
      } as ThreadItem);
    }

    return items;
  }
}