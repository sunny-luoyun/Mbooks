// entry/src/main/ets/components/settings/CrawlerSettings.ets
import { CrawlerConfig } from '../../models/SettingsModels';
import { SettingsService } from '../../services/SettingsService';
import promptAction from '@ohos.promptAction';
import common from '@ohos.app.ability.common';
import { getPixivService } from '../../services/PixivService';
import { saveSessionId, clearSessionId, saveDeepSeekApiKey, clearDeepSeekApiKey } from '../../utils/PreferencesUtil';
import { getDeepSeekService } from '../../services/DeepSeekService';

interface ColorConfig {
  pageBg: string;
  cardBg: string;
  headerBg: string;
  primaryText: string;
  secondaryText: string;
  tertiaryText: string;
  accentText: string;
  dangerText: string;
  sliderTrack: string;
  sliderBlock: string;
  toggleOn: string;
  toggleOff: string;
  hintText: string;
  divider: string;
}

function getCrawlerSettingsColors(mode: number): ColorConfig {
  const isDark = mode === 0;
  return {
    pageBg:        isDark ? '#0D0D0D' : '#F5F5F5',
    cardBg:        isDark ? '#1E1E1E' : '#FFFFFF',
    headerBg:      isDark ? '#141414' : '#FFFFFF',
    primaryText:   isDark ? '#E6E6E6' : '#000000',
    secondaryText: isDark ? '#999999' : '#666666',
    tertiaryText:  isDark ? '#666666' : '#999999',
    accentText:    '#007DFF',
    dangerText:    '#FF4D4F',
    sliderTrack:   isDark ? '#3A3A3A' : '#E5E5E5',
    sliderBlock:   '#007DFF',
    toggleOn:      '#007DFF',
    toggleOff:     isDark ? '#3A3A3A' : '#CCCCCC',
    hintText:      isDark ? '#555555' : '#999999',
    divider:       isDark ? '#2A2A2A' : '#E5E5E5'
  };
}

@Component
export struct CrawlerSettings {
  @State localConfig: CrawlerConfig = {
    maxPagesPerRun: 5,
    stopAfterOldPages: 2,
    requestDelay: 800,
    enableBreakpoint: true,
    autoCheckOnStartup: false,
    checkIntervalHours: 0
  };
  @State colorMode: number = 0;

  // ── Pixiv Cookie 状态 ──
  @StorageLink('pixivSessionId') pixivSessionId: string = '';
  @State showCookieText: boolean = false;
  @State cookieCheckState: string = 'idle';

  // Deepseek key
  @StorageLink('deepseekApiKey') deepseekApiKey: string = '';
  @State showApiKeyText: boolean = false;
  @State apiKeyCheckState: string = 'idle'; // 'idle', 'checking', 'ok', 'fail'

  private settingsService: SettingsService | null = null;
  private unsubscribe: (() => void) | null = null;
  private configChangeCallback: () => void = () => {};
  private configCallbackId: number = -1;

  aboutToAppear(): void {
    this.settingsService = SettingsService.getInstance(getContext(this));
    const settings = this.settingsService.getSettings();
    this.localConfig = this.copyConfig(settings.crawler);

    this.unsubscribe = this.settingsService.subscribe((settings): void => {
      this.localConfig = this.copyConfig(settings.crawler);
    });

    const ctx = getContext(this) as common.UIAbilityContext;
    this.colorMode = ctx.config?.colorMode || 0;
    this.configChangeCallback = () => {
      this.colorMode = ctx.config?.colorMode || 0;
    };
    this.configCallbackId = ctx.getApplicationContext().on('environment', {
      onConfigurationUpdated: this.configChangeCallback,
      onMemoryLevel: (_level: number) => {}
    });
  }

  aboutToDisappear(): void {
    if (this.unsubscribe) {
      this.unsubscribe();
    }
    const ctx = getContext(this) as common.UIAbilityContext;
    if (this.configCallbackId !== -1) {
      ctx.getApplicationContext().off('environment', this.configCallbackId);
    }
  }

  private getColors(): ColorConfig {
    return getCrawlerSettingsColors(this.colorMode);
  }

  private copyConfig(config: CrawlerConfig): CrawlerConfig {
    return {
      maxPagesPerRun:     config.maxPagesPerRun,
      stopAfterOldPages:  config.stopAfterOldPages,
      requestDelay:       config.requestDelay,
      enableBreakpoint:   config.enableBreakpoint,
      autoCheckOnStartup: config.autoCheckOnStartup,
      checkIntervalHours: config.checkIntervalHours
    };
  }

  private setConfigField(
    field: string,
    value: number | boolean,
    saveToService: boolean = true
  ): void {
    // 整体替换对象，触发 @State 响应
    this.localConfig = {
      maxPagesPerRun:     field === 'maxPagesPerRun'     ? value as number  : this.localConfig.maxPagesPerRun,
      stopAfterOldPages:  field === 'stopAfterOldPages'  ? value as number  : this.localConfig.stopAfterOldPages,
      requestDelay:       field === 'requestDelay'       ? value as number  : this.localConfig.requestDelay,
      enableBreakpoint:   field === 'enableBreakpoint'   ? value as boolean : this.localConfig.enableBreakpoint,
      autoCheckOnStartup: field === 'autoCheckOnStartup' ? value as boolean : this.localConfig.autoCheckOnStartup,
      checkIntervalHours: field === 'checkIntervalHours' ? value as number  : this.localConfig.checkIntervalHours
    };

    if (saveToService) {
      const partialConfig: Partial<CrawlerConfig> = {};
      switch (field) {
        case 'maxPagesPerRun':     partialConfig.maxPagesPerRun     = value as number;  break;
        case 'stopAfterOldPages':  partialConfig.stopAfterOldPages  = value as number;  break;
        case 'requestDelay':       partialConfig.requestDelay       = value as number;  break;
        case 'enableBreakpoint':   partialConfig.enableBreakpoint   = value as boolean; break;
        case 'autoCheckOnStartup': partialConfig.autoCheckOnStartup = value as boolean; break;
        case 'checkIntervalHours': partialConfig.checkIntervalHours = value as number;  break;
      }
      this.settingsService?.updateCrawlerConfig(partialConfig);
    }
  }

  private resetToDefault(): void {
    const defaultConfig: CrawlerConfig = {
      maxPagesPerRun: 5,
      stopAfterOldPages: 2,
      requestDelay: 800,
      enableBreakpoint: true,
      autoCheckOnStartup: false,
      checkIntervalHours: 0
    };
    this.localConfig = this.copyConfig(defaultConfig);
    this.settingsService?.updateCrawlerConfig(defaultConfig);
    promptAction.showToast({ message: '已恢复默认设置' });
  }

  private async checkCookieValidity(): Promise<void> {
    if (!this.pixivSessionId.trim()) {
      promptAction.showToast({ message: '请先填入 PHPSESSID' });
      return;
    }
    this.cookieCheckState = 'checking';
    try {
      const svc = getPixivService();
      const result = await svc.checkLogin();

      if (!result.success) {
        this.cookieCheckState = 'idle';
        promptAction.showToast({ message: `⚠️ 网络异常，无法验证：${result.error}` });
        return;
      }

      const ok = result.data ?? false;
      this.cookieCheckState = ok ? 'ok' : 'fail';
      promptAction.showToast({
        message: ok ? '✅ Cookie 有效，登录成功' : '❌ Cookie 已失效，请重新获取'
      });
    } catch (_) {
      this.cookieCheckState = 'idle';
      promptAction.showToast({ message: '网络异常，无法验证（非 Cookie 问题）' });
    }
  }

  private clearCookie(): void {
    this.pixivSessionId = '';
    this.cookieCheckState = 'idle';
    clearSessionId();
    promptAction.showToast({ message: 'Cookie 已清除' });
  }

  // 添加验证方法
  private async checkApiKeyValidity(): Promise<void> {
    if (!this.deepseekApiKey.trim()) {
      promptAction.showToast({ message: '请先填入 API 密钥' });
      return;
    }

    this.apiKeyCheckState = 'checking';

    // 简单测试：翻译一个短句
    const service = getDeepSeekService();
    const result = await service.translateText('こんにちは', true);

    if (result.success) {
      this.apiKeyCheckState = 'ok';
      promptAction.showToast({ message: '✅ API 密钥有效' });
    } else {
      this.apiKeyCheckState = 'fail';
      promptAction.showToast({ message: `❌ ${result.error || '验证失败'}` });
    }
  }

  private clearApiKey(): void {
    this.deepseekApiKey = '';
    this.apiKeyCheckState = 'idle';
    clearDeepSeekApiKey();  // 持久化清除
    promptAction.showToast({ message: 'API 密钥已清除' });
  }

  // ─────────────────────────────────────────────
  // ✅ 修复一：三个 Slider 的标题行改为独立 @Builder，
  //    内部直接读取 this.localConfig.xxx，不通过参数传递
  // ─────────────────────────────────────────────

  @Builder
  MaxPagesHeader() {
    Row() {
      Column() {
        Text('单次最大页数')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.getColors().primaryText)
        Text('每次检查更新的最大翻页数')
          .fontSize(12)
          .fontColor(this.getColors().tertiaryText)
          .margin({ top: 4 })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)

      // 直接引用 @State 字段，响应式实时刷新
      Text(this.localConfig.maxPagesPerRun + ' 页')
        .fontSize(14)
        .fontColor(this.getColors().accentText)
    }.width('100%').margin({ bottom: 8 })
  }

  @Builder
  StopAfterOldPagesHeader() {
    Row() {
      Column() {
        Text('智能停止')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.getColors().primaryText)
        Text('连续多少页无新内容后自动停止')
          .fontSize(12)
          .fontColor(this.getColors().tertiaryText)
          .margin({ top: 4 })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)

      Text(this.localConfig.stopAfterOldPages + ' 页')
        .fontSize(14)
        .fontColor(this.getColors().accentText)
    }.width('100%').margin({ bottom: 8 })
  }

  @Builder
  RequestDelayHeader() {
    Row() {
      Column() {
        Text('请求间隔')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.getColors().primaryText)
        Text('防止请求过快被封')
          .fontSize(12)
          .fontColor(this.getColors().tertiaryText)
          .margin({ top: 4 })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)

      Text(this.localConfig.requestDelay + ' ms')
        .fontSize(14)
        .fontColor(this.getColors().accentText)
    }.width('100%').margin({ bottom: 8 })
  }

  @Builder
  CheckIntervalHeader() {
    Row() {
      Column() {
        Text('检查间隔')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.getColors().primaryText)
        Text('后台自动检查的时间间隔')
          .fontSize(12)
          .fontColor(this.getColors().tertiaryText)
          .margin({ top: 4 })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)

      Text(this.localConfig.checkIntervalHours + ' 小时')
        .fontSize(14)
        .fontColor(this.getColors().accentText)
    }.width('100%').margin({ bottom: 8 })
  }

  @Builder
  PixivCookieCard() {
    Column() {
      // 标题行
      Row() {
        Row() {
          Text('Pixiv 账号 Cookie')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.getColors().primaryText)

          if (this.cookieCheckState === 'ok') {
            Text(' ●').fontSize(12).fontColor('#52C41A')
          } else if (this.cookieCheckState === 'fail') {
            Text(' ●').fontSize(12).fontColor('#FF4D4F')
          } else if (this.pixivSessionId.length > 0 && this.cookieCheckState === 'idle') {
            Text(' ●').fontSize(12).fontColor('#FAAD14')
          }
        }.alignItems(VerticalAlign.Center)

        Blank()

        Text(this.showCookieText ? '隐藏' : '显示')
          .fontSize(13)
          .fontColor(this.getColors().accentText)
          .onClick((): void => {
            this.showCookieText = !this.showCookieText;
          })
      }
      .width('100%')
      .margin({ bottom: 10 })

      // 输入框
      TextInput({
        text: this.pixivSessionId,
        placeholder: '粘贴浏览器中的 PHPSESSID 值...'
      })
        .width('100%')
        .height(44)
        .fontSize(13)
        .fontColor(this.getColors().primaryText)
        .placeholderColor(this.getColors().tertiaryText)
        .backgroundColor(this.getColors().pageBg)
        .borderRadius(8)
        .padding({ left: 12, right: 12 })
        .border({
          width: 1,
          color: this.pixivSessionId.length === 0
            ? this.getColors().divider
            : this.cookieCheckState === 'ok'
              ? '#52C41A'
              : this.cookieCheckState === 'fail'
                ? '#FF4D4F'
                : this.getColors().accentText,
          radius: 8
        })
        .type(this.showCookieText ? InputType.Normal : InputType.Password)
        .onChange((val: string): void => {
          this.pixivSessionId = val;
          this.cookieCheckState = 'idle';
          saveSessionId(val);
        })

      // 操作按钮行
      Row() {
        Button(this.cookieCheckState === 'checking' ? '验证中...' : '验证 Cookie')
          .fontSize(13)
          .height(36)
          .layoutWeight(1)
          .fontColor('#FFFFFF')
          .backgroundColor(
            this.cookieCheckState === 'ok'   ? '#52C41A' :
              this.cookieCheckState === 'fail' ? '#FF4D4F' :
                this.getColors().accentText
          )
          .borderRadius(8)
          .enabled(this.cookieCheckState !== 'checking')
          .onClick((): void => { this.checkCookieValidity(); })

        if (this.pixivSessionId.length > 0) {
          Button('清除')
            .fontSize(13)
            .height(36)
            .fontColor(this.getColors().dangerText)
            .backgroundColor(Color.Transparent)
            .borderRadius(8)
            .margin({ left: 8 })
            .onClick((): void => { this.clearCookie(); })
        }
      }
      .width('100%')
      .margin({ top: 12 })

      // 底部说明
      Text('在浏览器登录 pixiv.net 后，打开开发者工具 → Application → Cookies，找到 PHPSESSID 复制粘贴到此处')
        .fontSize(11)
        .fontColor(this.getColors().hintText)
        .margin({ top: 10 })
        .lineHeight(18)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.getColors().cardBg)
    .borderRadius(12)
    .margin({ bottom: 12 })
  }

  @Builder
  DeepSeekApiKeyCard() {
    Column() {
      // 标题行
      Row() {
        Row() {
          Text('DeepSeek API 密钥')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.getColors().primaryText)

          if (this.apiKeyCheckState === 'ok') {
            Text(' ●').fontSize(12).fontColor('#52C41A')
          } else if (this.apiKeyCheckState === 'fail') {
            Text(' ●').fontSize(12).fontColor('#FF4D4F')
          } else if (this.deepseekApiKey.length > 0 && this.apiKeyCheckState === 'idle') {
            Text(' ●').fontSize(12).fontColor('#FAAD14')
          }
        }.alignItems(VerticalAlign.Center)

        Blank()

        Text(this.showApiKeyText ? '隐藏' : '显示')
          .fontSize(13)
          .fontColor(this.getColors().accentText)
          .onClick((): void => {
            this.showApiKeyText = !this.showApiKeyText;
          })
      }
      .width('100%')
      .margin({ bottom: 10 })

      // 输入框
      TextInput({
        text: this.deepseekApiKey,
        placeholder: '粘贴 DeepSeek API 密钥...'
      })
        .width('100%')
        .height(44)
        .fontSize(13)
        .fontColor(this.getColors().primaryText)
        .placeholderColor(this.getColors().tertiaryText)
        .backgroundColor(this.getColors().pageBg)
        .borderRadius(8)
        .padding({ left: 12, right: 12 })
        .border({
          width: 1,
          color: this.deepseekApiKey.length === 0
            ? this.getColors().divider
            : this.apiKeyCheckState === 'ok'
              ? '#52C41A'
              : this.apiKeyCheckState === 'fail'
                ? '#FF4D4F'
                : this.getColors().accentText,
          radius: 8
        })
        .type(this.showApiKeyText ? InputType.Normal : InputType.Password)
        .onChange((val: string): void => {
          this.deepseekApiKey = val;
          this.apiKeyCheckState = 'idle';
          saveDeepSeekApiKey(val);  // 持久化到磁盘
        })

      // 操作按钮行
      Row() {
        Button(this.apiKeyCheckState === 'checking' ? '验证中...' : '验证密钥')
          .fontSize(13)
          .height(36)
          .layoutWeight(1)
          .fontColor('#FFFFFF')
          .backgroundColor(this.getColors().accentText)
          .borderRadius(8)
          .enabled(this.apiKeyCheckState !== 'checking' && this.deepseekApiKey.length > 0)
          .onClick((): void => { this.checkApiKeyValidity(); })

        if (this.deepseekApiKey.length > 0) {
          Button('清除')
            .fontSize(13)
            .height(36)
            .fontColor(this.getColors().dangerText)
            .backgroundColor(Color.Transparent)
            .borderRadius(8)
            .margin({ left: 8 })
            .onClick((): void => { this.clearApiKey(); })
        }
      }
      .width('100%')
      .margin({ top: 12 })

      // 底部说明
      Text('前往 deepseek.com 注册获取 API 密钥，用于翻译日文小说标题和内容')
        .fontSize(11)
        .fontColor(this.getColors().hintText)
        .margin({ top: 10 })
        .lineHeight(18)

      // 价格提示
      Text('约 ¥0.002 / 1K 字符（仅供参考，以官方价格为准）')
        .fontSize(10)
        .fontColor(this.getColors().tertiaryText)
        .margin({ top: 4 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.getColors().cardBg)
    .borderRadius(12)
    .margin({ bottom: 12 })
  }

  @Builder
  ToggleItemBuilder(title: string, desc: string, isOn: boolean, onChange: (val: boolean) => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.getColors().primaryText)
        Text(desc)
          .fontSize(12)
          .fontColor(this.getColors().tertiaryText)
          .margin({ top: 4 })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .onChange(onChange)
        .selectedColor(this.getColors().toggleOn)
        .switchPointColor(this.getColors().cardBg)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.getColors().cardBg)
    .borderRadius(12)
    .margin({ bottom: 12 })
  }

  build() {
    // ✅ 修复二：Scroll 包裹，解决底部卡片被遮挡无法滚动的问题
    Scroll() {
      Column() {
        // 标题栏
        Row() {
          Text('爬取参数')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.getColors().primaryText)
          Blank()
          Button('重置')
            .fontSize(14)
            .fontColor(this.getColors().dangerText)
            .backgroundColor(Color.Transparent)
            .onClick(() => this.resetToDefault())
        }
        .width('100%')
        .padding({ top: 16, bottom: 16 })

        // Pixiv Cookie 卡片
        this.PixivCookieCard()

        this.DeepSeekApiKeyCard()

        // 1. 单次最大页数
        Column() {
          this.MaxPagesHeader()  // ✅ 改用独立 @Builder，内部直接读 @State
          Slider({
            value: this.localConfig.maxPagesPerRun,
            min: 1,
            max: 600,
            step: 1
          })
            .width('100%')
            .showTips(true)
            .trackColor(this.getColors().sliderTrack)
            .blockColor(this.getColors().sliderBlock)
            .selectedColor(this.getColors().accentText)
            .onChange((val: number, mode: SliderChangeMode): void => {
              this.setConfigField('maxPagesPerRun', val, false);
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                this.settingsService?.updateCrawlerConfig({ maxPagesPerRun: val });
              }
            })
        }
        .width('100%')
        .padding(16)
        .backgroundColor(this.getColors().cardBg)
        .borderRadius(12)
        .margin({ bottom: 12 })

        // 2. 连续旧页停止
        Column() {
          this.StopAfterOldPagesHeader()  // ✅ 改用独立 @Builder
          Slider({
            value: this.localConfig.stopAfterOldPages,
            min: 1,
            max: 5,
            step: 1
          })
            .width('100%')
            .showTips(true)
            .trackColor(this.getColors().sliderTrack)
            .blockColor(this.getColors().sliderBlock)
            .selectedColor(this.getColors().accentText)
            .onChange((val: number, mode: SliderChangeMode): void => {
              this.setConfigField('stopAfterOldPages', val, false);
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                this.settingsService?.updateCrawlerConfig({ stopAfterOldPages: val });
              }
            })
        }
        .width('100%')
        .padding(16)
        .backgroundColor(this.getColors().cardBg)
        .borderRadius(12)
        .margin({ bottom: 12 })

        // 3. 请求间隔
        Column() {
          this.RequestDelayHeader()  // ✅ 改用独立 @Builder
          Slider({
            value: this.localConfig.requestDelay,
            min: 500,
            max: 3000,
            step: 100
          })
            .width('100%')
            .showTips(true)
            .trackColor(this.getColors().sliderTrack)
            .blockColor(this.getColors().sliderBlock)
            .selectedColor(this.getColors().accentText)
            .onChange((val: number, mode: SliderChangeMode): void => {
              this.setConfigField('requestDelay', val, false);
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                this.settingsService?.updateCrawlerConfig({ requestDelay: val });
              }
            })
        }
        .width('100%')
        .padding(16)
        .backgroundColor(this.getColors().cardBg)
        .borderRadius(12)
        .margin({ bottom: 12 })

        // 4. 断点续爬
        this.ToggleItemBuilder(
          '断点续爬',
          '网络中断后从上次位置继续',
          this.localConfig.enableBreakpoint,
          (val: boolean): void => { this.setConfigField('enableBreakpoint', val, true); }
        )

        // 5. 启动时自动检查
        this.ToggleItemBuilder(
          '启动时自动检查',
          '打开应用时自动检查更新',
          this.localConfig.autoCheckOnStartup,
          (val: boolean): void => { this.setConfigField('autoCheckOnStartup', val, true); }
        )

        // 6. 后台检查间隔（仅在开启自动检查时显示）
        if (this.localConfig.autoCheckOnStartup) {
          Column() {
            this.CheckIntervalHeader()  // ✅ 改用独立 @Builder
            Slider({
              value: this.localConfig.checkIntervalHours,
              min: 0,
              max: 24,
              step: 1
            })
              .width('100%')
              .showTips(true)
              .trackColor(this.getColors().sliderTrack)
              .blockColor(this.getColors().sliderBlock)
              .selectedColor(this.getColors().accentText)
              .onChange((val: number, mode: SliderChangeMode): void => {
                this.setConfigField('checkIntervalHours', val, false);
                if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                  this.settingsService?.updateCrawlerConfig({ checkIntervalHours: val });
                }
              })
            Text('设为 0 表示仅启动时检查一次')
              .fontSize(11)
              .fontColor(this.getColors().hintText)
              .margin({ top: 8 })
          }
          .width('100%')
          .padding(16)
          .backgroundColor(this.getColors().cardBg)
          .borderRadius(12)
          .margin({ bottom: 12 })
        }

        // 底部提示文字
        Text('提示：请求间隔建议保持 800ms 以上，避免被封 IP')
          .fontSize(12)
          .fontColor(this.getColors().hintText)
          .margin({ top: 8, bottom: 32 })  // bottom: 32 留出底部安全间距
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      .backgroundColor(this.getColors().pageBg)
    }
    .width('100%')
    .height('100%')              // ✅ Scroll 必须有明确高度才能生效
    .scrollBar(BarState.Off)     // 隐藏滚动条
    .edgeEffect(EdgeEffect.Spring) // 弹性回弹效果
    .backgroundColor(this.getColors().pageBg)
  }
}