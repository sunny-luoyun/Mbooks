// entry/src/main/ets/pages/DetailPage.ets
import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { CrawlerService } from '../services/CrawlerService';
import { SettingsService } from '../services/SettingsService';
import { ThreadItem } from '../models/SettingsModels';
import http from '@ohos.net.http';
import fs from '@ohos.file.fs';
import { DownloadService } from '../services/DownloadService';
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';

interface ThreadDetail {
  threadId: string;
  title: string;
  author: string;
  tags: string[];
  posts: PostContent[];
  totalPosts: number;
}

interface PostContent {
  pid: string;
  author: string;
  content: string;
  time: string;
}

@Entry
@Component
struct DetailPage {
  @StorageProp('currentColorMode') currentMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  // ✅ 新增：从 AppStorage 读取状态栏高度（由 EntryAbility 写入）
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  @State threadId: string = '';
  @State title: string = '';
  @State threadDetail: ThreadDetail | null = null;
  @State isLoading: boolean = false;
  @State isDownloading: boolean = false;
  @State downloadProgress: number = 0;
  @State isWatchedAuthor: boolean = false;
  @State isWatchedBook: boolean = false;
  @State errorMsg: string = '';
  @State fullContent: string = '';           // 完整内容（仅用于分段加载）
  @State displayContent: string = '';        // 当前显示的内容
  @State currentChunk: number = 1;           // 当前已加载的块数
  @State hasMore: boolean = false;           // 是否还有更多内容
  private readonly CHUNK_SIZE: number = 20000; // 每块字符数（可根据屏幕性能调整）

  private crawler: CrawlerService | null = null;
  private settings: SettingsService | null = null;
  private readonly BASE_URL = "https://mirror.chromaso.net";
  private downloadService: DownloadService | null = null;

  isDarkMode(): boolean {
    return this.currentMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object>;
    if (params) {
      this.threadId = (params['threadId'] as string) || '';
      this.title = (params['title'] as string) || '';
    }

    const context = getContext(this) as Context;
    this.crawler = new CrawlerService(context);
    this.settings = SettingsService.getInstance(context);
    this.downloadService = DownloadService.getInstance(context);

    this.loadDetail();
    this.checkWatchStatus();
  }

  async loadDetail(): Promise<void> {
    this.isLoading = true;
    this.errorMsg = '';

    const maxRetry = 2;
    for (let attempt = 0; attempt <= maxRetry; attempt++) {
      try {
        const localInfo = this.getLocalThreadInfo();
        const content = await this.fetchContent();

        const errorPrefixes = ['未找到', '获取内容失败', '解析内容失败', '内容为空', '下载失败'];
        const isError = !content ||
          content.length < 30 ||
        errorPrefixes.some(prefix => content.startsWith(prefix));

        if (!isError) {
          // ✅ 新逻辑：存储完整内容，并初始化分块显示
          this.fullContent = content;                     // 保存完整内容
          this.hasMore = content.length > this.CHUNK_SIZE; // 判断是否需要“加载更多”
          this.currentChunk = 1;                           // 当前显示到第1块

          // 截取第一块内容作为显示内容
          this.displayContent = content.substring(0, this.CHUNK_SIZE);

          // 获取本地信息（用于填充作者、标签等）
          const localInfo = this.getLocalThreadInfo();

          // 构建 threadDetail，并将 content 设置为 this.displayContent
          this.threadDetail = {
            threadId: this.threadId,
            title: localInfo?.title || this.title,
            author: localInfo?.author || '未知',
            tags: localInfo?.tags || [],
            posts: [{
              pid: localInfo?.lastPid || '1',
              author: localInfo?.author || '未知',
              content: this.displayContent,   // ⭐ 注意这里不再是完整内容，而是片段
              time: localInfo?.lastTime || '未知'
            }],
            totalPosts: 1
          };

          this.isLoading = false;
          return; // 成功返回
        } else {
          if (attempt < maxRetry) {
            console.warn(`[DetailPage] 内容加载异常，第${attempt + 1}次重试，原因: ${content?.substring(0, 80)}`);
            await new Promise<void>(resolve => setTimeout(resolve, 1000 * (attempt + 1)));
            continue;
          }
          this.errorMsg = `内容加载失败（已重试${maxRetry}次）: ` + (content?.substring(0, 60) || '空响应');
        }
      } catch (e) {
        console.error('[DetailPage] loadDetail error:', e);
        if (attempt < maxRetry) {
          await new Promise<void>(resolve => setTimeout(resolve, 1000 * (attempt + 1)));
          continue;
        }
        this.errorMsg = '加载出错: ' + JSON.stringify(e);
      }
    }

    this.isLoading = false;
  }

  private getLocalThreadInfo(): ThreadItem | null {
    if (!this.crawler) return null;
    const results = this.crawler.searchLocal(this.threadId);
    if (results.length > 0) {
      const item = results[0];
      return {
        threadId: item.threadId,
        title: item.title,
        author: item.author,
        lastPid: item.lastPid,
        lastTime: item.lastTime,
        tags: item.tags,
        createTime: item.createTime || '',
        isNew: item.isNew,
        isUpdated: item.isUpdated,
        prevLastPid: item.prevLastPid,
        prevLastTime: item.prevLastTime
      };
    }
    return null;
  }

  private async fetchContent(): Promise<string> {
    const localContent = await this.readLocalContent();
    if (localContent) return localContent;
    return await this.fetchFromNetwork();
  }

  private async readLocalContent(): Promise<string | null> {
    try {
      const filePath = `${(getContext(this) as Context).filesDir}/threads/${this.threadId}.txt`;
      if (fs.accessSync(filePath)) {
        // 使用异步读取，返回 Promise<string>
        return await fs.readText(filePath);
      }
    } catch (e) {
      console.log('No local file:', e);
    }
    return null;
  }

  private async fetchFromNetwork(): Promise<string> {
    const url = `${this.BASE_URL}/thread/${this.threadId}`;
    const httpRequest = http.createHttp();

    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
          'Accept-Encoding': 'identity',
          'Referer': this.BASE_URL + '/',
          'Connection': 'keep-alive',
          'Cache-Control': 'no-cache',
        },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 30000,
      });

      if (response.responseCode === 200) {
        const html = response.result as string;
        if (!html || html.length < 200) {
          return '获取内容失败: 响应内容过短（' + (html?.length || 0) + ' bytes）';
        }
        return this.parseContentFromHtml(html);
      } else if (response.responseCode === 404) {
        return '获取内容失败: 帖子不存在（404）';
      } else {
        return '获取内容失败: HTTP ' + response.responseCode;
      }
    } catch (err) {
      console.error('[DetailPage] Network fetch error:', err);
      return '获取内容失败: 网络错误 ' + JSON.stringify(err);
    } finally {
      httpRequest.destroy();
    }
  }

  private parseContentFromHtml(html: string): string {
    try {
      const postStart = html.indexOf('<div id="p');
      if (postStart !== -1) {
        const cardBodyIdx = html.indexOf('<div class="card-body"', postStart);
        if (cardBodyIdx !== -1) {
          const result = this.extractDivContent(html, cardBodyIdx);
          if (result && result.length > 20) {
            return this.cleanHtmlContent(result);
          }
        }
      }

      const firstCardBody = html.indexOf('<div class="card-body"');
      if (firstCardBody !== -1) {
        const result = this.extractDivContent(html, firstCardBody);
        if (result && result.length > 20) {
          return this.cleanHtmlContent(result);
        }
      }

      const rootIdx = html.indexOf('class="root container"');
      if (rootIdx !== -1) {
        const endIdx = html.indexOf('</div>', rootIdx + 500);
        if (endIdx !== -1) {
          return this.cleanHtmlContent(html.substring(rootIdx, endIdx));
        }
      }

      return '未找到帖子内容（页面结构不匹配）';
    } catch (e) {
      return '解析内容失败: ' + JSON.stringify(e);
    }
  }

  private extractDivContent(html: string, divStartIdx: number): string | null {
    try {
      const contentStart = html.indexOf('>', divStartIdx) + 1;
      if (contentStart <= 0) return null;

      let depth = 1;
      let pos = contentStart;
      const maxLen = Math.min(html.length, contentStart + 500000);

      while (depth > 0 && pos < maxLen) {
        const nextOpen = html.indexOf('<div', pos);
        const nextClose = html.indexOf('</div>', pos);

        if (nextClose === -1) break;

        if (nextOpen !== -1 && nextOpen < nextClose) {
          depth++;
          pos = nextOpen + 4;
        } else {
          depth--;
          if (depth === 0) {
            return html.substring(contentStart, nextClose);
          }
          pos = nextClose + 6;
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  private cleanHtmlContent(html: string): string {
    if (!html) return '内容为空';
    let text = html;
    const brRegex = new RegExp('<br\\s*/?>', 'gi');
    text = text.replace(brRegex, '\n');
    const pCloseOpenRegex = new RegExp('</p>\\s*<p[^>]*>', 'gi');
    text = text.replace(pCloseOpenRegex, '\n\n');
    const pOpenRegex = new RegExp('<p[^>]*>', 'gi');
    text = text.replace(pOpenRegex, '');
    const pCloseRegex = new RegExp('</p>', 'gi');
    text = text.replace(pCloseRegex, '');
    const tagRegex = new RegExp('<[^>]+>', 'g');
    text = text.replace(tagRegex, '');
    const entities: Record<string, string> = {
      '&nbsp;': ' ', '&lt;': '<', '&gt;': '>', '&amp;': '&', '&quot;': '"',
      '&#39;': "'", '&mdash;': '—', '&ndash;': '–', '&hellip;': '…',
      '&ldquo;': '"', '&rdquo;': '"', '&lsquo;': "", '&rsquo;': ""
    };
    for (const entry of Object.entries(entities)) {
      text = text.replace(new RegExp(entry[0], 'g'), entry[1]);
    }
    const decRegex = new RegExp('&#(\\d+);', 'g');
    text = text.replace(decRegex, (match: string, dec: string) => String.fromCharCode(parseInt(dec)));
    const hexRegex = new RegExp('&#x([0-9a-f]+);', 'gi');
    text = text.replace(hexRegex, (match: string, hex: string) => String.fromCharCode(parseInt(hex, 16)));
    text = text.replace(/\n[ \t]+\n/g, '\n\n');
    text = text.replace(/[ \t]+/g, ' ');
    text = text.replace(/\n{4,}/g, '\n\n\n');
    return text.trim();
  }

  checkWatchStatus(): void {
    if (!this.settings) return;
    const localInfo = this.getLocalThreadInfo();
    if (localInfo) {
      this.isWatchedAuthor = this.settings.isWatchedAuthor(localInfo.author);
    }
    this.isWatchedBook = this.settings.isWatchedBook(this.threadId);
  }

  toggleWatchAuthor(): void {
    if (!this.settings || !this.threadDetail) return;
    if (this.isWatchedAuthor) {
      this.settings.removeWatchedAuthor(this.threadDetail.author);
      promptAction.showToast({ message: '已取消关注作者' });
    } else {
      this.settings.addWatchedAuthor(this.threadDetail.author, true);
      promptAction.showToast({ message: '已关注作者' });
    }
    this.isWatchedAuthor = !this.isWatchedAuthor;
  }

  toggleWatchBook(): void {
    if (!this.settings) return;
    if (this.isWatchedBook) {
      this.settings.removeWatchedBook(this.threadId);
      promptAction.showToast({ message: '已取消关注帖子' });
    } else {
      this.settings.addWatchedBook(this.threadId, this.title, false);
      promptAction.showToast({ message: '已关注帖子' });
    }
    this.isWatchedBook = !this.isWatchedBook;
  }

  async downloadContent(): Promise<void> {
    if (this.isDownloading || !this.downloadService || !this.threadDetail) return;
    this.isDownloading = true;
    this.downloadProgress = 0;
    const author = this.threadDetail.author !== '未知' ? this.threadDetail.author : '楼主';
    try {
      const success = await this.downloadService.downloadThread(
        this.threadId, this.threadDetail.title, author,
        (p: number) => { this.downloadProgress = p; }
      );
      if (success) {
        promptAction.showToast({ message: '✨ 下载/更新完成！' });
        this.loadDetail();
      } else {
        promptAction.showToast({ message: '⚠️ 下载失败' });
      }
    } catch (e) {
      promptAction.showToast({ message: '⚠️ 下载发生异常' });
    } finally {
      this.isDownloading = false;
      this.downloadProgress = 0;
    }
  }

  @Builder
  HeaderBar() {
    Row() {
      Text('❮ 返回')
        .fontSize(16)
        .fontColor(this.isDarkMode() ? '#409EFF' : '#007DFF')
        .onClick(() => router.back())
      Blank()
      Text('帖子详情')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.isDarkMode() ? '#E5E5E5' : '#1A1A1A')
      Blank()
      Text('    ').fontSize(16)
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      // ✅ 核心改动：顶部 padding 加上状态栏高度，防止标题行被状态栏遮住
      // px2vp() 将物理像素转换为虚拟像素，保证不同分辨率屏幕下显示一致
      top: 12 + px2vp(this.statusBarHeight),
      bottom: 12
    })
    .backgroundColor(this.isDarkMode() ? '#1A1A1A' : '#FFFFFF')
    // ✅ 让 HeaderBar 背景色向上延伸填满状态栏区域，实现与状态栏"融为一体"的效果
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }

  @Builder
  ActionButtons() {
    Row({ space: 12 }) {
      Button(this.isWatchedAuthor ? '⭐ 已关注作者' : '关注作者')
        .fontSize(14)
        .fontColor(this.isWatchedAuthor ? (this.isDarkMode() ? '#73D13D' : '#52C41A') : '#007DFF')
        .backgroundColor(this.isWatchedAuthor ? (this.isDarkMode() ? '#1C2D12' : '#F6FFED') : (this.isDarkMode() ? '#1A2B3C' : '#E6F2FF'))
        .layoutWeight(1)
        .height(44)
        .borderRadius(8)
        .onClick(() => this.toggleWatchAuthor())

      Button(this.isWatchedBook ? '📚 已关注' : '关注帖子')
        .fontSize(14)
        .fontColor(this.isWatchedBook ? (this.isDarkMode() ? '#FFBB96' : '#FA8C16') : '#007DFF')
        .backgroundColor(this.isWatchedBook ? (this.isDarkMode() ? '#3E2613' : '#FFF7E6') : (this.isDarkMode() ? '#1A2B3C' : '#E6F2FF'))
        .layoutWeight(1)
        .height(44)
        .borderRadius(8)
        .onClick(() => this.toggleWatchBook())
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
  }

  @Builder
  DownloadSection() {
    Column() {
      if (this.isDownloading) {
        Column() {
          Text('正在下载...')
            .fontSize(14)
            .fontColor(this.isDarkMode() ? '#999' : '#666')
          Progress({ value: this.downloadProgress, total: 100, type: ProgressType.Linear })
            .width('100%')
            .margin({ top: 12 })
        }
        .width('100%')
        .padding(16)
        .backgroundColor(this.isDarkMode() ? '#2A2A2A' : '#F5F5F5')
        .borderRadius(8)
      } else {
        Button('📥 下载到本地')
          .width('100%')
          .height(50)
          .fontSize(16)
          .backgroundColor(this.isDarkMode() ? '#1E5CAB' : '#007DFF')
          .borderRadius(8)
          .enabled(!this.isLoading)
          .onClick(() => this.downloadContent())
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
  }

  @Builder
  LoadMoreButton() {
    if (this.hasMore) {
      Button(`加载更多 (已显示 ${this.currentChunk * this.CHUNK_SIZE} 字符)`)
        .fontSize(14)
        .width('100%')
        .onClick(() => {
          // 计算下一块的结束位置
          const end = Math.min((this.currentChunk + 1) * this.CHUNK_SIZE, this.fullContent.length);
          // 更新显示内容（这里采用“追加”方式，即一直显示到最新的 end）
          this.displayContent = this.fullContent.substring(0, end);
          this.currentChunk++;
          this.hasMore = end < this.fullContent.length;

          // 更新 threadDetail 中的 content，触发界面刷新
          if (this.threadDetail) {
            this.threadDetail.posts[0].content = this.displayContent;
          }
        })
        .margin({ top: 12 });
    }
  }

  @Builder
  ContentPreview() {
    Column() {
      if (this.isLoading) {
        LoadingProgress().width(40).height(40)
        Text('加载中...').fontSize(14).fontColor('#999').margin({ top: 12 })
      } else if (this.errorMsg) {
        Column() {
          Text('⚠️ ' + this.errorMsg).fontSize(14).fontColor('#FF4D4F').textAlign(TextAlign.Center)
          Button('重新加载').margin({ top: 16 }).onClick(() => this.loadDetail())
        }.width('100%').padding(20)
      } else if (this.threadDetail) {
        Text(this.threadDetail.title)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.isDarkMode() ? '#E5E5E5' : '#1A1A1A')
          .width('100%')
          .margin({ bottom: 12 })

        Row() {
          Text('作者: ' + this.threadDetail.author)
            .fontSize(14)
            .fontColor(this.isDarkMode() ? '#999' : '#666')
          if (this.isWatchedAuthor) {
            Text(' ⭐').fontSize(12).fontColor('#52C41A')
          }
        }.width('100%').margin({ bottom: 8 })

        if (this.threadDetail.tags.length > 0) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.threadDetail.tags, (tag: string) => {
              Text(tag)
                .fontSize(10)
                .fontColor(this.isDarkMode() ? '#409EFF' : '#007DFF')
                .backgroundColor(this.isDarkMode() ? '#1A2B3C' : '#E6F2FF')
                .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                .borderRadius(4)
                .margin({ right: 8, bottom: 4 })
            }, (tag: string) => tag)
          }.width('100%').margin({ bottom: 12 })
        }

        Column() {
          Row() {
            Text('内容预览').fontSize(12).fontColor(this.isDarkMode() ? '#666' : '#999')
            Blank()
            Text('🔗 浏览器打开')
              .fontSize(12)
              .fontColor(this.isDarkMode() ? '#409EFF' : '#007DFF')
              .onClick(() => promptAction.showToast({ message: 'URL: ' + this.BASE_URL + '/thread/' + this.threadId }))
          }.width('100%').margin({ bottom: 8 })

          Scroll() {
            Text(this.threadDetail.posts[0].content)
              .fontSize(14)
              .fontColor(this.isDarkMode() ? '#CCCCCC' : '#333333')
              .width('100%')
              .lineHeight(24)
          }
          .width('100%')
          .height(400)
          .backgroundColor(this.isDarkMode() ? '#1A1A1A' : '#FFFFFF')
          .padding(8)
        }
        .width('100%')
        .padding(12)
        .backgroundColor(this.isDarkMode() ? '#242424' : '#F0F0F0')
        .borderRadius(8)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.isDarkMode() ? '#1A1A1A' : '#FFFFFF')
    .borderRadius(12)
  }

  build() {
    Column() {
      this.HeaderBar()
      Scroll() {
        Column({ space: 16 }) {
          this.ContentPreview()
          this.ActionButtons()
          this.DownloadSection()
          Text('💡 提示：关注作者可在"最新"页面高亮显示')
            .fontSize(12)
            .fontColor(this.isDarkMode() ? '#555' : '#999')
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ bottom: 32 })
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(this.isDarkMode() ? '#000000' : '#F5F5F5')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.isDarkMode() ? '#000000' : '#FFFFFF')
    // ✅ 整体容器向上扩展，配合 EntryAbility 的全屏布局，让背景色填满状态栏区域
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}