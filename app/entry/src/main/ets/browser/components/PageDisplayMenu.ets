import {
  PageAction,
  pageModeMenuLabel,
  pageModeMenuSymbolName
} from '../model/PageActions';
import { PageFontSize } from '../model/PageDisplayState';
import { deviceInfo } from '@kit.BasicServicesKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';

/**
 * Native ArkUI menus for the video-matched address-bar "大小" affordance.
 * Short tap opens font-size choices; long press opens page actions.
 */
@ComponentV2
export struct PageDisplayMenu {
  @Param selectedFontSize: PageFontSize = PageFontSize.STANDARD;
  @Param readerMode: boolean = false;
  @Param webReady: boolean = false;
  @Param desktopMode: boolean = false;
  @Param onFontSize: (size: PageFontSize) => void = (_size: PageFontSize) => undefined;
  @Param onAction: (action: PageAction) => void = (_action: PageAction) => undefined;
  @Local actionMenuShown: boolean = false;

  private beginLongPress(): void {
    this.actionMenuShown = true;
  }

  private endLongPress(): void {
    this.actionMenuShown = false;
  }

  private sizeLabel(size: PageFontSize): string {
    if (size === PageFontSize.SMALL) {
      return '小';
    }
    if (size === PageFontSize.LARGE) {
      return '大';
    }
    return '标准';
  }

  private sizeItem(size: PageFontSize): string {
    return `${size === this.selectedFontSize ? '✓ ' : ''}${this.sizeLabel(size)}`;
  }

  private pageModeMenuSymbol(): SymbolGlyphModifier {
    const symbolName: string = pageModeMenuSymbolName(this.desktopMode, deviceInfo.deviceType);
    const symbolResource = symbolName === 'sys.symbol.rectangle_portrait'
      ? $r('sys.symbol.rectangle_portrait')
      : $r('sys.symbol.display');
    return new SymbolGlyphModifier(symbolResource)
      .fontSize('20vp')
      .fontColor(['#1D1D1F']);
  }

  @Builder
  private actionMenu() {
    Menu() {
      MenuItem({
        content: pageModeMenuLabel(this.desktopMode),
        symbolStartIcon: this.pageModeMenuSymbol()
      })
        .enabled(this.webReady)
        .onChange((selected: boolean) => {
          if (selected) {
            this.onAction(PageAction.DESKTOP_SITE);
          }
        })
    }
  }

  build() {
    // Keep the two native triggers on separate nodes: ArkUI intentionally
    // disallows bindMenu and bindContextMenu on one component. The child
    // owns the tap menu and the wrapper owns the long-press context menu.
    Stack() {
      Button('大小', { type: ButtonType.Normal, stateEffect: false })
        .id('page-display-size-button')
        .fontSize(13)
        .width(48)
        .height(34)
        .padding(0)
        .stateEffect(false)
        .bindMenu([
          {
            value: this.sizeItem(PageFontSize.SMALL),
            action: () => this.onFontSize(PageFontSize.SMALL)
          },
          {
            value: this.sizeItem(PageFontSize.STANDARD),
            action: () => this.onFontSize(PageFontSize.STANDARD)
          },
          {
            value: this.sizeItem(PageFontSize.LARGE),
            action: () => this.onFontSize(PageFontSize.LARGE)
          }
        ])
    }
    .id('page-display-size-host')
    .width(48)
    .height(34)
    .bindContextMenu(this.actionMenuShown, this.actionMenu, {
      onDisappear: () => this.endLongPress()
    })
    .parallelGesture(
      LongPressGesture({ duration: 300 })
        .onAction(() => this.beginLongPress())
        .onActionEnd(() => this.endLongPress())
        .onActionCancel(() => this.endLongPress())
    )
  }
}
