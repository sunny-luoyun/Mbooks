// entry/src/main/ets/components/reader/ReaderController.ets
import { Chapter, Bookmark } from '../../pages/ReaderPage';
import { Theme } from './ReaderStyles';

export enum ControllerState { HIDDEN, VISIBLE }

@Component
export struct ReaderController {
  @Prop controllerState: ControllerState;
  @Prop title: string;
  @Prop currentChapterIndex: number;
  @Prop currentPageIndex: number;
  @Prop totalChapters: number;
  @Prop chapters: Chapter[];
  @Prop bookmarks: Bookmark[];

  onBack: () => void = () => {};
  onAddBookmark: () => void = () => {};
  onJumpToChapter: (index: number, pageIndex: number) => void = () => {};
  onJumpToBookmark: (bm: Bookmark) => void = () => {};
  onDeleteBookmark: (id: string) => void = () => {};

  @State showPanel: boolean = false;
  @State panelTab: number = 0;

  build() {
    Stack() {
      if (this.controllerState === ControllerState.VISIBLE) {
        // 顶部栏
        Row() {
          Text('〈 返回')
            .fontSize(16)
            .fontColor(Theme.TEXT_MAIN)
            .onClick(() => this.onBack())

          Text(this.title)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontSize(16)
            .fontColor(Theme.TEXT_MAIN)

          Blank().width(40)
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .backgroundColor(Theme.BAR_BG)
        .position({ x: 0, y: 0 })
        .zIndex(20)

        // 底部栏
        Row() {
          Text('目录')
            .fontSize(14)
            .fontColor(Theme.TEXT_MAIN)
            .onClick(() => {
              this.panelTab = 0;
              this.showPanel = true;
            })

          Column() {
            Text(`${this.currentChapterIndex + 1}/${this.totalChapters}章`)
              .fontSize(12)
              .fontColor(Theme.TEXT_SECONDARY)
            Text(`第${this.currentPageIndex + 1}页`)
              .fontSize(14)
              .fontColor(Theme.TEXT_MAIN)
          }
          .layoutWeight(1)

          Text('书签')
            .fontSize(14)
            .fontColor(Theme.TEXT_MAIN)
            .onClick(() => {
              this.panelTab = 1;
              this.showPanel = true;
            })

          Text('＋')
            .fontSize(20)
            .fontColor(Theme.TEXT_MAIN)
            .padding(10)
            .onClick(() => this.onAddBookmark())
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .backgroundColor(Theme.BAR_BG)
        .position({ x: 0, y: '100%' })
        .markAnchor({ x: 0, y: 56 })
        .zIndex(20)
      }

      if (this.showPanel) {
        this.SidePanel()
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder SidePanel() {
    Stack({ alignContent: Alignment.TopStart }) {
      Rect()
        .width('100%')
        .height('100%')
        .fill('rgba(0,0,0,0.5)')
        .onClick(() => this.showPanel = false)

      Column() {
        Row() {
          Button('目录')
            .fontSize(14)
            .fontColor(this.panelTab === 0 ? Color.White : Color.Black)
            .backgroundColor(this.panelTab === 0 ? '#333' : '#f0f0f0')
            .onClick(() => this.panelTab = 0)

          Button('书签')
            .fontSize(14)
            .fontColor(this.panelTab === 1 ? Color.White : Color.Black)
            .backgroundColor(this.panelTab === 1 ? '#333' : '#f0f0f0')
            .onClick(() => this.panelTab = 1)
        }
        .width('100%')
        .height(50)
        .justifyContent(FlexAlign.SpaceEvenly)
        .margin({ top: 40 })

        List() {
          if (this.panelTab === 0) {
            ForEach(this.chapters, (item: Chapter, index: number) => {
              ListItem() {
                Column() {
                  Text(item.title)
                    .fontSize(14)
                    .fontColor(index === this.currentChapterIndex ? Theme.TEXT_ACCENT : '#333')
                    .width('100%')

                  Text(`共${item.pageCount}页`)
                    .fontSize(11)
                    .fontColor('#999')
                    .margin({ top: 4 })
                }
                .alignItems(HorizontalAlign.Start)
                .padding(15)
                .width('100%')
              }
              .backgroundColor(index === this.currentChapterIndex ? '#f5f5f5' : Color.White)
              .onClick(() => {
                this.onJumpToChapter(index, 0);
                this.showPanel = false;
              })
            })
          } else {
            ForEach(this.bookmarks, (bm: Bookmark) => {
              ListItem() {
                Row() {
                  Column() {
                    Text(bm.excerpt)
                      .fontSize(13)
                      .fontColor('#333')
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })

                    Text(`${this.chapters[bm.chapterIndex]?.title || ''} · 第${bm.pageIndex + 1}页 · ${new Date(bm.timestamp).toLocaleString()}`)
                      .fontSize(11)
                      .fontColor('#999')
                      .margin({ top: 5 })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  Button('删除')
                    .fontSize(12)
                    .fontColor('#ff4444')
                    .backgroundColor(Color.Transparent)
                    .onClick(() => {
                      this.onDeleteBookmark(bm.id);
                    })
                }
                .width('100%')
                .padding(12)
              }
              .onClick(() => {
                this.onJumpToBookmark(bm);
                this.showPanel = false;
              })
            })
          }
        }
        .layoutWeight(1)
        .width('100%')
        .divider({ strokeWidth: 0.5, color: '#e0e0e0' })
      }
      .width('75%')
      .height('100%')
      .backgroundColor(Color.White)
      .shadow({ radius: 10, color: 'rgba(0,0,0,0.2)', offsetX: 2 })
    }
    .width('100%')
    .height('100%')
    .zIndex(30)
  }
}