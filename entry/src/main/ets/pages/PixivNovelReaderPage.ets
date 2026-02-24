// entry/src/main/ets/pages/PixivNovelReaderPage.ets

import router from '@ohos.router';
import web_webview from '@ohos.web.webview';
import promptAction from '@ohos.promptAction';
import common from '@ohos.app.ability.common';
import { pixivCacheDB } from '../database/PixivCacheDB';

// ========================================
// 路由参数类型
// ========================================

interface ReaderRouterParams {
  novelId: string;
  title:   string;
  author:  string;
  offline: boolean;
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
  chapterColor:  string;
  hrColor:       string;
}

function getReaderColors(mode: number): ReaderColors {
  const isDark = mode === 0;
  return {
    pageBg:        isDark ? '#0D0D0D' : '#F9F7F2',
    headerBg:      isDark ? '#141414' : '#FFFFFF',
    primaryText:   isDark ? '#E6E6E6' : '#1A1A1A',
    secondaryText: isDark ? '#888888' : '#666666',
    accentText:    '#007DFF',
    divider:       isDark ? '#2A2A2A' : '#E5E5E5',
    iconBtnBg:     isDark ? '#2A2A2A' : '#F0F0F0',
    iconBtnText:   isDark ? '#CCCCCC' : '#444444',
    chapterColor:  isDark ? '#AADDFF' : '#0055AA',
    hrColor:       isDark ? '#333333' : '#DDDDDD',
  };
}

// ========================================
// ★ 新增：离线正文解析为"段落块"结构
// ========================================

// 每个段落块的类型
type BlockType = 'paragraph' | 'chapter' | 'hr' | 'blank';

// 段落块数据结构
interface ContentBlock {
  type:    BlockType;
  text:    string;   // paragraph / chapter 时有值，其余为空
  bold:    boolean;  // 段内是否有粗体（简化处理：整段判断）
  italic:  boolean;  // 段内是否有斜体
}

/**
 * 把 Pixiv 原始正文解析成段落块列表
 * 完全替代原来的 parsePixivContent → HTML 方案
 */
function parsePixivBlocks(raw: string): ContentBlock[] {
  if (!raw) return [];

  const blocks: ContentBlock[] = [];

  // 先按换行切割成行
  const lines = raw.split('\n');

  for (const line of lines) {
    const trimmed = line.trim();

    // 空行 → 空白块（起间距作用）
    if (!trimmed) {
      blocks.push({ type: 'blank', text: '', bold: false, italic: false });
      continue;
    }

    // 分页符 → 水平线块
    if (trimmed === '[newpage]') {
      blocks.push({ type: 'hr', text: '', bold: false, italic: false });
      continue;
    }

    // 章节标题 [chapter:xxx]
    const chapterMatch = trimmed.match(/^\[chapter:(.*?)\]$/);
    if (chapterMatch) {
      blocks.push({
        type:   'chapter',
        text:   chapterMatch[1],
        bold:   false,
        italic: false
      });
      continue;
    }

    // 普通段落：去掉 Pixiv 标记，保留文字
    let text = trimmed
    // 傍点注音 [[rb:文字>注音]] → 只保留文字
      .replace(/\[\[rb:(.*?)>(.*?)\]\]/g, '$1')
      // 粗体 [b]...[/b]
      .replace(/\[b\]([\s\S]*?)\[\/b\]/g, '$1')
      // 斜体 [i]...[/i]
      .replace(/\[i\]([\s\S]*?)\[\/i\]/g, '$1')
      // 链接跳转（直接丢弃）
      .replace(/\[jump:(.*?)\]/g, '')
      // 其他未知标记（保险兜底）
      .replace(/\[[^\]]*\]/g, '');

    if (!text.trim()) continue;

    // 简化判断：整段含 [b] 原始标记则标记 bold，含 [i] 则标记 italic
    // （因为已经 replace 处理完了，这里检测原始 line）
    const hasBold   = /\[b\]/.test(line);
    const hasItalic = /\[i\]/.test(line);

    blocks.push({
      type:   'paragraph',
      text:   text,
      bold:   hasBold,
      italic: hasItalic,
    });
  }

  return blocks;
}

// ========================================
// 页面主体
// ========================================

@Entry
@Component
struct PixivNovelReaderPage {

  // ── 路由参数 ──
  private params: ReaderRouterParams | null = null;

  // ── 核心状态 ──
  @State private offlineMode:  boolean = false;
  @State private novelTitle:   string  = '小说阅读';
  @State private novelAuthor:  string  = '';
  @State private colorMode:    number  = 0;

  // ── ★ 离线模式：解析后的段落块列表（替代 cachedText + WebView）──
  @State private contentBlocks: ContentBlock[] = [];
  @State private isLoading:     boolean = true;   // 离线：读 DB 中 / 在线：WebView 加载中

  // ── 字号（离线/在线共用）──
  @State private fontSize:      number  = 18;
  @State private showFontPanel: boolean = false;

  // ── 在线模式专用 ──
  @State private novelUrl:     string  = '';
  @State private loadProgress: number  = 0;
  private webController: web_webview.WebviewController =
    new web_webview.WebviewController();
  @State private isControllerReady: boolean = false;

  // ── 安全区 ──
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  // ── 颜色模式监听 ──
  private configCallbackId:      number    = -1;
  private configChangeCallback: () => void = () => {};

  // ========================================
  // 生命周期
  // ========================================

  aboutToAppear(): void {
    const TAG = '[PixivReader][aboutToAppear]';
    const ctx = getContext(this) as common.UIAbilityContext;

    this.colorMode  = ctx.config?.colorMode ?? 0;
    this.params     = router.getParams() as ReaderRouterParams;
    this.offlineMode = this.params?.offline === true ||
      String(this.params?.offline) === 'true';
    this.novelTitle  = this.params?.title  ?? '小说阅读';
    this.novelAuthor = this.params?.author ?? '';

    console.info(`${TAG} offline=${this.offlineMode} novelId=${this.params?.novelId}`);

    if (this.offlineMode && this.params?.novelId) {
      // ★ 离线：从 DB 读正文 → 解析成段落块
      this.loadOfflineContent(this.params.novelId);
    } else if (this.params?.novelId) {
      // 在线：构造 URL
      this.novelUrl = `https://www.pixiv.net/novel/show.php?id=${this.params.novelId}`;
      this.injectCookie();
    }

    // 监听深色/浅色模式变化
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
  // ★ 核心：离线内容加载（DB → 解析 → 渲染）
  // ========================================

  private async loadOfflineContent(novelId: string): Promise<void> {
    const TAG = '[PixivReader][loadOfflineContent]';
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      await pixivCacheDB.init(ctx);

      const text = await pixivCacheDB.getFullText(novelId);
      console.info(`${TAG} getFullText: ${text ? '长度=' + text.length : 'null'}`);

      if (!text) {
        promptAction.showToast({ message: '缓存内容丢失，请重新缓存' });
        router.back();
        return;
      }

      // ★ 解析成段落块，赋值触发重渲染
      this.contentBlocks = parsePixivBlocks(text);
      console.info(`${TAG} 解析完成，共 ${this.contentBlocks.length} 个块`);

    } catch (e) {
      console.error(`${TAG} 失败: ${JSON.stringify(e)}`);
      promptAction.showToast({ message: '加载失败，请重试' });
    } finally {
      // 无论成功与否都关闭 loading
      this.isLoading = false;
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

  // 在线模式：WebView 注入 Cookie
  private injectCookie(): void {
    try {
      const session = AppStorage.get<string>('pixivSessionId') ?? '';
      if (!session.trim()) return;
      web_webview.WebCookieManager.configCookieSync(
        'https://www.pixiv.net',
        `PHPSESSID=${session.trim()}`
      );
    } catch (e) {
      console.error(`[PixivReader][injectCookie] 失败: ${JSON.stringify(e)}`);
    }
  }

  // 在线模式：WebView 动态注入字号
  private injectFontSize(size: number): void {
    if (!this.isControllerReady) return;
    try {
      this.webController.runJavaScript(
        `document.body.style.fontSize = '${size}px';`
      );
    } catch (_) {}
  }

  // ========================================
  // UI：顶部导航栏
  // ========================================

  @Builder HeaderBar() {
    Row() {
      // 返回按钮
      Button({ type: ButtonType.Circle }) {
        Text('←')
          .fontSize(20)
          .fontColor(this.getColors().iconBtnText)
      }
      .width(40).height(40)
      .backgroundColor(this.getColors().iconBtnBg)
      .onClick(() => router.back())

      // 标题区
      Column() {
        Text(this.novelTitle)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getColors().primaryText)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (this.novelAuthor) {
          Text(this.novelAuthor)
            .fontSize(12)
            .fontColor(this.getColors().secondaryText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 12, right: 12 })

      // 字号调节按钮
      Button({ type: ButtonType.Circle }) {
        Text('A')
          .fontSize(16)
          .fontColor(this.getColors().iconBtnText)
      }
      .width(40).height(40)
      .backgroundColor(this.getColors().iconBtnBg)
      .onClick(() => { this.showFontPanel = !this.showFontPanel; })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.getColors().headerBg)
  }

  // ========================================
  // ★ 核心 UI：离线原生渲染（完全替代 OfflineWebView）
  // ========================================

  @Builder OfflineReaderView() {
    if (this.isLoading) {
      // 加载中
      Column() {
        LoadingProgress()
          .width(48).height(48)
          .color(this.getColors().accentText)
        Text('正在加载...')
          .fontSize(14)
          .fontColor(this.getColors().secondaryText)
          .margin({ top: 12 })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)

    } else if (this.contentBlocks.length === 0) {
      // 空内容
      Column() {
        Text('📭')
          .fontSize(48)
          .margin({ bottom: 12 })
        Text('内容为空')
          .fontSize(16)
          .fontColor(this.getColors().secondaryText)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)

    } else {
      // ★ 正文渲染：Scroll + List，流畅可滚动
      Scroll() {
        Column() {
          ForEach(
            this.contentBlocks,
            (block: ContentBlock, index: number) => {
              if (block.type === 'chapter') {
                // 章节标题
                Row() {
                  // 左侧边框
                  Blank()
                    .width(3)
                    .height('100%')
                    .backgroundColor(this.getColors().chapterColor)
                  
                  Text(block.text)
                    .fontSize(this.fontSize * 1.1)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.getColors().chapterColor)
                    .layoutWeight(1)
                    .padding({ left: 13, right: 16, top: 20, bottom: 8 })
                }
                .margin({ left: 16, top: 4, bottom: 4 })
                .width('100%')

              } else if (block.type === 'hr') {
                // 分页线
                Divider()
                  .color(this.getColors().hrColor)
                  .strokeWidth(1)
                  .margin({ top: 24, bottom: 24, left: 20, right: 20 })

              } else if (block.type === 'blank') {
                // 空行间距
                Row()
                  .height(this.fontSize * 0.6)
                  .width('100%')

              } else {
                // 普通段落
                Text(block.text)
                  .fontSize(this.fontSize)
                  .fontWeight(block.bold ? FontWeight.Bold : FontWeight.Normal)
                  .fontStyle(block.italic ? FontStyle.Italic : FontStyle.Normal)
                  .fontColor(this.getColors().primaryText)
                  .lineHeight(this.fontSize * 1.9)
                  .width('100%')
                  .padding({ left: 20, right: 20 })
                  .textAlign(TextAlign.Start)
                  .copyOption(CopyOptions.LocalDevice)
              }
            },
            (block: ContentBlock, index: number) => `block_${index}`
          )

          // 底部留白
          Row().height(80).width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .scrollable(ScrollDirection.Vertical)
      .edgeEffect(EdgeEffect.Spring)
    }
  }

  // ========================================
  // UI：在线 WebView（完全保留原逻辑）
  // ========================================

  @Builder OnlineWebView() {
    Web({
      src:        this.novelUrl || 'about:blank',
      controller: this.webController
    })
      .onControllerAttached((): void => {
        const TAG = '[PixivReader][OnlineWebView][onControllerAttached]';
        this.isControllerReady = true;
        if (this.novelUrl) {
          setTimeout(() => {
            try {
              this.injectCookie();
              this.webController.loadUrl(this.novelUrl);
            } catch (e) {
              console.error(`${TAG} loadUrl 失败: ${JSON.stringify(e)}`);
            }
          }, 100);
        }
      })
      .onProgressChange((event): void => {
        const progress = event?.newProgress ?? 0;
        this.loadProgress = progress;
        this.isLoading    = progress < 100;
      })
      .onPageEnd((): void => {
        this.isLoading = false;
        this.injectCookie();
        this.injectFontSize(this.fontSize);
      })
      .onErrorReceive((event): void => {
        const code = event?.error?.getErrorCode() ?? -1;
        console.error(`[PixivReader] onErrorReceive code=${code}`);
        if (code === -6) {
          promptAction.showToast({ message: '网络不可用，请先缓存后离线阅读' });
        }
      })
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .mixedMode(MixedMode.All)
      .width('100%')
      .height('100%')
  }

  // ========================================
  // UI：在线模式加载进度条
  // ========================================

  @Builder LoadingBar() {
    Column() {
      Progress({
        value: this.loadProgress,
        total: 100,
        type:  ProgressType.Linear
      })
        .width('100%')
        .height(3)
        .color(this.getColors().accentText)
        .backgroundColor(Color.Transparent)

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

  // ========================================
  // UI：字号调节面板
  // ========================================

  @Builder FontSizePanel() {
    Column() {
      // 遮罩
      Blank()
        .layoutWeight(1)
        .width('100%')
        .onClick(() => { this.showFontPanel = false; })

      // 控制面板
      Column() {
        Text('字体大小')
          .fontSize(14)
          .fontColor(this.getColors().secondaryText)
          .margin({ bottom: 12 })

        Row() {
          // 缩小
          Button('A-')
            .fontSize(16)
            .fontColor(this.getColors().iconBtnText)
            .backgroundColor(this.getColors().iconBtnBg)
            .borderRadius(8)
            .height(40)
            .padding({ left: 20, right: 20 })
            .onClick(() => {
              if (this.fontSize > 12) {
                this.fontSize -= 2;
                // 在线模式同步注入
                if (!this.offlineMode) this.injectFontSize(this.fontSize);
              }
            })

          Text(`${this.fontSize}px`)
            .fontSize(16)
            .fontColor(this.getColors().primaryText)
            .width(80)
            .textAlign(TextAlign.Center)

          // 放大
          Button('A+')
            .fontSize(16)
            .fontColor(this.getColors().iconBtnText)
            .backgroundColor(this.getColors().iconBtnBg)
            .borderRadius(8)
            .height(40)
            .padding({ left: 20, right: 20 })
            .onClick(() => {
              if (this.fontSize < 32) {
                this.fontSize += 2;
                if (!this.offlineMode) this.injectFontSize(this.fontSize);
              }
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .padding(20)
      .backgroundColor(this.getColors().headerBg)
      .borderRadius({ topLeft: 16, topRight: 16 })
      .shadow({ radius: 16, color: '#00000033', offsetY: -4 })
    }
    .width('100%')
    .height('100%')
  }

  // ========================================
  // 主 build
  // ========================================

  build() {
    Stack() {
      Column() {
        // 顶部导航栏
        this.HeaderBar()

        // 分割线
        Divider()
          .color(this.getColors().divider)
          .strokeWidth(0.5)

        // ★ 内容区：离线用原生渲染，在线用 WebView
        Stack() {
          if (this.offlineMode) {
            // ★ 完全原生渲染，无 WebView，无白屏风险
            this.OfflineReaderView()
          } else {
            this.OnlineWebView()
            // 在线加载进度条
            if (this.isLoading) {
              this.LoadingBar()
            }
          }
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.getColors().pageBg)

      // 字号面板浮层
      if (this.showFontPanel) {
        this.FontSizePanel()
      }
    }
    .width('100%')
    .height('100%')
  }
}