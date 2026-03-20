// entry/src/main/ets/components/settings/BookSettings.ets
import { SettingsService } from '../../services/SettingsService';
import { WatchedBook } from '../../models/SettingsModels';
import promptAction from '@ohos.promptAction';
import router from '@ohos.router';
import { Configuration } from '@ohos.app.ability.Configuration';
import common from '@ohos.app.ability.common';

interface ColorScheme {
  pageBg: string;
  cardBg: string;
  headerBg: string;
  primaryText: string;
  secondaryText: string;
  tertiaryText: string;
  quaternaryText: string;
  accentText: string;
  successText: string;
  dangerText: string;
  whiteText: string;
  notifyToggleOn: string;
  downloadToggleOn: string;
  toggleOff: string;
  autoDownloadTagBg: string;
  autoDownloadTagBorder: string;
  doNotDisturbTagBg: string;
  primaryBtnBg: string;
  deleteBtnBg: string;
  emptyIcon: string;
  emptyText: string;
  emptySubText: string;
  divider: string;
}
// 颜色配置函数 - 根据模式返回对应颜色
function getBookSettingsColors(mode: number): ColorScheme {
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
    quaternaryText: isDark ? '#888888' : '#BBBBBB',
    accentText: '#007DFF',
    successText: '#52C41A',
    dangerText: '#FF4D4F',
    whiteText: '#FFFFFF',

    // 开关颜色
    notifyToggleOn: '#007DFF',
    downloadToggleOn: '#52C41A',
    toggleOff: isDark ? '#3A3A3A' : '#CCCCCC',

    // 标签背景
    autoDownloadTagBg: isDark ? '#1A331A' : '#F6FFED',
    autoDownloadTagBorder: isDark ? '#2F5A2F' : '#B7EB8F',
    doNotDisturbTagBg: isDark ? '#2A2A2A' : '#F5F5F5',

    // 按钮
    primaryBtnBg: '#007DFF',
    deleteBtnBg: '#FF4D4F',

    // 空状态
    emptyIcon: isDark ? '#444444' : '#CCCCCC',
    emptyText: isDark ? '#666666' : '#999999',
    emptySubText: isDark ? '#444444' : '#BBBBBB',

    // 分割线
    divider: isDark ? '#2A2A2A' : '#E5E5E5'
  };
}
@Component
export struct BookSettings {
  @State books: WatchedBook[] = [];
  @State colorMode: number = 0; // 0 = Light, 1 = Dark
  private settingsService: SettingsService | null = null;
  private unsubscribe: (() => void) | null = null;
  private configChangeCallback: (config: Configuration) => void = () => {};
  private configCallbackId: number = -1;

  aboutToAppear(): void {
    this.settingsService = SettingsService.getInstance(getContext(this));
    this.unsubscribe = this.settingsService.subscribe((settings): void => {
      // 深拷贝避免引用问题
      const books: WatchedBook[] = settings.books;
      const copied: WatchedBook[] = [];
      for (let i: number = 0; i < books.length; i++) {
        copied.push({
          threadId: books[i].threadId,
          title: books[i].title,
          addTime: books[i].addTime,
          notifyOnUpdate: books[i].notifyOnUpdate,
          autoDownload: books[i].autoDownload
        });
      }
      this.books = copied;
    });
    // 初始化颜色模式
    const ctx = getContext(this) as common.UIAbilityContext;
    this.colorMode = ctx.config.colorMode ?? 0;
    // 监听系统颜色模式变化
    this.configChangeCallback = (config: Configuration) => {
      this.colorMode = config.colorMode ?? 0;
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
  private getColors(): ColorScheme {
    return getBookSettingsColors(this.colorMode);
  }

  private removeBook(threadId: string, title: string): void {
    this.settingsService?.removeWatchedBook(threadId);
    promptAction.showToast({ message: '已取消关注《' + title + '》' });
  }

  private updateBookNotify(book: WatchedBook, val: boolean): void {
    const success: boolean = this.settingsService?.updateWatchedBookNotify(book.threadId, val) || false;
    if (!success) {
      promptAction.showToast({ message: '更新失败' });
    }
  }

  private updateBookAutoDownload(book: WatchedBook, val: boolean): void {
    const success: boolean = this.settingsService?.updateWatchedBookAutoDownload(book.threadId, val) || false;
    if (!success) {
      promptAction.showToast({ message: '更新失败' });
    }
  }

  // 清空所有关注
  private clearAllBooks(): void {
    if (this.books.length === 0) return;

    const ids: string[] = [];
    for (let i: number = 0; i < this.books.length; i++) {
      ids.push(this.books[i].threadId);
    }
    for (let i: number = 0; i < ids.length; i++) {
      this.settingsService?.removeWatchedBook(ids[i]);
    }
    promptAction.showToast({ message: '已清空所有关注书籍' });
  }

  // 跳转到详情页
  private goToDetail(book: WatchedBook): void {
    router.pushUrl({
      url: 'pages/DetailPage',
      params: { threadId: book.threadId, title: book.title }
    });
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Text('关注书籍')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getColors().primaryText)
        Blank()
        if (this.books.length > 0) {
          Button('清空')
            .fontSize(14)
            .fontColor(this.getColors().dangerText)
            .backgroundColor(Color.Transparent)
            .onClick((): void => this.clearAllBooks())
        }
      }
      .width('100%')
      .margin({ bottom: 8 })

      Text('在书籍详情页点击"关注"添加，或点击卡片查看详情')
        .fontSize(12)
        .fontColor(this.getColors().tertiaryText)
        .margin({ bottom: 16 })

      // 统计信息
      if (this.books.length > 0) {
        Row() {
          Text('共 ' + this.books.length + ' 本书')
            .fontSize(12)
            .fontColor(this.getColors().tertiaryText)
          Blank()
          Text('自动下载: ' + this.books.filter((b: WatchedBook): boolean => b.autoDownload).length + ' 本')
            .fontSize(12)
            .fontColor(this.getColors().successText)
        }
        .width('100%')
        .padding({ left: 4, right: 4, bottom: 8 })
      }

      // 列表
      List({ space: 8 }) {
        ForEach(this.books, (book: WatchedBook): void => {
          ListItem() {
            Column() {
              // 第一行：标题和状态标签
              Row() {
                Text(book.title)
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.getColors().primaryText)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                // 状态标签
                if (book.autoDownload) {
                  Text('自动')
                    .fontSize(10)
                    .fontColor(this.getColors().successText)
                    .backgroundColor(this.getColors().autoDownloadTagBg)
                    .border({ width: 1, color: this.getColors().autoDownloadTagBorder })
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .borderRadius(4)
                    .margin({ left: 8 })
                }
                if (!book.notifyOnUpdate) {
                  Text('免打扰')
                    .fontSize(10)
                    .fontColor(this.getColors().tertiaryText)
                    .backgroundColor(this.getColors().doNotDisturbTagBg)
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .borderRadius(4)
                    .margin({ left: 8 })
                }
              }
              .width('100%')

              // 第二行：ID和添加时间
              Row() {
                Text('ID: ' + book.threadId)
                  .fontSize(12)
                  .fontColor(this.getColors().tertiaryText)
                Blank()
                Text(this.formatDate(book.addTime))
                  .fontSize(12)
                  .fontColor(this.getColors().tertiaryText)
              }
              .width('100%')
              .margin({ top: 6, bottom: 12 })

              // 第三行：操作开关
              Row() {
                // 通知开关
                Row() {
                  Toggle({ type: ToggleType.Switch, isOn: book.notifyOnUpdate })
                    .selectedColor(this.getColors().notifyToggleOn)
                    .switchPointColor(this.getColors().cardBg)
                    .scale({ x: 0.8, y: 0.8 })
                    .onChange((val: boolean): void => {
                      this.updateBookNotify(book, val);
                    })
                  Text('更新通知')
                    .fontSize(12)
                    .fontColor(book.notifyOnUpdate ? this.getColors().accentText : this.getColors().tertiaryText)
                    .margin({ left: 4 })
                }

                Blank()

                // 自动下载开关
                Row() {
                  Toggle({ type: ToggleType.Switch, isOn: book.autoDownload })
                    .selectedColor(this.getColors().downloadToggleOn)
                    .switchPointColor(this.getColors().cardBg)
                    .scale({ x: 0.8, y: 0.8 })
                    .onChange((val: boolean): void => {
                      this.updateBookAutoDownload(book, val);
                    })
                  Text('自动下载')
                    .fontSize(12)
                    .fontColor(book.autoDownload ? this.getColors().successText : this.getColors().tertiaryText)
                    .margin({ left: 4 })
                }

                Blank()

                // 删除按钮
                Button() {
                  Text('删除')
                    .fontSize(12)
                    .fontColor(this.getColors().dangerText)
                }
                .backgroundColor(Color.Transparent)
                .onClick((): void => this.removeBook(book.threadId, book.title))
              }
              .width('100%')
            }
            .width('100%')
            .padding(16)
          }
          .backgroundColor(this.getColors().cardBg)
          .borderRadius(12)
          .onClick((): void => this.goToDetail(book))
          .swipeAction({ end: this.DeleteBuilder(book.threadId, book.title) })
        }, (book: WatchedBook): string => book.threadId)
      }
      .width('100%')
      .layoutWeight(1)

      // 空状态
      if (this.books.length === 0) {
        Column() {
          Text('📚')
            .fontSize(60)
            .fontColor(this.getColors().emptyIcon)
            .margin({ bottom: 16 })
          Text('暂无关注书籍')
            .fontSize(16)
            .fontColor(this.getColors().emptyText)
          Text('关注喜欢的书籍，自动获取更新')
            .fontSize(12)
            .fontColor(this.getColors().emptySubText)
            .margin({ top: 8 })
          Button('去搜索书籍')
            .margin({ top: 24 })
            .fontColor(this.getColors().whiteText)
            .backgroundColor(this.getColors().primaryBtnBg)
            .onClick((): void => {
              // 跳转到搜索页，需要Index页面支持或router跳转
              // 这里简单提示
              promptAction.showToast({ message: '请切换到搜索页查找书籍' });
            })
        }
        .margin({ top: 80 })
      }
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor(this.getColors().pageBg)
  }

  // 删除按钮构建器（左滑）
  @Builder
  DeleteBuilder(threadId: string, title: string) {
    Button() {
      Text('删除')
        .fontColor(this.getColors().whiteText)
        .fontSize(14)
    }
    .width(60)
    .height('100%')
    .backgroundColor(this.getColors().deleteBtnBg)
    .onClick((): void => this.removeBook(threadId, title))
  }

  // 辅助方法：格式化日期
  private formatDate(timestamp: number): string {
    const date: Date = new Date(timestamp);
    const now: Date = new Date();
    const diff: number = now.getTime() - date.getTime();
    const days: number = Math.floor(diff / (1000 * 60 * 60 * 24));

    if (days === 0) return '今天';
    if (days === 1) return '昨天';
    if (days < 7) return days + '天前';
    if (days < 30) return Math.floor(days / 7) + '周前';

    return date.getFullYear() + '-' + (date.getMonth() + 1) + '-' + date.getDate();
  }
}