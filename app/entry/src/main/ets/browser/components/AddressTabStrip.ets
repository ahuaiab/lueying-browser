import { PageAction } from '../model/PageActions';
import { PageFontSize } from '../model/PageDisplayState';
import {
  BrowserTabRecord,
  PendingTabDraft,
  lastValidUrlForTab,
  searchQueryForUrl
} from '../model/BrowserTypes';
import {
  SAFARI_ADDRESS_ITEM_GAP_VP,
  SAFARI_ADDRESS_PREVIEW_FADE_DURATION_MS,
  SAFARI_ADDRESS_ROW_HEIGHT_VP,
  safariAddressItemWidth
} from '../model/BrowserVisualMetrics';
import {
  ADDRESS_SEARCH_BAR_STYLE,
  ADDRESS_SEARCH_BAR_TOP_PADDING,
  TabOverviewChromeFrame
} from '../model/TabOverviewActions';
import { TabBarRect, isPointInTabBar } from '../gesture/TabBarGestureGate';
import { TouchOwner, beginTouchOwnership } from '../gesture/TouchOwnership';
import {
  addressItemLeft,
  addressPreviewOpacity,
  newTabPreviewVisual,
  newTabHandoffVisual,
  shouldRenderAddressHandoff,
  shouldRenderAddressItem,
  shouldRenderPendingTabPreview
} from '../model/SafariTabTransition';
import { addressTextColorFor } from '../model/BrowserInteraction';
import { TabPreviewKind } from '../model/TabGestureMotion';
import { DownloadProgressSnapshot } from '../model/DownloadModels';
import {
  AddressSearchBar,
  AddressSearchBarDownloadProps,
  addressSearchBarDownloadProps
} from './AddressSearchBar';

export function addressTabStripDownloadSnapshotForItem(
  snapshot: DownloadProgressSnapshot | undefined,
  index: number,
  activeIndex: number
): DownloadProgressSnapshot | undefined {
  return index === activeIndex ? snapshot : undefined;
}

@ComponentV2
export struct AddressTabStrip {
  @Param tabs: BrowserTabRecord[] = [];
  @Param pendingTab: PendingTabDraft | undefined = undefined;
  @Param activeIndex: number = 0;
  @Param rawDragX: number = 0;
  @Param viewportWidth: number = 0;
  @Param interactionLocked: boolean = false;
  @Param address: string = '';
  @Param pageTitle: string = '';
  @Param searchQuery: string = '';
  @Param addressDraft: string = '';
  @Param isPrivate: boolean = false;
  @Param inputExpandProgress: number = 0;
  @Param barMode: string = 'collapsed';
  @Param addressEditing: boolean = false;
  @Param inputMounted: boolean = true;
  @Param activeInputIdentity: string = 'unknown';
  @Param addressInputFocusEnabled: boolean = true;
  @Param previewKind: TabPreviewKind = TabPreviewKind.NONE;
  @Param newTabProgress: number = 0;
  @Param addressHandoffMounted: boolean = false;
  @Param addressHandoffProgress: number = 1;
  @Param downloadProgress: DownloadProgressSnapshot | undefined = undefined;
  /** Shared page/chrome frame used while the address capsule leaves the bar. */
  @Param overviewTransitionActive: boolean = false;
  @Param overviewChromeFrame: TabOverviewChromeFrame | undefined = undefined;
  @Param inputFocusRequestToken: number = 0;
  @Param selectedFontSize: PageFontSize = PageFontSize.STANDARD;
  @Param readerMode: boolean = false;
  @Param webReady: boolean = false;
  @Param desktopMode: boolean = false;
  @Param onNavigate: (value: string) => void = (_value: string) => undefined;
  @Param onReload: () => void = () => undefined;
  @Param onOpenAddress: () => void = () => undefined;
  @Param onAddressChange: (value: string) => void = (_value: string) => undefined;
  @Param onInputFocusChange: (focused: boolean) => void = (_focused: boolean) => undefined;
  @Param onAddressSubmit: (value: string) => void = (_value: string) => undefined;
  @Param onAddressCancel: () => void = () => undefined;
  @Param onFontSize: (size: PageFontSize) => void = (_size: PageFontSize) => undefined;
  @Param onPageAction: (action: PageAction) => void = (_action: PageAction) => undefined;
  @Param onNewTab: () => void = () => undefined;
  @Param onNewPrivateTab: () => void = () => undefined;
  @Param onGestureTouchStart: (x: number, y: number, startInAddressStrip: boolean,
    owner: TouchOwner, buttonId: string) => void =
    (_x: number, _y: number, _startInAddressStrip: boolean, _owner: TouchOwner, _button: string) => undefined;
  @Param onGestureRectChange: (x: number, y: number, width: number, height: number) => void =
    (_x: number, _y: number, _width: number, _height: number) => undefined;
  @Param onGestureStart: (x: number, y: number) => void = (_x: number, _y: number) => undefined;
  @Param onGestureUpdate: (event: GestureEvent) => void = (_event: GestureEvent) => undefined;
  @Param onGestureEnd: (event: GestureEvent) => void = (_event: GestureEvent) => undefined;
  @Param onGestureCancel: () => void = () => undefined;

  // The address strip can be a fractional width smaller than the Web host
  // after the immersive material and window avoidance are applied. Use its
  // own measured width for the capsule track so both outer corner centers
  // are calculated in the same coordinate space.
  @Local addressLayoutWidth: number = 0;
  private addressStripRect: TabBarRect = { x: 0, y: 0, width: 0, height: 0 };
  private touchStartX: number = 0;
  private touchStartY: number = 0;

  private layoutWidth(): number {
    if (this.overviewTransitionActive && this.overviewChromeFrame !== undefined) {
      return this.overviewChromeFrame.addressWidth;
    }
    return this.addressLayoutWidth > 0 ? this.addressLayoutWidth : this.viewportWidth;
  }

  private frameWidth(): number | string {
    return this.overviewChromeFrame === undefined
      ? '100%'
      : this.overviewChromeFrame.addressWidth;
  }

  private framePosition(): Position {
    return this.overviewChromeFrame === undefined
      ? { x: 0, y: 0 }
      : {
        x: this.overviewChromeFrame.addressLeft,
        y: this.overviewChromeFrame.addressTop
      };
  }

  private frameScaleX(): number {
    if (this.overviewChromeFrame === undefined) {
      return 1;
    }
    return this.overviewChromeFrame.addressScaleX * this.overviewChromeFrame.addressJellyScaleX;
  }

  private frameScaleY(): number {
    if (this.overviewChromeFrame === undefined) {
      return 1;
    }
    return this.overviewChromeFrame.addressScaleY * this.overviewChromeFrame.addressJellyScaleY;
  }

  private frameTranslateY(): number {
    return this.overviewChromeFrame?.addressJellyTranslateY ?? 0;
  }

  private itemWidth(): number {
    return safariAddressItemWidth(this.layoutWidth());
  }

  private itemOffset(index: number): number {
    return addressItemLeft(index, this.activeIndex, this.itemWidth(),
      SAFARI_ADDRESS_ITEM_GAP_VP, this.rawDragX, this.layoutWidth());
  }

  private itemOpacity(index: number): number {
    return addressPreviewOpacity(index, this.activeIndex, this.rawDragX, this.viewportWidth);
  }

  private addressPlusOpacity(): number {
    return newTabPreviewVisual(this.newTabProgress).addressPlusOpacity;
  }

  private addressBackgroundOpacity(): number {
    return newTabPreviewVisual(this.newTabProgress).addressBackgroundOpacity;
  }

  private handoffPlusOpacity(): number {
    return this.handoffUsesPendingSlot()
      ? 0
      : newTabHandoffVisual(this.addressHandoffProgress).plusOpacity;
  }

  private handoffPlaceholderOpacity(): number {
    return newTabHandoffVisual(this.addressHandoffProgress).placeholderOpacity;
  }

  private handoffPlusScale(): number {
    return newTabHandoffVisual(this.addressHandoffProgress).plusScale;
  }

  private handoffPlaceholderScale(): number {
    return newTabHandoffVisual(this.addressHandoffProgress).placeholderScale;
  }

  private handoffPlaceholderTranslateX(): number {
    // The reference keeps the placeholder at its final left inset while its
    // opacity crossfades with the centered plus.
    return 0;
  }

  private handoffUsesPendingSlot(): boolean {
    return this.pendingTab !== undefined && this.previewKind === TabPreviewKind.NEW_TAB;
  }

  private handoffIndex(): number {
    return this.handoffUsesPendingSlot() ? this.tabs.length : this.activeIndex;
  }

  private touchPoint(event: TouchEvent): TouchObject | undefined {
    if (event.touches !== undefined && event.touches.length > 0) {
      return event.touches[0];
    }
    if (event.changedTouches !== undefined && event.changedTouches.length > 0) {
      return event.changedTouches[0];
    }
    return undefined;
  }

  private handleTouch(event?: TouchEvent): void {
    if (event === undefined || event.type !== TouchType.Down) {
      return;
    }
    const point: TouchObject | undefined = this.touchPoint(event);
    if (point === undefined) {
      return;
    }
    const windowX: number = point.windowX;
    const windowY: number = point.windowY;
    const startsInAddressStrip: boolean = isPointInTabBar(
      windowX,
      windowY,
      this.addressStripRect
    );
    const ownership = beginTouchOwnership(startsInAddressStrip, '');
    this.touchStartX = windowX;
    this.touchStartY = windowY;
    this.onGestureTouchStart(
      windowX,
      windowY,
      startsInAddressStrip,
      ownership.owner,
      ownership.buttonId
    );
  }

  @Builder
  private tabItem(tab: BrowserTabRecord, index: number) {
    AddressSearchBar({
      address: index === this.activeIndex ? this.address : lastValidUrlForTab(tab),
      pageTitle: index === this.activeIndex ? this.pageTitle : tab.title,
      searchQuery: index === this.activeIndex
        ? this.searchQuery
        : tab.addressSource === 'search'
          ? (tab.addressQuery ?? searchQueryForUrl(lastValidUrlForTab(tab)) ?? '')
          : '',
      initialDraft: index === this.activeIndex ? this.addressDraft : '',
      inputIdentity: index === this.activeIndex ? this.activeInputIdentity : `address-input-${tab.id}`,
      selectedFontSize: this.selectedFontSize,
      readerMode: this.readerMode,
      webReady: index === this.activeIndex && this.webReady,
      desktopMode: index === this.activeIndex && this.desktopMode,
      downloadActive: addressSearchBarDownloadProps(
        addressTabStripDownloadSnapshotForItem(this.downloadProgress, index, this.activeIndex)
      ).downloadActive,
      downloadProgress: addressSearchBarDownloadProps(
        addressTabStripDownloadSnapshotForItem(this.downloadProgress, index, this.activeIndex)
      ).downloadProgress,
      onNavigate: index === this.activeIndex ? this.onAddressSubmit : (_value: string) => undefined,
      onFontSize: index === this.activeIndex ? this.onFontSize : (_size: PageFontSize) => undefined,
      onPageAction: index === this.activeIndex ? this.onPageAction : (_action: PageAction) => undefined,
      onOpenAddress: index === this.activeIndex ? this.onOpenAddress : () => undefined,
      onAddressCancel: index === this.activeIndex ? this.onAddressCancel : () => undefined,
      onDraftChange: index === this.activeIndex ? this.onAddressChange : (_value: string) => undefined,
      onInputFocusChange: index === this.activeIndex ? this.onInputFocusChange : (_focused: boolean) => undefined,
      focusRequestToken: index === this.activeIndex ? this.inputFocusRequestToken : 0,
      allowFocus: index === this.activeIndex && !this.interactionLocked && this.addressInputFocusEnabled,
      gestureEnabled: index === this.activeIndex && !this.interactionLocked,
      inputMounted: index === this.activeIndex ? this.inputMounted : true,
      editorActive: index === this.activeIndex && this.addressEditing,
      editorClosing: index === this.activeIndex && this.barMode === 'collapsing',
      inputExpandProgress: index === this.activeIndex ? this.inputExpandProgress : 0,
      onGestureCancel: index === this.activeIndex ? this.onGestureCancel : () => undefined
    })
      .id(`address-tab-item-${tab.id}`)
      .width(this.itemWidth())
      .height(SAFARI_ADDRESS_ROW_HEIGHT_VP)
      .position({ x: this.itemOffset(index), y: 0 })
      .opacity(this.itemOpacity(index))
      // An adjacent tab is a transient visual item. If the gesture commits or
      // springs back, let ArkUI fade that item out before its keyed node is
      // removed. The active address field itself never receives a commit fade.
      .transition(
        TransitionEffect.asymmetric(
          TransitionEffect.IDENTITY,
          TransitionEffect.OPACITY
        ).animation({ duration: SAFARI_ADDRESS_PREVIEW_FADE_DURATION_MS, curve: Curve.EaseOut })
      )
      .hitTestBehavior(index === this.activeIndex ? HitTestMode.Default : HitTestMode.None);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.overviewTransitionActive) {
        if (this.activeIndex >= 0 && this.activeIndex < this.tabs.length) {
          this.tabItem(this.tabs[this.activeIndex], this.activeIndex);
        }
      } else {
        ForEach(this.tabs, (tab: BrowserTabRecord, index: number) => {
          if (shouldRenderAddressItem(index, this.activeIndex, this.rawDragX,
            this.tabs.length, this.previewKind)) {
            this.tabItem(tab, index);
          }
        }, (tab: BrowserTabRecord) => tab.id);
      }
      if (!this.overviewTransitionActive && this.pendingTab !== undefined && shouldRenderPendingTabPreview(
        this.previewKind, this.newTabProgress)) {
        Stack({ alignContent: Alignment.Center }) {
          Column() {
          }
            .width('100%')
            .height('100%')
            .backgroundColor(Color.White)
            .opacity(this.addressBackgroundOpacity());
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(26)
            .fontColor(['#1677FF'])
            .opacity(this.addressPlusOpacity());
          }
          .id('pending-address-tab-item')
          .width(this.itemWidth())
          .height(ADDRESS_SEARCH_BAR_STYLE.height)
          .position({ x: this.itemOffset(this.tabs.length), y: ADDRESS_SEARCH_BAR_TOP_PADDING })
          .backgroundColor(Color.Transparent)
          .borderRadius(ADDRESS_SEARCH_BAR_STYLE.cornerRadius)
          .hitTestBehavior(HitTestMode.None);
      }
      if (!this.overviewTransitionActive && shouldRenderAddressHandoff(
        this.addressHandoffMounted, this.addressHandoffProgress)) {
        Stack() {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(26)
            .fontColor(['#1677FF'])
            .opacity(this.handoffPlusOpacity())
            .scale({ x: this.handoffPlusScale(), y: this.handoffPlusScale() });
          Text('搜索或输入网站')
            .fontSize(16)
            .fontColor(addressTextColorFor(false))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Start)
            .width('100%')
            .padding({ left: 11, right: 11 })
            .opacity(this.handoffPlaceholderOpacity())
            .scale({ x: this.handoffPlaceholderScale(), y: this.handoffPlaceholderScale() })
            .translate({ x: this.handoffPlaceholderTranslateX(), y: 0, z: 0 });
        }
          .id('new-tab-address-handoff')
          .width(this.itemWidth())
          .height(ADDRESS_SEARCH_BAR_STYLE.height)
          .clip(true)
          .position({ x: this.itemOffset(this.handoffIndex()), y: ADDRESS_SEARCH_BAR_TOP_PADDING })
          .backgroundColor(this.handoffUsesPendingSlot() ? Color.Transparent : Color.White)
          .borderRadius(ADDRESS_SEARCH_BAR_STYLE.cornerRadius)
          .border({ width: this.handoffUsesPendingSlot() ? 0 : 1,
            color: this.handoffUsesPendingSlot() ? '#00000000' : '#55FFFFFF' })
          .shadow(this.handoffUsesPendingSlot()
            ? { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 }
            : { radius: 12, color: '#24000000', offsetX: 0, offsetY: 2 })
          .hitTestBehavior(HitTestMode.None);
      }
    }
      .id('address-tab-strip')
      .width(this.frameWidth())
      .height(SAFARI_ADDRESS_ROW_HEIGHT_VP)
      .position(this.framePosition())
      .scale({ x: this.frameScaleX(), y: this.frameScaleY(), z: 1 })
      .translate({ x: 0, y: this.frameTranslateY(), z: 0 })
      .opacity(this.overviewChromeFrame?.addressOpacity ?? 1)
      .clip(true)
      // The transition layer is mounted above the bottom chrome so the
      // address capsule can morph independently. In its normal position,
      // transparent hit testing keeps the capsule interactive without
      // swallowing the toolbar and tab-count button underneath it.
      .hitTestBehavior(this.overviewTransitionActive ? HitTestMode.None : HitTestMode.Transparent)
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        const globalPosition = newValue.globalPosition ?? newValue.position;
        const measuredWidth: number = Number(newValue.width);
        if (Number.isFinite(measuredWidth) && measuredWidth > 0 &&
          this.addressLayoutWidth !== measuredWidth) {
          this.addressLayoutWidth = measuredWidth;
        }
        this.addressStripRect = {
          x: Number(globalPosition?.x ?? 0),
          y: Number(globalPosition?.y ?? 0),
          width: measuredWidth,
          height: Number(newValue.height)
        };
        this.onGestureRectChange(
          this.addressStripRect.x,
          this.addressStripRect.y,
          measuredWidth,
          Number(newValue.height)
        );
      })
      .onTouch((event?: TouchEvent) => this.handleTouch(event))
      .hitTestBehavior(this.overviewTransitionActive ? HitTestMode.None : HitTestMode.Default)
      .gesture(
        PanGesture(new PanGestureOptions({ direction: PanDirection.All, fingers: 1, distance: 8 }))
          .onActionStart((_event: GestureEvent) =>
            this.onGestureStart(this.touchStartX, this.touchStartY))
          .onActionUpdate((event: GestureEvent) => this.onGestureUpdate(event))
          .onActionEnd((event: GestureEvent) => this.onGestureEnd(event))
          .onActionCancel(() => this.onGestureCancel())
      );
  }
}
