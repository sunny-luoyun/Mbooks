// entry/src/main/ets/pages/PixivNovelReaderPage.ets

import router from '@ohos.router';
import web_webview from '@ohos.web.webview';
import promptAction from '@ohos.promptAction';
import common from '@ohos.app.ability.common';
import { pixivCacheDB } from '../database/PixivCacheDB';
import { getDeepSeekService, TranslationResult } from '../services/DeepSeekService';
import preferences from '@ohos.data.preferences';



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
  translateBtnBg: string;
  translateBtnText: string;
  translatedTextColor: string;
  translationProgressBg: string;
  translationProgressFill: string;
  dangerText:    string;
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
    translateBtnBg: isDark ? '#2A2A2A' : '#F0F0F0',
    translateBtnText: '#007DFF',
    translatedTextColor: isDark ? '#CCE5FF' : '#0055AA',
    translationProgressBg: isDark ? '#333333' : '#E5E5E5',
    translationProgressFill: '#007DFF',
    dangerText: '#FF4D4F'
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

  // ── 阅读进度保存 ──
  private scroller: Scroller = new Scroller();          // Scroll 组件控制器
  private saveProgressTimer: number = -1;               // 防抖定时器
  private readonly PROGRESS_SAVE_DELAY = 800;          // 0.8秒防抖
  @State private hasRestoredPosition: boolean = false; // 防止重复恢复
  @State private hasReachedEnd: boolean = false;

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

  // 在组件类中添加新状态
  @State private showTranslation: boolean = false;  // 是否显示翻译
  @State private isTranslating: boolean = false;    // 是否正在翻译
  @State private translationProgress: number = 0;    // 翻译进度
  @State private translatedTitle: string = '';       // 翻译后的标题
  @State private translatedBlocks: ContentBlock[] = []; // 翻译后的段落块
  @State private showOriginal: boolean = true;       // 显示原文还是译文
  @State private renderBlocks: ContentBlock[] = [];

  private lastKnownScrollY: number = 0;
  private lastScrollCheckY: number = 0;

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
    if (this.configCallbackId !== -1) {
      getContext(this).getApplicationContext().off('environment', this.configCallbackId);
    }

    if (this.offlineMode && this.params?.novelId) {
      clearTimeout(this.saveProgressTimer);

      // ★ 改进的逻辑：精确判断是否已阅读完成
      const isFinished = this.isContentAtEnd();

      const progressToSave = isFinished ? 0 : this.lastKnownScrollY;

      pixivCacheDB.saveReadingProgress(
        this.params.novelId,
        progressToSave,
        !this.showOriginal
      );

      this.saveViewPreference(!this.showOriginal);

      console.info(`[aboutToDisappear] 保存进度: ${progressToSave} (finished=${isFinished})`);
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
      if (!text) {
        promptAction.showToast({ message: '缓存内容丢失，请重新缓存' });
        router.back();
        return;
      }

      this.contentBlocks = parsePixivBlocks(text);
      this.renderBlocks = this.contentBlocks;   // 暂时先用原文
      console.info(`${TAG} 解析完成，共 ${this.contentBlocks.length} 个块`);

      // 先获取小说信息（包括译文）
      const novel = await pixivCacheDB.getNovelById(novelId);
      if (novel?.hasTitleTranslation && novel.titleTranslated) {
        this.translatedTitle = novel.titleTranslated;
      }
      if (novel?.hasFullTranslation && novel.fullTextTranslated) {
        this.translatedBlocks = parsePixivBlocks(novel.fullTextTranslated);
      }

      // ★ 关键新增：根据读取的偏好决定初始显示
      if (this.translatedBlocks.length > 0) {
        const preferTranslation = await this.getViewPreference();
        if (preferTranslation) {
          this.showOriginal = false;
          this.showTranslation = true;
          this.renderBlocks = this.translatedBlocks;
        }
      }

      // 恢复滚动位置放在确定视图之后，保证恢复的是当前视图的进度
      if (this.renderBlocks.length > 0) {
        const savedY = await pixivCacheDB.getReadingProgress(novelId, !this.showOriginal);
        if (savedY > 0) {
          console.info(`${TAG} 恢复阅读位置: ${savedY}px (当前视图: ${this.showOriginal ? '原文' : '译文'})`);
          setTimeout(() => {
            this.scroller.scrollTo({ xOffset: 0, yOffset: savedY });
            this.hasRestoredPosition = true;
          }, 100);
        }
      }

    } catch (e) {
      console.error(`${TAG} 失败: ${JSON.stringify(e)}`);
      promptAction.showToast({ message: '加载失败，请重试' });
    } finally {
      this.isLoading = false;
    }
  }

  private isContentAtEnd(): boolean {
    try {
      const scrollOffset = this.scroller.currentOffset();
      const currentY = scrollOffset.yOffset;

      // 这是关键：获取 Scroll 组件的实际高度和内容高度
      // 但鸿蒙的 Scroll 没有直接 API，需要用估算或其他方式

      // 方案 1：用 renderBlocks 估算总高度（保留你现在的方式）
      let estimatedContentHeight = 0;
      for (let block of this.renderBlocks) {
        if (block.type === 'chapter') {
          estimatedContentHeight += this.fontSize * 1.1 * 2 + 28;
        } else if (block.type === 'hr') {
          estimatedContentHeight += 48;
        } else if (block.type === 'blank') {
          estimatedContentHeight += this.fontSize * 0.6;
        } else {
          const lines = Math.ceil(block.text.length / 40);
          estimatedContentHeight += this.fontSize * 1.9 * lines + 20;
        }
      }

      // 视口高度（实际上应该获取组件的真实高度，这里暂时用 500）
      const viewportHeight = 500;
      const scrollableHeight = estimatedContentHeight - viewportHeight;

      // 判断：是否滚到了最后 5%（更严格的判断）
      // currentY 接近 scrollableHeight 时，说明快到底了
      const isAtEnd = currentY >= scrollableHeight * 0.95;

      console.info(`[isContentAtEnd] currentY=${currentY}, scrollableHeight≈${scrollableHeight}, isAtEnd=${isAtEnd}`);
      return isAtEnd;
    } catch (e) {
      console.error(`[isContentAtEnd] 异常: ${JSON.stringify(e)}`);
      return false;
    }
  }

  // ✅ 新增：翻译标题
  private async translateTitle(): Promise<void> {
    const service = getDeepSeekService();

    if (!service.hasValidKey()) {
      promptAction.showToast({ message: '请先在设置中填入 DeepSeek API 密钥' });
      return;
    }

    this.isTranslating = true;

    const result = await service.translateText(this.novelTitle, true);

    if (result.success && result.translatedText) {
      this.translatedTitle = result.translatedText;

      // 保存到数据库
      if (this.params?.novelId) {
        await pixivCacheDB.saveTitleTranslation(this.params.novelId, result.translatedText);
      }

      promptAction.showToast({ message: '标题翻译完成' });
    } else {
      promptAction.showToast({ message: result.error || '翻译失败' });
    }

    this.isTranslating = false;
  }

  // ✅ 新增：翻译全文
  private async translateFullText(): Promise<void> {
    const service = getDeepSeekService();

    if (!service.hasValidKey()) {
      promptAction.showToast({ message: '请先在设置中填入 DeepSeek API 密钥' });
      return;
    }

    // 获取原文
    const novelId = this.params?.novelId;
    if (!novelId) return;

    const ctx = getContext(this) as common.UIAbilityContext;
    await pixivCacheDB.init(ctx);
    const originalText = await pixivCacheDB.getFullText(novelId);

    if (!originalText) {
      promptAction.showToast({ message: '找不到原文内容' });
      return;
    }

    // 估算费用
    const estimatedCost = service.estimateCost(originalText.length);

    // 确认对话框（鸿蒙没有内置confirm，用promptAction模拟）
    promptAction.showDialog({
      title: '确认翻译全文',
      message: `预计翻译 ${originalText.length} 字符，费用约 $${estimatedCost.toFixed(4)}（仅供参考）。\n是否继续？`,
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '开始翻译', color: '#007DFF' }
      ]
    }).then((data) => {
      if (data.index === 1) { // 用户点击了"开始翻译"
        this.performFullTranslation(novelId, originalText);
      }
    });
  }

  /**
   * 防抖保存阅读进度（停止滚动2秒后保存）
   */
  private debouncedSaveProgress(yOffset: number): void {
    // 清除之前的定时器
    if (this.saveProgressTimer !== -1) {
      clearTimeout(this.saveProgressTimer);
    }

    // 设置新定时器
    this.saveProgressTimer = setTimeout(() => {
      if (this.params?.novelId) {
        // 根据当前显示的是原文还是译文，分别保存
        pixivCacheDB.saveReadingProgress(
          this.params.novelId,
          Math.floor(yOffset),
          !this.showOriginal  // showOriginal=false 表示显示译文
        );
      }
    }, this.PROGRESS_SAVE_DELAY);
  }

  /**
   * 将短段落合并成较长段落，控制每段最大字符数
   * 空行不参与合并，直接过滤（翻译时无需处理空行）
   */
  private mergeShortParagraphs(paragraphs: string[], maxChars: number = 2000): string[] {
    const merged: string[] = [];
    let current = '';
    for (const para of paragraphs) {
      const text = para.trim();
      if (!text) continue;  // 空行跳过，不拆段
      if (current && (current.length + text.length + 1) > maxChars) {
        merged.push(current);
        current = text;
      } else {
        current = current ? current + '\n' + text : text;
      }
    }
    if (current) merged.push(current);
    return merged;
  }

  // ✅ 新增：执行全文翻译
  private async performFullTranslation(novelId: string, originalText: string): Promise<void> {
    this.isTranslating = true;
    this.showTranslation = true;
    this.translationProgress = 0;

    await pixivCacheDB.updateTranslationProgress(novelId, 0, 'in_progress');

    const paragraphs = originalText.split('\n');
    const mergedParagraphs = this.mergeShortParagraphs(paragraphs, 2000);  // 新增：合并短段落
    const service = getDeepSeekService();

    // ✅ 只用进度回调更新进度条，不在回调里收集结果
    const results = await service.translateParagraphs(
      mergedParagraphs,
      (current, total, _translated) => {
        this.translationProgress = Math.floor((current / total) * 100);
      }
    );

    // ✅ 直接从 results 按顺序提取，空行用原文填充，翻译失败也用原文兜底
    // 注意：translateParagraphs 对空行 push 了 {success:true, translatedText:''}
    // 所以 results.length === paragraphs.length，一一对应
    const translatedParagraphs = results.map((r, i) => {
      if (!mergedParagraphs[i]) {
        return '';  // 空段
      }
      return (r.success && r.translatedText) ? r.translatedText : mergedParagraphs[i];
    });

    const fullTranslated = translatedParagraphs.join('\n');

    // ✅ 先存到本地变量，避免 @State 响应式赋值的时序问题
    const newBlocks = parsePixivBlocks(fullTranslated);
    this.translatedBlocks = newBlocks;
    this.showOriginal = false;
    this.showTranslation = true;
    this.renderBlocks = newBlocks;  // ✅ 用本地变量，保证是最新解析结果

    console.info(`[translate] renderBlocks 数量: ${this.renderBlocks.length}`);
    console.info(`[translate] showOriginal=${this.showOriginal}, showTranslation=${this.showTranslation}`);

    // 保存到数据库
    await pixivCacheDB.saveFullTextTranslation(novelId, fullTranslated);

    this.isTranslating = false;
    promptAction.showToast({ message: '全文翻译完成' });
  }

  /**
   * 保存 & 读取文字偏好
   */
  private async saveViewPreference(showTranslation: boolean): Promise<void> {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const pref = await preferences.getPreferences(ctx, 'pixiv_novel_view');
      await pref.put(`${this.params!.novelId}_showTranslation`, showTranslation);
      await pref.flush();
    } catch (e) {
      console.error('saveViewPreference failed', JSON.stringify(e));
    }
  }

  private async getViewPreference(): Promise<boolean> {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const pref = await preferences.getPreferences(ctx, 'pixiv_novel_view');
      const value = await pref.get(`${this.params!.novelId}_showTranslation`, false);
      return value as boolean;
    } catch (e) {
      return false;
    }
  }

  /**
   * 检测是否已阅读到底部
   */
  private checkIfReachedEnd(): void {
    const TAG = '[PixivReader][checkIfReachedEnd]';

    try {
      const scrollOffset = this.scroller.currentOffset();
      const currentY = scrollOffset.yOffset;

      // ✅ 计算内容总高度（通过渲染块估算）
      // 每个段落大约 fontSize * 1.9 的高度 + padding
      let estimatedContentHeight = 0;
      for (let block of this.renderBlocks) {
        if (block.type === 'chapter') {
          estimatedContentHeight += this.fontSize * 1.1 * 2 + 28; // 标题更高
        } else if (block.type === 'hr') {
          estimatedContentHeight += 48; // 分页线
        } else if (block.type === 'blank') {
          estimatedContentHeight += this.fontSize * 0.6;
        } else {
          // 普通段落
          const lines = Math.ceil(block.text.length / 40); // 估算行数
          estimatedContentHeight += this.fontSize * 1.9 * lines + 20; // padding
        }
      }

      // ✅ 视口高度（假设约500px，或从组件尺寸获取）
      const viewportHeight = 500;
      const totalScrollableHeight = estimatedContentHeight - viewportHeight;

      // ✅ 判断是否在最后10%范围内（容差更大，避免误触）
      const isAtBottom = currentY >= totalScrollableHeight * 0.9;

      if (isAtBottom && currentY > 500) { // 至少要滚了很远
        console.info(`${TAG} 检测到阅读完成！currentY=${currentY}, total≈${totalScrollableHeight}px`);

        if (this.params?.novelId && !this.hasReachedEnd) { // ← 新增标志防重复
          this.hasReachedEnd = true; // 标记已显示过提示

          pixivCacheDB.saveReadingProgress(
            this.params.novelId,
            0,
            !this.showOriginal
          );

          promptAction.showToast({
            message: '✓ 阅读完成！下次将从头开始'
          });
        }
      }
    } catch (e) {
      console.error(`${TAG} 异常: ${JSON.stringify(e)}`);
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
        if (this.showTranslation && this.translatedTitle) {
          // 显示翻译后的标题
          Text(this.translatedTitle)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getColors().translatedTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(this.novelTitle)
            .fontSize(11)
            .fontColor(this.getColors().secondaryText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        } else {
          Text(this.novelTitle)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getColors().primaryText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }

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

      // ✅ 新增：翻译按钮（只在离线模式显示）
      if (this.offlineMode) {
        // 原文/译文切换
        Button({ type: ButtonType.Circle }) {
          Text(this.showOriginal ? '译' : '原')
            .fontSize(16)
            .fontColor(this.getColors().translateBtnText)
        }
        .width(40).height(40)
        .backgroundColor(this.getColors().translateBtnBg)
        .margin({ right: 8 })
        .enabled(this.translatedBlocks.length > 0)
        .onClick(() => {
          if (!this.params?.novelId) return;

          // 1. 先保存当前视图的进度
          const currentY = this.scroller.currentOffset().yOffset;
          pixivCacheDB.saveReadingProgress(
            this.params.novelId,
            currentY,
            !this.showOriginal  // 当前是原文就保存原文进度
          );

          // 2. 切换状态
          this.showOriginal = !this.showOriginal;
          this.showTranslation = !this.showOriginal;
          this.renderBlocks = this.showOriginal
            ? this.contentBlocks
            : this.translatedBlocks;
          this.saveViewPreference(!this.showOriginal);

          // 3. 异步加载新视图的进度
          setTimeout(async () => {
            const targetY = await pixivCacheDB.getReadingProgress(
              this.params!.novelId,
              !this.showOriginal  // 新视图的类型
            );

            // 滚动到新位置（如果无记录则回顶部）
            this.scroller.scrollTo({
              xOffset: 0,
              yOffset: targetY > 0 ? targetY : 0
            });
          }, 50);
        })

        // 翻译按钮
        Button({ type: ButtonType.Circle }) {
          if (this.isTranslating) {
            LoadingProgress()
              .width(20).height(20)
              .color(this.getColors().accentText)
          } else {
            Text('翻')
              .fontSize(16)
              .fontColor(this.translatedBlocks.length > 0
                ? this.getColors().translatedTextColor
                : this.getColors().translateBtnText)
          }
        }
        .width(40).height(40)
        .backgroundColor(this.getColors().translateBtnBg)
        .margin({ right: 8 })
        .onClick(() => {
          if (this.translatedBlocks.length > 0) {
            // ✅ 同时切换 showTranslation、showOriginal、renderBlocks 三个状态
            this.showTranslation = !this.showTranslation;
            this.showOriginal = !this.showTranslation; // showTranslation=true 时显示译文
            this.renderBlocks = this.showTranslation
              ? this.translatedBlocks
              : this.contentBlocks;
          } else {
            this.translateFullText();
          }
        })
      }

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
    .padding({
      left: 16,
      right: 16,
      top: 12 + px2vp(this.statusBarHeight),  // ← 加上状态栏高度
      bottom: 12
    })
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
      Scroll(this.scroller) {
        Column() {
          ForEach(
            this.renderBlocks,
            (block: ContentBlock, index: number) => {
              if (block.type === 'chapter') {
                // 章节标题（翻译时用不同颜色）
                Row() {
                  Blank()
                    .width(3)
                    .height('100%')
                    .backgroundColor(this.showOriginal
                      ? this.getColors().chapterColor
                      : this.getColors().translatedTextColor)

                  Text(block.text)
                    .fontSize(this.fontSize * 1.1)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.showOriginal
                      ? this.getColors().chapterColor
                      : this.getColors().translatedTextColor)
                    .layoutWeight(1)
                    .padding({ left: 13, right: 16, top: 20, bottom: 8 })
                }
                .margin({ left: 16, top: 4, bottom: 4 })
                .width('100%')

              } else if (block.type === 'hr') {
                // 分页线...
                Divider().color(this.getColors().hrColor)
                  .strokeWidth(1)
                  .margin({ top: 24, bottom: 24, left: 20, right: 20 })

              } else if (block.type === 'blank') {
                // 空行...
                Row().height(this.fontSize * 0.6).width('100%')

              } else {
                // 普通段落
                Text(block.text)
                  .fontSize(this.fontSize)
                  .fontWeight(block.bold ? FontWeight.Bold : FontWeight.Normal)
                  .fontStyle(block.italic ? FontStyle.Italic : FontStyle.Normal)
                  .fontColor(this.showOriginal
                    ? this.getColors().primaryText
                    : this.getColors().translatedTextColor)
                  .lineHeight(this.fontSize * 1.9)
                  .width('100%')
                  .padding({ left: 20, right: 20 })
                  .textAlign(TextAlign.Start)
                  .copyOption(CopyOptions.LocalDevice)
              }
            },
            (block: ContentBlock, index: number) => `${this.showOriginal ? 'orig' : 'trans'}_${index}`
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
      .onScroll((_x: number, _y: number) => {
        this.lastKnownScrollY = this.scroller.currentOffset().yOffset;
        if (this.offlineMode && !this.isLoading && this.params?.novelId) {
          this.debouncedSaveProgress(this.lastKnownScrollY);
          // ★ 移除 checkIfReachedEnd() 调用
        }
      })

      // 翻译进度条
      if (this.isTranslating) {
        Column() {
          Row() {
            Text(`翻译中... ${this.translationProgress}%`)
              .fontSize(12)
              .fontColor(this.getColors().secondaryText)
            Blank()
            Text('取消')
              .fontSize(12)
              .fontColor(this.getColors().dangerText)
              .onClick(() => {
                // 取消翻译逻辑（需要实现取消功能）
              })
          }
          .width('100%')
          .padding({ left: 20, right: 20, bottom: 8 })

          Progress({
            value: this.translationProgress,
            total: 100,
            type: ProgressType.Linear
          })
            .width('100%')
            .height(4)
            .color(this.getColors().accentText)
            .backgroundColor(this.getColors().translationProgressBg)
        }
        .width('100%')
        .backgroundColor(this.getColors().headerBg)
        .padding({ top: 8, bottom: 8 })
        .position({ y: '100%' })
        .translate({ y: -80 }) // 放在底部上方
      }
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