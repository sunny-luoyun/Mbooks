// entry/src/main/ets/components/settings/CrawlerSettings.ets
import { CrawlerConfig } from '../../models/SettingsModels';
import { SettingsService } from '../../services/SettingsService';
import promptAction from '@ohos.promptAction';
import { Configuration } from '@ohos.app.ability.Configuration';
import common from '@ohos.app.ability.common';
// ✅ 修复：静态导入，替代之前的动态 import + 解构
import { getPixivService } from '../../services/PixivService';
import { saveSessionId, clearSessionId } from '../../utils/PreferencesUtil';

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
    pageBg: isDark ? '#0D0D0D' : '#F5F5F5',
    cardBg: isDark ? '#1E1E1E' : '#FFFFFF',
    headerBg: isDark ? '#141414' : '#FFFFFF',
    primaryText: isDark ? '#E6E6E6' : '#000000',
    secondaryText: isDark ? '#999999' : '#666666',
    tertiaryText: isDark ? '#666666' : '#999999',
    accentText: '#007DFF',
    dangerText: '#FF4D4F',
    sliderTrack: isDark ? '#3A3A3A' : '#E5E5E5',
    sliderBlock: '#007DFF',
    toggleOn: '#007DFF',
    toggleOff: isDark ? '#3A3A3A' : '#CCCCCC',
    hintText: isDark ? '#555555' : '#999999',
    divider: isDark ? '#2A2A2A' : '#E5E5E5'
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
      onMemoryLevel: (level: number) => {}
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
      maxPagesPerRun: config.maxPagesPerRun,
      stopAfterOldPages: config.stopAfterOldPages,
      requestDelay: config.requestDelay,
      enableBreakpoint: config.enableBreakpoint,
      autoCheckOnStartup: config.autoCheckOnStartup,
      checkIntervalHours: config.checkIntervalHours
    };
  }

  private setConfigField(
    field: string,
    value: number | boolean,
    saveToService: boolean = true
  ): void {
    this.localConfig = {
      maxPagesPerRun:    field === 'maxPagesPerRun'    ? value as number  : this.localConfig.maxPagesPerRun,
      stopAfterOldPages: field === 'stopAfterOldPages' ? value as number  : this.localConfig.stopAfterOldPages,
      requestDelay:      field === 'requestDelay'      ? value as number  : this.localConfig.requestDelay,
      enableBreakpoint:  field === 'enableBreakpoint'  ? value as boolean : this.localConfig.enableBreakpoint,
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

  // ✅ 修复：去掉动态 import 和解构，直接调用顶部静态导入的 getPixivService
  private async checkCookieValidity(): Promise<void> {
    if (!this.pixivSessionId.trim()) {
      promptAction.showToast({ message: '请先填入 PHPSESSID' });
      return;
    }
    this.cookieCheckState = 'checking';
    try {
      const svc = getPixivService();
      const result = await svc.checkLogin();   // 现在返回 ServiceResult<boolean>

      if (!result.success) {
        // 网络错误，不是 Cookie 问题
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
      this.cookieCheckState = 'idle';   // 注意：这里改为 'idle' 而非 'fail'
      promptAction.showToast({ message: '网络异常，无法验证（非 Cookie 问题）' });
    }
  }

  private clearCookie(): void {
    this.pixivSessionId = '';
    this.cookieCheckState = 'idle';
    clearSessionId();  // ✅ 同时从磁盘清除
    promptAction.showToast({ message: 'Cookie 已清除' });
  }

  @Builder
  ItemHeader(title: string, desc: string, value: string) {
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

      Text(value)
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
            Text(' ●')
              .fontSize(12)
              .fontColor('#52C41A')
          } else if (this.cookieCheckState === 'fail') {
            Text(' ●')
              .fontSize(12)
              .fontColor('#FF4D4F')
          } else if (this.pixivSessionId.length > 0 && this.cookieCheckState === 'idle') {
            Text(' ●')
              .fontSize(12)
              .fontColor('#FAAD14')
          }
        }
        .alignItems(VerticalAlign.Center)

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
          // ✅ 实时持久化，防止用户输一半就退出
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

  build() {
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

      // 1. 单次最大页数
      Column() {
        this.ItemHeader('单次最大页数', '每次检查更新的最大翻页数', this.localConfig.maxPagesPerRun + '页')
        Slider({
          value: this.localConfig.maxPagesPerRun,
          min: 1,
          max: 300,
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
        this.ItemHeader('智能停止', '连续多少页无新内容后自动停止', this.localConfig.stopAfterOldPages + '页')
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
        this.ItemHeader('请求间隔', '防止请求过快被封', this.localConfig.requestDelay + 'ms')
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
      this.ToggleItemBuilder('断点续爬', '网络中断后从上次位置继续', this.localConfig.enableBreakpoint, (val: boolean): void => {
        this.setConfigField('enableBreakpoint', val, true);
      })

      // 5. 启动时自动检查
      this.ToggleItemBuilder('启动时自动检查', '打开应用时自动检查更新', this.localConfig.autoCheckOnStartup, (val: boolean): void => {
        this.setConfigField('autoCheckOnStartup', val, true);
      })

      // 6. 后台检查间隔
      if (this.localConfig.autoCheckOnStartup) {
        Column() {
          this.ItemHeader('检查间隔', '后台自动检查的时间间隔', this.localConfig.checkIntervalHours + '小时')
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
          Text('设为0表示仅启动时检查一次')
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

      Text('提示：请求间隔建议保持800ms以上，避免被封IP')
        .fontSize(12)
        .fontColor(this.getColors().hintText)
        .margin({ top: 8, bottom: 20 })
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .backgroundColor(this.getColors().pageBg)
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
}