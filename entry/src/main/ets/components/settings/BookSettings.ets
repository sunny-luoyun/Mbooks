// entry/src/main/ets/components/settings/BookSettings.ets
import { SettingsService } from '../../services/SettingsService';
import { WatchedBook } from '../../models/SettingsModels';
import promptAction from '@ohos.promptAction';
import router from '@ohos.router';

@Component
export struct BookSettings {
  @State books: WatchedBook[] = [];
  private settingsService: SettingsService | null = null;
  private unsubscribe: (() => void) | null = null;

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
  }

  aboutToDisappear(): void {
    if (this.unsubscribe) {
      this.unsubscribe();
    }
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
        Text('关注书籍').fontSize(20).fontWeight(FontWeight.Bold)
        Blank()
        if (this.books.length > 0) {
          Button('清空')
            .fontSize(14)
            .fontColor('#FF4D4F')
            .backgroundColor(Color.Transparent)
            .onClick((): void => this.clearAllBooks())
        }
      }
      .width('100%')
      .margin({ bottom: 8 })

      Text('在书籍详情页点击"关注"添加，或点击卡片查看详情')
        .fontSize(12)
        .fontColor('#999')
        .margin({ bottom: 16 })

      // 统计信息
      if (this.books.length > 0) {
        Row() {
          Text('共 ' + this.books.length + ' 本书')
            .fontSize(12)
            .fontColor('#999')
          Blank()
          Text('自动下载: ' + this.books.filter((b: WatchedBook): boolean => b.autoDownload).length + ' 本')
            .fontSize(12)
            .fontColor('#52C41A')
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
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                // 状态标签
                if (book.autoDownload) {
                  Text('自动')
                    .fontSize(10)
                    .fontColor('#52C41A')
                    .backgroundColor('#F6FFED')
                    .border({ width: 1, color: '#B7EB8F' })
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .borderRadius(4)
                    .margin({ left: 8 })
                }
                if (!book.notifyOnUpdate) {
                  Text('免打扰')
                    .fontSize(10)
                    .fontColor('#999')
                    .backgroundColor('#F5F5F5')
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
                  .fontColor('#999')
                Blank()
                Text(this.formatDate(book.addTime))
                  .fontSize(12)
                  .fontColor('#999')
              }
              .width('100%')
              .margin({ top: 6, bottom: 12 })

              // 第三行：操作开关
              Row() {
                // 通知开关
                Row() {
                  Toggle({ type: ToggleType.Switch, isOn: book.notifyOnUpdate })
                    .selectedColor('#007DFF')
                    .scale({ x: 0.8, y: 0.8 })
                    .onChange((val: boolean): void => {
                      this.updateBookNotify(book, val);
                    })
                  Text('更新通知')
                    .fontSize(12)
                    .fontColor(book.notifyOnUpdate ? '#007DFF' : '#999')
                    .margin({ left: 4 })
                }

                Blank()

                // 自动下载开关
                Row() {
                  Toggle({ type: ToggleType.Switch, isOn: book.autoDownload })
                    .selectedColor('#52C41A')
                    .scale({ x: 0.8, y: 0.8 })
                    .onChange((val: boolean): void => {
                      this.updateBookAutoDownload(book, val);
                    })
                  Text('自动下载')
                    .fontSize(12)
                    .fontColor(book.autoDownload ? '#52C41A' : '#999')
                    .margin({ left: 4 })
                }

                Blank()

                // 删除按钮
                Button() {
                  Text('删除')
                    .fontSize(12)
                    .fontColor('#FF4D4F')
                }
                .backgroundColor(Color.Transparent)
                .onClick((): void => this.removeBook(book.threadId, book.title))
              }
              .width('100%')
            }
            .width('100%')
            .padding(16)
          }
          .backgroundColor('#FFF')
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
            .margin({ bottom: 16 })
          Text('暂无关注书籍')
            .fontSize(16)
            .fontColor('#999')
          Text('关注喜欢的书籍，自动获取更新')
            .fontSize(12)
            .fontColor('#BBB')
            .margin({ top: 8 })
          Button('去搜索书籍')
            .margin({ top: 24 })
            .backgroundColor('#007DFF')
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
    .backgroundColor('#F5F5F5')
  }

  // 删除按钮构建器（左滑）
  @Builder
  DeleteBuilder(threadId: string, title: string) {
    Button() {
      Text('删除')
        .fontColor('#FFFFFF')
        .fontSize(14)
    }
    .width(60)
    .height('100%')
    .backgroundColor('#FF4D4F')
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