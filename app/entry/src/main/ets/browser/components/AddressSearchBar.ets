import {
  PageAction,
  pageModeMenuLabel,
  pageModeMenuSymbolName
} from '../model/PageActions';
import {
  addressBarLabelFor,
  AddressSecurityState,
  addressSecurityStateFor,
  searchQueryForUrl,
  searchQueryTextFor
} from '../model/BrowserTypes';
import { PageFontSize } from '../model/PageDisplayState';
import { deviceInfo } from '@kit.BasicServicesKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import {
  ADDRESS_SEARCH_BAR_STYLE,
  ADDRESS_SEARCH_BAR_TOP_PADDING
} from '../model/TabOverviewActions';
import {
  addressEditorText,
  addressClearButtonVisibleFor,
  addressLockImageVerticalOffsetFor,
  addressLockVerticalOffsetFor,
  addressTextAlignmentFor,
  addressTextColorFor,
  addressCollapsedTextPaddingFor,
  addressEditorLeftPaddingFor,
  placeholderForFocus,
  syncAddressDraft
} from '../model/BrowserInteraction';
import { SAFARI_ADDRESS_LOCK_SAFE_INSET_VP } from '../model/BrowserVisualMetrics';
import { DownloadProgressSnapshot } from '../model/DownloadModels';

export interface AddressSearchBarDownloadProps {
  downloadActive: boolean;
  downloadProgress: number;
}

export function addressSearchBarDownloadProps(
  snapshot: DownloadProgressSnapshot | undefined
): AddressSearchBarDownloadProps {
  return {
    downloadActive: snapshot !== undefined,
    downloadProgress: snapshot?.percent ?? 0
  };
}

export interface DownloadProgressRingProps {
  visible: boolean;
  id: string;
  value: number;
  status: 'PROGRESSING';
  color: string;
  buttonSize: number;
  lockImageSize: number;
  lockImageOffsetX: number;
  size: number;
  ringOffset: number;
  strokeWidth: number;
}

export function downloadProgressRingProps(
  inputIdentity: string,
  downloadActive: boolean,
  downloadProgress: number
): DownloadProgressRingProps {
  const hasDeterminateProgress: boolean = downloadActive && Number.isFinite(downloadProgress) &&
    downloadProgress >= 0;
  const determinateValue: number = hasDeterminateProgress
    ? Math.max(0, Math.min(100, downloadProgress))
    : 0;
  return {
    // ProgressStatus.LOADING is an animated indeterminate spinner and does
    // not consume value. Keep the lock visible while the backend has no
    // denominator, then show the ring only when its percentage is real.
    visible: hasDeterminateProgress,
    id: `browser-download-progress-ring-${inputIdentity}`,
    value: determinateValue,
    status: 'PROGRESSING',
    color: '#1677FF',
    buttonSize: 32,
    lockImageSize: 20,
    lockImageOffsetX: 6,
    size: 28,
    ringOffset: 2,
    strokeWidth: 2
  };
}

export function addressLeadingActionVisibleFor(
  isStartPage: boolean,
  addressInputFocused: boolean
): boolean {
  return !isStartPage && !addressInputFocused;
}

export function addressInputLeftPaddingFor(
  isStartPage: boolean,
  addressInputFocused: boolean
): number {
  return addressEditorLeftPaddingFor(
    addressLeadingActionVisibleFor(isStartPage, addressInputFocused)
  );
}

/**
 * Safari-like address/search chrome. The search field is intentionally a
 * address item used by the upper AddressTabStrip row.
 */
@ComponentV2
export struct AddressSearchBar {
  @Param address: string = '';
  @Param pageTitle: string = '';
  @Param searchQuery: string = '';
  @Param initialDraft: string = '';
  @Param inputIdentity: string = 'unknown';
  @Param selectedFontSize: PageFontSize = PageFontSize.STANDARD;
  @Param readerMode: boolean = false;
  @Param webReady: boolean = false;
  @Param desktopMode: boolean = false;
  @Param downloadActive: boolean = false;
  /** -1 represents a running download with no known total size. */
  @Param downloadProgress: number = 0;
  @Param onNavigate: (value: string) => void = (_value: string) => undefined;
  @Param onOpenAddress: () => void = () => undefined;
  @Param onAddressCancel: () => void = () => undefined;
  @Param onFontSize: (size: PageFontSize) => void = (_size: PageFontSize) => undefined;
  @Param onPageAction: (action: PageAction) => void = (_action: PageAction) => undefined;
  @Param onGestureCancel: () => void = () => undefined;
  @Param onDraftChange: (value: string) => void = (_value: string) => undefined;
  @Param onInputFocusChange: (focused: boolean) => void = (_focused: boolean) => undefined;
  @Param focusRequestToken: number = 0;
  @Param allowFocus: boolean = true;
  @Param gestureEnabled: boolean = true;
  @Param inputMounted: boolean = true;
  // Standalone previews keep the historical click-to-edit behavior; the
  // production AddressTabStrip supplies the authoritative collapsed state.
  @Param editorActive: boolean = true;
  @Param editorClosing: boolean = false;
  @Param inputExpandProgress: number = 0;

  @Local draftAddress: string = '';
  @Local pageMenuShown: boolean = false;
  @Local longPressActive: boolean = false;
  @Local addressInputFocused: boolean = false;
  private readonly inputController: TextInputController = new TextInputController();

  aboutToAppear(): void {
    this.draftAddress = this.initialDraft.length > 0
      ? this.initialDraft
      : (this.address === 'about:blank' ? '' : this.address);
    this.addressInputFocused = false;
    this.lastFocusRequestToken = this.focusRequestToken;
    this.onInputFocusChange(false);
  }

  private lastFocusRequestToken: number = 0;

  /** Mount and focus the real TextInput after a root-level chrome tap. */
  @Monitor('focusRequestToken')
  private onExternalFocusRequest(): void {
    if (this.focusRequestToken <= this.lastFocusRequestToken) {
      return;
    }
    this.lastFocusRequestToken = this.focusRequestToken;
    this.requestAddressFocus();
  }

  /**
   * TextInput retains its native editing buffer when a parent only changes a
   * parameter. The parent changes inputIdentity at each tab/navigation
   * boundary, so this monitor only resets the local display state; deleting
   * through the controller here could race the user's final backspace.
   */
  @Monitor('inputIdentity', 'address')
  private onAddressIdentityChanged(): void {
    this.draftAddress = syncAddressDraft(this.address, this.initialDraft, this.editorActive);
    this.addressInputFocused = false;
    this.onInputFocusChange(false);
  }

  /**
   * Parent draft changes include a deliberate empty string when the user has
   * deleted the complete URL. Synchronize that value without touching focus;
   * otherwise the native field can restore its old buffer on blur or close.
   */
  @Monitor('initialDraft', 'editorActive')
  private onParentDraftChanged(): void {
    this.draftAddress = syncAddressDraft(this.address, this.initialDraft, this.editorActive);
  }

  private submitAddress(): void {
    this.onNavigate(this.draftAddress);
    // The parent owns the committed URL. Clearing the local draft lets the
    // field immediately follow a page-internal navigation or a history
    // gesture instead of retaining the previous submitted address.
    this.draftAddress = '';
  }

  private clearAddressInput(): void {
    // Clear the native TextInput buffer as well as the parent-authoritative
    // draft. Updating only the bound text can leave the native editor buffer
    // visible until the next remount.
    try {
      this.inputController.deleteText();
    } catch (_error) {
      // The controller can be between mount and focus transitions; the local
      // draft update below still clears the rendered value on the next frame.
    }
    this.draftAddress = '';
    this.onDraftChange('');
    this.requestAddressFocus();
  }

  private visibleAddress(): string {
    // The parent editor state is authoritative. A transient native focus
    // callback must not restore the committed URL while the user deletes the
    // last character from the draft.
    return addressEditorText(this.address, this.draftAddress, this.editorActive);
  }

  private collapsedAddress(): string {
    const explicitQuery: string = searchQueryTextFor(this.searchQuery);
    if (explicitQuery.length > 0) {
      return explicitQuery;
    }
    const searchQuery: string | undefined = searchQueryForUrl(this.address);
    if (searchQuery !== undefined) {
      return searchQuery;
    }
    const label: string = addressBarLabelFor(this.address, this.pageTitle);
    const searchSuffix: string = ' - 搜索';
    if (label.endsWith(searchSuffix)) {
      return searchQueryTextFor(label.slice(0, label.length - searchSuffix.length));
    }
    return searchQueryTextFor(label);
  }

  private editorCollapseProgress(): number {
    return Math.max(0, Math.min(1, this.inputExpandProgress));
  }

  private downloadRingProps(): DownloadProgressRingProps {
    return downloadProgressRingProps(
      this.inputIdentity,
      this.downloadActive,
      this.downloadProgress
    );
  }

  private isStartPage(): boolean {
    return this.address === 'about:blank';
  }

  private beginLongPress(): void {
    if (!this.gestureEnabled) {
      return;
    }
    // Cancel a pan that may have started before the long-press threshold. A
    // held address bar is now exclusively a context-menu interaction, so
    // dragging it upward must not open the tab overview.
    this.onGestureCancel();
    this.longPressActive = true;
    this.pageMenuShown = true;
  }

  private endLongPress(): void {
    if (!this.gestureEnabled) {
      return;
    }
    this.longPressActive = false;
    // Keep the menu state until the native Menu window reports onDisappear.
    // Releasing the finger must not unmount the builder before ArkUI opens it.
  }

  /**
   * The collapsed state is a display-only Text, so the parent
   * AddressTabStrip PanGesture remains the only drag recognizer. Mount the
   * native TextInput only after a tap has requested editing, preserving the
   * platform's normal caret and selection behavior while focused.
   */
  private requestAddressFocus(): void {
    if (!this.inputMounted || !this.gestureEnabled || !this.allowFocus) {
      return;
    }
    // Mount the editor after the tap has been classified and focus it next
    // frame so the native field owns only the editing sequence.
    this.addressInputFocused = true;
    this.onInputFocusChange(true);
    setTimeout(() => {
      try {
        this.getUIContext().getFocusController().requestFocus(this.inputIdentity);
      } catch (_error) {
        // The TextInput can be between remounts during a tab commit.
      }
    }, 0);
  }

  private dismissPageMenu(): void {
    this.longPressActive = false;
    this.pageMenuShown = false;
  }

  private runPageAction(action: PageAction): void {
    this.onPageAction(action);
    this.dismissPageMenu();
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
  private pageMenu() {
    Menu() {
      MenuItem({ content: '下载管理' })
        .id('browser-download-manager-menu-item')
        .onChange((selected: boolean) => {
          if (selected) {
            this.runPageAction(PageAction.DOWNLOAD_MANAGER);
          }
        })
      MenuItem({
        content: pageModeMenuLabel(this.desktopMode),
        symbolStartIcon: this.pageModeMenuSymbol()
      })
        .enabled(this.webReady)
        .onChange((selected: boolean) => {
          if (selected) {
            this.runPageAction(PageAction.DESKTOP_SITE);
          }
        })
    }
  }

  build() {
    Stack() {
      Row({ space: 8 }) {
        Stack({ alignContent: Alignment.TopStart }) {
          if (addressLeadingActionVisibleFor(this.isStartPage(), this.addressInputFocused)) {
            Button({ type: ButtonType.Normal, stateEffect: false }) {
              Stack({ alignContent: Alignment.TopStart }) {
                if (this.downloadRingProps().visible) {
                  Progress({
                    value: this.downloadRingProps().value,
                    total: 100,
                    type: ProgressType.Ring
                  })
                    .id(this.downloadRingProps().id)
                    .width(this.downloadRingProps().size)
                    .height(this.downloadRingProps().size)
                    .position({
                      x: this.downloadRingProps().ringOffset,
                      y: this.downloadRingProps().ringOffset
                    })
                    .color(this.downloadRingProps().color)
                    .style({
                      strokeWidth: this.downloadRingProps().strokeWidth,
                      status: ProgressStatus.PROGRESSING
                    });
                }
                  Image(addressSecurityStateFor(this.address) === AddressSecurityState.SECURE
                  ? $r('app.media.address_secure_lock')
                  : $r('app.media.address_insecure_lock'))
                  .width(this.downloadRingProps().lockImageSize)
                  .height(this.downloadRingProps().lockImageSize)
                  .position({
                    x: this.downloadRingProps().lockImageOffsetX,
                    y: addressLockImageVerticalOffsetFor(
                      this.downloadRingProps().buttonSize,
                      this.downloadRingProps().lockImageSize
                    )
                  });
              }
                .width(this.downloadRingProps().buttonSize)
                .height(this.downloadRingProps().buttonSize);
            }
              .id('browser-page-menu-button')
              .width(this.downloadRingProps().buttonSize)
              .height(this.downloadRingProps().buttonSize)
              .padding(0)
              .backgroundColor(Color.Transparent)
              .stateEffect(false)
              .align(Alignment.TopStart)
              .position({ x: 0, y: addressLockVerticalOffsetFor(
                ADDRESS_SEARCH_BAR_STYLE.height,
                this.downloadRingProps().buttonSize
              ) })
              .zIndex(1)
              .onClick(() => this.pageMenuShown = true)
              .bindContextMenu(this.pageMenuShown, this.pageMenu, {
                placement: Placement.TopLeft,
                onDisappear: () => this.dismissPageMenu()
              })
              .parallelGesture(
                LongPressGesture({ duration: 300 })
                  .onAction(() => this.beginLongPress())
                  .onActionEnd(() => this.endLongPress())
                  .onActionCancel(() => this.endLongPress())
              );
          }
          if (addressClearButtonVisibleFor(
            this.editorActive,
            this.inputMounted,
            this.addressInputFocused
          )) {
            Stack({ alignContent: Alignment.TopEnd }) {
              Button({ type: ButtonType.Normal, stateEffect: false }) {
                Stack({ alignContent: Alignment.Center }) {
                  Text('×')
                    .fontSize(22)
                    .fontColor('#6B7280');
                }
                  .width(32)
                  .height(32);
              }
                .id('browser-address-clear-button')
                .width(32)
                .height(32)
                .padding(0)
                .backgroundColor(Color.Transparent)
                .stateEffect(false)
                .zIndex(2)
                .onClick(() => this.clearAddressInput());
            }
              .width('100%')
              .height(ADDRESS_SEARCH_BAR_STYLE.height)
              .padding({ top: addressLockVerticalOffsetFor(
                ADDRESS_SEARCH_BAR_STYLE.height,
                32
              ) })
              .hitTestBehavior(HitTestMode.Transparent)
              .zIndex(2)
          }
          if (this.inputMounted && this.editorActive) {
            TextInput({
            text: this.visibleAddress(),
            placeholder: placeholderForFocus('搜索或输入网站', this.addressInputFocused),
            controller: this.inputController
          })
            .id(this.inputIdentity)
            .width('100%')
            .height(44)
            .focusable(this.allowFocus && this.gestureEnabled)
            // While the field is not focused, let the surrounding chrome own
            // the pointer stream. ArkWeb/TextInput installs native selection
            // recognizers that otherwise win a horizontal drag and expose
            // selection handles instead of forwarding the tab transition.
            .hitTestBehavior(this.addressInputFocused ? HitTestMode.Default : HitTestMode.None)
            .fontSize(16)
            .fontColor(addressTextColorFor(true))
            .placeholderColor(addressTextColorFor(false))
            .textAlign(addressTextAlignmentFor(this.editorActive) === 'start'
              ? TextAlign.Start
              : TextAlign.Center)
            .opacity(this.editorClosing ? this.editorCollapseProgress() : 1)
            .backgroundColor(Color.Transparent)
            .padding({
              left: addressTextAlignmentFor(this.editorActive) === 'start'
                ? addressInputLeftPaddingFor(this.isStartPage(), this.addressInputFocused)
                : 0,
              right: addressClearButtonVisibleFor(
                this.editorActive,
                this.inputMounted,
                this.addressInputFocused
              ) ? SAFARI_ADDRESS_LOCK_SAFE_INSET_VP : 0
            })
            .onFocus(() => {
              this.addressInputFocused = true;
              this.onInputFocusChange(true);
            })
            .onBlur(() => {
              this.addressInputFocused = false;
              this.onInputFocusChange(false);
              // A native TextInput blur is the platform's dismissal signal
              // for a tap/back action outside the editor. Defer one UI turn
              // so a parent-driven close can publish editorActive=false
              // before this callback decides whether to collapse again.
              setTimeout(() => {
                if (this.editorActive && !this.editorClosing && !this.addressInputFocused) {
                  this.onAddressCancel();
                }
              }, 0);
            })
            .onChange((value: string) => {
              this.draftAddress = value;
              this.onDraftChange(value);
            })
              .onSubmit(() => this.submitAddress());
          } else {
            Text(this.collapsedAddress())
              .width('100%')
              .height(44)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontSize(16)
              .fontColor(addressTextColorFor(this.visibleAddress().length > 0))
              .textAlign(TextAlign.Center)
              .padding(addressCollapsedTextPaddingFor(!this.isStartPage()))
              // The unfocused label is display-only.  Explicitly disable
              // ArkUI text selection so a long/slow horizontal drag cannot
              // open the system selection handles instead of the tab swipe.
              .textSelectable(TextSelectableMode.UNSELECTABLE)
              .padding({ left: 0, right: 0 });
          }
          if (this.editorClosing && this.editorActive) {
            Text(this.collapsedAddress())
              .width('100%')
              .height(44)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontSize(16)
              .fontColor(addressTextColorFor(this.visibleAddress().length > 0))
              .textAlign(TextAlign.Center)
              .textSelectable(TextSelectableMode.UNSELECTABLE)
              .padding(addressCollapsedTextPaddingFor(!this.isStartPage()))
              .opacity(1 - this.editorCollapseProgress())
              .hitTestBehavior(HitTestMode.None);
          }
        }
          .layoutWeight(1)
          .height(ADDRESS_SEARCH_BAR_STYLE.height)
          .padding({ left: 9, right: 9 })
          .backgroundColor(Color.White)
          .borderRadius(ADDRESS_SEARCH_BAR_STYLE.cornerRadius)
          .border({ width: this.addressInputFocused ? 0 : 1,
            color: this.addressInputFocused ? '#00000000' : '#55FFFFFF' })
          .shadow(this.addressInputFocused
            ? { radius: 8, color: '#18000000', offsetX: 0, offsetY: 1 }
            : { radius: 12, color: '#24000000', offsetX: 0, offsetY: 2 })
          // The unfocused state is display-only, so the field itself can own
          // taps without mounting a native TextInput or exposing selection
          // handles. The parent PanGesture below still receives horizontal
          // movement and forwards it to BrowserShell.
          .onClick(() => {
            this.onOpenAddress();
            this.requestAddressFocus();
          });
      }
        .width('100%')
        .height(ADDRESS_SEARCH_BAR_STYLE.height);
    }
      .id(`bottom-address-search-bar-${this.inputIdentity}`)
      .width('100%')
      .height(56)
      .padding({ top: ADDRESS_SEARCH_BAR_TOP_PADDING,
        bottom: 56 - ADDRESS_SEARCH_BAR_TOP_PADDING - ADDRESS_SEARCH_BAR_STYLE.height })
      .backgroundColor(Color.Transparent)
      .bindContextMenu(this.gestureEnabled && this.pageMenuShown, this.pageMenu, {
        onDisappear: () => this.dismissPageMenu()
      })
      .hitTestBehavior(this.gestureEnabled ? HitTestMode.Default : HitTestMode.None)
      // Horizontal tab gestures are owned by BrowserTransitionScene's single
      // root recognizer. Keeping this component free of a competing priority
      // PanGesture lets its TextInput/tap behavior coexist with the root
      // scene's parallel gesture stream.
  }
}
