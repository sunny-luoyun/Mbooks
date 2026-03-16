// entry/src/main/ets/services/DownloadService.ets
import http from '@ohos.net.http';
import fs from '@ohos.file.fs';

export interface DownloadedPost {
  postId: string;
  time: string;
  content: string;
}

export interface PostTimeInfo {
  time: string;
}

export interface ThreadMeta {
  threadId: string;
  title: string;
  author: string;
  lastUpdate: string;
  lastPageOffset: number;
  posts: Record<string, PostTimeInfo>;
}

export class DownloadService {
  private static instance: DownloadService;
  private readonly BASE_URL = "https://mirror.chromaso.net";
  private readonly PAGE_SIZE = 20;
  private readonly MIN_CONTENT_LENGTH = 500;
  private context: Context;

  private constructor(context: Context) {
    this.context = context;
  }

  public static getInstance(context: Context): DownloadService {
    if (!DownloadService.instance) {
      DownloadService.instance = new DownloadService(context);
    }
    return DownloadService.instance;
  }

  /**
   * 执行全量或增量下载
   * 增量模式：从最后一页倒序扫描，遇到全页重复即停
   * 全量模式：从第 1 页正序扫到底
   */
  public async downloadThread(
    threadId: string,
    title: string,
    author: string,
    onProgress: (progress: number) => void
  ): Promise<boolean> {
    try {
      onProgress(5);

      // 1. 读取本地 Meta 信息
      const dir = `${this.context.filesDir}/threads`;
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir);
      }
      const metaPath = `${dir}/${threadId}_meta.json`;
      const txtPath  = `${dir}/${threadId}.txt`;

      let meta: ThreadMeta = {
        threadId,
        title,
        author,
        lastUpdate: '',
        lastPageOffset: 0,
        posts: {}
      };
      let isUpdateMode = false;

      if (fs.accessSync(metaPath)) {
        try {
          const metaStr = fs.readTextSync(metaPath);
          meta = JSON.parse(metaStr) as ThreadMeta;
          isUpdateMode = Object.keys(meta.posts).length > 0;
          console.log(`[DownloadService] 增量模式，已有 ${Object.keys(meta.posts).length} 条楼层`);
        } catch (e) {
          console.warn('[DownloadService] 读取 meta 失败，降级为全量下载', e);
        }
      }

      const existingPostIds = new Set<string>(Object.keys(meta.posts));

      // 2. 请求第一页，获取真实作者和总页数
      const firstHtml = await this.fetchHtml(`${this.BASE_URL}/thread/${threadId}`);
      if (!firstHtml) return false;

      const realAuthor = this.parseThreadAuthor(firstHtml) || meta.author || author;
      const totalPages = this.getTotalPages(firstHtml);

      const newPosts: DownloadedPost[] = [];

      if (isUpdateMode) {
        // ── 增量模式：从最后一页倒序扫，遇到全页重复即停 ──────────────────
        console.log(`[DownloadService] 共 ${totalPages} 页，增量倒序从第 ${totalPages} 页开始，作者=${realAuthor}`);

        for (let p = totalPages; p >= 1; p--) {
          // 进度：扫过的页数 / 总页数
          const progress = 5 + Math.floor(((totalPages - p + 1) / totalPages) * 85);
          onProgress(progress);

          // 第 1 页复用已请求的 firstHtml，其余重新请求
          const url = p > 1
            ? `${this.BASE_URL}/thread/${threadId}/+${(p - 1) * this.PAGE_SIZE}`
            : `${this.BASE_URL}/thread/${threadId}`;
          const html = (p === 1) ? firstHtml : await this.fetchHtml(url);

          if (!html) {
            console.warn(`[DownloadService] 第 ${p} 页获取失败，跳过`);
            continue;
          }

          const pagePosts  = this.parsePosts(html, realAuthor);
          const newOnPage  = pagePosts.filter(post => !existingPostIds.has(post.postId));

          // 倒序收集，用 unshift 保证最终顺序仍是从早到晚
          newPosts.unshift(...newOnPage);

          console.log(`[DownloadService] 第 ${p}/${totalPages} 页：作者帖 ${pagePosts.length} 条，新增 ${newOnPage.length} 条`);

          // 这一页楼主帖全部是旧数据 → 更早的页肯定也是旧数据，停止
          if (pagePosts.length > 0 && newOnPage.length === 0) {
            console.log(`[DownloadService] 第 ${p} 页全部重复，停止倒序扫描`);
            break;
          }

          // 已扫到第 1 页就不需要再等了
          if (p > 1) {
            await this.sleep(500 + Math.floor(Math.random() * 500));
          }
        }

      } else {
        // ── 全量模式：正序从第 1 页扫到底 ─────────────────────────────────
        console.log(`[DownloadService] 共 ${totalPages} 页，全量正序，作者=${realAuthor}`);

        for (let p = 1; p <= totalPages; p++) {
          const progress = 5 + Math.floor((p / totalPages) * 85);
          onProgress(progress);

          const url = p > 1
            ? `${this.BASE_URL}/thread/${threadId}/+${(p - 1) * this.PAGE_SIZE}`
            : `${this.BASE_URL}/thread/${threadId}`;
          const html = (p === 1) ? firstHtml : await this.fetchHtml(url);

          if (!html) {
            console.warn(`[DownloadService] 第 ${p} 页获取失败，跳过`);
            continue;
          }

          const pagePosts = this.parsePosts(html, realAuthor);
          newPosts.push(...pagePosts);

          console.log(`[DownloadService] 第 ${p}/${totalPages} 页：作者帖 ${pagePosts.length} 条`);

          if (p < totalPages) {
            await this.sleep(500 + Math.floor(Math.random() * 500));
          }
        }
      }

      // 3. 保存数据
      onProgress(95);
      await this.saveData(threadId, meta.title || title, realAuthor, newPosts, meta, metaPath, txtPath, isUpdateMode);

      onProgress(100);
      console.log(`[DownloadService] 完成：新增 ${newPosts.length} 章`);
      return true;

    } catch (e) {
      console.error('[DownloadService] downloadThread Error:', e);
      return false;
    }
  }

  // ─── 解析帖子真实作者（首楼的 ui-link） ────────────────────────────────
  private parseThreadAuthor(html: string): string {
    // 找第一个 mm-post div 里的 ui-link
    const postStart = html.indexOf('class="mm-post"');
    if (postStart === -1) return '';
    // 在这个 post 范围内找 ui-link
    const linkIdx = html.indexOf('class="ui-link"', postStart);
    if (linkIdx === -1) return '';
    const textStart = html.indexOf('>', linkIdx) + 1;
    const textEnd   = html.indexOf('<', textStart);
    if (textStart > 0 && textEnd > textStart) {
      return html.substring(textStart, textEnd).trim();
    }
    return '';
  }

  // ─── 网络请求 ────────────────────────────────────────────────────────────
  private async fetchHtml(url: string): Promise<string | null> {
    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9',
        },
        readTimeout: 15000,
        connectTimeout: 15000
      });
      if (response.responseCode === 200) {
        return response.result as string;
      }
      return null;
    } catch (err) {
      console.error(`[DownloadService] Fetch error for ${url}:`, err);
      return null;
    } finally {
      httpRequest.destroy();
    }
  }

  // ─── 获取总页数 ──────────────────────────────────────────────────────────
  private getTotalPages(html: string): number {
    let maxPage = 1;
    const regex = new RegExp('/thread/\\d+/\\+(\\d+)', 'g');
    let match: RegExpExecArray | null;
    while ((match = regex.exec(html)) !== null) {
      const page = Math.floor(parseInt(match[1]) / this.PAGE_SIZE) + 1;
      if (page > maxPage) maxPage = page;
    }
    return maxPage;
  }

  // ─── 解析某一页的楼主帖子 ────────────────────────────────────────────────
  private parsePosts(html: string, targetAuthor: string): DownloadedPost[] {
    const posts: DownloadedPost[] = [];
    let pos = 0;
    const htmlLength = html.length;

    while (pos < htmlLength) {
      // 查找帖子 div：<div id="p数字"
      const divStart = html.indexOf('<div id="p', pos);
      if (divStart === -1) break;

      const idStart = divStart + 10;
      const idEnd = html.indexOf('"', idStart);
      if (idEnd === -1) break;

      // 确认是纯数字 id
      const rawId = html.substring(idStart, idEnd);
      if (!/^\d+$/.test(rawId)) {
        pos = idEnd + 1;
        continue;
      }
      const postId = 'p' + rawId;

      // 找到这个 div 完整结束位置
      const tagEnd = html.indexOf('>', idEnd);
      if (tagEnd === -1) break;

      let depth = 1;
      let searchPos = tagEnd + 1;
      let divEnd = tagEnd + 1;

      while (depth > 0 && searchPos < htmlLength) {
        const nextOpen  = html.indexOf('<div', searchPos);
        const nextClose = html.indexOf('</div>', searchPos);
        if (nextClose === -1) break;

        if (nextOpen !== -1 && nextOpen < nextClose) {
          depth++;
          searchPos = nextOpen + 4;
        } else {
          depth--;
          divEnd = nextClose;
          searchPos = nextClose + 6;
        }
      }

      const postHtml = html.substring(divStart, divEnd + 6);

      // 提取作者
      const postAuthor = this.extractAuthor(postHtml);
      if (postAuthor !== targetAuthor) {
        pos = divEnd + 6;
        continue;
      }

      // 提取正文
      const content = this.extractContent(postHtml);
      if (content && content.length >= this.MIN_CONTENT_LENGTH) {
        const time = this.extractTime(postHtml);
        posts.push({ postId, time, content });
      }

      pos = divEnd + 6;
    }

    return posts;
  }

  private extractAuthor(postHtml: string): string {
    const idx = postHtml.indexOf('class="ui-link"');
    if (idx === -1) return '';
    const textStart = postHtml.indexOf('>', idx) + 1;
    const textEnd   = postHtml.indexOf('<', textStart);
    if (textStart > 0 && textEnd > textStart) {
      return postHtml.substring(textStart, textEnd).trim();
    }
    return '';
  }

  private extractContent(postHtml: string): string {
    const bodyStartIdx = postHtml.indexOf('<div class="card-body"');
    if (bodyStartIdx === -1) return '';

    const contentStart = postHtml.indexOf('>', bodyStartIdx) + 1;
    let depth = 1;
    let pos = contentStart;
    const len = postHtml.length;

    while (depth > 0 && pos < len) {
      const openIdx  = postHtml.indexOf('<div', pos);
      const closeIdx = postHtml.indexOf('</div>', pos);
      if (closeIdx === -1) break;

      if (openIdx !== -1 && openIdx < closeIdx) {
        depth++;
        pos = openIdx + 4;
      } else {
        depth--;
        if (depth === 0) {
          let rawContent = postHtml.substring(contentStart, closeIdx);
          rawContent = this.removeBlockquotes(rawContent);
          return this.cleanHtmlContent(rawContent);
        }
        pos = closeIdx + 6;
      }
    }
    return '';
  }

  private removeBlockquotes(html: string): string {
    let result = html;
    let start = result.indexOf('<blockquote');
    while (start !== -1) {
      let depth = 1;
      let pos = result.indexOf('>', start) + 1;
      while (depth > 0 && pos < result.length) {
        const open  = result.indexOf('<blockquote', pos);
        const close = result.indexOf('</blockquote>', pos);
        if (close === -1) break;
        if (open !== -1 && open < close) {
          depth++;
          pos = open + 11;
        } else {
          depth--;
          if (depth === 0) {
            result = result.substring(0, start) + result.substring(close + 13);
            break;
          }
          pos = close + 13;
        }
      }
      start = result.indexOf('<blockquote');
    }
    return result;
  }

  private extractTime(postHtml: string): string {
    const timeIdx = postHtml.indexOf('<time');
    if (timeIdx === -1) return '';
    const datetimeIdx = postHtml.indexOf('datetime="', timeIdx);
    if (datetimeIdx === -1) return '';
    const valStart = datetimeIdx + 10;
    const valEnd   = postHtml.indexOf('"', valStart);
    if (valEnd > valStart) {
      return postHtml.substring(valStart, valEnd);
    }
    return '';
  }

  private cleanHtmlContent(html: string): string {
    if (!html) return '';
    let text = html;
    text = text.replace(/<br\s*\/?>/gi, '\n');
    text = text.replace(/<\/p>\s*<p[^>]*>/gi, '\n\n');
    text = text.replace(/<\/?p[^>]*>/gi, '');
    text = text.replace(/<[^>]+>/g, '');

    const entities: Record<string, string> = {
      '&nbsp;': ' ', '&lt;': '<', '&gt;': '>', '&amp;': '&',
      '&quot;': '"', '&#39;': "'", '&mdash;': '—', '&ndash;': '–',
      '&hellip;': '…', '&ldquo;': '\u201c', '&rdquo;': '\u201d',
      '&lsquo;': '\u2018', '&rsquo;': '\u2019'
    };
    for (const entry of Object.entries(entities)) {
      text = text.split(entry[0]).join(entry[1]);
    }

    text = text.replace(/\n[ \t]+\n/g, '\n\n');
    text = text.replace(/[ \t]+/g, ' ');
    text = text.replace(/\n{4,}/g, '\n\n\n');
    return text.trim();
  }

  // ─── 【核心修复】从旧 TXT 中恢复章节列表 ──────────────────────────────
  /**
   * 对齐 Python 版 get_old_chapters_from_txt：
   * 用 【章节 N】 作为分隔符 split，取 index≥1 的部分 strip 后返回。
   * 不做二次 split，不过滤长度（已在写入时过滤过）。
   */
  private getOldChaptersFromTxt(txtPath: string): string[] {
    if (!fs.accessSync(txtPath)) return [];
    try {
      const content = fs.readTextSync(txtPath);
      // 以 【章节 数字】 为分隔符切割
      const parts = content.split(/【章节 \d+】/);
      // parts[0] 是书名/作者头部，从 parts[1] 开始是正文
      const chapters: string[] = [];
      for (let i = 1; i < parts.length; i++) {
        const stripped = parts[i].trim();
        // 去掉末尾的分割线（---- ... ----）
        const cleanedChapter = stripped.replace(/\n*-{10,}\n*$/, '').trim();
        if (cleanedChapter.length > 0) {
          chapters.push(cleanedChapter);
        }
      }
      console.log(`[DownloadService] 从 TXT 恢复旧章节: ${chapters.length} 章`);
      return chapters;
    } catch (e) {
      console.warn('[DownloadService] 读取旧 TXT 失败:', e);
      return [];
    }
  }

  // ─── 计算下次增量起始 offset ─────────────────────────────────────────────
  private calcLastPageOffset(_existingCount: number, _newCount: number): number {
    return 0;
  }

  // ─── 【核心修复】持久化：正确拼合旧章节 + 新章节 ───────────────────────
  private async saveData(
    threadId: string,
    title: string,
    author: string,
    newPosts: DownloadedPost[],
    meta: ThreadMeta,
    metaPath: string,
    txtPath: string,
    isUpdateMode: boolean
  ): Promise<void> {
    const dir = `${this.context.filesDir}/threads`;
    if (!fs.accessSync(dir)) {
      fs.mkdirSync(dir);
    }

    // 用 post_id 去重（与 Python save_data 一致）
    const existingPostIds = new Set<string>(Object.keys(meta.posts));
    const newValidPosts = newPosts.filter(
      p => !existingPostIds.has(p.postId) && p.content.length >= this.MIN_CONTENT_LENGTH
    );

    // ── 拼合章节（对齐 Python save_data 逻辑） ──────────────────────────
    let finalContents: string[];

    if (isUpdateMode && fs.accessSync(txtPath) && Object.keys(meta.posts).length > 0) {
      // 增量模式：读取旧 TXT 恢复章节，追加新章节
      const oldChapters = this.getOldChaptersFromTxt(txtPath);
      finalContents = [...oldChapters, ...newValidPosts.map(p => p.content)];
      console.log(`[DownloadService] 增量拼合：旧 ${oldChapters.length} 章 + 新 ${newValidPosts.length} 章 = 共 ${finalContents.length} 章`);
    } else {
      // 全量模式
      finalContents = newPosts
        .filter(p => p.content.length >= this.MIN_CONTENT_LENGTH)
        .map(p => p.content);
      console.log(`[DownloadService] 全量保存：共 ${finalContents.length} 章`);
    }

    // ── 写 TXT ───────────────────────────────────────────────────────────
    if (finalContents.length > 0) {
      let outText = `${title}\n作者: ${author}\n${'='.repeat(60)}\n\n`;
      finalContents.forEach((content, index) => {
        outText += `【章节 ${index + 1}】\n\n${content}\n\n${'-'.repeat(60)}\n\n`;
      });

      const file = fs.openSync(txtPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, outText);
      fs.closeSync(file);
      console.log(`[DownloadService] TXT 写入完成: ${txtPath}`);
    }

    // ── 写 Meta JSON（合并 posts） ────────────────────────────────────────
    const newIdsDict: Record<string, PostTimeInfo> = {};
    newPosts.forEach(p => {
      newIdsDict[p.postId] = { time: p.time };
    });

    // 合并旧 posts + 新 posts
    const allPosts: Record<string, PostTimeInfo> = {};
    for (const key of Object.keys(meta.posts)) {
      allPosts[key] = meta.posts[key];
    }
    for (const key of Object.keys(newIdsDict)) {
      allPosts[key] = newIdsDict[key];
    }

    meta.title        = title;   // 更新可能变化的标题
    meta.author       = author;
    meta.lastUpdate   = new Date().toISOString();
    meta.lastPageOffset = this.calcLastPageOffset(
      Object.keys(meta.posts).length,
      Object.keys(newIdsDict).length
    );
    meta.posts = allPosts;

    const metaFile = fs.openSync(metaPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(metaFile.fd, JSON.stringify(meta, null, 2));
    fs.closeSync(metaFile);
    console.log(`[DownloadService] Meta 写入完成，总楼层: ${Object.keys(allPosts).length}`);
  }

  // ─── 工具 ────────────────────────────────────────────────────────────────
  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  // ─── 查询本地已下载列表 ──────────────────────────────────────────────────
  public getDownloadedThreadIds(): string[] {
    const dir = `${this.context.filesDir}/threads`;
    if (!fs.accessSync(dir)) return [];
    try {
      const files = fs.listFileSync(dir);
      return files
        .filter((f: string) => f.endsWith('_meta.json'))
        .map((f: string) => f.replace('_meta.json', ''));
    } catch (e) {
      return [];
    }
  }

  public isDownloaded(threadId: string): boolean {
    return fs.accessSync(`${this.context.filesDir}/threads/${threadId}.txt`);
  }

  public readLocalContent(threadId: string): string {
    const path = `${this.context.filesDir}/threads/${threadId}.txt`;
    if (!fs.accessSync(path)) return '';
    try {
      return fs.readTextSync(path);
    } catch (e) {
      return '';
    }
  }

  public getLocalMeta(threadId: string): ThreadMeta | null {
    const path = `${this.context.filesDir}/threads/${threadId}_meta.json`;
    if (!fs.accessSync(path)) return null;
    try {
      return JSON.parse(fs.readTextSync(path)) as ThreadMeta;
    } catch (e) {
      return null;
    }
  }
}