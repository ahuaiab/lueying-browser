import { PageAction } from '../model/PageActions';
import { PageFontSize } from '../model/PageDisplayState';
import { uiMaterial } from '@kit.ArkUI';
import { BrowserTabRecord, PendingTabDraft } from '../model/BrowserTypes';
import { TabPreviewKind } from '../model/TabGestureMotion';
import { TouchOwner } from '../gesture/TouchOwnership';
import { AddressTabStrip } from './AddressTabStrip';
import { BrowserActionToolbar } from './BrowserActionToolbar';
import {
  SAFARI_ADDRESS_ROW_HEIGHT_VP,
  SAFARI_BOTTOM_CHROME_BASE_HEIGHT_VP,
  SAFARI_BOTTOM_CHROME_RADIUS_VP
} from '../model/BrowserVisualMetrics';

@ComponentV2
export struct BottomBrowserBar {
  @Param tabs: BrowserTabRecord[] = [];
  @Param pendingTab: PendingTabDraft | undefined = undefined;
  @Param address: string = '';
  @Param pageTitle: string = '';
  @Param searchQuery: string = '';
  @Param addressDraft: string = '';
  @Param tabCount: number = 1;
  @Param isPrivate: boolean = false;
  @Param currentIndex: number = 0;
  @Param rawDragX: number = 0;
  @Param viewportWidth: number = 0;
  @Param interactionLocked: boolean = false;
  @Param bottomInset: number = 0;
  @Param canGoBack: boolean = false;
  @Param canGoForward: boolean = false;
  @Param navigationStateRevision: number = 0;
  @Param inputExpandProgress: number = 0;
  @Param barMode: string = 'collapsed';
  @Param addressEditing: boolean = false;
  @Param inputMounted: boolean = true;
  @Param activeInputIdentity: string = 'unknown';
  @Param addressInputFocusEnabled: boolean = true;
  @Param inputFocusRequestToken: number = 0;
  @Param selectedFontSize: PageFontSize = PageFontSize.STANDARD;
  @Param readerMode: boolean = false;
  @Param webReady: boolean = false;
  @Param desktopMode: boolean = false;
  @Param previewKind: TabPreviewKind = TabPreviewKind.NONE;
  @Param newTabProgress: number = 0;
  @Param addressHandoffMounted: boolean = false;
  @Param addressHandoffProgress: number = 1;
  /** BrowserShell renders the shared address strip above this surface. */
  @Param renderAddress: boolean = true;
  @Param gestureState: string = 'idle';
  @Param onNavigate: (value: string) => void = (_value: string) => undefined;
  @Param onReload: () => void = () => undefined;
  @Param onNewTab: () => void = () => undefined;
  @Param onNewPrivateTab: () => void = () => undefined;
  @Param onShare: () => void = () => undefined;
  @Param onShowLibrary: () => void = () => undefined;
  @Param canAddBookmark: boolean = false;
  @Param onAddBookmark: () => void = () => undefined;
  @Param onCloseAllTabs: () => void = () => undefined;
  @Param onReopenClosedTab: () => void = () => undefined;
  @Param onShowOverview: () => void = () => undefined;
  @Param onOpenAddress: () => void = () => undefined;
  @Param onAddressChange: (value: string) => void = (_value: string) => undefined;
  @Param onInputFocusChange: (focused: boolean) => void = (_focused: boolean) => undefined;
  @Param onAddressSubmit: (value: string) => void = (_value: string) => undefined;
  @Param onAddressCancel: () => void = () => undefined;
  @Param onFontSize: (size: PageFontSize) => void = (_size: PageFontSize) => undefined;
  @Param onPageAction: (action: PageAction) => void = (_action: PageAction) => undefined;
  @Param onBarTouchStart: (x: number, y: number, startInAddressStrip: boolean,
    owner: TouchOwner, buttonId: string) => void =
    (_x: number, _y: number, _startInAddressStrip: boolean, _owner: TouchOwner, _button: string) => undefined;
  @Param onBarRectChange: (x: number, y: number, width: number, height: number) => void =
    (_x: number, _y: number, _width: number, _height: number) => undefined;
  @Param onBarGestureStart: (x: number, y: number) => void = (_x: number, _y: number) => undefined;
  @Param onBarGestureUpdate: (event: GestureEvent) => void = (_event: GestureEvent) => undefined;
  @Param onBarGestureEnd: (event: GestureEvent) => void = (_event: GestureEvent) => undefined;
  @Param onBarGestureCancel: () => void = () => undefined;
  @Param onBack: () => void = () => undefined;
  @Param onForward: () => void = () => undefined;

  build() {
    Column() {
      Column() {
        if (this.renderAddress) {
          AddressTabStrip({
          tabs: this.tabs, pendingTab: this.pendingTab, activeIndex: this.currentIndex,
          rawDragX: this.rawDragX, viewportWidth: this.viewportWidth,
          interactionLocked: this.interactionLocked,
          address: this.address, searchQuery: this.searchQuery,
          addressDraft: this.addressDraft, isPrivate: this.isPrivate,
          pageTitle: this.pageTitle,
          previewKind: this.previewKind,
          newTabProgress: this.newTabProgress,
          addressHandoffMounted: this.addressHandoffMounted,
          addressHandoffProgress: this.addressHandoffProgress,
          inputExpandProgress: this.inputExpandProgress, barMode: this.barMode,
          addressEditing: this.addressEditing, inputMounted: this.inputMounted,
          activeInputIdentity: this.activeInputIdentity,
          addressInputFocusEnabled: this.addressInputFocusEnabled,
          inputFocusRequestToken: this.inputFocusRequestToken, selectedFontSize: this.selectedFontSize,
          readerMode: this.readerMode, webReady: this.webReady, desktopMode: this.desktopMode,
          onNavigate: this.onNavigate, onReload: this.onReload, onOpenAddress: this.onOpenAddress,
          onAddressChange: this.onAddressChange, onInputFocusChange: this.onInputFocusChange,
          onAddressSubmit: this.onAddressSubmit,
          onAddressCancel: this.onAddressCancel, onFontSize: this.onFontSize,
          onPageAction: this.onPageAction, onNewTab: this.onNewTab, onNewPrivateTab: this.onNewPrivateTab,
          onGestureTouchStart: this.onBarTouchStart,
          onGestureRectChange: this.onBarRectChange, onGestureStart: this.onBarGestureStart,
          onGestureUpdate: this.onBarGestureUpdate, onGestureEnd: this.onBarGestureEnd,
          onGestureCancel: this.onBarGestureCancel
          });
        } else {
          // Preserve the toolbar's original vertical slot while the address
          // capsule is rendered by BrowserShell as a shared transition layer.
          Blank()
            .width('100%')
            .height(SAFARI_ADDRESS_ROW_HEIGHT_VP);
        }
        BrowserActionToolbar({
          canGoBack: this.canGoBack, canGoForward: this.canGoForward,
          navigationStateRevision: this.navigationStateRevision,
          interactionLocked: this.interactionLocked, onBack: this.onBack, onForward: this.onForward,
          onShare: this.onShare, onShowLibrary: this.onShowLibrary,
          canAddBookmark: this.canAddBookmark, onAddBookmark: this.onAddBookmark,
          onShowOverview: this.onShowOverview,
          onReload: this.onReload,
          onNewTab: this.onNewTab, onNewPrivateTab: this.onNewPrivateTab,
          onCloseAllTabs: this.onCloseAllTabs, onReopenClosedTab: this.onReopenClosedTab
        });
      }
        .width('100%')
        .height(SAFARI_BOTTOM_CHROME_BASE_HEIGHT_VP);
      Blank()
        .width('100%')
        .height(Math.max(0, this.bottomInset));
    }
      .id('safari-bottom-chrome')
      .width('100%')
      .height(SAFARI_BOTTOM_CHROME_BASE_HEIGHT_VP + Math.max(0, this.bottomInset))
      .backgroundColor('#F2F2F7')
      .borderRadius({ topLeft: SAFARI_BOTTOM_CHROME_RADIUS_VP,
        topRight: SAFARI_BOTTOM_CHROME_RADIUS_VP, bottomLeft: 0, bottomRight: 0 })
      .clip(true)
      .shadow({ radius: 16, color: '#28000000', offsetX: 0, offsetY: 4 })
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        interactive: true
      }))
      .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY);
  }
}
