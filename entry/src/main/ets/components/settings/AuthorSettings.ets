// entry/src/main/ets/components/settings/AuthorSettings.ets
import { SettingsService } from '../../services/SettingsService';
import { WatchedAuthor } from '../../models/SettingsModels';
import promptAction from '@ohos.promptAction';

@Component
export struct AuthorSettings {
  @State authors: WatchedAuthor[] = [];
  @State newAuthorName: string = '';
  private settingsService: SettingsService | null = null;
  private unsubscribe: (() => void) | null = null;

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
  }

  aboutToDisappear(): void {
    if (this.unsubscribe) {
      this.unsubscribe();
    }
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
    // 调用 SettingsService 的新方法
    const success: boolean = this.settingsService?.updateWatchedAuthorNotify(author.name, val) || false;
    if (!success) {
      promptAction.showToast({ message: '更新失败' });
    }
  }

  // 清空所有关注
  private clearAllAuthors(): void {
    if (this.authors.length === 0) return;

    // 逐个删除（或者添加 clearAllWatchedAuthors 方法）
    const names: string[] = [];
    for (let i: number = 0; i < this.authors.length; i++) {
      names.push(this.authors[i].name);
    }
    for (let i: number = 0; i < names.length; i++) {
      this.settingsService?.removeWatchedAuthor(names[i]);
    }
    promptAction.showToast({ message: '已清空所有关注' });
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Text('关注作者').fontSize(20).fontWeight(FontWeight.Bold)
        Blank()
        if (this.authors.length > 0) {
          Button('清空')
            .fontSize(14)
            .fontColor('#FF4D4F')
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
          .backgroundColor('#F5F5F5')
          .borderRadius(8)
          .padding({ left: 12 })
        Button('添加')
          .margin({ left: 12 })
          .height(44)
          .backgroundColor('#007DFF')
          .onClick((): void => this.addAuthor())
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFF')
      .borderRadius(12)
      .margin({ bottom: 12 })

      // 统计信息
      if (this.authors.length > 0) {
        Row() {
          Text('共 ' + this.authors.length + ' 位作者')
            .fontSize(12)
            .fontColor('#999')
          Blank()
          Text('开启通知: ' + this.authors.filter((a: WatchedAuthor): boolean => a.notifyOnUpdate).length + ' 人')
            .fontSize(12)
            .fontColor('#007DFF')
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
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  // 关注标记
                  if (this.isPopularAuthor(author.name)) {
                    Text('热')
                      .fontSize(10)
                      .fontColor('#FFF')
                      .backgroundColor('#FA8C16')
                      .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                      .borderRadius(4)
                      .margin({ left: 8 })
                  }
                }
                .width('100%')

                Text('添加于 ' + this.formatDate(author.addTime))
                  .fontSize(12)
                  .fontColor('#999')
                  .margin({ top: 4 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              .margin({ right: 12 })

              // 通知开关
              Column() {
                Toggle({ type: ToggleType.Switch, isOn: author.notifyOnUpdate })
                  .selectedColor('#007DFF')
                  .onChange((val: boolean): void => {
                    this.updateAuthorNotify(author, val);
                  })
                Text(author.notifyOnUpdate ? '通知开启' : '通知关闭')
                  .fontSize(10)
                  .fontColor(author.notifyOnUpdate ? '#007DFF' : '#999')
                  .margin({ top: 4 })
              }
              // 删除按钮
              Button() {
                Text('删除')
                  .fontSize(12)
                  .fontColor('#FF4D4F')
              }
              .width(40)
              .height(40)
              .backgroundColor(Color.Transparent)
              .onClick((): void => this.removeAuthor(author.name))
            }
            .width('100%')
            .padding(16)
          }
          .backgroundColor('#FFF')
          .borderRadius(12)
          .swipeAction({ end: this.DeleteBuilder(author.name) }) // 左滑删除
        }, (author: WatchedAuthor): string => author.name)
      }
      .width('100%')
      .layoutWeight(1)
      // 空状态
      if (this.authors.length === 0) {
        Column() {
          Text('📚')
            .fontSize(60)
            .fontColor('#CCC')
            .margin({ bottom: 16 })
          Text('暂无关注作者')
            .fontSize(16)
            .fontColor('#999')
          Text('添加关注的作者，及时获取更新提醒')
            .fontSize(12)
            .fontColor('#BBB')
            .margin({ top: 8 })
        }
        .margin({ top: 100 })
      }
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor('#F5F5F5')
  }

  // 删除按钮构建器（用于左滑）
  @Builder
  DeleteBuilder(name: string) {
    Button() {
      Text('删除')
        .fontColor('#FFFFFF')
        .fontSize(14)
    }
    .width(60)
    .height('100%')
    .backgroundColor('#FF4D4F')
    .onClick((): void => this.removeAuthor(name))
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

  // 辅助方法：判断热门作者（示例）
  private isPopularAuthor(name: string): boolean {
    // 可以根据更新频率等判断，这里简单示例
    return false;
  }
}