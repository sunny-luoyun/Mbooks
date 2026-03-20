// entry/src/main/ets/components/settings/AuthorSettings.ets
import { SettingsService } from '../../services/SettingsService';
import { WatchedAuthor } from '../../models/SettingsModels';
import promptAction from '@ohos.promptAction';
import router from '@ohos.router';
import { Configuration } from '@ohos.app.ability.Configuration';
import common from '@ohos.app.ability.common';

interface ColorConfig {
  pageBg: string;
  cardBg: string;
  inputBg: string;
  deleteBtnBg: string;
  primaryText: string;
  secondaryText: string;
  tertiaryText: string;
  quaternaryText: string;
  accentText: string;
  dangerText: string;
  whiteText: string;
  toggleOn: string;
  toggleOff: string;
  hotTagBg: string;
  hotTagText: string;
  emptyIcon: string;
  emptyText: string;
  emptySubText: string;
  divider: string;
}

// 颜色配置函数 - 统一判断逻辑：0为浅色，1为深色
function getAuthorSettingsColors(mode: number): ColorConfig {
  const isDark = mode === 0; // 与 CrawlerSettings 逻辑保持一致，若系统返回0代表深色(具体取决于你的环境定义)
  // 注意：在标准鸿蒙中 ColorMode.DARK 通常为 1。这里保持与你 CrawlerSettings 工作的逻辑一致
  return {
    // 背景色
    pageBg: isDark ? '#0D0D0D' : '#F5F5F5',
    cardBg: isDark ? '#1E1E1E' : '#FFFFFF',
    inputBg: isDark ? '#2A2A2A' : '#F5F5F5',
    deleteBtnBg: '#FF4D4F',

    // 文字色
    primaryText: isDark ? '#E6E6E6' : '#000000',
    secondaryText: isDark ? '#999999' : '#666666',
    tertiaryText: isDark ? '#666666' : '#999999',
    quaternaryText: isDark ? '#888888' : '#BBBBBB',
    accentText: '#007DFF',
    dangerText: '#FF4D4F',
    whiteText: '#FFFFFF',

    // 开关颜色
    toggleOn: '#007DFF',
    toggleOff: isDark ? '#3A3A2A' : '#CCCCCC',

    // 热门标记
    hotTagBg: '#FA8C16',
    hotTagText: '#FFFFFF',

    // 空状态
    emptyIcon: isDark ? '#444444' : '#CCCCCC',
    emptyText: isDark ? '#666666' : '#999999',
    emptySubText: isDark ? '#444444' : '#BBBBBB',

    // 分割线
    divider: isDark ? '#2A2A2A' : '#E5E5E5'
  };
}

@Component
export struct AuthorSettings {
  @State authors: WatchedAuthor[] = [];
  @State newAuthorName: string = '';
  @State colorMode: number = 0;
  @State showClearConfirm: boolean = false;

  private settingsService: SettingsService | null = null;
  private unsubscribe: (() => void) | null = null;
  private configChangeCallback: () => void = () => {};
  private configCallbackId: number = -1;

  aboutToAppear(): void {
    this.settingsService = SettingsService.getInstance(getContext(this));
    this.unsubscribe = this.settingsService.subscribe((settings): void => {
      // 深拷贝避免引用问题
      const authors: WatchedAuthor[] = settings.authors;
      const copied: WatchedAuthor[] = [];
      for (let i: number = 0; i < authors.length; i++) {
        copied.push({
          name: authors[i].name,
          addTime: authors[i].addTime,
          notifyOnUpdate: authors[i].notifyOnUpdate
        });
      }
      this.authors = copied;
    });

    // --- 修复点：完善颜色模式监听 ---
    const ctx = getContext(this) as common.UIAbilityContext;
    this.colorMode = ctx.config?.colorMode || 0;

    this.configChangeCallback = () => {
      this.colorMode = ctx.config?.colorMode || 0;
    };

    // 必须通过 getApplicationContext().on 注册才能收到回调
    this.configCallbackId = ctx.getApplicationContext().on('environment', {
      onConfigurationUpdated: this.configChangeCallback,
      onMemoryLevel: (level: number) => {}
    });
  }

  aboutToDisappear(): void {
    if (this.unsubscribe) {
      this.unsubscribe();
    }
    // --- 修复点：销毁监听，防止内存泄漏 ---
    const ctx = getContext(this) as common.UIAbilityContext;
    if (this.configCallbackId !== -1) {
      ctx.getApplicationContext().off('environment', this.configCallbackId);
    }
  }

  // 获取当前颜色配置
  private getColors(): ColorConfig {
    return getAuthorSettingsColors(this.colorMode);
  }

  private addAuthor(): void {
    const trimmedName: string = this.newAuthorName.trim();
    if (!trimmedName) {
      promptAction.showToast({ message: '请输入作者名' });
      return;
    }
    const success: boolean = this.settingsService?.addWatchedAuthor(trimmedName, true) || false;
    if (success) {
      this.newAuthorName = '';
      promptAction.showToast({ message: '添加成功' });
    } else {
      promptAction.showToast({ message: '该作者已在关注列表' });
    }
  }

  private removeAuthor(name: string): void {
    this.settingsService?.removeWatchedAuthor(name);
    promptAction.showToast({ message: '已取消关注' });
  }

  private updateAuthorNotify(author: WatchedAuthor, val: boolean): void {
    const success: boolean = this.settingsService?.updateWatchedAuthorNotify(author.name, val) || false;
    if (!success) {
      promptAction.showToast({ message: '更新失败' });
    }
  }

  private clearAllAuthors(): void {
    if (this.authors.length === 0) return;
    this.showClearConfirm = true;  // 打开确认对话框
  }

  private executeClearAllAuthors(): void {
    const names: string[] = [];
    for (let i: number = 0; i < this.authors.length; i++) {
      names.push(this.authors[i].name);
    }
    for (let i: number = 0; i < names.length; i++) {
      this.settingsService?.removeWatchedAuthor(names[i]);
    }
    promptAction.showToast({ message: '已清空所有关注' });
    this.showClearConfirm = false;  // 关闭确认对话框
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Text('关注作者')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getColors().primaryText)
        Blank()
        if (this.authors.length > 0) {
          Button('清空')
            .fontSize(14)
            .fontColor(this.getColors().dangerText)
            .backgroundColor(Color.Transparent)
            .onClick((): void => this.clearAllAuthors())
        }
      }
      .width('100%')
      .margin({ bottom: 16 })

      // 添加输入框
      Row() {
        TextInput({ placeholder: '输入作者名...', text: $$this.newAuthorName })
          .layoutWeight(1)
          .height(44)
          .backgroundColor(this.getColors().inputBg)
          .borderRadius(8)
          .padding({ left: 12 })
          .fontColor(this.getColors().primaryText)
          .placeholderColor(this.getColors().tertiaryText)
        Button('添加')
          .margin({ left: 12 })
          .height(44)
          .fontColor(this.getColors().whiteText)
          .backgroundColor(this.getColors().accentText)
          .onClick((): void => this.addAuthor())
      }
      .width('100%')
      .padding(16)
      .backgroundColor(this.getColors().cardBg)
      .borderRadius(12)
      .margin({ bottom: 12 })

      // 统计信息
      if (this.authors.length > 0) {
        Row() {
          Text('共 ' + this.authors.length + ' 位作者')
            .fontSize(12)
            .fontColor(this.getColors().tertiaryText)
          Blank()
          Text('开启通知: ' + this.authors.filter((a: WatchedAuthor): boolean => a.notifyOnUpdate).length + ' 人')
            .fontSize(12)
            .fontColor(this.getColors().accentText)
        }
        .width('100%')
        .padding({ left: 4, right: 4, bottom: 8 })
      }

      // 列表
      List({ space: 8 }) {
        ForEach(this.authors, (author: WatchedAuthor): void => {
          ListItem() {
            Row() {
              Column() {
                Row() {
                  Text(author.name)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.getColors().primaryText)
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  if (this.isPopularAuthor(author.name)) {
                    Text('热')
                      .fontSize(10)
                      .fontColor(this.getColors().hotTagText)
                      .backgroundColor(this.getColors().hotTagBg)
                      .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                      .borderRadius(4)
                      .margin({ left: 8 })
                  }
                }
                .width('100%')

                Text('添加于 ' + this.formatDate(author.addTime))
                  .fontSize(12)
                  .fontColor(this.getColors().tertiaryText)
                  .margin({ top: 4 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              .margin({ right: 12 })
              .onClick(() => {
                AppStorage.setOrCreate('globalSearchKey', author.name);
                AppStorage.setOrCreate('mainTabIndex', 2);
              })

              Column() {
                Toggle({ type: ToggleType.Switch, isOn: author.notifyOnUpdate })
                  .selectedColor(this.getColors().toggleOn)
                  .switchPointColor(this.getColors().cardBg)
                  .onChange((val: boolean): void => {
                    this.updateAuthorNotify(author, val);
                  })
                Text(author.notifyOnUpdate ? '通知开启' : '通知关闭')
                  .fontSize(10)
                  .fontColor(author.notifyOnUpdate ? this.getColors().accentText : this.getColors().tertiaryText)
                  .margin({ top: 4 })
              }

              Button() {
                Text('删除')
                  .fontSize(12)
                  .fontColor(this.getColors().dangerText)
              }
              .width(40)
              .height(40)
              .backgroundColor(Color.Transparent)
              .onClick((): void => this.removeAuthor(author.name))
            }
            .width('100%')
            .padding(16)
          }
          .backgroundColor(this.getColors().cardBg)
          .borderRadius(12)
          .swipeAction({ end: this.DeleteBuilder(author.name) })
        }, (author: WatchedAuthor): string => author.name)
      }
      .width('100%')
      .layoutWeight(1)

      // 空状态
      if (this.authors.length === 0) {
        Column() {
          Text('📚')
            .fontSize(60)
            .fontColor(this.getColors().emptyIcon)
            .margin({ bottom: 16 })
          Text('暂无关注作者')
            .fontSize(16)
            .fontColor(this.getColors().emptyText)
          Text('添加关注的作者，及时获取更新提醒')
            .fontSize(12)
            .fontColor(this.getColors().emptySubText)
            .margin({ top: 8 })
        }
        .margin({ top: 100 })
      }
      if (this.showClearConfirm) {
        Stack() {
          // 半透明遮罩背景
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0, 0, 0, 0.5)')
            .onClick(() => {
              // 点击遮罩自动关闭（可选，删除此行则遮罩不能关闭对话框）
              this.showClearConfirm = false;
            })

          // 确认对话框卡片
          Column() {
            // 对话框标题
            Text('确认清空')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.getColors().primaryText)
              .margin({ bottom: 12 })

            // 对话框内容
            Text('确定要清空所有关注的作者吗？')
              .fontSize(14)
              .fontColor(this.getColors().secondaryText)
              .lineHeight(1.5)
              .margin({ bottom: 24 })
              .width('100%')

            // 按钮行
            Row() {
              Button('取消')
                .layoutWeight(1)
                .height(44)
                .backgroundColor(this.getColors().inputBg)
                .fontColor(this.getColors().primaryText)
                .fontSize(14)
                .border({ width: 1, color: this.getColors().divider })
                .borderRadius(8)
                .onClick(() => {
                  this.showClearConfirm = false;
                })

              Blank()
                .width(12)

              Button('确认清空')
                .layoutWeight(1)
                .height(44)
                .backgroundColor(this.getColors().dangerText)
                .fontColor(this.getColors().whiteText)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .borderRadius(8)
                .onClick(() => {
                  this.executeClearAllAuthors();
                })
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
          }
          .width(280)
          .padding(20)
          .backgroundColor(this.getColors().cardBg)
          .borderRadius(12)
          .alignSelf(ItemAlign.Center)
          .shadow({ radius: 16, color: 'rgba(0, 0, 0, 0.3)' })
        }
        .width('100%')
        .height('100%')
        .position({ x: 0, y: 0 })
      }
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor(this.getColors().pageBg)
  }

  @Builder
  DeleteBuilder(name: string) {
    Button() {
      Text('删除')
        .fontColor(this.getColors().whiteText)
        .fontSize(14)
    }
    .width(60)
    .height('100%')
    .backgroundColor(this.getColors().deleteBtnBg)
    .onClick((): void => this.removeAuthor(name))
  }

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

  private isPopularAuthor(name: string): boolean {
    return false;
  }
}