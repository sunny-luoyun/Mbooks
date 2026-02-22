// entry/src/main/ets/services/DownloadService.ets (修复版)

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

export interface PostDivInfo {
  id: string;
  html: string;
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
      const metaPath = `${this.context.filesDir}/threads/${threadId}_meta.json`;
      let meta: ThreadMeta = {
        threadId: threadId, title: title, author: author,
        lastUpdate: '', lastPageOffset: 0, posts: {}
      } as ThreadMeta;
      let existingPostIds = new Set<string>();

      if (fs.accessSync(metaPath)) {
        const metaStr = fs.readTextSync(metaPath);
        meta = JSON.parse(metaStr) as ThreadMeta;
        existingPostIds = new Set(Object.keys(meta.posts));
      }

      // 2. 请求第一页，获取总页数
      const firstHtml = await this.fetchHtml(`${this.BASE_URL}/thread/${threadId}`);
      if (!firstHtml) return false;

      const totalPages = this.getTotalPages(firstHtml);
      const startPage = Math.max(1, Math.min(Math.floor(meta.lastPageOffset / this.PAGE_SIZE) + 1, totalPages));

      let newPosts: DownloadedPost[] = [];

      // 3. 开始分页抓取
      for (let p = startPage; p <= totalPages; p++) {
        const progress = 5 + Math.floor(((p - startPage + 1) / (totalPages - startPage + 1)) * 85);
        onProgress(progress);

        const url = p > 1
          ? `${this.BASE_URL}/thread/${threadId}/+${(p - 1) * this.PAGE_SIZE}`
          : `${this.BASE_URL}/thread/${threadId}`;
        const html = p === 1 ? firstHtml : await this.fetchHtml(url);

        if (!html) continue;

        const pagePosts = this.parsePosts(html, author);
        const newOnPage = pagePosts.filter(post => !existingPostIds.has(post.postId));

        newPosts.push(...newOnPage);

        // 增量拦截：如果本页所有楼主楼层都已存在，停止扫描
        if (pagePosts.length > 0 && newOnPage.length === 0 && Object.keys(meta.posts).length > 0) {
          break;
        }

        if (p < totalPages) {
          await new Promise<void>(resolve => setTimeout(resolve, 500 + Math.random() * 500));
        }
      }

      // 4. 保存数据
      onProgress(95);
      if (newPosts.length > 0 || !fs.accessSync(`${this.context.filesDir}/threads/${threadId}.txt`)) {
        await this.saveData(threadId, title, author, newPosts, meta, metaPath);
      }

      onProgress(100);
      return true;

    } catch (e) {
      console.error('DownloadService Error:', e);
      return false;
    }
  }

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
      console.error(`Fetch error for ${url}:`, err);
      return null;
    } finally {
      httpRequest.destroy();
    }
  }

  private getTotalPages(html: string): number {
    let maxPage = 1;
    // 修复：使用 RegExp 构造函数替代正则字面量
    const regex = new RegExp('/thread/\\d+/\\+(\\d+)', 'g');
    let match: RegExpExecArray | null;

    while ((match = regex.exec(html)) !== null) {
      const offset = parseInt(match[1]);
      const page = Math.floor(offset / this.PAGE_SIZE) + 1;
      if (page > maxPage) maxPage = page;
    }
    return maxPage;
  }


  private parsePosts(html: string, targetAuthor: string): DownloadedPost[] {
    const posts: DownloadedPost[] = [];

    // 使用字符串扫描而非正则，避免灾难性回溯
    let pos = 0;
    const htmlLength = html.length;

    while (pos < htmlLength) {
      // 查找下一个帖子 div 开始
      const divStart = html.indexOf('<div id="p', pos);
      if (divStart === -1) break;

      // 提取 post ID
      const idStart = divStart + 10; // 跳过 '<div id="p'
      const idEnd = html.indexOf('"', idStart);
      if (idEnd === -1) break;

      const postId = 'p' + html.substring(idStart, idEnd);

      // 找到这个 div 的结束位置（找到对应的 </div>）
      let depth = 1;
      let searchPos = html.indexOf('>', idEnd) + 1; // 跳过开始标签
      let divEnd = searchPos;

      while (depth > 0 && searchPos < htmlLength) {
        const nextOpen = html.indexOf('<div', searchPos);
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

      // 提取作者 - 使用简单字符串查找
      const authorMatch = this.extractAuthor(postHtml);
      if (authorMatch !== targetAuthor) {
        pos = divEnd + 6;
        continue;
      }

      // 提取内容
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
    // 查找 <a class="ui-link"> 或 <a ... class="ui-link">
    const idx = postHtml.indexOf('class="ui-link"');
    if (idx === -1) return '';

    // 向前找 <a 标签开始
    const aStart = postHtml.lastIndexOf('<a', idx);
    if (aStart === -1) return '';

    // 向后找 > 和 <
    const textStart = postHtml.indexOf('>', idx) + 1;
    const textEnd = postHtml.indexOf('<', textStart);

    if (textStart > 0 && textEnd > textStart) {
      return postHtml.substring(textStart, textEnd).trim();
    }
    return '';
  }

  private extractContent(postHtml: string): string {
    // 找到 card-body
    const bodyStartIdx = postHtml.indexOf('<div class="card-body"');
    if (bodyStartIdx === -1) return '';

    const contentStart = postHtml.indexOf('>', bodyStartIdx) + 1;

    // 找到对应的 </div>（需要处理嵌套）
    let depth = 1;
    let pos = contentStart;
    const len = postHtml.length;

    while (depth > 0 && pos < len) {
      const openIdx = postHtml.indexOf('<div', pos);
      const closeIdx = postHtml.indexOf('</div>', pos);

      if (closeIdx === -1) break;

      if (openIdx !== -1 && openIdx < closeIdx) {
        depth++;
        pos = openIdx + 4;
      } else {
        depth--;
        if (depth === 0) {
          let rawContent = postHtml.substring(contentStart, closeIdx);

          // 剔除 blockquote
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
        const open = result.indexOf('<blockquote', pos);
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
    const valEnd = postHtml.indexOf('"', valStart);

    if (valEnd > valStart) {
      return postHtml.substring(valStart, valEnd);
    }
    return '';
  }

  private cleanHtmlContent(html: string): string {
    if (!html) return '';

    let text = html;

    // 替换 <br>
    text = text.replace(/<br\s*\/?>/gi, '\n');

    // 替换 <p> 标签
    text = text.replace(/<\/p>\s*<p[^>]*>/gi, '\n\n');
    text = text.replace(/<\/?p[^>]*>/gi, '');

    // 移除所有其他 HTML 标签
    text = text.replace(/<[^>]+>/g, '');

    // 解码 HTML 实体
    const entities: Record<string, string> = {
      '&nbsp;': ' ', '&lt;': '<', '&gt;': '>', '&amp;': '&',
      '&quot;': '"', '&#39;': "'", '&mdash;': '—', '&ndash;': '–',
      '&hellip;': '…', '&ldquo;': '“', '&rdquo;': '”',
      '&lsquo;': '‘', '&rsquo;': '’'
    };
    for (const entry of Object.entries(entities)) {
      text = text.split(entry[0]).join(entry[1]);
    }

    // 清理空白
    text = text.replace(/\n[ \t]+\n/g, '\n\n');
    text = text.replace(/[ \t]+/g, ' ');
    text = text.replace(/\n{4,}/g, '\n\n\n');

    return text.trim();
  }

  private async saveData(
    threadId: string,
    title: string,
    author: string,
    newPosts: DownloadedPost[],
    meta: ThreadMeta,
    metaPath: string
  ): Promise<void> {
    const dir = `${this.context.filesDir}/threads`;
    if (!fs.accessSync(dir)) {
      fs.mkdirSync(dir);
    }

    const txtPath = `${dir}/${threadId}.txt`;

    // 1. 拼接并保存 TXT
    let finalContents: string[] = [];
    if (fs.accessSync(txtPath) && Object.keys(meta.posts).length > 0) {
      // 增量模式：读取旧内容并分割章节
      const oldText = fs.readTextSync(txtPath);
      // 修复：使用 RegExp 构造函数
      const chapterRegex = new RegExp('【章节 \\d+】\\n\\n', 'g');
      const parts = oldText.split(chapterRegex);

      for (let i = 1; i < parts.length; i++) {
        // 去除末尾的分割线
        const separatorRegex = new RegExp('\\n\\n-{60}\\n\\n', 'g');
        const chapterParts = parts[i].split(separatorRegex);
        const chapterText = chapterParts[0];
        if (chapterText.trim().length >= this.MIN_CONTENT_LENGTH) {
          finalContents.push(chapterText.trim());
        }
      }
    }

    // 追加新章节
    newPosts.forEach(p => finalContents.push(p.content));

    // 写入新 TXT
    const file = fs.openSync(txtPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    let outText = `${title}\n作者: ${author}\n${"=".repeat(60)}\n\n`;

    finalContents.forEach((content, index) => {
      outText += `【章节 ${index + 1}】\n\n${content}\n\n${"-".repeat(60)}\n\n`;
    });

    fs.writeSync(file.fd, outText);
    fs.closeSync(file);

    // 2. 更新 Meta JSON
    const newIdsDict: Record<string, PostTimeInfo> = {};
    newPosts.forEach(p => {
      newIdsDict[p.postId] = { time: p.time };
    });
    // 合并 posts
    const allPosts: Record<string, PostTimeInfo> = {};
    // 复制 meta.posts 到 allPosts
    const metaPostKeys = Object.keys(meta.posts);
    for (let i = 0; i < metaPostKeys.length; i++) {
      const key = metaPostKeys[i];
      allPosts[key] = meta.posts[key];
    }
    // 复制 newIdsDict 到 allPosts
    const newIdsKeys = Object.keys(newIdsDict);
    for (let i = 0; i < newIdsKeys.length; i++) {
      const key = newIdsKeys[i];
      allPosts[key] = newIdsDict[key];
    }
    const totalPosts = Object.keys(allPosts).length;

    meta.lastUpdate = new Date().toISOString();
    meta.lastPageOffset = totalPosts <= this.PAGE_SIZE
      ? 0
      : Math.max(0, Math.floor(totalPosts / this.PAGE_SIZE) - 1) * this.PAGE_SIZE;
    meta.posts = allPosts;

    const metaFile = fs.openSync(metaPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(metaFile.fd, JSON.stringify(meta, null, 2));
    fs.closeSync(metaFile);
  }
}