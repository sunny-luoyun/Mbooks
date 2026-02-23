// entry/src/main/ets/pages/PixivNovelReaderPage.ets

import router from '@ohos.router';
import web_webview from '@ohos.web.webview';
import promptAction from '@ohos.promptAction';
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';
import common from '@ohos.app.ability.common';
import { pixivCacheDB } from '../database/PixivCacheDB';
import util from '@ohos.util';
import fs from '@ohos.file.fs';

// ========================================
// 路由参数类型
// ========================================

interface ReaderRouterParams {
  novelId:    string;
  title:      string;
  author:     string;
  offline:    boolean;     // true = 离线渲染，false = WebView 在线
       // offline=true 时传入正文
}

// ========================================
// 阅读器颜色配置
// ========================================

interface ReaderColors {
  pageBg:        string;
  headerBg:      string;
  primaryText:   string;
  secondaryText: string;
  accentText:    string;
  divider:       string;
  iconBtnBg:     string;
  iconBtnText:   string;
}

function getReaderColors(mode: number): ReaderColors {
  const isDark = mode === 0;
  return {
    pageBg:        isDark ? '#0D0D0D' : '#F1F3F5',
    headerBg:      isDark ? '#141414' : '#FFFFFF',
    primaryText:   isDark ? '#E6E6E6' : '#1A1A1A',
    secondaryText: isDark ? '#888888' : '#666666',
    accentText:    '#007DFF',
    divider:       isDark ? '#2A2A2A' : '#E5E5E5',
    iconBtnBg:     isDark ? '#2A2A2A' : '#F0F0F0',
    iconBtnText:   isDark ? '#CCCCCC' : '#444444',
  };
}

// ========================================
// Pixiv 正文标记解析
// ========================================

// Pixiv 小说正文特殊标记处理器
function parsePixivContent(raw: string, isDark: boolean): string {
  if (!raw) return '';

  const textColor    = isDark ? '#E6E6E6' : '#1A1A1A';
  const bgColor      = isDark ? '#0D0D0D' : '#F9F7F2';
  const chapterColor = isDark ? '#AADDFF' : '#0055AA';
  const hrColor      = isDark ? '#333333' : '#DDDDDD';
  const rubyColor    = isDark ? '#AAAAAA' : '#888888';

  let content = raw
  // 分页符 → 水平分割线
    .replace(/\[newpage\]/g,
      `<div class="page-break"><hr style="border:none;border-top:1px solid ${hrColor};margin:32px 0;"/></div>`)

    // 章节标题 [chapter:xxx]
    .replace(/\[chapter:(.*?)\]/g,
      `<h2 style="color:${chapterColor};font-size:1.15em;font-weight:bold;
        margin:28px 0 14px;padding-left:10px;
        border-left:3px solid ${chapterColor};">$1</h2>`)

    // 傍点强调 [[rb:文字>注音]]
    .replace(/\[\[rb:(.*?)>(.*?)\]\]/g,
      `<ruby>$1<rt style="color:${rubyColor};font-size:0.6em;">$2</rt></ruby>`)

    // 粗体 [b]...[/b]
    .replace(/\[b\]([\s\S]*?)\[\/b\]/g,
      `<strong>$1</strong>`)

    // 斜体 [i]...[/i]
    .replace(/\[i\]([\s\S]*?)\[\/i\]/g,
      `<em>$1</em>`)

    // 链接 [jump:xxx]
    .replace(/\[jump:(.*?)\]/g, '')

    // 换行
    .replace(/\n/g, '<br/>');

  return `<!DOCTYPE html>
<html lang="zh">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1.0,user-scalable=yes"/>
  <title>阅读</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }

    body {
      background-color: ${bgColor};
      color: ${textColor};
      font-family: "Noto Serif CJK SC", "Source Han Serif CN",
                   "PingFang SC", serif;
      font-size: 18px;
      line-height: 1.9;
      padding: 20px 20px 60px;
      word-break: break-all;
      -webkit-text-size-adjust: 100%;
    }

    /* 段落间距 */
    br + br { display: block; content: ''; margin-top: 0.5em; }

    /* 章节标题已内联样式，此处备用 */
    h2 { line-height: 1.4; }

    /* 分页符容器 */
    .page-break { margin: 24px 0; }

    /* 选中文字颜色 */
    ::selection { background: #007DFF44; }

    /* 滚动条（WebView 内） */
    ::-webkit-scrollbar { width: 4px; }
    ::-webkit-scrollbar-thumb {
      background: ${isDark ? '#444' : '#CCC'};
      border-radius: 2px;
    }
  </style>
</head>
<body>
  ${content}
</body>
</html>`;
}


// ========================================
// 页面主体
// ========================================

@Entry
@Component
struct PixivNovelReaderPage {

  // ── 路由参数 ──
  private params: ReaderRouterParams | null = null;

  // ✅ 新增：用 @State 存需要在 build() 里用到的路由参数
  @State private offlineMode:  boolean = false;
  @State @Watch('onCachedTextReady') private cachedText: string = '';
  @State private isOfflineReady: boolean = false; // 新增：控制 WebView 是否渲染
  @State private novelTitle:   string  = '小说阅读';
  @State private novelAuthor:  string  = '';

  // ── WebView 控制器 ──
  private webController: web_webview.WebviewController =
    new web_webview.WebviewController();

  private onCachedTextReady(): void {
    const TAG = '[PixivReader][onCachedTextReady]';
    if (!this.cachedText) return;
    this.isOfflineReady = true;
    if (this.isControllerReady) {
      console.info(`${TAG} 控制器已就绪，写文件并 loadUrl`);
      this.loadOfflineHtmlFile();
    }
  }

  // ── 状态 ──
  @State colorMode:      number  = 0;
  @State isPageLoading:  boolean = true;   // WebView 加载中
  @State loadProgress:   number  = 0;      // WebView 加载进度 0~100
  @State showFontPanel:  boolean = false;  // 字体调节面板
  @State fontSize:       number  = 18;     // 当前字号（px）

  // ── 安全区 ──
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  // ── 颜色模式监听 ──
  private configCallbackId: number = -1;
  private configChangeCallback: () => void = () => {};

  private async loadCachedTextFromDB(novelId: string): Promise<void> {
    const TAG = '[PixivReader][loadCachedTextFromDB]';
    console.info(`${TAG} 开始读取，novelId=${novelId}`);

    const ctx = getContext(this) as common.UIAbilityContext;

    console.info(`${TAG} 调用 pixivCacheDB.init ...`);
    await pixivCacheDB.init(ctx);
    await pixivCacheDB.debugGetNovelRaw(novelId);
    console.info(`${TAG} pixivCacheDB.init 完成`);

    const text = await pixivCacheDB.getFullText(novelId);
    console.info(`${TAG} getFullText 返回: ${text ? '有内容，长度=' + text.length : 'null/空'}`);

    if (!text) {
      console.error(`${TAG} ❌ 正文为空！novelId=${novelId} 未缓存或 cache_status 不是 CACHED`);
      promptAction.showToast({ message: '缓存内容丢失，请重新缓存' });
      router.back();
      return;
    }

    console.info(`${TAG} ✅ 即将赋值 cachedText，长度=${text.length}`);
    this.cachedText = text;
  }

  // ========================================
  // 生命周期
  // ========================================
  aboutToAppear(): void {
    const TAG = '[PixivReader][aboutToAppear]';
    const ctx = getContext(this) as common.UIAbilityContext;
    this.colorMode = ctx.config?.colorMode ?? 0;
    this.params = router.getParams() as ReaderRouterParams;

    // ✅ 赋值到 @State 字段，触发重渲染
    this.offlineMode  = this.params?.offline === true || String(this.params?.offline) === 'true';

    this.novelTitle   = this.params?.title  ?? '小说阅读';
    this.novelAuthor  = this.params?.author ?? '';

    if (this.offlineMode && this.params?.novelId) {
      // ✅ 从 DB 读，不从路由参数读
      this.loadCachedTextFromDB(this.params.novelId);
    }

    console.info(`${TAG} params = ${JSON.stringify(this.params)}`);
    console.info(`${TAG} offline = ${this.params?.offline}, novelId = ${this.params?.novelId}`);

    // 如果是在线模式，预先构造好 URL
    if (this.params && !this.params.offline) {
      const id = this.params.novelId;
      console.info(`${TAG} 在线模式，novelId=${id}`);
      if (id) {
        this.novelUrl = `https://www.pixiv.net/novel/show.php?id=${id}`;
        console.info(`${TAG} 构造 novelUrl = ${this.novelUrl}`);
      } else {
        console.error(`${TAG} ❌ novelId 为空，无法构造 URL`);
        promptAction.showToast({ message: '小说ID无效' });
      }

      // ✅ 提前注入一次 Cookie（WebCookieManager 是全局的，不依赖 WebView 实例）
      this.injectCookie();
    }

    this.configChangeCallback = () => {
      this.colorMode = ctx.config?.colorMode ?? 0;
    };
    this.configCallbackId = ctx.getApplicationContext().on('environment', {
      onConfigurationUpdated: this.configChangeCallback,
      onMemoryLevel: (_level: number) => {}
    });

  }

  aboutToDisappear(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    if (this.configCallbackId !== -1) {
      ctx.getApplicationContext().off('environment', this.configCallbackId);
    }
  }

  // ========================================
  // 工具
  // ========================================

  private getColors(): ReaderColors {
    return getReaderColors(this.colorMode);
  }

  private get isDark(): boolean {
    return this.colorMode === 0;
  }

  // 字号注入（离线 WebView 动态调整）
  private injectFontSize(size: number): void {
    try {
      this.webController.runJavaScript(
        `document.body.style.fontSize = '${size}px';`
      );
    } catch (_) {}
  }

  private loadOfflineHtmlFile(): void {
    const TAG = '[PixivReader][loadOfflineHtmlFile]';
    try {
      const html = parsePixivContent(this.cachedText, this.isDark);
      const ctx = getContext(this) as common.UIAbilityContext;
      const filePath = ctx.cacheDir + '/offline_novel.html';

      // 同步写入临时 HTML 文件
      const file = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, html);
      fs.closeSync(file.fd);
      console.info(`${TAG} ✅ HTML 文件已写入: ${filePath}，大小=${html.length}`);

      // 用 file:// 协议加载
      const fileUrl = 'file://' + filePath;
      console.info(`${TAG} 开始 loadUrl: ${fileUrl}`);
      this.webController.loadUrl(fileUrl);
      console.info(`${TAG} ✅ loadUrl 调用完成`);
    } catch (e) {
      console.error(`${TAG} ❌ loadOfflineHtmlFile 失败: ${JSON.stringify(e)}`);
    }
  }

  // 在线模式注入 Cookie（让 WebView 携带登录态）
  private injectCookie(): void {
    const TAG = '[PixivReader][injectCookie]';
    try {
      // 方式1：直接从 AppStorage 读（注意：key 必须存在才能读到）
      const session = AppStorage.get<string>('pixivSessionId') ?? '';

      console.info(`${TAG} AppStorage.get('pixivSessionId') = "${session ? session.substring(0, 8) + '...' : '(empty)'}"`);
      console.info(`${TAG} session 长度 = ${session.length}`);

      if (!session || session.trim() === '') {
        console.warn(`${TAG} ⚠️ PHPSESSID 为空，跳过 Cookie 注入！`);
        console.warn(`${TAG} 请确认：1) CrawlerSettings 中已输入 PHPSESSID；2) AppStorage key 拼写正确`);
        return;
      }

      const cookieStr = `PHPSESSID=${session.trim()}`;
      console.info(`${TAG} 准备注入 Cookie: ${cookieStr.substring(0, 20)}...`);

      web_webview.WebCookieManager.configCookieSync(
        'https://www.pixiv.net',
        cookieStr
      );
      console.info(`${TAG} ✅ Cookie 注入成功`);

      // 验证注入结果
      const injected = web_webview.WebCookieManager.fetchCookieSync('https://www.pixiv.net');
      console.info(`${TAG} 当前 pixiv.net Cookie: ${injected ? injected.substring(0, 50) : '(none)'}`);

    } catch (e) {
      // ✅ 不再吞异常，改为详细打印
      console.error(`${TAG} ❌ Cookie 注入失败: ${JSON.stringify(e)}`);
    }
  }

  // ========================================
  // UI
  // ========================================

  build() {
    Column() {

      // ── 顶部导航栏 ──
      this.HeaderBar()

      // ── 分割线 ──
      Divider()
        .color(this.getColors().divider)
        .strokeWidth(0.5)

      // ── 内容区 ──
      Stack() {
        // 离线模式 & 在线模式 共用同一个 WebView，内容来源不同
        if (this.offlineMode) {
          this.OfflineWebView()
        } else {
          this.OnlineWebView()
        }
        if (!this.offlineMode && this.isPageLoading) {
          this.LoadingBar()
        }

        // WebView 加载进度条（在线模式才显示）
        if (!this.params?.offline && this.isPageLoading) {
          this.LoadingBar()
        }
      }
      .width('100%')
      .layoutWeight(1)

      // ── 字体调节面板（浮层）──
      if (this.showFontPanel) {
        this.FontSizePanel()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getColors().pageBg)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  // ----------------------------------------
  // 顶部导航栏
  // ----------------------------------------

  @Builder HeaderBar() {
    Row() {
      // 返回按钮
      Text('←')
        .fontSize(22)
        .fontColor(this.getColors().primaryText)
        .padding({ left: 4, right: 4 })
        .backgroundColor(Color.Transparent)
        .onClick((): void => { router.back() })

      // 标题 + 作者
      Column() {
        Text(this.novelTitle)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getColors().primaryText)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.params?.author) {
          Text(this.novelAuthor)
            .fontSize(12)
            .fontColor(this.getColors().secondaryText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })

      // 离线/在线 徽章
      Text(this.offlineMode ? '📥 离线' : '🌐 在线')
        .fontSize(11)
        .fontColor(this.params?.offline ? '#52C41A' : this.getColors().accentText)
        .backgroundColor(this.getColors().iconBtnBg)
        .borderRadius(6)
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })

      // 字号调节按钮
      Text('字')
        .fontSize(15)
        .fontColor(this.getColors().iconBtnText)
        .backgroundColor(this.getColors().iconBtnBg)
        .borderRadius(6)
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .margin({ left: 8 })
        .onClick((): void => {
          this.showFontPanel = !this.showFontPanel
        })
    }
    .width('100%')
    .padding({
      left:   16,
      right:  16,
      top:    12 + px2vp(this.statusBarHeight),
      bottom: 12
    })
    .backgroundColor(this.getColors().headerBg)
  }

  // ----------------------------------------
  // 离线 WebView（渲染本地 HTML）
  // ----------------------------------------

  // ✅ 修复后
  @Builder OfflineWebView() {
    Web({
      src: 'about:blank',
      controller: this.webController
    })
      .onControllerAttached((): void => {
        this.isControllerReady = true;
        if (this.cachedText) {
          this.loadOfflineHtmlFile();
        }
      })
      .onPageEnd((): void => {
        this.injectFontSize(this.fontSize);
      })
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .fileAccess(true)
      .width('100%')
      .height('100%')
      .backgroundColor(this.isDark ? '#0D0D0D' : '#F9F7F2')
  }

  // ── 当 novelUrl 被 aboutToAppear 设置时，若控制器已就绪则立刻加载 ──
  @State @Watch('onNovelUrlChange') private novelUrl: string = '';
  @State private isControllerReady: boolean = false;

  private onNovelUrlChange(): void {
    if (this.isControllerReady && this.novelUrl) {
      setTimeout(() => {
        try {
          this.injectCookie();
          this.webController.loadUrl(this.novelUrl);
        } catch (e) {
          console.error('[onNovelUrlChange] loadUrl 失败: ' + JSON.stringify(e));
        }
      }, 100);
    }
  }


  // ----------------------------------------
  // 在线 WebView（带 Cookie 打开 Pixiv 真实页面）
  // ----------------------------------------

  @Builder OnlineWebView() {
    Web({
      src: 'about:blank',
      controller: this.webController
    })
      .width('100%')
      .height('100%')
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .onControllerAttached((): void => {
        const TAG = '[PixivReader][OnlineWebView]';
        console.info(`${TAG} onControllerAttached 触发`);
        console.info(`${TAG} novelUrl = ${this.novelUrl}`);

        this.isControllerReady = true;
        if (this.novelUrl) {
          setTimeout(() => {
            try {
              console.info(`${TAG} 开始注入 Cookie...`);
              this.injectCookie();
              console.info(`${TAG} 开始 loadUrl: ${this.novelUrl}`);
              this.webController.loadUrl(this.novelUrl);
              console.info(`${TAG} loadUrl 调用完成`);
            } catch (e) {
              console.error(`${TAG} ❌ loadUrl 失败: ${JSON.stringify(e)}`);
            }
          }, 100);
        } else {
          console.warn(`${TAG} ⚠️ novelUrl 为空，不执行 loadUrl`);
        }
      })
      .onProgressChange((event): void => {
        const progress = event?.newProgress ?? 0;
        this.loadProgress  = progress;
        this.isPageLoading = progress < 100;
        if (progress % 20 === 0) { // 每20%打一次log，不刷屏
          console.info(`[PixivReader] 加载进度: ${progress}%`);
        }
      })
      .onPageBegin((event): void => {
        console.info(`[PixivReader] onPageBegin url=${event?.url ?? '(unknown)'}`);
      })
      .onPageEnd((event): void => {
        const TAG = '[PixivReader][onPageEnd]';
        this.isPageLoading = false;
        console.info(`${TAG} 页面加载完成 url=${event?.url ?? '(unknown)'}`);
        // 页面加载完成后再次注入，防止页面跳转导致 Cookie 丢失
        this.injectCookie();
      })
      .onErrorReceive((event): void => {
        const code = event?.error?.getErrorCode() ?? -1;
        const desc = event?.error?.getErrorInfo() ?? '';
        console.error(`[PixivReader] ❌ onErrorReceive code=${code} desc=${desc}`);
        if (code === -6) {
          promptAction.showToast({ message: '网络不可用，请先缓存后离线阅读' });
        }
      })
      .onHttpErrorReceive((event): void => {
        const code = event?.response?.getResponseCode() ?? -1;
        console.error(`[PixivReader] ❌ HTTP错误 code=${code} url=${event?.request?.getRequestUrl() ?? ''}`);
      })
  }

  // ----------------------------------------
  // 加载进度条（在线模式）
  // ----------------------------------------

  @Builder LoadingBar() {
    Column() {
      // 顶部细线进度条
      Progress({
        value: this.loadProgress,
        total: 100,
        type:  ProgressType.Linear
      })
        .width('100%')
        .height(3)
        .color(this.getColors().accentText)
        .backgroundColor(Color.Transparent)

      // 中央 Loading 提示（进度 < 30% 时显示，避免一闪而过）
      if (this.loadProgress < 30) {
        Column() {
          LoadingProgress()
            .width(48).height(48)
            .color(this.getColors().accentText)
          Text('正在加载 Pixiv 页面...')
            .fontSize(14)
            .fontColor(this.getColors().secondaryText)
            .margin({ top: 12 })
          Text('如长时间无响应，请检查 Cookie 设置')
            .fontSize(11)
            .fontColor(this.getColors().secondaryText)
            .margin({ top: 6 })
            .opacity(0.6)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.getColors().pageBg)
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ----------------------------------------
  // 字号调节面板（底部浮层）
  // ----------------------------------------

  @Builder FontSizePanel() {
    Column() {
      // 遮罩（点击关闭）
      Blank()
        .layoutWeight(1)
        .width('100%')
        .onClick((): void => {
          this.showFontPanel = false
        })

      // 面板主体
      Column() {
        // 拖动条标题
        Row() {
          Text('字体大小')
            .fontSize(14)
            .fontColor(this.getColors().primaryText)
            .fontWeight(FontWeight.Medium)
          Blank()
          Text(`${this.fontSize}px`)
            .fontSize(14)
            .fontColor(this.getColors().accentText)
            .fontWeight(FontWeight.Bold)
        }
        .width('100%')
        .padding({ bottom: 14 })

        // 快捷字号按钮
        Row() {
          ForEach([14, 16, 18, 20, 22, 26] as number[], (size: number): void => {
            Text(`${size}`)
              .fontSize(13)
              .fontColor(this.fontSize === size
                ? '#FFFFFF'
                : this.getColors().primaryText)
              .backgroundColor(this.fontSize === size
                ? this.getColors().accentText
                : this.getColors().iconBtnBg)
              .borderRadius(8)
              .padding({ left: 12, right: 12, top: 7, bottom: 7 })
              .margin({ right: 8 })
              .onClick((): void => {
                this.fontSize = size;
                this.injectFontSize(size);
              })
          })
        }
        .width('100%')

        // 增减按钮
        Row() {
          Button('A-')
            .fontSize(15)
            .fontColor(this.getColors().primaryText)
            .backgroundColor(this.getColors().iconBtnBg)
            .borderRadius(10)
            .height(40)
            .layoutWeight(1)
            .onClick((): void => {
              if (this.fontSize > 12) {
                this.fontSize -= 1;
                this.injectFontSize(this.fontSize);
              }
            })

          Text(`${this.fontSize}px`)
            .fontSize(16)
            .fontColor(this.getColors().primaryText)
            .fontWeight(FontWeight.Bold)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)

          Button('A+')
            .fontSize(15)
            .fontColor(this.getColors().primaryText)
            .backgroundColor(this.getColors().iconBtnBg)
            .borderRadius(10)
            .height(40)
            .layoutWeight(1)
            .onClick((): void => {
              if (this.fontSize < 32) {
                this.fontSize += 1;
                this.injectFontSize(this.fontSize);
              }
            })
        }
        .width('100%')
        .margin({ top: 14 })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 20, bottom: 30 })
      .backgroundColor(this.getColors().headerBg)
      .borderRadius({ topLeft: 16, topRight: 16 })
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
  }
}