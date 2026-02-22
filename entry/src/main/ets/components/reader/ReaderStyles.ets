// entry/src/main/ets/components/reader/ReaderStyles.ets

// 主题配置
export class Theme {
  // 背景色：护眼纸纹色
  static readonly BG_COLOR: string = '#F4EFE7';
  static readonly BG_COLOR_DARK: string = '#1A1A1A';

  // 文字颜色
  static readonly TEXT_MAIN: string = '#2C2C2C';
  static readonly TEXT_SECONDARY: string = '#8A8A8A';
  static readonly TEXT_ACCENT: string = '#C0392B'; // 砖红色

  // 组件背景
  static readonly BAR_BG: string = '#FDFBF7';
  static readonly BAR_BG_DARK: string = '#262626';
  static readonly PANEL_BG: string = '#FFFFFF';

  // 字体大小
  static readonly FONT_CHAPTER: number = 22;
  static readonly FONT_BODY: number = 18;
  static readonly FONT_SMALL: number = 14;

  // 间距
  static readonly PAGE_PADDING: number = 24;
  // 修复：行高需要略大于字体大小，确保不重叠
  static readonly LINE_HEIGHT: number = 32; // 原来是34，稍微减小以容纳更多行，但要确保大于FONT_BODY(18)
}

// 布局配置（用于分页计算）
export class LayoutConfig {
  // 字符宽度估算（根据字体大小18sp估算）
  // 修复：更精确的估算，中文约等于字体大小，英文约一半
  static readonly CHAR_WIDTH: number = 9;  // 这个值在ReaderPage中不再直接使用，改用 FONT_BODY * 0.9

  // 页面边距
  static readonly TOP_MARGIN: number = 40;
  static readonly BOTTOM_MARGIN: number = 60;

  // 修复：安全底部边距，防止最后一行被截断
  static readonly SAFE_BOTTOM_MARGIN: number = 20;
}

// 动画配置
export class Animations {
  static readonly FADE_IN: AnimationConfig = { duration: 200, curve: Curve.EaseInOut };
  static readonly SLIDE_UP: AnimationConfig = { duration: 300, curve: Curve.EaseOut };
}

interface AnimationConfig {
  duration: number;
  curve: Curve;
}