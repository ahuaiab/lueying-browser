import {
  committedUrlForTabState,
  loadableUrlFor,
  searchQueryTextFor
} from './BrowserTypes';
import { SAFARI_ADDRESS_LOCK_SAFE_INSET_VP } from './BrowserVisualMetrics';

/**
 * Returns whether the embedded ArkWeb surface should participate in hit
 * testing for the current browser state.
 *
 * The native start page is rendered above the blank ArkWeb document. Keeping
 * that document out of the hit-test chain lets the start-page controls receive
 * their click events instead of sending them to the transparent Web surface.
 */
export function webHostInputEnabled(activeAddress: string, gestureActive: boolean): boolean {
  return !gestureActive && activeAddress !== 'about:blank';
}

/**
 * State to apply after a navigation submit. A TextInput can start a pan
 * recognizer before the IME's submit action arrives; returning to this
 * canonical state makes the newly loaded ArkWeb surface interactive again.
 */
export interface BrowserGestureState {
  gestureActive: boolean;
  addressGestureFinished: boolean;
  overviewProgress: number;
  horizontalOffset: number;
}

export function resetBrowserGestureState(): BrowserGestureState {
  return {
    gestureActive: false,
    addressGestureFinished: true,
    overviewProgress: 0,
    horizontalOffset: 0
  };
}

/**
 * Normalize the URL reported by ArkWeb's page lifecycle callbacks before it
 * is committed to the tab model. Some callbacks can be delivered with an
 * empty URL while the renderer is being restored; preserving the last known
 * address keeps the address bar and tab search stable in that interval.
 */
export function committedNavigationUrl(reportedUrl: string, fallbackUrl: string): string {
  return committedUrlForTabState(reportedUrl, fallbackUrl);
}

/**
 * ArkWeb controllers created while the tab overview is visible can finish a
 * navigation while their renderer is still inactive. Reactivate only a real
 * page URL after a submit; the native start page remains above about:blank.
 */
export function shouldActivateWebController(url: string): boolean {
  const normalized: string | undefined = loadableUrlFor(url);
  return normalized !== undefined && normalized !== 'about:blank';
}

/**
 * Existing native Tabs pages already retain their ArkWeb controller.  Only a
 * missing controller for a real web URL is eligible for the saved-URL
 * recovery path; blank tabs remain owned by the native start page.
 */
export function shouldRecoverMissingTabController(controllerAvailable: boolean, savedUrl: string): boolean {
  return !controllerAvailable && shouldActivateWebController(savedUrl);
}

/**
 * A blank tab created behind the overview has no reliable renderer surface.
 * Build that first navigation as a fresh ArkWeb runtime whose initial source
 * is the requested URL instead of trying to reuse the hidden blank document.
 */
export function shouldRecreateBlankTabRuntime(currentUrl: string, targetUrl: string): boolean {
  return currentUrl.trim() === 'about:blank' && shouldActivateWebController(targetUrl);
}

/**
 * BuilderNode can publish its FrameNode one UI turn after build() when it is
 * created while an overlay is animating. Retry a bounded number of times so a
 * transiently empty NodeContainer is repaired without spinning forever.
 */
export function shouldRetryWebHostAttachment(framePending: boolean, attempt: number): boolean {
  return framePending && attempt >= 0 && attempt < 3;
}

/**
 * ArkWeb can report page-end before its compositor has produced a frame for
 * webPageSnapshot(). Keep the last-known thumbnail path alive for a bounded
 * number of attempts; a failed capture must not turn the transition target
 * into a white surface forever.
 */
export function shouldRetryTabSnapshot(snapshotUnavailable: boolean, attempt: number): boolean {
  return snapshotUnavailable && attempt >= 0 && attempt < 3;
}

/**
 * Keep dynamic ArkWeb creation out of the overview overlay's layout pass.
 * The caller can animate the sheet away first and still cancel the request.
 */
export function shouldDismissOverviewBeforeCreatingTab(overviewProgress: number): boolean {
  return overviewProgress > 0;
}

/**
 * A new tab must wait for both the visible overview animation and its async
 * selection finalization. A zero progress value alone is not sufficient:
 * the reverse animator can publish zero before finishOverviewClose() has
 * rebased the scene and released the overlay transaction.
 */
export function shouldWaitForOverviewClose(
  overviewProgress: number,
  overviewClosing: boolean,
  overviewAnimationClosing: boolean,
  completionPending: boolean
): boolean {
  return completionPending || overviewClosing || overviewAnimationClosing ||
    (Number.isFinite(overviewProgress) && overviewProgress > 0);
}

/**
 * A partially revealed overview is still an interactive transition.  It must
 * be allowed to settle to 1 after an upward swipe; treating any value above
 * zero as "already open" leaves the whole overview panel translucent.
 */
export function isOverviewSettled(overviewProgress: number): boolean {
  return Number.isFinite(overviewProgress) && overviewProgress >= 1;
}

/**
 * Keep the interactive overview reveal on one native scale track.  The
 * programmatic entry uses TransitionEffect.scale; this helper is only for
 * the overview that is already mounted under the user's upward drag.
 */
export function overviewScaleAtProgress(progress: number, entryScale: number): number {
  const safeEntryScale: number = Number.isFinite(entryScale) && entryScale > 0 && entryScale <= 1
    ? entryScale
    : 1;
  if (!Number.isFinite(progress)) {
    return safeEntryScale;
  }
  const boundedProgress: number = Math.max(0, Math.min(1, progress));
  return safeEntryScale + (1 - safeEntryScale) * boundedProgress;
}

/**
 * Live ArkWeb hosts are mounted only in the page state.  The overview renders
 * snapshots, so keeping a NodeContainer in its card layout can resize the
 * renderer backing store and leave the next active tab blank.
 */
export function shouldMountWebHost(overviewProgress: number): boolean {
  return overviewProgress <= 0;
}

/**
 * The native start page owns the blank-tab surface. Mounting ArkWeb for
 * about:blank lets its built-in document paint above ArkUI overlays on some
 * devices, so wait until a real URL has been committed before publishing the
 * live Web component.
 */
export function shouldRenderLiveWebHost(overviewProgress: number, activeAddress: string): boolean {
  return shouldMountWebHost(overviewProgress) && shouldActivateWebController(activeAddress);
}

/**
 * Only tabs with a committed URL own a visible ArkWeb surface. Blank tabs are
 * rendered by the native start page; mounting their about:blank frame beside
 * an active page can cover the active renderer during a tab transition.
 */
export function shouldMountTabWebHost(url: string): boolean {
  return shouldActivateWebController(url);
}

/**
 * A NodeContainer can publish its native frame after the first measured
 * viewport callback. Refresh the host once the real viewport is available,
 * but never while the snapshot overview is still mounted.
 */
export function shouldRefreshHostsForViewport(
  previousWidth: number,
  nextWidth: number,
  overviewProgress: number
): boolean {
  return nextWidth > 0 && nextWidth !== previousWidth && overviewProgress <= 0;
}

/**
 * An address-bar transition may outlive the touch that started it.  A new
 * gesture (or an explicit cancellation) advances the token so the stale
 * animation cannot activate a tab or overwrite the new gesture's layout.
 */
export function isAddressTransitionCurrent(startToken: number, currentToken: number): boolean {
  return startToken === currentToken;
}

/**
 * Gives the native address editor a new identity whenever its tab or parent
 * remount generation changes. ArkUI otherwise keeps TextInput's internal
 * editing buffer when only the `text` parameter changes.
 */
export function addressInputIdentity(tabId: string, remountToken: number): string {
  const normalizedTabId: string = tabId.trim().length > 0 ? tabId.trim() : 'unknown';
  const normalizedToken: number = Number.isFinite(remountToken) && remountToken >= 0
    ? Math.floor(remountToken)
    : 0;
  return `address-input-${normalizedTabId}-${normalizedToken}`;
}

/** The only settled state in which the address strip may accept a new pan. */
export interface ClosedAddressEditorState {
  addressDraft: string;
  addressInputFocused: boolean;
  addressEditing: boolean;
  barMode: string;
  inputExpandProgress: number;
  addressInputFocusEnabled: boolean;
}

export function closedAddressEditorState(): ClosedAddressEditorState {
  return {
    addressDraft: '',
    addressInputFocused: false,
    addressEditing: false,
    barMode: 'collapsed',
    inputExpandProgress: 0,
    addressInputFocusEnabled: true
  };
}

/**
 * Resolve the native editor's local buffer from the parent chrome state.
 * While the editor is active, an empty draft is a real user value. Outside the
 * editor, an empty draft means that the committed address should be displayed
 * again. Keeping this rule pure prevents a stale TextInput buffer from
 * resurrecting a deleted or cancelled URL.
 */
export function syncAddressDraft(
  committedAddress: string,
  draftAddress: string,
  editorActive: boolean
): string {
  if (editorActive) {
    return draftAddress;
  }
  return draftAddress.length > 0
    ? draftAddress
    : (committedAddress === 'about:blank' ? '' : committedAddress);
}

/**
 * Keep the reason an address was opened separate from the URL that the
 * search engine eventually produced. A search-result URL can look like a
 * normal URL, but its editor should restore the user's original query.
 */
export enum AddressBarPresentationMode {
  SEARCH = 'search',
  URL = 'url'
}

/** Classify the raw editor submission before it is normalized into a URL. */
export function addressBarPresentationForInput(input: string): AddressBarPresentationMode {
  const value: string = input.trim();
  if (value.length === 0) {
    return AddressBarPresentationMode.SEARCH;
  }
  if (loadableUrlFor(value) !== undefined) {
    return AddressBarPresentationMode.URL;
  }
  if (!value.includes(' ') && value.includes('.')) {
    const hostnameUrl: string = `https://${value}`;
    if (loadableUrlFor(hostnameUrl) !== undefined) {
      return AddressBarPresentationMode.URL;
    }
  }
  return AddressBarPresentationMode.SEARCH;
}

/** Resolve the text shown when a user taps the collapsed address item. */
export function addressEditorDraftFor(
  committedAddress: string,
  mode: AddressBarPresentationMode,
  searchQuery: string
): string {
  if (mode === AddressBarPresentationMode.SEARCH) {
    return searchQueryTextFor(searchQuery);
  }
  return committedAddress === 'about:blank' ? '' : committedAddress;
}

/** Display text follows the same parent-authoritative draft rule. */
export function addressEditorText(
  committedAddress: string,
  draftAddress: string,
  editorActive: boolean
): string {
  return syncAddressDraft(committedAddress, draftAddress, editorActive);
}

/** Keep editable text readable from the leading edge while collapsed chrome is centered. */
export type AddressTextAlignment = 'start' | 'center';

export function addressTextAlignmentFor(editorActive: boolean): AddressTextAlignment {
  return editorActive ? 'start' : 'center';
}

/** Keep address content and placeholder text visually consistent across states. */
export function addressTextColorFor(hasContent: boolean): string {
  return hasContent ? '#1D1D1F' : '#6B7280';
}

export interface AddressTextPadding {
  left: number;
  right: number;
}

/** Keep editable web-address text clear of the leading security control. */
export function addressEditorLeftPaddingFor(hasSecurityControl: boolean): number {
  return hasSecurityControl ? SAFARI_ADDRESS_LOCK_SAFE_INSET_VP : 0;
}

/** Keep collapsed web-address text clear of the leading security control. */
export function addressCollapsedTextPaddingFor(hasSecurityControl: boolean): AddressTextPadding {
  const inset: number = addressEditorLeftPaddingFor(hasSecurityControl);
  return { left: inset, right: inset };
}

/** The clear affordance belongs only to a focused, mounted address editor. */
export function addressClearButtonVisibleFor(
  editorActive: boolean,
  inputMounted: boolean,
  inputFocused: boolean
): boolean {
  return editorActive && inputMounted && inputFocused;
}

/** Place the security control at the exact vertical center of the address capsule. */
export function addressLockVerticalOffsetFor(containerHeight: number, controlHeight: number): number {
  const safeContainerHeight: number = Number.isFinite(containerHeight) && containerHeight > 0
    ? containerHeight
    : 0;
  const safeControlHeight: number = Number.isFinite(controlHeight) && controlHeight > 0
    ? controlHeight
    : 0;
  return Math.max(0, (safeContainerHeight - safeControlHeight) / 2);
}

/** Place the lock artwork at the exact center of the button content box. */
export function addressLockImageVerticalOffsetFor(controlHeight: number, imageHeight: number): number {
  const safeControlHeight: number = Number.isFinite(controlHeight) && controlHeight > 0
    ? controlHeight
    : 0;
  const safeImageHeight: number = Number.isFinite(imageHeight) && imageHeight > 0
    ? imageHeight
    : 0;
  return Math.max(0, (safeControlHeight - safeImageHeight) / 2);
}

/**
 * The parent chrome state is authoritative for gesture admission. A stale
 * native TextInput focus flag must not disable a later swipe after the editor
 * has visibly collapsed.
 */
export function canStartAddressStripGesture(
  startInAddressStrip: boolean,
  barMode: string,
  inputExpandProgress: number,
  addressEditing: boolean
): boolean {
  return startInAddressStrip &&
    (barMode === 'collapsed' || barMode === 'collapsing') &&
    inputExpandProgress <= 0 &&
    !addressEditing;
}

/**
 * Safari keeps search fields visually quiet once they are active: the hint is
 * replaced by the insertion caret and the user's input. Keep that rule in a
 * shared helper so every native search field applies it consistently.
 */
export function placeholderForFocus(placeholder: string, focused: boolean): string {
  return focused ? '' : placeholder;
}

/**
 * Lifecycle events emitted by ArkWeb while a tab is loading or rendering.
 * Keeping this classification pure makes the diagnostic path testable without
 * depending on a device callback or inventing a network root cause.
 */
export enum BrowserLifecycleEventKind {
  PAGE_END = 'page_end',
  NETWORK_ERROR = 'network_error',
  SSL_ERROR = 'ssl_error',
  RENDERER_EXITED = 'renderer_exited'
}

export interface BrowserLifecycleDiagnostic {
  kind: BrowserLifecycleEventKind;
  code: number;
  isMainFrame: boolean;
}

export function browserLifecycleDiagnostic(
  kind: BrowserLifecycleEventKind,
  code: number = 0,
  isMainFrame: boolean = true
): BrowserLifecycleDiagnostic {
  return { kind, code, isMainFrame };
}
