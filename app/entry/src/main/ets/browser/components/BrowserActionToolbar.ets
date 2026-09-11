/** Fixed lower action row for the shared Safari bottom chrome. */
import {
  HARMONY_RADIUS_TINY,
  SAFARI_ACTION_TOOLBAR_HEIGHT_VP,
  SAFARI_BOTTOM_CHROME_RAIL_INSET_VP
} from '../model/BrowserVisualMetrics';
import { LIBRARY_BOOKMARK_BUTTON_MENU_LABEL } from '../model/LibraryModels';
import { SymbolGlyphModifier } from '@kit.ArkUI';

@ComponentV2
export struct BrowserActionToolbar {
  @Param canGoBack: boolean = false;
  @Param canGoForward: boolean = false;
  @Param interactionLocked: boolean = false;
  @Param navigationStateRevision: number = 0;
  @Param onBack: () => void = () => undefined;
  @Param onForward: () => void = () => undefined;
  @Param onShare: () => void = () => undefined;
  @Param onShowLibrary: () => void = () => undefined;
  @Param canAddBookmark: boolean = false;
  @Param onAddBookmark: () => void = () => undefined;
  @Param onShowOverview: () => void = () => undefined;
  @Param onReload: () => void = () => undefined;
  @Param onNewTab: () => void = () => undefined;
  @Param onNewPrivateTab: () => void = () => undefined;
  @Param onCloseAllTabs: () => void = () => undefined;
  @Param onReopenClosedTab: () => void = () => undefined;

  @Local menuShownId: string = '';
  @Local longPressedId: string = '';
  @Local suppressNextClickId: string = '';

  private beginLongPress(id: string): void {
    if (this.interactionLocked) {
      return;
    }
    this.longPressedId = id;
    this.menuShownId = id;
    this.suppressNextClickId = id;
  }

  private endLongPress(id: string): void {
    if (this.longPressedId === id) {
      this.longPressedId = '';
    }
  }

  private dismissMenu(id: string): void {
    this.endLongPress(id);
    if (this.menuShownId === id) {
      this.menuShownId = '';
    }
    setTimeout(() => {
      if (this.menuShownId !== id && this.longPressedId !== id && this.suppressNextClickId === id) {
        this.suppressNextClickId = '';
      }
    }, 0);
  }

  private handleClick(id: string, action: () => void): void {
    if (this.interactionLocked) {
      return;
    }
    if (this.suppressNextClickId === id) {
      this.suppressNextClickId = '';
      return;
    }
    action();
  }

  @Builder
  private tabOverviewIcon() {
    Stack() {
      SymbolGlyph($r('sys.symbol.square'))
        .fontSize(24)
        .fontColor(['#007AFF'])
        .offset({ x: -3, y: -3 });
      Column()
        .width(18)
        .height(18)
        .backgroundColor('#F2F2F7')
        .borderRadius(HARMONY_RADIUS_TINY)
        .offset({ x: 3, y: 3 });
      SymbolGlyph($r('sys.symbol.square'))
        .fontSize(24)
        .fontColor(['#007AFF'])
        .offset({ x: 3, y: 3 });
    }
      .width(32)
      .height(32);
  }

  @Builder
  private iconButton(symbol: Resource, id: string, action: () => void, enabled: boolean = true) {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      SymbolGlyph(symbol)
        .fontSize(25)
        .fontColor([enabled ? '#007AFF' : '#AAB2BD']);
    }
      .id(id)
      .width('100%')
      .height(44)
      .layoutWeight(1)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .stateEffect(false)
      .enabled(enabled)
      .opacity(enabled ? 1 : 0.45)
      .onClick(() => this.handleClick(id, action));
  }

  @Builder
  private tabMenu() {
    Menu() {
      MenuItem({ content: '新建标签页' }).onChange((selected: boolean) => {
        if (selected) {
          this.onNewTab();
          this.dismissMenu('tab-count-button');
        }
      })
      MenuItem({ content: '关闭所有标签页' }).onChange((selected: boolean) => {
        if (selected) {
          this.onCloseAllTabs();
          this.dismissMenu('tab-count-button');
        }
      })
    }
  }

  @Builder
  private libraryMenu() {
    Menu() {
      MenuItem({
        content: LIBRARY_BOOKMARK_BUTTON_MENU_LABEL,
        symbolStartIcon: this.bookmarkMenuSymbol()
      })
        .enabled(this.canAddBookmark)
        .onChange((selected: boolean) => {
          if (selected) {
            this.onAddBookmark();
            this.dismissMenu('browser-library-button');
          }
        })
    }
  }

  private bookmarkMenuSymbol(): SymbolGlyphModifier {
    return new SymbolGlyphModifier($r('sys.symbol.bookmark'))
      .fontSize('20vp')
      .fontColor(['#1D1D1F']);
  }

  @Builder
  private libraryButton() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      SymbolGlyph($r('sys.symbol.bookmark'))
        .fontSize(25)
        .fontColor(['#007AFF']);
    }
      .id('browser-library-button')
      .width('100%')
      .height(44)
      .layoutWeight(1)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .stateEffect(false)
      .onClick(() => this.handleClick('browser-library-button', this.onShowLibrary))
      .bindContextMenu(!this.interactionLocked && this.menuShownId === 'browser-library-button', this.libraryMenu, {
        placement: Placement.TopRight,
        onDisappear: () => this.dismissMenu('browser-library-button')
      })
      .parallelGesture(
        LongPressGesture({ duration: 300 })
          .onAction(() => this.beginLongPress('browser-library-button'))
          .onActionEnd(() => this.endLongPress('browser-library-button'))
          .onActionCancel(() => this.endLongPress('browser-library-button'))
      );
  }

  build() {
    if (this.navigationStateRevision >= 0) {
      Row() {
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(25)
          .fontColor([this.canGoBack ? '#007AFF' : '#AAB2BD']);
      }
        .id('browser-back-button')
        .width('100%')
        .height(44)
        .layoutWeight(1)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .stateEffect(false)
        .enabled(this.canGoBack)
        .opacity(this.canGoBack ? 1 : 0.45)
        .onClick(() => this.handleClick('browser-back-button', this.onBack));
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(25)
          .fontColor([this.canGoForward ? '#007AFF' : '#AAB2BD']);
      }
        .id('browser-forward-button')
        .width('100%')
        .height(44)
        .layoutWeight(1)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .stateEffect(false)
        .enabled(this.canGoForward)
        .opacity(this.canGoForward ? 1 : 0.45)
        .onClick(() => this.handleClick('browser-forward-button', this.onForward));
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        SymbolGlyph($r('sys.symbol.share'))
          .fontSize(25)
          .fontColor(['#007AFF']);
      }
        .id('browser-share-button')
        .width('100%')
        .height(44)
        .layoutWeight(1)
      .padding(0)
      .backgroundColor(Color.Transparent)
      .stateEffect(false)
        // Keep sharing as a tap-only action. The exclusive long-press branch
        // intentionally has no callback, so a held share button cannot fall
        // through to the tap action when the finger is released.
        .gesture(
          GestureGroup(
            GestureMode.Exclusive,
            TapGesture({ count: 1 })
              .onAction(() => this.handleClick('browser-share-button', this.onShare)),
            LongPressGesture({ duration: 300 })
              .onAction(() => undefined)
              .onActionEnd(() => undefined)
              .onActionCancel(() => undefined)
          )
        );
      this.libraryButton();
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        this.tabOverviewIcon();
      }
        .id('tab-count-button')
        .width('100%')
        .height(44)
        .layoutWeight(1)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .stateEffect(false)
        .onClick(() => this.handleClick('tab-count-button', this.onShowOverview))
        .bindContextMenu(!this.interactionLocked && this.menuShownId === 'tab-count-button', this.tabMenu, {
          placement: Placement.TopRight,
          onDisappear: () => this.dismissMenu('tab-count-button')
        })
        .parallelGesture(
          LongPressGesture({ duration: 300 })
            .onAction(() => this.beginLongPress('tab-count-button'))
            .onActionEnd(() => this.endLongPress('tab-count-button'))
            .onActionCancel(() => this.endLongPress('tab-count-button'))
        );
      }
        .id('browser-action-toolbar')
        .width('100%')
        .height(SAFARI_ACTION_TOOLBAR_HEIGHT_VP)
        .padding({ left: SAFARI_BOTTOM_CHROME_RAIL_INSET_VP,
          right: SAFARI_BOTTOM_CHROME_RAIL_INSET_VP })
        .justifyContent(FlexAlign.Start)
        .hitTestBehavior(this.interactionLocked ? HitTestMode.None : HitTestMode.Default);
    }
  }
}
