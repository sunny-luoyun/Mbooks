// entry/src/main/ets/components/reader/ReaderStyles.ets

// 颜色模式类型
export enum ColorMode {
  LIGHT = 0,
  DARK = 1
}

// 动态主题类 - 根据当前颜色模式返回对应颜色
export class Theme {
  // 当前颜色模式，从 AppStorage 获取
  static getCurrentMode(): ColorMode {
    const mode = AppStorage.get<number>('currentColorMode');
    return mode === 0 ? ColorMode.DARK : ColorMode.LIGHT;
  }

  static isDarkMode(): boolean {
    return Theme.getCurrentMode() === ColorMode.DARK;
  }

  // 背景色：护眼纸纹色 / 深色背景
  static get BG_COLOR(): string {
    return Theme.isDarkMode() ? '#1A1A1A' : '#F4EFE7';
  }

  // 为了兼容性保留静态常量（浅色模式默认值）
  static readonly BG_COLOR_LIGHT: string = '#F4EFE7';
  static readonly BG_COLOR_DARK: string = '#1A1A1A';

  // 文字颜色
  static get TEXT_MAIN(): string {
    return Theme.isDarkMode() ? '#E0E0E0' : '#2C2C2C';
  }

  static get TEXT_SECONDARY(): string {
    return Theme.isDarkMode() ? '#888888' : '#8A8A8A';
  }

  static get TEXT_ACCENT(): string {
    return Theme.isDarkMode() ? '#E74C3C' : '#C0392B'; // 深色模式用更亮的砖红
  }

  // 组件背景
  static get BAR_BG(): string {
    return Theme.isDarkMode() ? '#262626' : '#FDFBF7';
  }

  static get BAR_BG_DARK(): string {
    return '#262626'; // 保持原有常量
  }

  static get PANEL_BG(): string {
    return Theme.isDarkMode() ? '#2D2D2D' : '#FFFFFF';
  }

  // 字体大小（保持不变）
  static readonly FONT_CHAPTER: number = 22;
  static readonly FONT_BODY: number = 18;
  static readonly FONT_SMALL: number = 14;

  // 间距（保持不变）
  static readonly PAGE_PADDING: number = 24;
  static readonly LINE_HEIGHT: number = 32;
}

// 布局配置（用于分页计算）- 保持不变
export class LayoutConfig {
  static readonly CHAR_WIDTH: number = 9;
  static readonly TOP_MARGIN: number = 40;
  static readonly BOTTOM_MARGIN: number = 60;
  static readonly SAFE_BOTTOM_MARGIN: number = 20;
}

// 动画配置 - 保持不变
export class Animations {
  static readonly FADE_IN: AnimationConfig = { duration: 200, curve: Curve.EaseInOut };
  static readonly SLIDE_UP: AnimationConfig = { duration: 300, curve: Curve.EaseOut };
}

interface AnimationConfig {
  duration: number;
  curve: Curve;
}