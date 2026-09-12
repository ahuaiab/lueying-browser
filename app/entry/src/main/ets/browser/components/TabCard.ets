import {
  BrowserTabRecord,
  GestureSample,
  lastValidUrlForTab,
  TabId,
  tabOverviewTitleFor
} from '../model/BrowserTypes';
import { image } from '@kit.ImageKit';
import { SymbolGlyphModifier, uiMaterial } from '@kit.ArkUI';
import {
  TAB_CARD_MENU_DESTRUCTIVE_COLOR,
  TAB_CARD_MENU_LABELS,
  TAB_OVERVIEW_LAYOUT,
  TAB_OVERVIEW_CAPTION_FONT_SIZE,
  tabOverviewCardCaptionVisualOpacity,
  tabOverviewLivePageCloseFrame,
  TabOverviewLivePageCloseFrame,
  tabCardMenuItemIsDestructive
} from '../model/TabOverviewActions';
import { DEFAULT_GESTURE_PROFILE } from '../gesture/GestureProfile';
import {
  HARMONY_RADIUS_CARD
} from '../model/BrowserVisualMetrics';

/**
 * A Safari-style tab card: the live page preview and its title/close row are
 * one clipped rounded surface. Closing and reordering still delegate to
 * BrowserShell's shared gesture state machine; this component only owns the
 * card composition and gesture bridge.
 */
@ComponentV2
export struct TabCard {
  @Require @Param tab: BrowserTabRecord;
  @Param index: number = 0;
  @Param tabCount: number = 1;
  @Param cardHeight: number = TAB_OVERVIEW_LAYOUT.cardHeight;
  /** Visual breathing room below the system safe area in the overview grid. */
  @Param topOffset: number = 0;
  @Param isActive: boolean = false;
  /** When true, the mounted live page is visible through this card shell. */
  @Param livePreview: boolean = false;
  /** Paint the active ring after the live page has handed off ownership. */
  @Param livePreviewBorder: boolean = false;
  @Param thumbnail: image.PixelMap | undefined = undefined;
  @Param closeProgress: number = 0;
  @Param verticalOffset: number = 0;
  @Param horizontalOffset: number = 0;
  @Param onOpen: (tabId: TabId) => void = (_tabId: TabId) => undefined;
  @Param onCloseStart: (tabId: TabId) => void = (_tabId: TabId) => undefined;
  @Param onCloseUpdate: (tabId: TabId, sample: GestureSample) => void =
    (_tabId: TabId, _sample: GestureSample) => undefined;
  @Param onCloseEnd: (tabId: TabId, sample: GestureSample) => void =
    (_tabId: TabId, _sample: GestureSample) => undefined;
  @Param onCloseCancel: (tabId: TabId) => void = (_tabId: TabId) => undefined;
  @Param onCloseTap: (tabId: TabId) => void = (_tabId: TabId) => undefined;
  @Param onNewTab: () => void = () => undefined;
  @Param onCloseAllTabs: () => void = () => undefined;
  @Param onReorderStart: (tabId: TabId) => void = (_tabId: TabId) => undefined;
  @Param onReorder: (tabId: TabId, targetIndex: number) => void =
    (_tabId: TabId, _targetIndex: number) => undefined;

  @Local reorderActive: boolean = false;
  @Local reorderOffsetY: number = 0;
  @Local longPressActive: boolean = false;
  @Local menuShown: boolean = false;
  private gestureFinished: boolean = false;
  private panObserved: boolean = false;

  private sample(event?: GestureEvent): GestureSample {
    return {
      dx: event?.offsetX ?? 0,
      dy: event?.offsetY ?? 0,
      velocityX: event?.velocityX ?? 0,
      velocityY: event?.velocityY ?? 0
    };
  }

  private beginPan(): void {
    if (this.longPressActive) {
      return;
    }
    this.gestureFinished = false;
    this.panObserved = false;
    if (!this.reorderActive) {
      this.onCloseStart(this.tab.id);
    }
  }

  private updatePan(event?: GestureEvent): void {
    if (this.gestureFinished || this.longPressActive) {
      return;
    }
    if (this.reorderActive) {
      this.reorderOffsetY = event?.offsetY ?? 0;
      this.panObserved = true;
      return;
    }
    this.onCloseUpdate(this.tab.id, this.sample(event));
  }

  private targetIndex(event?: GestureEvent): number {
    const offsetY: number = event?.offsetY ?? this.reorderOffsetY;
    const rowDelta: number = Math.round(offsetY / (this.cardHeight + TAB_OVERVIEW_LAYOUT.gap));
    return Math.max(0, Math.min(this.tabCount - 1, this.index + rowDelta));
  }

  private finishPan(event?: GestureEvent): void {
    if (this.gestureFinished) {
      return;
    }
    this.gestureFinished = true;
    if (this.reorderActive) {
      this.onReorder(this.tab.id, this.targetIndex(event));
      this.reorderActive = false;
      this.reorderOffsetY = 0;
      this.panObserved = false;
      return;
    }
    this.onCloseEnd(this.tab.id, this.sample(event));
    this.panObserved = false;
  }

  private cancelPan(): void {
    if (this.gestureFinished) {
      return;
    }
    this.gestureFinished = true;
    if (this.reorderActive) {
      this.reorderActive = false;
      this.reorderOffsetY = 0;
      this.panObserved = false;
      return;
    }
    this.onCloseCancel(this.tab.id);
    this.panObserved = false;
  }

  private beginReorder(): void {
    // A held card opens the native context menu. Keep this separate from the
    // horizontal close pan so a long press can never start closing a card.
    this.longPressActive = true;
    this.gestureFinished = true;
    this.onCloseCancel(this.tab.id);
    this.menuShown = true;
  }

  private finishLongPress(): void {
    this.longPressActive = false;
    // Keep the native menu mounted until onDisappear. Clearing this flag on
    // finger-up races ArkUI's context-menu presentation.
  }

  private dismissMenu(): void {
    this.longPressActive = false;
    this.menuShown = false;
  }

  private tabMenuSymbol(index: number): SymbolGlyphModifier {
    const color: ResourceColor = tabCardMenuItemIsDestructive(index)
      ? TAB_CARD_MENU_DESTRUCTIVE_COLOR
      : '#1D1D1F';
    if (index === 0) {
      return new SymbolGlyphModifier($r('sys.symbol.plus'))
        .fontSize('20vp')
        .fontColor([color]);
    }
    if (index === 1) {
      return new SymbolGlyphModifier($r('sys.symbol.xmark'))
        .fontSize('20vp')
        .fontColor([color]);
    }
    return new SymbolGlyphModifier($r('sys.symbol.xmark_circle'))
      .fontSize('20vp')
      .fontColor([color]);
  }

  @Builder
  private tabMenu() {
    Menu() {
      MenuItem({
        content: TAB_CARD_MENU_LABELS[0],
        symbolStartIcon: this.tabMenuSymbol(0)
      })
        .onChange((selected: boolean) => {
          if (selected) {
            this.onNewTab();
            this.dismissMenu();
          }
        })
      MenuItem({
        content: TAB_CARD_MENU_LABELS[1],
        symbolStartIcon: this.tabMenuSymbol(1)
      })
        .contentFontColor(TAB_CARD_MENU_DESTRUCTIVE_COLOR)
        .onChange((selected: boolean) => {
          if (selected) {
            this.onCloseTap(this.tab.id);
            this.dismissMenu();
          }
        })
      MenuItem({
        content: TAB_CARD_MENU_LABELS[2],
        symbolStartIcon: this.tabMenuSymbol(2)
      })
        .contentFontColor(TAB_CARD_MENU_DESTRUCTIVE_COLOR)
        .onChange((selected: boolean) => {
          if (selected) {
            this.onCloseAllTabs();
            this.dismissMenu();
          }
        })
    }
  }

  private titleText(): string {
    return tabOverviewTitleFor(lastValidUrlForTab(this.tab), this.tab.title);
  }

  private closeFrame(): TabOverviewLivePageCloseFrame {
    return tabOverviewLivePageCloseFrame(this.closeProgress, this.horizontalOffset);
  }

  private closeScale(): number {
    const frame: TabOverviewLivePageCloseFrame = this.closeFrame();
    return this.reorderActive ? frame.scale + 0.04 : frame.scale;
  }

  @Builder
  private pagePreview() {
    if (this.livePreview) {
      // The active card must not paint an independent thumbnail. The live
      // BrowserTransitionScene is transformed underneath this transparent
      // shell and remains the only page visual during the handoff.
      Blank()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent);
    } else if (this.thumbnail !== undefined) {
      Image(this.thumbnail)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover);
    } else {
      // Do not draw a synthetic placeholder. The overview is a snapshot of
      // the actual page; until the system PixelMap is ready, keep this area
      // empty and let the cache update it on the next native capture frame.
      Blank()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.White);
    }
  }

  @Builder
  private cardBody() {
    Column() {
      Column() {
        Stack() {
          this.pagePreview();
        }
          .width('100%')
          // Keep the thumbnail height unchanged while the caption is moved
          // inside the same card surface. The previous 4vp gap plus the
          // 28vp external caption becomes a single 32vp internal row.
          .height(this.cardHeight - 32)
          .backgroundColor(this.livePreview ? Color.Transparent : '#FFFFFF')
          .borderRadius({ topLeft: HARMONY_RADIUS_CARD, topRight: HARMONY_RADIUS_CARD })
          .clip(true);
      }
        .width('100%')
        .height(this.cardHeight - 32)
        .backgroundColor(this.livePreview ? Color.Transparent :
          (this.tab.isPrivate ? '#F2EEFF' : '#FFFFFF'));

      this.caption();
    }
  }

  @Builder
  private cardSurface() {
    if (this.livePreview) {
      Column() {
        this.cardBody();
      }
        .id(`tab-card-preview-${this.tab.id}`)
        .width('100%')
        .height(this.cardHeight)
        .backgroundColor(Color.Transparent)
        .borderRadius(HARMONY_RADIUS_CARD)
        // At the settled frame this shell becomes the single owner of the
        // active ring. During movement the live page owns it instead.
        .border({
          width: this.livePreviewBorder ? 2 : 0,
          color: '#007AFF'
        })
        .clip(true)
        .shadow({ radius: 9, color: '#24000000', offsetX: 0, offsetY: 3 });
    } else {
      Column() {
        this.cardBody();
      }
      .id(`tab-card-preview-${this.tab.id}`)
      .width('100%')
      .height(this.cardHeight)
      .backgroundColor(this.tab.isPrivate ? '#F2EEFF' : '#FFFFFF')
      // Apply the native immersive surface first; the active/inactive ring
      // is painted afterwards so the selected card remains an explicit blue
      // outline instead of being washed out by the material layer.
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        interactive: true
      }))
      .borderRadius(HARMONY_RADIUS_CARD)
      .border({
        width: this.isActive ? 2 : 1,
        color: this.isActive ? '#007AFF' : '#E1E3E6'
      })
      // Clip both children to this one outline so the thumbnail, caption and
      // close action read as a single card instead of two stacked panels.
      .clip(true)
      .shadow({ radius: 9, color: '#24000000', offsetX: 0, offsetY: 3 });
    }
  }

  @Builder
  private caption() {
    Row() {
      Text(this.titleText())
        .fontSize(TAB_OVERVIEW_CAPTION_FONT_SIZE)
        .fontWeight(FontWeight.Medium)
        .fontColor('#1D1D1F')
        .opacity(tabOverviewCardCaptionVisualOpacity(this.livePreview))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1);
      // Keep the close action with the caption, below the thumbnail, matching
      // the reference layout. The hit-test boundary prevents the card's
      // parallel pan gesture from consuming a direct tap.
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(14)
          .fontColor(['#69727C'])
          .opacity(tabOverviewCardCaptionVisualOpacity(this.livePreview));
      }
        .id(`tab-close-button-${this.tab.id}`)
        .width(28)
        .height(28)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .stateEffect(false)
        .onClick(() => this.onCloseTap(this.tab.id));
    }
      .id(`tab-card-caption-${this.tab.id}`)
      .width('100%')
      .height(32)
      // The transformed live page paints the active caption. Keep this row's
      // invisible close button in place so the settled card remains operable.
      .backgroundColor(this.livePreview ? Color.Transparent : '#FFFFFF')
      .borderRadius({ bottomLeft: HARMONY_RADIUS_CARD, bottomRight: HARMONY_RADIUS_CARD })
      .padding({ left: 12, right: 2 });
  }

  build() {
    Column() {
      this.cardSurface();
    }
      .id(`tab-card-${this.tab.id}`)
      .width('100%')
      .height(this.cardHeight)
      .opacity(this.closeFrame().opacity)
      .scale({
        x: this.closeScale(),
        y: this.closeScale(),
        z: 1
      })
      .translate({
        x: this.closeFrame().horizontalOffset,
        y: this.topOffset + this.verticalOffset + (this.reorderActive ? this.reorderOffsetY : 0),
        z: 0
      })
      .onClick(() => this.onOpen(this.tab.id))
      // Pass the builder itself (rather than invoking it while the card tree
      // is built) so ArkUI can materialize the native context-menu window when
      // the long-press state flips to true.
      .bindContextMenu(this.menuShown, this.tabMenu, {
        placement: Placement.BottomRight,
        onDisappear: () => this.dismissMenu(),
        // Keep the menu aligned with the same native immersive material used
        // by the floating browser chrome. No preview image is needed because
        // the card itself remains visible behind the menu.
        systemMaterial: new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THIN,
          interactive: true
        })
      })
      .gesture(
        GestureGroup(
          // Long press and horizontal close are mutually exclusive. This
          // prevents a 300ms hold from also moving the card, while a real
          // left swipe still wins as soon as horizontal travel is detected.
          GestureMode.Exclusive,
          LongPressGesture({ duration: DEFAULT_GESTURE_PROFILE.reorderLongPressMs })
            .onAction(() => this.beginReorder())
            .onActionEnd(() => this.finishLongPress())
            .onActionCancel(() => undefined),
          // A card owns only the horizontal close gesture. Directional
          // recognition keeps it from competing with the overview's vertical
          // pull-to-search and with the system back gesture.
          PanGesture({ direction: PanDirection.Horizontal })
            .onActionStart(() => this.beginPan())
            .onActionUpdate((event: GestureEvent | undefined) => this.updatePan(event))
            .onActionEnd((event: GestureEvent | undefined) => this.finishPan(event))
            .onActionCancel(() => this.cancelPan())
        )
      );
  }
}
