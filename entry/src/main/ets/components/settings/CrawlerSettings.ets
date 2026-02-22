// entry/src/main/ets/components/settings/CrawlerSettings.ets
import { CrawlerConfig } from '../../models/SettingsModels';
import { SettingsService } from '../../services/SettingsService';
import promptAction from '@ohos.promptAction';
import { Configuration } from '@ohos.app.ability.Configuration';
import common from '@ohos.app.ability.common';

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

// 颜色配置函数 - 根据模式返回对应颜色
function getCrawlerSettingsColors(mode: number): ColorConfig {
  const isDark = mode === 0; // ColorMode.Dark = 1
  return {
    // 背景色
    pageBg: isDark ? '#0D0D0D' : '#F5F5F5',
    cardBg: isDark ? '#1E1E1E' : '#FFFFFF',
    headerBg: isDark ? '#141414' : '#FFFFFF',

    // 文字色
    primaryText: isDark ? '#E6E6E6' : '#000000',
    secondaryText: isDark ? '#999999' : '#666666',
    tertiaryText: isDark ? '#666666' : '#999999',
    accentText: '#007DFF',
    dangerText: '#FF4D4F',

    // 滑块颜色
    sliderTrack: isDark ? '#3A3A3A' : '#E5E5E5',
    sliderBlock: '#007DFF',

    // 开关颜色
    toggleOn: '#007DFF',
    toggleOff: isDark ? '#3A3A3A' : '#CCCCCC',

    // 提示文字
    hintText: isDark ? '#555555' : '#999999',

    // 分割线（如有需要）
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
  @State colorMode: number = 0; // 0 = Light, 1 = Dark
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
    // 初始化颜色模式
    const ctx = getContext(this) as common.UIAbilityContext;
    this.colorMode = ctx.config?.colorMode || 0;
    // 监听系统颜色模式变化 - 使用ApplicationContext的配置监听
    this.configChangeCallback = () => {
      this.colorMode = ctx.config?.colorMode || 0;
    };
    this.configCallbackId = ctx.getApplicationContext().on('environment', {
      onConfigurationUpdated: this.configChangeCallback,
      onMemoryLevel: (level: number) => {
        // 内存级别变化的处理
      }
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
  // 获取当前颜色配置
  private getColors(): ColorConfig {
    return getCrawlerSettingsColors(this.colorMode);
  }

  // 深拷贝配置
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

  // 关键方法：更新指定字段，替换整个对象触发UI
  private setConfigField(
    field: string,
    value: number | boolean,
    saveToService: boolean = true
  ): void {
    // 创建新对象，确保ArkTS检测到变化
    this.localConfig = {
      maxPagesPerRun: field === 'maxPagesPerRun' ? value as number : this.localConfig.maxPagesPerRun,
      stopAfterOldPages: field === 'stopAfterOldPages' ? value as number : this.localConfig.stopAfterOldPages,
      requestDelay: field === 'requestDelay' ? value as number : this.localConfig.requestDelay,
      enableBreakpoint: field === 'enableBreakpoint' ? value as boolean : this.localConfig.enableBreakpoint,
      autoCheckOnStartup: field === 'autoCheckOnStartup' ? value as boolean : this.localConfig.autoCheckOnStartup,
      checkIntervalHours: field === 'checkIntervalHours' ? value as number : this.localConfig.checkIntervalHours
    };

    // 保存到Service
    if (saveToService) {
      // 使用条件判断替代动态属性名
      const partialConfig: Partial<CrawlerConfig> = {};
      switch (field) {
        case 'maxPagesPerRun':
          partialConfig.maxPagesPerRun = value as number;
          break;
        case 'stopAfterOldPages':
          partialConfig.stopAfterOldPages = value as number;
          break;
        case 'requestDelay':
          partialConfig.requestDelay = value as number;
          break;
        case 'enableBreakpoint':
          partialConfig.enableBreakpoint = value as boolean;
          break;
        case 'autoCheckOnStartup':
          partialConfig.autoCheckOnStartup = value as boolean;
          break;
        case 'checkIntervalHours':
          partialConfig.checkIntervalHours = value as number;
          break;
      }
      this.settingsService?.updateCrawlerConfig(partialConfig);
    }
  }

  // 重置为默认
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

  // 头部文字信息组件
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
            // 实时更新UI（不保存到Service）
            this.setConfigField('maxPagesPerRun', val, false);
            // 滑动结束时保存
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

      // 底部说明
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