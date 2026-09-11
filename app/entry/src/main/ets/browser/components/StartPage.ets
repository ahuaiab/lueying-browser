import { BrowserSettings } from '../model/BrowserSettings';
import {
  StartPageItem,
  StartPageItemType,
  shouldRenderStartPageSection,
  sortStartPageItems,
  startPageBackgroundSource
} from '../model/StartPageModels';
import {
  HARMONY_RADIUS_CONTROL,
  HARMONY_RADIUS_CARD
} from '../model/BrowserVisualMetrics';

/**
 * Native blank-tab surface.  The reference starts with a quiet canvas, a
 * centered “编辑” pill and the address bar anchored below the page.  The
 * address bar is owned by BrowserShell, so this component deliberately does
 * not render a second search field.
 */
@ComponentV2
export struct StartPage {
  @Param items: StartPageItem[] = [];
  @Require @Param settings: BrowserSettings;
  @Param onOpen: (url: string) => void = (_url: string) => undefined;
  @Param onAddFavorite: () => void = () => undefined;
  @Param onCustomize: () => void = () => undefined;
  @Param pageTranslateX: number = 0;

  private itemsFor(type: StartPageItemType): StartPageItem[] {
    return sortStartPageItems(this.items.filter((item: StartPageItem) => item.type === type));
  }

  private sectionTitle(type: StartPageItemType): string {
    if (type === StartPageItemType.FAVORITE) {
      return '书签';
    }
    return '经常访问的网站';
  }

  private startPageBackgroundColor(): string {
    // Page surfaces stay white.  The gray material belongs to browser chrome
    // (the address/search bar and bottom toolbar), not to page content.
    return '#FFFFFF';
  }

  private selectedBackgroundSource(): string {
    return startPageBackgroundSource(this.settings.startPageBackgroundId) ?? '';
  }

  @Builder
  private pageBackground() {
    if (this.selectedBackgroundSource().length === 0) {
      Blank()
        .id('start-page-background-default')
        .width('100%')
        .height('100%')
        .backgroundColor('#FFFFFF');
    } else {
      Image(this.selectedBackgroundSource())
        .id('start-page-background-image')
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover);
    }
  }

  @Builder
  private editButton() {
    Button('编辑', { type: ButtonType.Capsule, stateEffect: false })
      .id('start-page-customize-button')
      .width(72)
      .height(36)
      .padding(0)
      .fontSize(15)
      .fontColor('#1D1D1F')
      .backgroundColor('#F2F2F7')
      .onClick(() => this.onCustomize());
  }

  @Builder
  private favoriteTile(item: StartPageItem) {
    Column({ space: 6 }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.bookmark_fill'))
          .fontSize(25)
          .fontWeight(FontWeight.Bold)
          .fontColor([Color.White])
      }
      .width(56)
      .height(56)
      .backgroundColor('#F2F2F7')
      .borderRadius(HARMONY_RADIUS_CONTROL)

      Text(item.title.length > 0 ? item.title : item.url)
        .fontSize(13)
        .fontColor('#1D1D1F')
        .maxLines(1)
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .id(`start-page-favorite-${item.id}`)
    .width('100%')
    .padding({ bottom: 4 })
    .shadow({ radius: 8, color: '#22000000', offsetX: 0, offsetY: 2 })
    .onClick(() => this.onOpen(item.url));
  }

  @Builder
  private listCard(item: StartPageItem) {
    Row({ space: 12 }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.clock'))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor([Color.White])
      }
      .width(54)
      .height(54)
      .backgroundColor('#6C84B5')
      .borderRadius(HARMONY_RADIUS_CONTROL)

      Column({ space: 3 }) {
        Text(item.title.length > 0 ? item.title : item.url)
          .fontSize(15)
          .fontColor('#1D1D1F')
          .maxLines(1)
          .width('100%')
        Text(item.url)
          .fontSize(11)
          .fontColor('#8A8A90')
          .maxLines(1)
          .width('100%')
      }
      .layoutWeight(1)
    }
    .id(`start-page-item-${item.id}`)
    .width('100%')
    .height(82)
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    // HarmonyOS uses AARRGGBB for eight-digit colors; use the explicit
    // system white token here so page cards cannot become pale yellow.
    .backgroundColor('#F2F2F7')
    .borderRadius(HARMONY_RADIUS_CARD)
    .clip(true)
    .shadow({ radius: 8, color: '#22000000', offsetX: 0, offsetY: 2 })
    .onClick(() => this.onOpen(item.url));
  }

  @Builder
  private section(type: StartPageItemType, visible: boolean) {
    if (shouldRenderStartPageSection(type, visible, this.itemsFor(type).length)) {
      Column({ space: 12 }) {
        Row() {
          Text(this.sectionTitle(type))
            .fontSize(type === StartPageItemType.FAVORITE ? 22 : 20)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1D1D1F')
            .layoutWeight(1)

          if (type !== StartPageItemType.FAVORITE) {
            Row({ space: 4 }) {
              Text('折叠')
                .fontSize(14)
                .fontColor('#5C5C60')
              SymbolGlyph($r('sys.symbol.chevron_down'))
                .fontSize(14)
                .fontColor([Color.Gray])
            }
          }
        }
        .width('100%')

        if (type === StartPageItemType.FAVORITE) {
          Grid() {
            ForEach(this.itemsFor(type), (item: StartPageItem) => {
              GridItem() {
                this.favoriteTile(item)
              }
            }, (item: StartPageItem) => item.id)
          }
          .id('start-page-favorites-grid')
          .columnsTemplate('1fr 1fr 1fr')
          .columnsGap(12)
          .rowsGap(14)
          .width('100%')
        } else {
          Column({ space: 10 }) {
            ForEach(this.itemsFor(type), (item: StartPageItem) => {
              this.listCard(item)
            }, (item: StartPageItem) => item.id)
          }
          .width('100%')
        }
      }
      .id(`start-page-section-${type}`)
      .width('100%')
    }
  }

  build() {
    Stack() {
      this.pageBackground();
      Scroll() {
        Column({ space: 22 }) {
          // Keep the editor affordance visible after a user enables a section;
          // Safari's start-page editor remains reachable from the page header.
          Row() {
            this.editButton()
          }
          .id('start-page-header')
          .width('100%')
          .height(82)
          .justifyContent(FlexAlign.Center)

          this.section(StartPageItemType.FAVORITE, this.settings.showFavorites)
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 16, bottom: 28 })
      }
      .backgroundColor(Color.Transparent)
      .id('start-page-content-scroll')
      .width('100%')
      .height('100%')
    }
    .id('start-page')
    .width('100%')
    .height('100%')
    .translate({ x: this.pageTranslateX, y: 0, z: 0 })
    .backgroundColor(this.startPageBackgroundColor())
  }
}
