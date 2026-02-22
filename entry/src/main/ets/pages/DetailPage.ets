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
  // 监听系统颜色模式变化
  @StorageProp('currentColorMode') currentMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  @State threadId: string = '';
  @State title: string = '';
  @State threadDetail: ThreadDetail | null = null;
  @State isLoading: boolean = false;
  @State isDownloading: boolean = false;
  @State downloadProgress: number = 0;
  @State isWatchedAuthor: boolean = false;
  @State isWatchedBook: boolean = false;
  @State errorMsg: string = '';

  private crawler: CrawlerService | null = null;
  private settings: SettingsService | null = null;
  private readonly BASE_URL = "https://mirror.chromaso.net";
  private downloadService: DownloadService | null = null;

  // 辅助函数：判断是否为深色模式
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

    try {
      const localInfo = this.getLocalThreadInfo();
      const content = await this.fetchContent();

      if (content && content.length > 50 && !content.includes('失败')) {
        this.threadDetail = {
          threadId: this.threadId,
          title: localInfo?.title || this.title,
          author: localInfo?.author || '未知',
          tags: localInfo?.tags || [],
          posts: [{
            pid: localInfo?.lastPid || '1',
            author: localInfo?.author || '未知',
            content: content,
            time: localInfo?.lastTime || '未知'
          }],
          totalPosts: 1
        };
      } else {
        this.errorMsg = '内容太短或加载失败: ' + (content?.substring(0, 50) || '空');
      }
    } catch (e) {
      console.error('Load detail error:', e);
      this.errorMsg = '加载出错';
    } finally {
      this.isLoading = false;
    }
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
        lastUser: item.lastUser || item.author,
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
        return fs.readTextSync(filePath);
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
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.0.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9',
        },
        expectDataType: http.HttpDataType.STRING
      });

      if (response.responseCode === 200) {
        const html = response.result as string;
        return this.parseContentFromHtml(html);
      } else {
        return '获取内容失败: HTTP ' + response.responseCode;
      }
    } catch (err) {
      console.error('Network fetch error:', err);
      return '获取内容失败: 网络错误';
    } finally {
      httpRequest.destroy();
    }
  }

  private parseContentFromHtml(html: string): string {
    try {
      const postStart = html.indexOf('<div id="p');
      if (postStart === -1) return '未找到帖子内容';
      const cardBodyIdx = html.indexOf('<div class="card-body"', postStart);
      if (cardBodyIdx === -1) return '未找到内容区域';
      const contentStart = html.indexOf('>', cardBodyIdx) + 1;
      let depth = 1;
      let pos = contentStart;
      while (depth > 0 && pos < html.length) {
        const open = html.indexOf('<div', pos);
        const close = html.indexOf('</div>', pos);
        if (close === -1) break;
        if (open !== -1 && open < close) {
          depth++;
          pos = open + 4;
        } else {
          depth--;
          if (depth === 0) {
            const content = html.substring(contentStart, close);
            return this.cleanHtmlContent(content);
          }
          pos = close + 6;
        }
      }
      return '解析内容失败: 无法确定内容边界';
    } catch (e) {
      return '解析内容失败: ' + JSON.stringify(e);
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
      '&ldquo;': '“', '&碰rdquo;': '”', '&lsquo;': '‘', '&rsquo;': '’'
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
    .padding(16)
    .backgroundColor(this.isDarkMode() ? '#1A1A1A' : '#FFFFFF')
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
  }
}