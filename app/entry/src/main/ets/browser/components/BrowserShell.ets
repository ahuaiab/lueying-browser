import { webview } from '@kit.ArkWeb';
import { AnimatorResult, UIContext, curves } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { systemShare } from '@kit.ShareKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import inputMethod from '@ohos.inputMethod';
import window from '@ohos.window';
import { AddressTabStrip } from './AddressTabStrip';
import { BottomBrowserBar } from './BottomBrowserBar';
import { GestureLab } from './GestureLab';
import { LibrarySheet } from './LibrarySheet';
import { StartPage } from './StartPage';
import { StartPageCustomizeSheet } from './StartPageCustomizeSheet';
import { BrowserTransitionScene } from './BrowserTransitionScene';
import { TabOverview } from './TabOverview';
import {
  DefaultBrowserCommandDispatcher,
  NoopSnapshotPort,
  SessionPort,
  TabRuntimePort
} from '../command/BrowserCommandDispatcher';
import { GestureDecisionEngine } from '../gesture/GestureDecisionEngine';
import { DEFAULT_GESTURE_PROFILE } from '../gesture/GestureProfile';
import {
  ArkWebRuntimeFactory,
  ArkWebRuntimeHandle,
  WebNodeHostController,
  WebPageLifecycleObserver,
  WebDownloadObserver,
  WebLoadError,
  WebSslError
} from '../web/WebTabNode';
import { WebTabPool } from '../web/WebTabPool';
import { MemorySnapshotStorage, TabSnapshotCache } from '../snapshot/TabSnapshotCache';
import { BrowserRepository } from '../data/BrowserRepository';
import { DownloadRecordStorage, DownloadStore } from '../data/DownloadStore';
import { KeyValueStore, MemoryKeyValueStore, PreferencesKeyValueStore } from '../data/KeyValueStore';
import { BrowserLifecyclePort, BrowserLifecycleRegistry } from '../lifecycle/BrowserLifecyclePort';
import {
  DownloadProgressSnapshot,
  DownloadStatus,
  DownloadTaskRecord
} from '../model/DownloadModels';
import { PageAction, desktopUserAgentFor } from '../model/PageActions';
import {
  HistoryDeleteRange,
  historyDeleteCutoff,
  libraryBookmarkActionEnabled
} from '../model/LibraryModels';
import {
  BrowserSettings,
  AutoCloseTabsPolicy,
  BrowserSearchEngine,
  copyBrowserSettings,
  DEFAULT_BROWSER_SETTINGS,
  StartPageAppearance
} from '../model/BrowserSettings';
import { ClosedTabStack, closedTabFromRecord } from '../data/ClosedTabStack';
import {
  PageDisplayState,
  DEFAULT_PAGE_DISPLAY_STATE,
  PageFontSize,
  copyPageDisplayState
} from '../model/PageDisplayState';
import {
  StartPageItem,
  StartPageItemType,
  copyStartPageItem
} from '../model/StartPageModels';
import {
  TAB_OVERVIEW_GESTURE_CARD_HEIGHT,
  tabOverviewCardWidth,
  tabOverviewPageFrame,
  tabOverviewChromeFrame,
  TabOverviewChromeFrame,
  TabOverviewPageFrame,
  tabOverviewSpringEasing,
  tabOverviewBorderOwner,
  tabOverviewCaptionHandoffOpacity,
  shouldMountBottomBrowserBar,
  shouldMountAddressTransitionLayer,
  tabOverviewAddressLayerZIndex,
  tabOverviewBottomChromeZIndex,
} from '../model/TabOverviewActions';
import { topContentInsetFromAvoidRects } from '../model/WindowAvoidance';
import {
  BROWSER_OVERVIEW_ANIMATION_DURATION_MS,
  BROWSER_OVERVIEW_TRANSITION_DURATION_MS,
  HARMONY_RADIUS_CARD,
  SAFARI_ADDRESS_ITEM_GAP_VP,
  SAFARI_ADDRESS_HANDOFF_CROSSFADE_DURATION_MS,
  SAFARI_ADDRESS_HANDOFF_LEAD_IN_MS,
  SAFARI_ADDRESS_PREVIEW_FADE_DURATION_MS,
  SAFARI_BOTTOM_CHROME_BASE_HEIGHT_VP,
  safariAddressItemWidth,
  START_PAGE_CUSTOMIZE_DISMISS_SPRING_RESPONSE,
  START_PAGE_CUSTOMIZE_DISMISS_SPRING_DAMPING,
  START_PAGE_CUSTOMIZE_DISMISS_SPRING_OVERLAP
} from '../model/BrowserVisualMetrics';
import {
  AddressBarPresentationMode,
  addressBarPresentationForInput,
  addressEditorDraftFor,
  resetBrowserGestureState,
  committedNavigationUrl,
  shouldActivateWebController,
  shouldRecoverMissingTabController,
  shouldRecreateBlankTabRuntime,
  shouldRetryTabSnapshot,
  shouldDismissOverviewBeforeCreatingTab,
  isOverviewSettled,
  shouldMountTabWebHost,
  shouldRefreshHostsForViewport,
  isAddressTransitionCurrent,
  addressInputIdentity,
  closedAddressEditorState,
  canStartAddressStripGesture,
  BrowserGestureState
} from '../model/BrowserInteraction';
import {
  TabGestureMotionState,
  tabGestureMotion,
  emptyTabGestureMotion,
  verticalOverviewGestureMotion,
  TabPreviewKind,
  TabGestureState
} from '../model/TabGestureMotion';
import {
  safariTransitionFrame,
  shouldPrimeFinalTabPreview,
  shouldRenderPendingTabPreview
} from '../model/SafariTabTransition';
import { TouchOwner } from '../gesture/TouchOwnership';
import {
  AddressBarSource,
  BrowserErrorKind,
  BrowserErrorState,
  BrowserSessionSnapshot,
  BrowserTabRecord,
  PendingTabDraft,
  BookmarkRecord,
  GestureAxis,
  GestureDecision,
  GestureOutcome,
  GestureSample,
  HistoryRecord,
  TabDirection,
  TabId,
  displayUrlFor,
  lastValidUrlForTab,
  validateBrowserUrl,
  loadableUrlFor,
  normalizeAddressInput,
  searchQueryForUrl,
  searchQueryTextFor,
  tabOverviewTitleFor,
  bookmarkRecordForPage
} from '../model/BrowserTypes';
import { TabStore } from '../store/TabStore';
import { DownloadNotificationGateway } from '../web/DownloadNotificationGateway';
import { DownloadService, WebCookiePort } from '../web/DownloadService';
import { RequestAgentGateway } from '../web/RequestAgentGateway';
import {
  takePendingExternalUrl
} from '../model/BrowserLaunchState';

const ENABLE_GESTURE_LAB: boolean = false;
const BROWSER_WEB_DOMAIN: number = 0x0000;
const BROWSER_WEB_TAG: string = 'BrowserWeb';
const TAB_SNAPSHOT_RETRY_DELAYS_MS: number[] = [120, 280, 640];
const DOWNLOAD_RECORDS_KEY: string = 'downloads.v1';
let sharedDownloadService: DownloadService | undefined = undefined;
let sharedDownloadFilesDir: string = '';

class KeyValueDownloadRecordStorage implements DownloadRecordStorage {
  private readonly store: KeyValueStore;

  constructor(store: KeyValueStore) {
    this.store = store;
  }

  async load(): Promise<DownloadTaskRecord[]> {
    const raw: string = await this.store.getString(DOWNLOAD_RECORDS_KEY, '[]');
    try {
      const records: DownloadTaskRecord[] = JSON.parse(raw) as DownloadTaskRecord[];
      return Array.isArray(records) ? records : [];
    } catch (_error) {
      return [];
    }
  }

  async save(records: DownloadTaskRecord[]): Promise<void> {
    await this.store.putString(DOWNLOAD_RECORDS_KEY, JSON.stringify(records));
    await this.store.flush();
  }
}

class ArkWebCookiePort implements WebCookiePort {
  async fetchCookie(url: string, isPrivate: boolean): Promise<string> {
    if (isPrivate) {
      return '';
    }
    try {
      return await webview.WebCookieManager.fetchCookie(url, false, false);
    } catch (_error) {
      return '';
    }
  }
}

export interface BrowserDownloadServicePort {
  restore(): Promise<void>;
  markUiLoaded(): void;
  snapshot(): DownloadTaskRecord[];
  pause(id: string): Promise<void>;
  resume(id: string): Promise<void>;
  cancel(id: string): Promise<void>;
  retry(id: string): Promise<void>;
  setListener(listener: (tasks: DownloadTaskRecord[]) => void): void;
  clearListener(listener: (tasks: DownloadTaskRecord[]) => void): void;
}

/** Selects the one read-only download indicator owned by an address tab. */
export function selectDownloadProgressForTab(
  tasks: DownloadTaskRecord[],
  tabId: string
): DownloadProgressSnapshot | undefined {
  const active: DownloadTaskRecord[] = tasks.filter((task: DownloadTaskRecord): boolean =>
    task.tabId === tabId && task.status !== DownloadStatus.COMPLETED &&
    task.status !== DownloadStatus.FAILED && task.status !== DownloadStatus.CANCELLED
  );
  if (active.length === 0) {
    return undefined;
  }
  const newest: DownloadTaskRecord = active.reduce(
    (current: DownloadTaskRecord, task: DownloadTaskRecord): DownloadTaskRecord =>
      task.updatedAt > current.updatedAt ? task : current
  );
  return {
    id: newest.id,
    tabId: newest.tabId,
    status: newest.status,
    receivedBytes: newest.receivedBytes,
    totalBytes: newest.totalBytes,
    percent: newest.percent,
    filename: newest.filename,
    url: newest.url
  };
}

class DownloadServiceLifecyclePort implements BrowserDownloadServicePort {
  private readonly service: DownloadService;

  constructor(service: DownloadService) {
    this.service = service;
  }

  async restore(): Promise<void> {
    await this.service.restore();
  }

  markUiLoaded(): void {
    this.service.markUiLoaded();
  }

  snapshot(): DownloadTaskRecord[] {
    return this.service.snapshot();
  }

  async pause(id: string): Promise<void> {
    await this.service.pause(id);
  }

  async resume(id: string): Promise<void> {
    await this.service.resume(id);
  }

  async cancel(id: string): Promise<void> {
    await this.service.cancel(id);
  }

  async retry(id: string): Promise<void> {
    await this.service.retry(id);
  }

  setListener(listener: (tasks: DownloadTaskRecord[]) => void): void {
    this.service.setListener(listener);
  }

  clearListener(listener: (tasks: DownloadTaskRecord[]) => void): void {
    this.service.clearListener(listener);
  }
}

/** Keeps shell visibility separate from request.agent task ownership. */
export class BrowserDownloadLifecycle {
  private readonly service: BrowserDownloadServicePort;
  private readonly snapshotListener: (tasks: DownloadTaskRecord[]) => void;
  private readonly managerVisibilityListener: (visible: boolean) => void;
  private boundListener: ((tasks: DownloadTaskRecord[]) => void) | undefined = undefined;
  private stopped: boolean = false;

  constructor(
    service: BrowserDownloadServicePort,
    snapshotListener: (tasks: DownloadTaskRecord[]) => void,
    managerVisibilityListener: (visible: boolean) => void
  ) {
    this.service = service;
    this.snapshotListener = snapshotListener;
    this.managerVisibilityListener = managerVisibilityListener;
  }

  async start(): Promise<void> {
    this.stopped = false;
    if (this.boundListener === undefined) {
      this.boundListener = (tasks: DownloadTaskRecord[]): void => {
        this.snapshotListener(tasks.slice());
      };
    }
    this.service.setListener(this.boundListener);
    this.service.markUiLoaded();
    try {
      await this.service.restore();
    } catch (_error) {
      // The service must expose its loaded snapshot even if system task
      // recovery fails; this also keeps void start() rejection-free.
      if (!this.stopped) {
        this.snapshotListener(this.service.snapshot().slice());
      }
    }
  }

  stop(): void {
    this.stopped = true;
    const listener: ((tasks: DownloadTaskRecord[]) => void) | undefined = this.boundListener;
    if (listener !== undefined) {
      this.service.clearListener(listener);
      this.boundListener = undefined;
    }
  }

  onHidden(): void {
    // request.agent owns live background tasks; shell visibility must not
    // pause or cancel them.
  }

  openDownloadManager(_pageActionsReady: boolean = false): boolean {
    this.managerVisibilityListener(true);
    return true;
  }

  closeDownloadManager(): void {
    this.managerVisibilityListener(false);
  }

  async pause(id: string): Promise<void> {
    await this.service.pause(id);
  }

  async resume(id: string): Promise<void> {
    await this.service.resume(id);
  }

  async cancel(id: string): Promise<void> {
    await this.service.cancel(id);
  }

  async retry(id: string): Promise<void> {
    await this.service.retry(id);
  }
}

/** Adapts the stable ArkWeb runtime registry to the serial browser command port. */
class ArkWebTabRuntimePort implements TabRuntimePort {
  private readonly store: TabStore;
  private readonly pool: WebTabPool;

  constructor(store: TabStore, pool: WebTabPool) {
    this.store = store;
    this.pool = pool;
  }

  ensureBalanced(): void {
    this.pool.ensureBalanced(this.store.tabs, this.store.activeTabId);
  }

  ensureTab(tabId: TabId): void {
    this.pool.ensureTab(this.store.tabs, tabId);
  }

  release(tabId: TabId): void {
    this.pool.release(tabId);
  }

  goBack(tabId: TabId): boolean {
    const controller: webview.WebviewController | undefined = this.controllerFor(tabId);
    if (controller === undefined) {
      return false;
    }
    try {
      if (!controller.accessBackward()) {
        return false;
      }
      controller.backward();
      return true;
    } catch (_error) {
      return false;
    }
  }

  goForward(tabId: TabId): boolean {
    const controller: webview.WebviewController | undefined = this.controllerFor(tabId);
    if (controller === undefined) {
      return false;
    }
    try {
      if (!controller.accessForward()) {
        return false;
      }
      controller.forward();
      return true;
    } catch (_error) {
      return false;
    }
  }

  reload(tabId: TabId): void {
    const controller: webview.WebviewController | undefined = this.controllerFor(tabId);
    if (controller === undefined) {
      return;
    }
    try {
      controller.refresh();
    } catch (_error) {
      // A detached controller is expected during host replacement.
    }
  }

  controllerFor(tabId: TabId): webview.WebviewController | undefined {
    const runtime: ArkWebRuntimeHandle | undefined = this.pool.get(tabId) as ArkWebRuntimeHandle | undefined;
    return runtime?.getController();
  }

  controllerIdFor(tabId: TabId): string {
    return this.pool.runtimeIdFor(tabId);
  }
}

class BrowserPageLifecycleObserver implements WebPageLifecycleObserver, WebDownloadObserver {
  private readonly pageBeginCallback: (tabId: TabId, controller: webview.WebviewController, url: string) => void;
  private readonly callback: (tabId: TabId, controller: webview.WebviewController) => void;
  private readonly titleCallback: (tabId: TabId, controller: webview.WebviewController, title: string) => void;
  private readonly errorCallback: (tabId: TabId, controller: webview.WebviewController, diagnostic: WebLoadError) => void;
  private readonly sslErrorCallback: (tabId: TabId, controller: webview.WebviewController, diagnostic: WebSslError) => void;
  private readonly renderExitCallback: (tabId: TabId, controller: webview.WebviewController) => boolean;
  private readonly windowNewCallback: (tabId: TabId, controller: webview.WebviewController) => boolean;
  private readonly fullScreenEnterCallback: (tabId: TabId, controller: webview.WebviewController) => void;
  private readonly fullScreenExitCallback: (tabId: TabId, controller: webview.WebviewController) => void;
  private readonly downloadStartCallback: (tabId: TabId, fileName: string) => void;
  private readonly downloadFinishCallback: (tabId: TabId, filePath: string) => void;
  private readonly downloadFailedCallback: (tabId: TabId) => void;

  constructor(
    callback: (tabId: TabId, controller: webview.WebviewController) => void,
    errorCallback: (tabId: TabId, controller: webview.WebviewController, diagnostic: WebLoadError) => void =
      (_tabId: TabId, _controller: webview.WebviewController, _diagnostic: WebLoadError) => undefined,
    sslErrorCallback: (tabId: TabId, controller: webview.WebviewController, diagnostic: WebSslError) => void =
      (_tabId: TabId, _controller: webview.WebviewController, _diagnostic: WebSslError) => undefined,
    renderExitCallback: (tabId: TabId, controller: webview.WebviewController) => boolean =
      (_tabId: TabId, _controller: webview.WebviewController) => false,
    windowNewCallback: (tabId: TabId, controller: webview.WebviewController) => boolean =
      (_tabId: TabId, _controller: webview.WebviewController) => false,
    titleCallback: (tabId: TabId, controller: webview.WebviewController, title: string) => void =
      (_tabId: TabId, _controller: webview.WebviewController, _title: string) => undefined,
    fullScreenEnterCallback: (tabId: TabId, controller: webview.WebviewController) => void =
      (_tabId: TabId, _controller: webview.WebviewController) => undefined,
    fullScreenExitCallback: (tabId: TabId, controller: webview.WebviewController) => void =
      (_tabId: TabId, _controller: webview.WebviewController) => undefined,
    downloadStartCallback: (tabId: TabId, fileName: string) => void =
      (_tabId: TabId, _fileName: string) => undefined,
    downloadFinishCallback: (tabId: TabId, filePath: string) => void =
      (_tabId: TabId, _filePath: string) => undefined,
    downloadFailedCallback: (tabId: TabId) => void =
      (_tabId: TabId) => undefined,
    pageBeginCallback: (tabId: TabId, controller: webview.WebviewController, url: string) => void =
      (_tabId: TabId, _controller: webview.WebviewController, _url: string) => undefined
  ) {
    this.pageBeginCallback = pageBeginCallback;
    this.callback = callback;
    this.titleCallback = titleCallback;
    this.errorCallback = errorCallback;
    this.sslErrorCallback = sslErrorCallback;
    this.renderExitCallback = renderExitCallback;
    this.windowNewCallback = windowNewCallback;
    this.fullScreenEnterCallback = fullScreenEnterCallback;
    this.fullScreenExitCallback = fullScreenExitCallback;
    this.downloadStartCallback = downloadStartCallback;
    this.downloadFinishCallback = downloadFinishCallback;
    this.downloadFailedCallback = downloadFailedCallback;
  }

  onPageBegin(tabId: TabId, controller: webview.WebviewController, url: string): void {
    this.pageBeginCallback(tabId, controller, url);
  }

  onPageEnd(tabId: TabId, controller: webview.WebviewController): void {
    this.callback(tabId, controller);
  }

  onTitleReceive(tabId: TabId, controller: webview.WebviewController, title: string): void {
    this.titleCallback(tabId, controller, title);
  }

  onError(tabId: TabId, controller: webview.WebviewController, diagnostic: WebLoadError): void {
    this.errorCallback(tabId, controller, diagnostic);
  }

  onSslError(tabId: TabId, controller: webview.WebviewController, diagnostic: WebSslError): void {
    this.sslErrorCallback(tabId, controller, diagnostic);
  }

  onRenderExited(tabId: TabId, controller: webview.WebviewController): boolean {
    return this.renderExitCallback(tabId, controller);
  }

  onWindowNew(tabId: TabId, controller: webview.WebviewController): boolean {
    return this.windowNewCallback(tabId, controller);
  }

  onFullScreenEnter(tabId: TabId, controller: webview.WebviewController): void {
    this.fullScreenEnterCallback(tabId, controller);
  }

  onFullScreenExit(tabId: TabId, controller: webview.WebviewController): void {
    this.fullScreenExitCallback(tabId, controller);
  }

  onDownloadStart(tabId: TabId, fileName: string): void {
    this.downloadStartCallback(tabId, fileName);
  }

  onDownloadFinish(tabId: TabId, filePath: string): void {
    this.downloadFinishCallback(tabId, filePath);
  }

  onDownloadFailed(tabId: TabId): void {
    this.downloadFailedCallback(tabId);
  }
}

class RepositorySessionPort implements SessionPort {
  private readonly store: TabStore;
  private readonly repository: BrowserRepository;

  constructor(store: TabStore, repository: BrowserRepository) {
    this.store = store;
    this.repository = repository;
  }

  async save(): Promise<void> {
    await this.repository.saveSession(this.store.snapshot());
  }
}

class ShellLifecyclePort implements BrowserLifecyclePort {
  private readonly foregroundCallback: () => void;
  private readonly backgroundCallback: () => Promise<void>;
  private readonly memoryCallback: (level: number) => void;
  private readonly backCallback: () => boolean;
  private readonly externalUrlCallback: (url: string) => void;

  constructor(
    foregroundCallback: () => void,
    backgroundCallback: () => Promise<void>,
    memoryCallback: (level: number) => void,
    backCallback: () => boolean,
    externalUrlCallback: (url: string) => void
  ) {
    this.foregroundCallback = foregroundCallback;
    this.backgroundCallback = backgroundCallback;
    this.memoryCallback = memoryCallback;
    this.backCallback = backCallback;
    this.externalUrlCallback = externalUrlCallback;
  }

  onForeground(): void {
    this.foregroundCallback();
  }

  async onBackground(): Promise<void> {
    await this.backgroundCallback();
  }

  onMemoryPressure(level: number): void {
    this.memoryCallback(level);
  }

  onBackPress(): boolean {
    return this.backCallback();
  }

  onExternalUrl(url: string): void {
    this.externalUrlCallback(url);
  }
}

@ComponentV2
export struct BrowserShell {
  @Local overviewProgress: number = 0;
  // Search-field reveal is part of the same vertical geometry as the live
  // page's overview card. Keeping it in the shell prevents the WebView frame
  // from retaining the hidden-search target while the grid moves down.
  @Local overviewSearchProgress: number = 0;
  // During card selection the live page must paint above the overview shell so
  // its blue outline and reverse expansion cannot be covered by the cards.
  @Local overviewClosing: boolean = false;
  // Keeps the live page above the card shell during reverse expansion.
  @Local overviewAnimationClosing: boolean = false;
  // Visual selection is held separately from TabStore while a card expands
  // back to full screen. This keeps the selected card's page/address scene
  // stable until the reverse spring has completed.
  @Local overviewVisualTabId: TabId = '';
  private overviewAnimationToken: number = 0;
  private overviewReleaseAnimator: AnimatorResult | undefined = undefined;
  // Programmatic tab-count entry uses ArkUI's native scale transition. An
  // upward bar swipe keeps this false so the mounted overview follows the
  // finger through overviewProgress instead of starting a second animation.
  @Local overviewEntryAnimation: boolean = false;
  // Render-only tab gesture state. The committed tab index remains in
  // TabStore until a spring transition finishes.
  @Local rawDragX: number = 0;
  @Local pageTranslateX: number = 0;
  @Local adjacentTranslateX: number = 0;
  @Local transitionProgress: number = 0;
  @Local newTabProgress: number = 0;
  // Native capsule handoff used only after the edge-created tab is published.
  // 0 keeps the plus visible; 1 leaves the normal native placeholder visible.
  @Local addressHandoffActive: boolean = false;
  @Local addressHandoffProgress: number = 1;
  private addressHandoffAnimator: AnimatorResult | undefined = undefined;
  @Local previewIndex: number = -1;
  @Local previewKind: TabPreviewKind = TabPreviewKind.NONE;
  @Local gestureState: TabGestureState = TabGestureState.IDLE;
  @Local touchOwner: TouchOwner = TouchOwner.NONE;
  @Local touchButtonId: string = '';
  @Local touchHitTestMode: string = 'Block';
  @Local isDragging: boolean = false;
  @Local gestureActive: boolean = false;
  // Bottom chrome is one Root-stack TabBar.  The editor expands inside that
  // same surface; these two values are the only source of truth for its
  // expansion animation and input interaction mode.
  @Local barMode: string = 'collapsed';
  @Local inputExpandProgress: number = 0;
  @Local addressEditing: boolean = false;
  // Keep an unsubmitted address/search draft alive while the toolbar is
  // temporarily unmounted by the overview or a library sheet.
  @Local addressDraft: string = '';
  @Local addressDraftTabId: TabId = '';
  @Local addressInputFocused: boolean = false;
  @Local addressInputMounted: boolean = true;
  @Local addressInputFocusEnabled: boolean = true;
  // Incremented when the in-place address editor requests focus. The editor
  // observes this token and mounts/focuses the real TextInput on the next UI
  // turn.
  @Local addressFocusRequestToken: number = 0;
  @Local cardRevision: number = 0;
  // Explicitly invalidates the retained transition scene after a tab is
  // activated or created. This prevents the overview's active card and the
  // underlying page node from diverging after the overview closes.
  @Local tabStateRevision: number = 0;
  @Local sceneActiveTabId: TabId = '';
  @Local sceneTabs: BrowserTabRecord[] = [];
  @Local sceneActiveTab: BrowserTabRecord | undefined = undefined;
  @Local pendingTabDraft: PendingTabDraft | undefined = undefined;
  @Local errorState: BrowserErrorState | undefined = undefined;
  // Keep Previewer defaults runtime-independent; initialize persisted values
  // later in aboutToAppear().
  @Local browserSettings: BrowserSettings = {
    searchEngine: BrowserSearchEngine.BING,
    autoCloseTabs: AutoCloseTabsPolicy.NEVER,
    contentBlockingEnabled: false,
    showFavorites: false,
    showFrequentSites: false,
    startPageSectionsConfigured: false,
    startPageBackgroundId: 'system-gradient',
    startPageAppearance: StartPageAppearance.FOLLOW_SYSTEM,
    defaultFontSize: 'standard'
  };
  @Local startPageItems: StartPageItem[] = [];
  @Local historyItems: HistoryRecord[] = [];
  @Local bookmarkItems: BookmarkRecord[] = [];
  @Local pageDisplayState: PageDisplayState = {
    fontSize: PageFontSize.STANDARD,
    readerMode: false,
    translated: false,
    fullScreen: false
  };
  @Local pageReady: boolean = false;
  @Local showLibrary: boolean = false;
  @Local showStartPageCustomize: boolean = false;
  @Local downloadTasks: DownloadTaskRecord[] = [];
  @Local showDownloadManager: boolean = false;
  @Local startPageCustomizeDismissProgress: number = 0;
  private startPageCustomizeDismissRequested: boolean = false;
  @Local pageSnapshot: image.PixelMap | undefined = undefined;
  @Local canNavigateBack: boolean = false;
  @Local canNavigateForward: boolean = false;
  @Local navigationStateRevision: number = 0;
  // The window is laid out edge-to-edge. Keep the immersive background, but
  // expose one unified top avoid inset for web content and top overlays. The
  // value includes the larger of TYPE_SYSTEM and TYPE_CUTOUT and is applied
  // once by BrowserTransitionScene.
  @Local topAvoidInset: number = 0;
  // Bottom gesture-navigation indicator height used by bottom sheets and
  // footer controls. The background can extend into this area; actions may
  // not be placed beneath it.
  @Local bottomAvoidInset: number = 0;

  private readonly tabStore: TabStore = new TabStore();
  // The fixed TabBar owns the only app-level horizontal gesture stream and
  // forwards it to this shared transition engine. Browser content remains a
  // native ArkWeb surface and never starts tab transitions itself.
  private readonly addressGestureEngine: GestureDecisionEngine = new GestureDecisionEngine();
  private readonly viewportFallbackWidth: number = 400;
  private readonly viewportFallbackHeight: number = 800;
  @Local viewportWidth: number = 400;
  @Local viewportHeight: number = 800;
  private measuredHostViewportWidth: number = this.viewportFallbackWidth;
  private addressGestureFinished: boolean = false;
  // Keep close/reorder gesture geometry aligned with the rendered tab card.
  private readonly cardHeight: number = TAB_OVERVIEW_GESTURE_CARD_HEIGHT;
  private readonly cardEngines: Map<TabId, GestureDecisionEngine> = new Map();
  private readonly cardProgress: Map<TabId, number> = new Map();
  private readonly cardOffsets: Map<TabId, number> = new Map();
  private readonly cardHorizontalOffsets: Map<TabId, number> = new Map();
  private readonly cardFinished: Set<TabId> = new Set();
  private readonly closingCards: Set<TabId> = new Set();
  private readonly reorderingCards: Set<TabId> = new Set();
  private readonly hapticTriggered: Set<TabId> = new Set();
  // Keep each BuilderNode host attached for its lifetime. Detaching and
  // recreating NodeContainers on every tab switch can leave the newly-active
  // ArkWeb frame empty, especially when it was created under the overview.
  private readonly hostControllers: Map<TabId, WebNodeHostController> = new Map();
  private readonly closedTabStack: ClosedTabStack = new ClosedTabStack(20);
  private readonly snapshotCache: TabSnapshotCache =
    new TabSnapshotCache(new MemorySnapshotStorage(), 64 * 1024 * 1024);
  private readonly thumbnails: Map<TabId, image.PixelMap> = new Map();
  // A blank tab has no ArkWeb document to snapshot. Reuse the real rendered
  // native start-page surface for every blank card instead of drawing a
  // placeholder glyph.
  private startPageThumbnail: image.PixelMap | undefined = undefined;
  private readonly snapshotGenerations: Map<TabId, number> = new Map();
  private readonly snapshotInFlight: Set<TabId> = new Set();
  // Page/UI state belongs to a stable tab id, not to the currently rendered
  // array slot.  This keeps an overview round-trip from resetting the page
  // controls when another card is selected.
  private readonly pageDisplayStates: Map<TabId, PageDisplayState> = new Map();
  private readonly desktopModeByTab: Map<TabId, boolean> = new Map();
  private readonly mobileUserAgentByTab: Map<TabId, string> = new Map();
  // Keep the semantic search label while a search provider performs an
  // intermediate redirect (for example Bing's login handoff). The compact
  // address bar must not fall back to that redirect URL or a generic page
  // title such as "网页".
  private readonly searchLabelsByTab: Map<TabId, string> = new Map();
  // The editor presentation is source-driven: a search result restores the
  // submitted query, while a direct/external URL restores the real URL.
  private readonly addressPresentationByTab: Map<TabId, AddressBarPresentationMode> = new Map();
  private readonly searchQueriesByTab: Map<TabId, string> = new Map();
  // Keep the source selected by the user across provider redirects. A search
  // stays in search presentation until the user submits a new address.
  private readonly pendingSearchNavigationByTab: Set<TabId> = new Set();
  private readonly searchResultSettledAtByTab: Map<TabId, number> = new Map();
  private readonly desktopAppliedControllerIds: Set<string> = new Set();
  private readonly pageReadyByTab: Map<TabId, boolean> = new Map();
  private readonly canNavigateBackByTab: Map<TabId, boolean> = new Map();
  private readonly canNavigateForwardByTab: Map<TabId, boolean> = new Map();
  private readonly errorStatesByTab: Map<TabId, BrowserErrorState | undefined> = new Map();
  private repository: BrowserRepository | undefined = undefined;
  private downloadService: DownloadService | undefined = undefined;
  private downloadLifecycle: BrowserDownloadLifecycle | undefined = undefined;
  private lifecyclePort: BrowserLifecyclePort | undefined = undefined;
  private webTabPool: WebTabPool | undefined = undefined;
  private runtimePort: ArkWebTabRuntimePort | undefined = undefined;
  private dispatcher: DefaultBrowserCommandDispatcher | undefined = undefined;
  private mainWindow: window.Window | undefined = undefined;
  private avoidAreaListener: ((data: window.AvoidAreaOptions) => void) | undefined = undefined;
  private windowSizeChangeListener: ((size: window.Size) => void) | undefined = undefined;
  private overviewTabRequestToken: number = 0;
  private addressInputRemountToken: number = 0;
  // Invalidates an async adjacent-tab/new-tab animation when the user starts
  // another gesture or cancels the current one before the settle finishes.
  private addressTransitionToken: number = 0;
  // Invalidates an editor open/close animation when a new tap or gesture
  // starts before the previous spring has finished.
  private addressEditorAnimationToken: number = 0;
  private addressHandoffAnimationToken: number = 0;
  // Debug-only gesture diagnostics. Keep the records at info level so the
  // emulator's devecocli log stream can collect the complete transition
  // evidence; the caller only invokes this method for gesture operations.
  private gestureStartIndex: number = 0;
  private gestureStartX: number = 0;
  private gestureStartY: number = 0;
  private startInAddressStrip: boolean = false;
  private addressStripRectX: number = 0;
  private addressStripRectY: number = 0;
  private addressStripRectWidth: number = 0;
  private addressStripRectHeight: number = 0;
  private lastGestureVelocityX: number = 0;
  private lastGestureDy: number = 0;
  aboutToAppear(): void {
    if (ENABLE_GESTURE_LAB) {
      return;
    }
    this.addressInputMounted = true;
    this.addressInputFocusEnabled = true;
    const uiContext: UIContext = this.getUIContext();
    this.observeTopAvoidArea(uiContext);
    const hostContext = uiContext.getHostContext();
    const pageLifecycleObserver: WebPageLifecycleObserver = new BrowserPageLifecycleObserver(
      (tabId: TabId, controller: webview.WebviewController) => {
        this.applyUserAgentMode(tabId, controller, false);
        const currentUrl: string = this.urlForTab(tabId);
        let renderedUrl: string = '';
        try {
          renderedUrl = controller.getUrl();
        } catch (_error) {
          renderedUrl = currentUrl;
        }
        const validation = validateBrowserUrl(renderedUrl);
        const committedUrl: string = committedNavigationUrl(renderedUrl, currentUrl);
        if (!validation.valid && renderedUrl.trim().length > 0) {
          this.logRejectedLifecycleUrl(tabId, renderedUrl, currentUrl, 'onPageEnd');
        }
        this.updateAddressPresentationForNavigation(tabId, committedUrl, 'end');
        const committedTitle: string = this.titleForNavigation(tabId, committedUrl);
        if (committedUrl !== currentUrl &&
          this.tabStore.updateTabUrl(
            tabId,
            committedUrl,
            committedTitle,
            this.addressSourceForTab(tabId),
            this.searchQueriesByTab.get(tabId)
          )) {
          this.cardRevision += 1;
          this.bumpTabStateRevision();
          void this.repository?.saveSession(this.tabStore.snapshot());
        }
        this.logBrowserLifecycle(
          'page_end',
          tabId,
          committedUrl,
          0,
          true,
          '',
          renderedUrl,
          validation.valid ? 'page-end-committed' : 'preserved-last-valid'
        );
        if (tabId === this.tabStore.activeTabId) {
          this.pageReady = true;
          this.refreshNavigationState(controller);
          this.rememberTabViewState(tabId);
        }
        this.scheduleSnapshot(tabId, controller);
        // ArkWeb can settle its back/forward list one frame after page-end.
        // Re-read it after that settle so the nested toolbar does not retain
        // the availability from the previous history entry.
        setTimeout(() => {
          if (tabId === this.tabStore.activeTabId && this.pageReady) {
            this.refreshNavigationState(controller);
          }
        }, 260);
      },
      (tabId: TabId, _controller: webview.WebviewController, diagnostic: WebLoadError) => {
        this.logBrowserLifecycle(
          'network_error',
          tabId,
          this.urlForTab(tabId),
          diagnostic.code,
          diagnostic.isMainFrame,
          diagnostic.info,
          diagnostic.url,
          'preserved-last-valid'
        );
        if (diagnostic.isMainFrame) {
          this.showBrowserError(tabId, BrowserErrorKind.NETWORK, diagnostic.code, diagnostic.url);
        }
      },
      (tabId: TabId, _controller: webview.WebviewController, diagnostic: WebSslError) => {
        this.logBrowserLifecycle(
          `ssl_error${diagnostic.isFatal ? '_fatal' : ''}`,
          tabId,
          this.urlForTab(tabId),
          diagnostic.code,
          diagnostic.isMainFrame,
          '',
          diagnostic.url,
          'preserved-last-valid'
        );
        if (diagnostic.isMainFrame) {
          this.showBrowserError(tabId, BrowserErrorKind.SSL, diagnostic.code, diagnostic.url);
        }
      },
      (tabId: TabId, _controller: webview.WebviewController) => {
        this.logBrowserLifecycle('renderer_exited', tabId, this.urlForTab(tabId), 0, true, '');
        this.showBrowserError(tabId, BrowserErrorKind.RENDERER_EXITED, 0, this.urlForTab(tabId));
        return true;
      },
      (_tabId: TabId, _controller: webview.WebviewController) => false,
      (tabId: TabId, _controller: webview.WebviewController, title: string) => {
        const normalizedTitle: string = title.trim();
        if (normalizedTitle.length === 0) {
          return;
        }
        const tab: BrowserTabRecord | undefined = this.tabStore.tabs.find(
          (item: BrowserTabRecord) => item.id === tabId
        );
        const presentationMode: AddressBarPresentationMode | undefined = tab === undefined
          ? undefined
          : this.addressPresentationByTab.get(tabId);
        const searchLabel: string | undefined = tab === undefined ||
          (presentationMode !== undefined && presentationMode !== AddressBarPresentationMode.SEARCH)
          ? undefined
          : this.searchLabelsByTab.get(tabId) ?? this.searchLabelForUrl(lastValidUrlForTab(tab));
        if (searchLabel !== undefined && this.isGenericSearchPageTitle(normalizedTitle)) {
          if (tab !== undefined && tab.title !== searchLabel &&
            this.tabStore.updateTabTitle(tabId, searchLabel)) {
            this.cardRevision += 1;
            this.bumpTabStateRevision();
            void this.repository?.saveSession(this.tabStore.snapshot());
          }
          return;
        }
        if (searchLabel !== undefined) {
          this.searchLabelsByTab.delete(tabId);
        }
        // ArkWeb reports `about:blank` as the title for the local start page.
        // Preserve the user-facing seeded title so it remains searchable in
        // the tab overview.
        if (tab === undefined ||
          (tab.url === 'about:blank' && normalizedTitle === 'about:blank') ||
          tab.title === normalizedTitle) {
          return;
        }
        if (this.tabStore.updateTabTitle(tabId, normalizedTitle)) {
          this.cardRevision += 1;
          this.bumpTabStateRevision();
          void this.repository?.saveSession(this.tabStore.snapshot());
        }
      },
      (tabId: TabId, _controller: webview.WebviewController) => this.setFullScreen(tabId, true),
      (tabId: TabId, _controller: webview.WebviewController) => this.setFullScreen(tabId, false),
      (tabId: TabId, fileName: string) => {
        void tabId;
        void fileName;
      },
      (tabId: TabId, filePath: string) => {
        void tabId;
        void filePath;
      },
      (tabId: TabId) => {
        void tabId;
      },
      (tabId: TabId, controller: webview.WebviewController, reportedUrl: string) => {
        const currentUrl: string = this.urlForTab(tabId);
        const validation = validateBrowserUrl(reportedUrl);
        const nextUrl: string = committedNavigationUrl(reportedUrl, currentUrl);
        const tab: BrowserTabRecord | undefined = this.tabStore.tabs.find(
          (item: BrowserTabRecord) => item.id === tabId
        );
        if (!validation.valid && reportedUrl.trim().length > 0) {
          this.logRejectedLifecycleUrl(tabId, reportedUrl, currentUrl, 'onPageBegin');
        }
        const currentCommittedUrl: string = tab === undefined ? currentUrl : lastValidUrlForTab(tab);
        this.logBrowserLifecycle(
          'page_begin',
          tabId,
          nextUrl,
          0,
          true,
          `reported=${reportedUrl} current=${currentCommittedUrl}`,
          reportedUrl,
          nextUrl === currentCommittedUrl ? 'page-begin-preserved' : 'page-begin-commit'
        );
        if (tab === undefined || nextUrl === currentCommittedUrl) {
          if (tabId === this.tabStore.activeTabId) {
            this.refreshNavigationState(controller);
          }
          return;
        }
        this.updateAddressPresentationForNavigation(tabId, nextUrl, 'begin');
        const nextTitle: string = this.titleForNavigation(tabId, nextUrl);
        if (this.tabStore.updateTabUrl(
          tabId,
          nextUrl,
          nextTitle,
          this.addressSourceForTab(tabId),
          this.searchQueriesByTab.get(tabId)
        )) {
          this.cardRevision += 1;
          this.bumpTabStateRevision();
          if (tabId === this.tabStore.activeTabId) {
            this.pageReady = false;
            this.errorState = undefined;
            this.resetAddressDraft();
            this.refreshNavigationState(controller);
            this.rememberTabViewState(tabId);
          }
          void this.repository?.saveSession(this.tabStore.snapshot());
        }
      }
    );
    const keyValueStore: KeyValueStore = hostContext === undefined
      ? new MemoryKeyValueStore()
      : new PreferencesKeyValueStore(hostContext);
    this.repository = new BrowserRepository(keyValueStore);
    if (hostContext !== undefined) {
      const existingDownloadService: DownloadService | undefined = sharedDownloadService;
      const downloadService: DownloadService = existingDownloadService === undefined ||
        sharedDownloadFilesDir !== hostContext.filesDir
        ? new DownloadService(
          new DownloadStore(new KeyValueDownloadRecordStorage(keyValueStore)),
          new RequestAgentGateway(hostContext),
          new DownloadNotificationGateway(hostContext),
          new ArkWebCookiePort(),
          hostContext.filesDir
        )
        : existingDownloadService;
      if (downloadService !== existingDownloadService) {
        sharedDownloadService = downloadService;
        sharedDownloadFilesDir = hostContext.filesDir;
      }
      this.downloadService = downloadService;
      this.downloadLifecycle = new BrowserDownloadLifecycle(
        new DownloadServiceLifecyclePort(downloadService),
        (tasks: DownloadTaskRecord[]): void => {
          this.downloadTasks = tasks.slice();
        },
        (visible: boolean): void => {
          this.showDownloadManager = visible;
        }
      );
      void this.downloadLifecycle.start();
    } else {
      this.downloadService = undefined;
      this.downloadLifecycle = undefined;
      this.downloadTasks = [];
      this.showDownloadManager = false;
    }
    this.webTabPool = new WebTabPool(new ArkWebRuntimeFactory(
      uiContext,
      pageLifecycleObserver,
      this.downloadService,
      (tabId: TabId, url: string, runtimeId: string) =>
        this.logLoadUrl(
          url,
          'tab-runtime-create-saved-url',
          'ArkWebRuntimeFactory.create',
          false,
          tabId,
          runtimeId,
          '',
          'web-src-runtime-created'
        )
    ));
    this.runtimePort = new ArkWebTabRuntimePort(this.tabStore, this.webTabPool);
    this.dispatcher = new DefaultBrowserCommandDispatcher(
      this.tabStore,
      this.runtimePort,
      new NoopSnapshotPort(),
      new RepositorySessionPort(this.tabStore, this.repository)
    );
    this.lifecyclePort = new ShellLifecyclePort(
      () => this.handleForeground(),
      () => this.handleBackground(),
      (level: number) => this.handleMemoryPressure(level),
      () => this.onSystemBackPress(),
      (url: string) => this.openExternalUrl(url)
    );
    BrowserLifecycleRegistry.register(this.lifecyclePort);
    void this.initializeSession();
  }

  aboutToDisappear(): void {
    this.overviewAnimationToken += 1;
    this.cancelOverviewReleaseAnimation();
    this.addressHandoffAnimationToken += 1;
    this.addressHandoffAnimator?.finish();
    this.addressHandoffAnimator = undefined;
    if (this.mainWindow !== undefined && this.avoidAreaListener !== undefined) {
      this.mainWindow.off('avoidAreaChange', this.avoidAreaListener);
    }
    if (this.mainWindow !== undefined && this.windowSizeChangeListener !== undefined) {
      this.mainWindow.off('windowSizeChange', this.windowSizeChangeListener);
    }
    this.avoidAreaListener = undefined;
    this.windowSizeChangeListener = undefined;
    this.mainWindow = undefined;
    this.downloadLifecycle?.stop();
    this.downloadLifecycle = undefined;
    if (this.lifecyclePort !== undefined) {
      BrowserLifecycleRegistry.clear(this.lifecyclePort);
      this.lifecyclePort = undefined;
    }
    this.webTabPool?.releaseAll();
    this.cardHorizontalOffsets.clear();
  }

  /**
   * Read all window avoid areas in px, convert once to vp, and keep the
   * immersive background separate from the page content layer.  Re-reading
   * all three areas on every event avoids stale TYPE_CUTOUT data during
   * rotation or a full-screen/window-size transition.
   */
  private observeTopAvoidArea(uiContext: UIContext): void {
    const hostContext = uiContext.getHostContext();
    if (hostContext === undefined) {
      return;
    }
    window.getLastWindow(hostContext, (error, mainWindow) => {
      if (error.code !== 0) {
        return;
      }
      this.mainWindow = mainWindow;
      const updateAvoidInsets = (reason: string): void => {
        let systemTopPx: number = 0;
        let systemHeightPx: number = 0;
        let cutoutTopPx: number = 0;
        let cutoutHeightPx: number = 0;
        try {
          const systemArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
          systemTopPx = systemArea.topRect.top;
          systemHeightPx = systemArea.topRect.height;
        } catch (_error) {
          systemTopPx = 0;
          systemHeightPx = 0;
        }
        try {
          const cutoutArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
          cutoutTopPx = cutoutArea.topRect.top;
          cutoutHeightPx = cutoutArea.topRect.height;
        } catch (_error) {
          cutoutTopPx = 0;
          cutoutHeightPx = 0;
        }
        const topInsetPx: number = topContentInsetFromAvoidRects(
          systemTopPx,
          systemHeightPx,
          cutoutTopPx,
          cutoutHeightPx
        );
        try {
          this.topAvoidInset = Math.max(0, uiContext.px2vp(topInsetPx));
        } catch (_error) {
          this.topAvoidInset = 0;
        }
        let navigationHeightPx: number = 0;
        try {
          const navigationArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
          navigationHeightPx = navigationArea.bottomRect.height;
        } catch (_error) {
          navigationHeightPx = 0;
        }
        try {
          this.bottomAvoidInset = Math.max(0, uiContext.px2vp(navigationHeightPx));
        } catch (_error) {
          this.bottomAvoidInset = 0;
        }
        hilog.info(BROWSER_WEB_DOMAIN, BROWSER_WEB_TAG,
          'windowAvoidance reason=%{public}s systemTopPx=%{public}d systemHeightPx=%{public}d ' +
          'cutoutTopPx=%{public}d cutoutHeightPx=%{public}d topInsetPx=%{public}d ' +
          'topInsetVp=%{public}s navigationHeightPx=%{public}d bottomInsetVp=%{public}s',
          reason,
          systemTopPx,
          systemHeightPx,
          cutoutTopPx,
          cutoutHeightPx,
          topInsetPx,
          String(this.topAvoidInset),
          navigationHeightPx,
          String(this.bottomAvoidInset));
      };
      updateAvoidInsets('initial-window-ready');
      this.avoidAreaListener = (data: window.AvoidAreaOptions): void => {
        updateAvoidInsets(`avoidAreaChange-${String(data.type)}`);
      };
      mainWindow.on('avoidAreaChange', this.avoidAreaListener);
      this.windowSizeChangeListener = (_size: window.Size): void => {
        updateAvoidInsets('windowSizeChange');
      };
      mainWindow.on('windowSizeChange', this.windowSizeChangeListener);
    });
  }

  private activeTab(): BrowserTabRecord | undefined {
    return this.tabStore.tabs.find((tab: BrowserTabRecord) => tab.id === this.tabStore.activeTabId);
  }

  private pageActionsReady(): boolean {
    const tab: BrowserTabRecord | undefined = this.activeTab();
    if (tab === undefined || lastValidUrlForTab(tab) === 'about:blank') {
      return false;
    }
    return this.pageReady || this.runtimePort?.controllerFor(tab.id) !== undefined;
  }

  private downloadProgressForTab(tabId: TabId): DownloadProgressSnapshot | undefined {
    return selectDownloadProgressForTab(this.downloadTasks, tabId);
  }

  private openDownloadManager(): void {
    this.showLibrary = false;
    if (this.showStartPageCustomize) {
      this.closeStartPageCustomize();
    }
    if (this.addressEditing) {
      this.closeAddressEditor();
    }
    if (this.downloadLifecycle === undefined) {
      this.showDownloadManager = true;
      return;
    }
    this.downloadLifecycle.openDownloadManager(this.pageActionsReady());
  }

  private closeDownloadManager(): void {
    if (this.downloadLifecycle === undefined) {
      this.showDownloadManager = false;
      return;
    }
    this.downloadLifecycle.closeDownloadManager();
  }

  private pauseDownload(id: string): void {
    void this.downloadLifecycle?.pause(id);
  }

  private resumeDownload(id: string): void {
    void this.downloadLifecycle?.resume(id);
  }

  private cancelDownload(id: string): void {
    void this.downloadLifecycle?.cancel(id);
  }

  private retryDownload(id: string): void {
    void this.downloadLifecycle?.retry(id);
  }

  private activeAddress(): string {
    const tab: BrowserTabRecord | undefined = this.activeTab();
    return tab === undefined ? 'about:blank' : lastValidUrlForTab(tab);
  }

  private activeTabIndex(): number {
    return this.tabStore.tabs.findIndex((tab: BrowserTabRecord) => tab.id === this.tabStore.activeTabId);
  }

  private searchLabelForUrl(url: string): string | undefined {
    const label: string = tabOverviewTitleFor(url, '');
    return label === '起始页' ? undefined : label;
  }

  private addressPresentationForTab(tabId: TabId, url: string): AddressBarPresentationMode {
    const stored: AddressBarPresentationMode | undefined = this.addressPresentationByTab.get(tabId);
    if (stored !== undefined) {
      return stored;
    }
    const tab: BrowserTabRecord | undefined = this.tabStore.tabs.find(
      (item: BrowserTabRecord) => item.id === tabId
    );
    const inferred: AddressBarPresentationMode = tab?.addressSource === 'search'
      ? AddressBarPresentationMode.SEARCH
      : tab?.addressSource === 'url'
        ? AddressBarPresentationMode.URL
        : this.searchLabelForUrl(url) === undefined
          ? AddressBarPresentationMode.URL
          : AddressBarPresentationMode.SEARCH;
    this.addressPresentationByTab.set(tabId, inferred);
    if (inferred === AddressBarPresentationMode.SEARCH) {
      const query: string | undefined = tab?.addressQuery ?? searchQueryForUrl(url);
      if (query !== undefined) {
        this.searchQueriesByTab.set(tabId, query);
      }
      if (searchQueryForUrl(url) === undefined) {
        this.pendingSearchNavigationByTab.add(tabId);
      }
    }
    return inferred;
  }

  /** Keep the source selected by the user until a new address is submitted. */
  private updateAddressPresentationForNavigation(
    tabId: TabId,
    url: string,
    phase: 'begin' | 'end'
  ): void {
    const current: AddressBarPresentationMode | undefined =
      this.addressPresentationByTab.get(tabId);
    if (current === undefined) {
      this.addressPresentationForTab(tabId, url);
      return;
    }
    if (current !== AddressBarPresentationMode.SEARCH) {
      return;
    }
    if (this.searchLabelForUrl(url) !== undefined) {
      if (phase === 'end') {
        this.searchResultSettledAtByTab.set(tabId, Date.now());
      }
      return;
    }
    // Search-provider redirects and result-page sub-navigations can briefly
    // expose an OAuth or tracking URL. They must not replace the query the
    // user entered. A direct URL submission is the only source transition;
    // loadAddress() updates this mode before ArkWeb lifecycle callbacks run.
    return;
  }

  private addressSourceForTab(tabId: TabId): AddressBarSource {
    return this.addressPresentationByTab.get(tabId) === AddressBarPresentationMode.SEARCH
      ? 'search'
      : 'url';
  }

  private titleForNavigation(tabId: TabId, url: string): string {
    const mode: AddressBarPresentationMode = this.addressPresentationForTab(tabId, url);
    if (mode === AddressBarPresentationMode.SEARCH) {
      const searchLabel: string | undefined = this.searchLabelForUrl(url);
      if (searchLabel !== undefined) {
        this.searchLabelsByTab.set(tabId, searchLabel);
        return searchLabel;
      }
      return this.searchLabelsByTab.get(tabId) ?? '';
    }
    this.searchLabelsByTab.delete(tabId);
    return '';
  }

  private isGenericSearchPageTitle(title: string): boolean {
    return title === '网页' || title === '搜索' || title === '必应' ||
      title === 'Bing' || title === 'Microsoft Bing';
  }

  /**
   * The tab store is the committed model, while the transition scene is the
   * published visual model. Keep the bottom chrome on the latter until the
   * outgoing page has finished settling; otherwise activateTab() can update
   * the address capsule one render turn before the visible ArkWeb page.
   */
  private sceneTabForRender(): BrowserTabRecord | undefined {
    const published: BrowserTabRecord | undefined = this.sceneTabs.find(
      (tab: BrowserTabRecord) => tab.id === this.sceneActiveTabId
    );
    return published ?? this.activeTab();
  }

  private sceneAddress(): string {
    const tab: BrowserTabRecord | undefined = this.sceneTabForRender();
    return tab === undefined ? 'about:blank' : lastValidUrlForTab(tab);
  }

  /**
   * Search presentation is sticky across provider redirects. Keep the
   * original query as a separate chrome value instead of deriving it from
   * the current ArkWeb URL, which may already be an OAuth or tracking URL.
   */
  private sceneSearchQuery(): string {
    const tab: BrowserTabRecord | undefined = this.sceneTabForRender();
    if (tab === undefined) {
      return '';
    }
    const url: string = lastValidUrlForTab(tab);
    if (this.addressPresentationForTab(tab.id, url) !== AddressBarPresentationMode.SEARCH) {
      return '';
    }
    return searchQueryTextFor(
      this.searchQueriesByTab.get(tab.id) ??
      tab.addressQuery ??
      searchQueryForUrl(url) ??
      ''
    );
  }

  private previewTab(): BrowserTabRecord | undefined {
    if (this.previewIndex < 0 || this.previewIndex >= this.tabStore.tabs.length) {
      return undefined;
    }
    return this.tabStore.tabs[this.previewIndex];
  }

  private previewHost(): WebNodeHostController | undefined {
    const tab: BrowserTabRecord | undefined = this.previewTab();
    return tab === undefined ? undefined : this.hostControllers.get(tab.id);
  }

  private previewThumbnail(): image.PixelMap | undefined {
    const tab: BrowserTabRecord | undefined = this.previewTab();
    return tab === undefined ? undefined : this.thumbnailFor(tab.id);
  }

  private sceneActiveTabIndex(): number {
    const publishedIndex: number = this.sceneTabs.findIndex(
      (tab: BrowserTabRecord) => tab.id === this.sceneActiveTabId
    );
    return publishedIndex >= 0 ? publishedIndex : this.activeTabIndex();
  }

  private reattachTabControllerIfMissing(tabId: TabId, caller: string): boolean {
    const savedUrl: string = this.urlForTab(tabId);
    const controllerAvailable: boolean = this.runtimePort?.controllerFor(tabId) !== undefined;
    if (!shouldRecoverMissingTabController(controllerAvailable, savedUrl)) {
      return false;
    }
    return this.reattachTabController(tabId, caller);
  }

  private draftForSceneTab(): string {
    return this.addressDraftTabId === this.sceneActiveTabId ? this.addressDraft : '';
  }

  private sceneInputIdentity(): string {
    const publishedId: TabId = this.sceneActiveTabId.length > 0
      ? this.sceneActiveTabId
      : this.tabStore.activeTabId;
    return addressInputIdentity(publishedId, this.addressInputRemountToken);
  }

  private addressItemStride(): number {
    // AddressTabStrip reports the exact rendered strip width. Keep address
    // item spacing in that coordinate space; page movement still uses the
    // Web viewport width below in the gesture engine.
    const addressWidth: number = this.addressStripRectWidth > 0
      ? this.addressStripRectWidth
      : this.viewportWidth;
    return safariAddressItemWidth(addressWidth) +
      SAFARI_ADDRESS_ITEM_GAP_VP;
  }

  private bumpTabStateRevision(): void {
    this.sceneActiveTabId = this.tabStore.activeTabId;
    this.sceneTabs = this.tabStore.tabs.slice();
    this.sceneActiveTab = this.tabStore.tabs.find(
      (tab: BrowserTabRecord) => tab.id === this.tabStore.activeTabId
    );
    this.tabStateRevision += 1;
  }

  private pendingTabForRender(): PendingTabDraft | undefined {
    if (!shouldRenderPendingTabPreview(this.previewKind, this.newTabProgress)) {
      return undefined;
    }
    return this.pendingTabDraft;
  }

  private initializeTabViewState(tabId: TabId): void {
    if (!this.pageDisplayStates.has(tabId)) {
      this.pageDisplayStates.set(tabId, copyPageDisplayState(DEFAULT_PAGE_DISPLAY_STATE));
    }
    if (!this.pageReadyByTab.has(tabId)) {
      this.pageReadyByTab.set(tabId, false);
    }
    if (!this.canNavigateBackByTab.has(tabId)) {
      this.canNavigateBackByTab.set(tabId, false);
    }
    if (!this.canNavigateForwardByTab.has(tabId)) {
      this.canNavigateForwardByTab.set(tabId, false);
    }
    if (!this.errorStatesByTab.has(tabId)) {
      this.errorStatesByTab.set(tabId, undefined);
    }
  }

  private rememberTabViewState(tabId: TabId = this.tabStore.activeTabId): void {
    if (tabId.length === 0) {
      return;
    }
    this.pageDisplayStates.set(tabId, copyPageDisplayState(this.pageDisplayState));
    this.pageReadyByTab.set(tabId, this.pageReady);
    this.canNavigateBackByTab.set(tabId, this.canNavigateBack);
    this.canNavigateForwardByTab.set(tabId, this.canNavigateForward);
    const error: BrowserErrorState | undefined = this.errorState;
    this.errorStatesByTab.set(tabId, error === undefined ? undefined : {
      kind: error.kind,
      code: error.code,
      host: error.host,
      message: error.message
    });
  }

  private restoreTabViewState(tabId: TabId): void {
    this.initializeTabViewState(tabId);
    this.pageDisplayState = copyPageDisplayState(
      this.pageDisplayStates.get(tabId) ?? DEFAULT_PAGE_DISPLAY_STATE
    );
    this.pageReady = this.pageReadyByTab.get(tabId) ?? false;
    this.canNavigateBack = this.canNavigateBackByTab.get(tabId) ?? false;
    this.canNavigateForward = this.canNavigateForwardByTab.get(tabId) ?? false;
    const error: BrowserErrorState | undefined = this.errorStatesByTab.get(tabId);
    this.errorState = error === undefined ? undefined : {
      kind: error.kind,
      code: error.code,
      host: error.host,
      message: error.message
    };
  }

  private resetTabViewState(tabId: TabId): void {
    this.pageDisplayStates.set(tabId, copyPageDisplayState(DEFAULT_PAGE_DISPLAY_STATE));
    this.pageReadyByTab.set(tabId, false);
    this.canNavigateBackByTab.set(tabId, false);
    this.canNavigateForwardByTab.set(tabId, false);
    this.errorStatesByTab.set(tabId, undefined);
    this.restoreTabViewState(tabId);
  }

  private removeTabViewState(tabId: TabId): void {
    this.pageDisplayStates.delete(tabId);
    this.pageReadyByTab.delete(tabId);
    this.canNavigateBackByTab.delete(tabId);
    this.canNavigateForwardByTab.delete(tabId);
    this.errorStatesByTab.delete(tabId);
    this.addressPresentationByTab.delete(tabId);
    this.searchLabelsByTab.delete(tabId);
    this.searchQueriesByTab.delete(tabId);
    this.pendingSearchNavigationByTab.delete(tabId);
    this.searchResultSettledAtByTab.delete(tabId);
  }

  private applyTabGestureMotion(state: TabGestureMotionState): void {
    this.rawDragX = state.rawDragX;
    this.pageTranslateX = state.pageTranslateX;
    this.adjacentTranslateX = state.adjacentTranslateX;
    this.transitionProgress = state.transitionProgress;
    this.newTabProgress = state.newTabProgress;
    this.previewIndex = state.previewIndex;
    this.previewKind = state.previewKind;
    this.isDragging = state.isDragging;
  }

  private resetTabGestureMotion(dragging: boolean = false): void {
    const state: TabGestureMotionState = emptyTabGestureMotion();
    state.isDragging = dragging;
    this.applyTabGestureMotion(state);
    if (!dragging) {
      this.gestureState = TabGestureState.IDLE;
    }
  }

  private draftForActiveTab(): string {
    return this.addressDraftTabId === this.tabStore.activeTabId ? this.addressDraft : '';
  }

  private updateAddressDraft(value: string): void {
    this.addressDraftTabId = this.tabStore.activeTabId;
    this.addressDraft = value;
  }

  private updateAddressInputFocus(focused: boolean): void {
    this.addressInputFocused = focused;
  }

  /** Start the in-place editor in the address slot of the floating TabBar. */
  private openAddressEditor(): void {
    if (this.overviewProgress !== 0 || this.showLibrary || this.showStartPageCustomize ||
      this.showDownloadManager ||
      this.pageDisplayState.fullScreen || this.gestureActive ||
      this.addressHandoffProgress < 1) {
      return;
    }
    const animationToken: number = this.addressEditorAnimationToken + 1;
    this.addressEditorAnimationToken = animationToken;
    const activeTabId: TabId = this.tabStore.activeTabId;
    const activeAddress: string = this.activeAddress();
    const presentationMode: AddressBarPresentationMode = this.addressPresentationForTab(
      activeTabId,
      activeAddress
    );
    const searchQuery: string = this.searchQueriesByTab.get(activeTabId) ??
      searchQueryForUrl(activeAddress) ?? '';
    this.addressDraftTabId = activeTabId;
    this.addressDraft = addressEditorDraftFor(activeAddress, presentationMode, searchQuery);
    // Opening can reuse a collapsed TextInput node after a provider redirect.
    // Give the editor a fresh identity so its native buffer starts from the
    // source-aware draft instead of the last committed URL.
    this.addressInputRemountToken += 1;
    this.addressInputMounted = true;
    this.addressInputFocusEnabled = true;
    this.addressInputFocused = true;
    this.addressEditing = true;
    this.addressFocusRequestToken += 1;
    this.barMode = 'expanding';
    this.getUIContext().animateTo({
      curve: curves.springMotion(),
      onFinish: () => {
        if (animationToken === this.addressEditorAnimationToken) {
          this.inputExpandProgress = 1;
          this.barMode = 'expanded';
        }
      }
    }, () => {
      if (animationToken === this.addressEditorAnimationToken) {
        this.inputExpandProgress = 1;
      }
    });
    // The editor is mounted by the same TabBar render pass. Request focus on
    // the next frame so ArkUI presents the platform IME without navigating to
    // or layering a separate address page.
    setTimeout(() => {
      if (animationToken !== this.addressEditorAnimationToken || this.barMode === 'collapsed' ||
        !this.addressInputMounted) {
        return;
      }
      try {
        this.getUIContext().getFocusController().requestFocus(
          addressInputIdentity(this.tabStore.activeTabId, this.addressInputRemountToken)
        );
      } catch (_error) {
        // The node may still be entering the expanding transition; the
        // component-level focus monitor retries for the request token.
      }
    }, 120);
    hilog.info(BROWSER_WEB_DOMAIN, BROWSER_WEB_TAG,
      'address-editor open progress=%{public}f token=%{public}d',
      this.inputExpandProgress, this.addressFocusRequestToken);
  }

  /** Collapse the editor back into the exact address/search slot. */
  private closeAddressEditor(): void {
    if (this.addressEditing && this.barMode === 'collapsing') {
      return;
    }
    const closedState = closedAddressEditorState();
    const animationToken: number = this.addressEditorAnimationToken + 1;
    this.addressEditorAnimationToken = animationToken;
    this.addressDraftTabId = this.tabStore.activeTabId;
    this.addressInputFocused = closedState.addressInputFocused;
    this.addressInputFocusEnabled = false;
    this.clearAddressFocus();
    this.barMode = 'collapsing';
    // Keep the submitted editor mounted while the capsule hands its text back
    // to the collapsed label. The shared progress drives an actual crossfade;
    // unmounting here would make a URL disappear before the search term lands.
    this.inputExpandProgress = Math.max(0, Math.min(1, this.inputExpandProgress));
    this.getUIContext().animateTo({
      curve: curves.springMotion(),
      onFinish: () => {
        if (animationToken === this.addressEditorAnimationToken) {
          this.inputExpandProgress = closedState.inputExpandProgress;
          this.addressEditing = closedState.addressEditing;
          this.resetAddressDraft();
          this.barMode = closedState.barMode;
          this.addressInputFocusEnabled = closedState.addressInputFocusEnabled;
        }
      }
    }, () => {
      if (animationToken === this.addressEditorAnimationToken) {
        this.inputExpandProgress = closedState.inputExpandProgress;
      }
    });
  }

  private submitAddressEditor(value: string): void {
    const next: string = value.trim();
    if (next.length === 0) {
      this.closeAddressEditor();
      return;
    }
    // Reuse the existing URL/search normalisation and controller path. It
    // keeps the active WebView alive and only changes its loaded document.
    this.loadAddress(next, 'address-submit', 'submitAddressEditor');
    this.closeAddressEditor();
  }

  /**
   * End the native editor session when navigation changes the active tab.
   * ArkUI can keep a TextInput's focus in the IME window for one frame after
   * its node is removed; clearing both focus owners prevents a new blank tab
   * from opening with the keyboard already covering the browser chrome.
   */
  private clearAddressFocus(): void {
    try {
      this.getUIContext().getFocusController().clearFocus();
      void inputMethod.getController().hideSoftKeyboard().catch(() => undefined);
    } catch (_error) {
      // The input node may be between mount and unmount. The remount token
      // below still guarantees a fresh editor on the next UI turn.
    }
  }

  private resetAddressDraft(): void {
    this.addressDraftTabId = this.tabStore.activeTabId;
    this.addressDraft = '';
    this.addressInputFocused = false;
    this.clearAddressFocus();
    // TextInput keeps its internal editing buffer when only its `text`
    // parameter changes. Recreate the field at the navigation/tab boundary so
    // a newly selected start page cannot inherit the previous URL or caret.
    const token: number = this.addressInputRemountToken + 1;
    this.addressInputRemountToken = token;
    this.addressInputMounted = false;
    setTimeout(() => {
      if (token === this.addressInputRemountToken) {
        this.addressInputMounted = true;
      }
    }, 0);
  }

  private setFullScreen(tabId: TabId, enabled: boolean): void {
    if (tabId !== this.tabStore.activeTabId) {
      return;
    }
    this.pageDisplayState = {
      fontSize: this.pageDisplayState.fontSize,
      readerMode: this.pageDisplayState.readerMode,
      translated: this.pageDisplayState.translated,
      fullScreen: enabled
    };
    this.rememberTabViewState(tabId);
    this.cardRevision += 1;
  }

  /** Keep the Safari-style navigation arrows in sync with ArkWeb history. */
  private applyNavigationState(tabId: TabId, canGoBack: boolean, canGoForward: boolean): void {
    if (tabId !== this.tabStore.activeTabId) {
      return;
    }
    this.canNavigateBack = canGoBack;
    this.canNavigateForward = canGoForward;
    this.rememberTabViewState(tabId);
    this.navigationStateRevision += 1;
    // Also touch the scene inputs consumed by the nested bottom chrome.
    // This keeps the toolbar update observable when the source callback
    // arrives between ArkUI V2 render turns.
    this.bumpTabStateRevision();
  }

  private scheduleNavigationStateApply(tabId: TabId, canGoBack: boolean,
    canGoForward: boolean): void {
    // WebView lifecycle callbacks can arrive outside the ArkUI state-update
    // turn. Use the component UIContext to apply the result on a render turn
    // so nested V2 children receive the changed @Param values immediately.
    // Keep a timer fallback for stage recreation, when the UI context is not
    // temporarily available.
    try {
      this.getUIContext().animateTo({ duration: 1, curve: Curve.EaseOut }, () => {
        this.applyNavigationState(tabId, canGoBack, canGoForward);
      });
    } catch (_error) {
      setTimeout(() => {
        this.applyNavigationState(tabId, canGoBack, canGoForward);
      }, 0);
    }
  }

  private refreshNavigationState(controller?: webview.WebviewController): void {
    const activeTabId: TabId = this.tabStore.activeTabId;
    const activeController: webview.WebviewController | undefined = controller ??
      this.runtimePort?.controllerFor(activeTabId);
    if (activeController === undefined) {
      this.applyNavigationState(activeTabId, false, false);
      this.scheduleNavigationStateApply(activeTabId, false, false);
      return;
    }
    try {
      const canGoBack: boolean = activeController.accessBackward();
      const canGoForward: boolean = activeController.accessForward();
      hilog.info(
        BROWSER_WEB_DOMAIN,
        BROWSER_WEB_TAG,
        'event=history_state tab=%{public}s back=%{public}s forward=%{public}s',
        activeTabId,
        canGoBack ? 'true' : 'false',
        canGoForward ? 'true' : 'false'
      );
      this.applyNavigationState(activeTabId, canGoBack, canGoForward);
      this.scheduleNavigationStateApply(activeTabId, canGoBack, canGoForward);
    } catch (_error) {
      // A detached ArkWeb controller has no history state to expose.
      this.applyNavigationState(activeTabId, false, false);
      this.scheduleNavigationStateApply(activeTabId, false, false);
    }
  }

  private urlForTab(tabId: TabId): string {
    const tab: BrowserTabRecord | undefined = this.tabStore.tabs.find(
      (item: BrowserTabRecord) => item.id === tabId
    );
    return tab === undefined ? 'about:blank' : lastValidUrlForTab(tab);
  }

  private hostForUrl(url: string): string {
    const loadable: string | undefined = loadableUrlFor(url);
    return loadable === undefined ? '起始页' : displayUrlFor(loadable);
  }

  private hostFor(tabId: TabId): string {
    return this.hostForUrl(this.urlForTab(tabId));
  }

  private diagnosticText(value: string): string {
    return value.replace(/\s+/g, ' ').slice(0, 160);
  }

  private logLoadUrl(
    url: string,
    reason: string,
    caller: string,
    isNewTab: boolean,
    tabId: TabId = this.tabStore.activeTabId,
    controllerId: string = this.runtimePort?.controllerIdFor(tabId) ?? '',
    urlPassedToLoadUrl: string = url,
    restoreResult: string = 'not-applicable'
  ): void {
    const tab: BrowserTabRecord | undefined = this.tabStore.tabs.find(
      (item: BrowserTabRecord) => item.id === tabId
    );
    const lastValidUrl: string = tab === undefined ? 'about:blank' : lastValidUrlForTab(tab);
    const savedDisplayUrl: string | undefined = tab?.displayUrl;
    const displayUrl: string = savedDisplayUrl === undefined || savedDisplayUrl.length === 0
      ? displayUrlFor(lastValidUrl)
      : savedDisplayUrl;
    const validation = validateBrowserUrl(url);
    const snapshotKey: string | undefined = tab?.pageSnapshot ?? tab?.thumbnailKey;
    hilog.info(
      BROWSER_WEB_DOMAIN,
      BROWSER_WEB_TAG,
      'loadUrlReason=%{public}s loadUrlCaller=%{public}s isNewTab=%{public}s tabId=%{public}s ' +
        'url=%{public}s urlPassedToLoadUrl=%{public}s urlScheme=%{public}s lastValidUrl=%{public}s ' +
        'displayUrl=%{public}s webViewControllerId=%{public}s tabOverviewOpen=%{public}s ' +
        'pageSnapshotRestored=%{public}s restoreResult=%{public}s gestureState=%{public}s ' +
        'pageSnapshot=%{public}s arkWebErrorCode=%{public}d',
      reason,
      caller,
      isNewTab ? 'true' : 'false',
      tabId,
      url,
      urlPassedToLoadUrl.length === 0 ? 'none' : urlPassedToLoadUrl,
      validation.urlScheme,
      lastValidUrl,
      displayUrl,
      controllerId,
      this.overviewProgress > 0 ? 'true' : 'false',
      this.thumbnailFor(tabId) !== undefined || (snapshotKey !== undefined && snapshotKey.length > 0)
        ? 'true' : 'false',
      restoreResult,
      String(this.gestureState),
      snapshotKey ?? '',
      this.errorState?.code ?? 0
    );
  }

  private logTabOverview(
    opening: boolean,
    currentIndexBefore: number,
    currentIndexAfter: number,
    currentTabId: TabId,
    currentUrlBefore: string,
    currentUrlAfter: string,
    selectedTabId: TabId,
    webViewReattached: boolean,
    pageSnapshotRestored: boolean = false,
    restoreResult: string = 'not-applicable'
  ): void {
    const selectedTab: BrowserTabRecord | undefined = this.tabStore.tabs.find(
      (tab: BrowserTabRecord) => tab.id === selectedTabId
    );
    const selectedLastValidUrl: string = selectedTab === undefined
      ? 'about:blank'
      : lastValidUrlForTab(selectedTab);
    const selectedDisplayUrl: string = selectedTab?.displayUrl ?? displayUrlFor(selectedLastValidUrl);
    const selectedValidation = validateBrowserUrl(selectedLastValidUrl);
    hilog.info(
      BROWSER_WEB_DOMAIN,
      BROWSER_WEB_TAG,
      'tabOverviewOpen=%{public}s tabOverviewClose=%{public}s currentIndexBefore=%{public}d ' +
        'currentIndexAfter=%{public}d currentTabId=%{public}s currentUrlBefore=%{public}s ' +
        'currentUrlAfter=%{public}s tabsCount=%{public}d selectedTabId=%{public}s ' +
        'webViewControllerId=%{public}s webViewReattached=%{public}s loadUrlReason=%{public}s ' +
        'loadUrlCaller=%{public}s isNewTab=%{public}s lastValidUrl=%{public}s displayUrl=%{public}s ' +
        'urlPassedToLoadUrl=%{public}s urlScheme=%{public}s pageSnapshotRestored=%{public}s ' +
        'restoreResult=%{public}s arkWebErrorCode=%{public}d gestureState=%{public}s',
      opening ? 'true' : 'false',
      opening ? 'false' : 'true',
      currentIndexBefore,
      currentIndexAfter,
      currentTabId,
      currentUrlBefore,
      currentUrlAfter,
      this.tabStore.tabs.length,
      selectedTabId,
      this.runtimePort?.controllerIdFor(selectedTabId) ?? '',
      webViewReattached ? 'true' : 'false',
      webViewReattached ? 'tab-url-fallback-controller-unavailable' : 'none',
      webViewReattached ? (opening ? 'openTabOverview' : 'closeTabOverview') : 'none',
      'false',
      selectedLastValidUrl,
      selectedDisplayUrl,
      'none',
      selectedValidation.urlScheme,
      pageSnapshotRestored ? 'true' : 'false',
      restoreResult,
      this.errorState?.code ?? 0,
      String(this.gestureState)
    );
  }

  private logTabSelection(
    currentIndexBefore: number,
    currentIndexAfter: number,
    currentTabId: TabId,
    currentUrlBefore: string,
    currentUrlAfter: string,
    selectedTabId: TabId,
    webViewReattached: boolean,
    restoreResult: string
  ): void {
    const selectedTab: BrowserTabRecord | undefined = this.tabStore.tabs.find(
      (tab: BrowserTabRecord) => tab.id === selectedTabId
    );
    const selectedLastValidUrl: string = selectedTab === undefined
      ? 'about:blank'
      : lastValidUrlForTab(selectedTab);
    const selectedDisplayUrl: string = selectedTab?.displayUrl ?? displayUrlFor(selectedLastValidUrl);
    const selectedValidation = validateBrowserUrl(selectedLastValidUrl);
    hilog.info(
      BROWSER_WEB_DOMAIN,
      BROWSER_WEB_TAG,
      'tabSelection=true tabOverviewOpen=%{public}s tabOverviewClose=%{public}s ' +
        'currentIndexBefore=%{public}d currentIndexAfter=%{public}d currentTabId=%{public}s ' +
        'currentUrlBefore=%{public}s currentUrlAfter=%{public}s tabsCount=%{public}d ' +
        'selectedTabId=%{public}s webViewControllerId=%{public}s webViewReattached=%{public}s ' +
        'loadUrlReason=%{public}s loadUrlCaller=%{public}s isNewTab=false lastValidUrl=%{public}s ' +
        'displayUrl=%{public}s urlPassedToLoadUrl=none urlScheme=%{public}s ' +
        'pageSnapshotRestored=%{public}s restoreResult=%{public}s arkWebErrorCode=%{public}d ' +
        'gestureState=%{public}s',
      this.overviewProgress > 0 ? 'true' : 'false',
      'false',
      currentIndexBefore,
      currentIndexAfter,
      currentTabId,
      currentUrlBefore,
      currentUrlAfter,
      this.tabStore.tabs.length,
      selectedTabId,
      this.runtimePort?.controllerIdFor(selectedTabId) ?? '',
      webViewReattached ? 'true' : 'false',
      webViewReattached ? 'tab-url-fallback-controller-unavailable' : 'none',
      'BrowserShell.nativeTabSelection',
      selectedLastValidUrl,
      selectedDisplayUrl,
      selectedValidation.urlScheme,
      this.thumbnailFor(selectedTabId) !== undefined ? 'true' : 'false',
      restoreResult,
      this.errorState?.code ?? 0,
      String(this.gestureState)
    );
  }

  private logBrowserLifecycle(
    eventName: string,
    tabId: TabId,
    url: string,
    code: number,
    isMainFrame: boolean,
    info: string,
    rawUrl: string = url,
    restoreResult: string = 'not-applicable'
  ): void {
    const tab: BrowserTabRecord | undefined = this.tabStore.tabs.find(
      (item: BrowserTabRecord) => item.id === tabId
    );
    const lastValidUrl: string = tab === undefined ? 'about:blank' : lastValidUrlForTab(tab);
    const displayUrl: string = tab?.displayUrl ?? displayUrlFor(lastValidUrl);
    const validation = validateBrowserUrl(rawUrl);
    hilog.info(
      BROWSER_WEB_DOMAIN,
      BROWSER_WEB_TAG,
      'event=%{public}s tab=%{public}s host=%{public}s code=%{public}d mainFrame=%{public}s ' +
        'rawUrl=%{public}s parsedUrl=%{public}s urlScheme=%{public}s lastValidUrl=%{public}s ' +
        'displayUrl=%{public}s urlPassedToLoadUrl=%{public}s loadUrlReason=%{public}s ' +
        'loadUrlCaller=%{public}s webViewControllerId=%{public}s pageSnapshotRestored=%{public}s ' +
        'arkWebErrorCode=%{public}d restoreResult=%{public}s gestureState=%{public}s detail=%{public}s',
      eventName,
      tabId,
      this.hostForUrl(url),
      code,
      isMainFrame ? 'true' : 'false',
      rawUrl,
      url,
      validation.urlScheme,
      lastValidUrl,
      displayUrl,
      'none',
      'none',
      eventName,
      this.runtimePort?.controllerIdFor(tabId) ?? '',
      this.thumbnailFor(tabId) !== undefined ? 'true' : 'false',
      code,
      restoreResult,
      String(this.gestureState),
      this.diagnosticText(info)
    );
  }

  private logRejectedLifecycleUrl(tabId: TabId, rawUrl: string, fallbackUrl: string, caller: string): void {
    const validation = validateBrowserUrl(rawUrl);
    const tab: BrowserTabRecord | undefined = this.tabStore.tabs.find(
      (item: BrowserTabRecord) => item.id === tabId
    );
    const lastValidUrl: string = tab === undefined ? fallbackUrl : lastValidUrlForTab(tab);
    const displayUrl: string = tab?.displayUrl ?? displayUrlFor(lastValidUrl);
    hilog.info(
      BROWSER_WEB_DOMAIN,
      BROWSER_WEB_TAG,
      'event=url_rejected tab=%{public}s rawUrl=%{public}s parsedUrl=%{public}s ' +
        'urlScheme=%{public}s lastValidUrl=%{public}s displayUrl=%{public}s ' +
        'urlPassedToLoadUrl=%{public}s loadUrlReason=%{public}s loadUrlCaller=%{public}s ' +
        'webViewControllerId=%{public}s pageSnapshotRestored=%{public}s arkWebErrorCode=%{public}d ' +
        'restoreResult=%{public}s gestureState=%{public}s reason=%{public}s',
      tabId,
      rawUrl,
      validation.normalizedUrl,
      validation.urlScheme,
      lastValidUrl,
      displayUrl,
      'none',
      'lifecycle-url-rejected',
      caller,
      this.runtimePort?.controllerIdFor(tabId) ?? '',
      this.thumbnailFor(tabId) !== undefined ? 'true' : 'false',
      0,
      'preserved-last-valid',
      String(this.gestureState),
      validation.reason
    );
  }

  private loadValidatedUrl(
    controller: webview.WebviewController,
    requestedUrl: string,
    reason: string,
    caller: string,
    tabId: TabId,
    isNewTab: boolean = false
  ): boolean {
    const validation = validateBrowserUrl(requestedUrl);
    if (!validation.valid) {
      this.logRejectedLifecycleUrl(tabId, requestedUrl, this.urlForTab(tabId), caller);
      return false;
    }
    const url: string = validation.normalizedUrl;
    this.logLoadUrl(
      url,
      reason,
      caller,
      isNewTab,
      tabId,
      this.runtimePort?.controllerIdFor(tabId) ?? '',
      url,
      'loadUrl-requested'
    );
    try {
      controller.loadUrl(url);
      return true;
    } catch (_error) {
      this.logBrowserLifecycle(
        'loadUrl_throw',
        tabId,
        this.urlForTab(tabId),
        0,
        true,
        'controller.loadUrl threw synchronously',
        url,
        'loadUrl-throw'
      );
      return false;
    }
  }

  private showBrowserError(
    tabId: TabId,
    kind: BrowserErrorKind,
    code: number,
    sourceUrl: string = ''
  ): void {
    if (tabId !== this.tabStore.activeTabId) {
      return;
    }
    this.pageReady = false;
    this.errorState = {
      kind,
      code,
      host: this.hostFor(tabId),
      message: kind === BrowserErrorKind.SSL ? '证书校验失败' : '页面加载失败'
    };
    this.logBrowserLifecycle(
      'error-state',
      tabId,
      this.urlForTab(tabId),
      code,
      true,
      '',
      sourceUrl.length === 0 ? this.urlForTab(tabId) : sourceUrl,
      'error-preserved-last-valid'
    );
    this.rememberTabViewState(tabId);
    this.cardRevision += 1;
  }

  private retryBrowserError(): void {
    const activeId: TabId = this.tabStore.activeTabId;
    const tab: BrowserTabRecord | undefined = this.activeTab();
    const savedUrl: string = tab === undefined ? 'about:blank' : lastValidUrlForTab(tab);
    let controller: webview.WebviewController | undefined = this.runtimePort?.controllerFor(activeId);
    if (controller === undefined) {
      // The only recovery source is this tab's own canonical URL. The pool's
      // factory uses the same value as Web.src and never the display label.
      this.runtimePort?.ensureTab(activeId);
      controller = this.runtimePort?.controllerFor(activeId);
      this.attachCurrentHosts();
    }
    if (controller === undefined) {
      this.logLoadUrl(
        savedUrl,
        'error-retry-controller-unavailable',
        'retryBrowserError',
        false,
        activeId,
        '',
        '',
        'restore-controller-unavailable'
      );
      return;
    }
    this.gestureActive = false;
    this.addressGestureFinished = true;
    this.addressTransitionToken += 1;
    this.addressGestureEngine.cancel();
    this.resetTabGestureMotion(false);
    if (!this.loadValidatedUrl(controller, savedUrl, 'error-retry', 'retryBrowserError', activeId)) {
      return;
    }
    this.errorState = undefined;
    this.errorStatesByTab.set(activeId, undefined);
    this.pageReady = false;
    this.attachCurrentHosts();
    this.scheduleHostReattach(activeId);
    this.rememberTabViewState(activeId);
    this.cardRevision += 1;
  }

  private backFromBrowserError(): void {
    const activeId: TabId = this.tabStore.activeTabId;
    const moved: boolean = this.dispatcher?.goBack() ?? false;
    if (moved) {
      this.errorState = undefined;
      this.errorStatesByTab.set(activeId, undefined);
      this.rememberTabViewState();
      this.refreshNavigationState();
      return;
    }
    // If the error page has no history entry, reattach the same tab runtime
    // (or recreate it from its own lastValidUrl) instead of navigating home.
    const restored: boolean = this.reattachTabController(activeId, 'backFromBrowserError');
    if (restored) {
      this.errorState = undefined;
      this.errorStatesByTab.set(activeId, undefined);
      this.pageReady = false;
      this.attachCurrentHosts();
      this.rememberTabViewState(activeId);
      this.cardRevision += 1;
    }
  }

  private async initializeSession(): Promise<void> {
    this.browserSettings = await this.repository?.loadSettings() ?? copyBrowserSettings(DEFAULT_BROWSER_SETTINGS);
    this.startPageItems = await this.repository?.listStartPageItems() ?? [];
    this.historyItems = await this.repository?.listHistory() ?? [];
    this.syncFrequentSites(this.historyItems);
    const closedTabs = await this.repository?.loadClosedTabs() ?? [];
    closedTabs.forEach((record) => this.closedTabStack.push(record));
    const snapshot: BrowserSessionSnapshot | undefined = await this.repository?.loadSession();
    if (snapshot !== undefined) {
      this.tabStore.restore(snapshot);
    } else if (this.tabStore.tabs.length === 0) {
      this.tabStore.createTab('about:blank', false);
      await this.repository?.saveSession(this.tabStore.snapshot());
    }
    for (const tab of this.tabStore.tabs) {
      this.initializeTabViewState(tab.id);
      const restoredUrl: string = lastValidUrlForTab(tab);
      const restoredMode: AddressBarPresentationMode = tab.addressSource === 'search'
        ? AddressBarPresentationMode.SEARCH
        : tab.addressSource === 'url'
          ? AddressBarPresentationMode.URL
          : searchQueryForUrl(restoredUrl) === undefined
            ? AddressBarPresentationMode.URL
            : AddressBarPresentationMode.SEARCH;
      this.addressPresentationByTab.set(tab.id, restoredMode);
      if (restoredMode === AddressBarPresentationMode.SEARCH) {
        const restoredQuery: string | undefined = tab.addressQuery ?? searchQueryForUrl(restoredUrl);
        if (restoredQuery !== undefined) {
          this.searchQueriesByTab.set(tab.id, restoredQuery);
        }
        if (searchQueryForUrl(restoredUrl) === undefined) {
          this.pendingSearchNavigationByTab.add(tab.id);
        }
      }
    }
    this.restoreTabViewState(this.tabStore.activeTabId);
    this.sceneActiveTabId = this.tabStore.activeTabId;
    this.sceneTabs = this.tabStore.tabs.slice();
    this.sceneActiveTab = this.tabStore.tabs.find(
      (tab: BrowserTabRecord) => tab.id === this.tabStore.activeTabId
    );
    this.addressDraftTabId = this.tabStore.activeTabId;
    this.addressDraft = '';
    this.addressInputFocused = false;
    this.runtimePort?.ensureBalanced();
    this.attachCurrentHosts();
    const pendingExternalUrl: string | undefined = takePendingExternalUrl();
    if (pendingExternalUrl !== undefined) {
      setTimeout(() => this.openExternalUrl(pendingExternalUrl), 0);
    }
  }

  private openExternalUrl(url: string): void {
    const canonicalUrl: string | undefined = loadableUrlFor(url);
    if (canonicalUrl === undefined || canonicalUrl === 'about:blank') {
      return;
    }
    this.showLibrary = false;
    this.showStartPageCustomize = false;
    this.closeDownloadManager();
    if (this.addressEditing) {
      this.closeAddressEditor();
    }
    this.loadAddress(canonicalUrl, 'external-app-launch', 'EntryAbility.onNewWant');
  }

  /**
   * Pair ArkWeb's explicit inactive/active lifecycle with the ability scene.
   * Keeping the existing NodeContainer attached is important: detaching and
   * rebuilding it during a desktop transition can leave a restored page with
   * a valid URL but no renderer surface. ArkWeb pauses safe content here and
   * is reactivated by handleForeground().
   */
  private async handleBackground(): Promise<void> {
    this.downloadLifecycle?.onHidden();
    const controller: webview.WebviewController | undefined =
      this.runtimePort?.controllerFor(this.tabStore.activeTabId);
    if (controller !== undefined) {
      try {
        controller.onInactive();
      } catch (_error) {
        // The renderer can already be detached while the ability backgrounds.
      }
    }
    await this.saveSession();
  }

  private async saveSession(): Promise<void> {
    const repository: BrowserRepository | undefined = this.repository;
    if (repository === undefined) {
      return;
    }
    await repository.saveSession(this.tabStore.snapshot());
    await repository.saveSettings(this.browserSettings);
    await repository.saveStartPageItems(this.startPageItems);
    await repository.saveClosedTabs(this.closedTabStack.snapshot());
  }

  private handleMemoryPressure(level: number): void {
    if (level <= 0 || this.webTabPool === undefined) {
      return;
    }
    this.runtimePort?.ensureBalanced();
    this.webTabPool.handleMemoryPressure(this.tabStore.tabs, this.tabStore.activeTabId);
    this.attachCurrentHosts();
  }

  /**
   * Rebuild the visible ArkWeb host when the ability returns from the
   * desktop/recents surface. ArkWeb may detach its NodeContainer while the
   * window is backgrounded; retaining the old focus state also leaves the
   * address field claiming the keyboard after the page is visible again.
   */
  private handleForeground(): void {
    this.gestureActive = false;
    this.addressGestureFinished = true;
    this.addressTransitionToken += 1;
    this.resetTabGestureMotion(false);
    this.lastGestureVelocityX = 0;
    this.lastGestureDy = 0;
    this.addressInputFocused = false;
    this.addressEditing = false;
    // Force a real TextInput lifecycle boundary. This is more reliable than
    // only clearing the focus chain when the IME kept a stale editor session
    // while the ability was in the desktop/recents surface.
    this.addressInputMounted = false;
    this.addressInputFocusEnabled = false;
    try {
      this.getUIContext().getFocusController().clearFocus();
      void inputMethod.getController().hideSoftKeyboard().catch(() => undefined);
    } catch (_error) {
      // The UI context can be between stage recreation callbacks. The next
      // host attach below remains the source of truth for page recovery.
    }
    this.runtimePort?.ensureBalanced();
    // ArkWeb pauses its renderer when the ability loses focus. Reactivate the
    // existing controller instead of detaching/recreating the NodeContainer;
    // the latter can leave a restored page with a live URL but a blank surface.
    const activeController: webview.WebviewController | undefined =
      this.runtimePort?.controllerFor(this.tabStore.activeTabId);
    if (activeController !== undefined) {
      try {
        activeController.onActive();
      } catch (_error) {
        // The controller may still be associating with its Web node during
        // the first foreground frame. The delayed retry below covers it.
      }
    }
    if (this.hostControllers.get(this.tabStore.activeTabId) === undefined) {
      this.attachCurrentHosts();
    }
    this.refreshNavigationState();
    // Allow the rebuilt NodeContainer to attach before asking ArkWeb for its
    // history state; this also clears a stale focused TextInput on resume.
    setTimeout(() => {
      this.addressInputMounted = true;
      this.addressInputFocused = false;
      this.addressEditing = false;
      this.refreshNavigationState();
    }, 80);
    setTimeout(() => {
      this.addressInputFocusEnabled = true;
    }, 600);
    setTimeout(() => {
      const restoredController: webview.WebviewController | undefined =
        this.runtimePort?.controllerFor(this.tabStore.activeTabId);
      if (restoredController !== undefined) {
        try {
          restoredController.onActive();
        } catch (_error) {
          // Ignore a controller that is still being re-associated by ArkUI.
        }
      }
    }, 160);
    // Refresh history after ArkWeb has restored its renderer. The first
    // foreground callback can arrive before the page's navigation state is
    // available, which otherwise leaves the forward action visually stale.
    setTimeout(() => this.refreshNavigationState(), 260);
  }

  private attachHost(tabId: TabId | undefined): WebNodeHostController | undefined {
    if (tabId === undefined || this.webTabPool === undefined) {
      return undefined;
    }
    const tab: BrowserTabRecord | undefined = this.tabStore.tabs.find(
      (item: BrowserTabRecord) => item.id === tabId
    );
    // Blank tabs are owned by the native StartPage. Do not publish their
    // about:blank FrameNode as a neighbouring slot: ArkWeb paints a white
    // document even when the slot is translated off-screen and can cover the
    // active page during a horizontal tab transition.
    if (tab === undefined || !shouldMountTabWebHost(tab.url)) {
      const existingBlankHost: WebNodeHostController | undefined = this.hostControllers.get(tabId);
      if (existingBlankHost !== undefined) {
        existingBlankHost.setFrameNode(null);
        this.hostControllers.delete(tabId);
      }
      return undefined;
    }
    const runtime = this.webTabPool.get(tabId);
    if (runtime === undefined) {
      return undefined;
    }
    const existing: WebNodeHostController | undefined = this.hostControllers.get(tabId);
    if (existing !== undefined) {
      // A runtime can be replaced for the first navigation of a blank tab.
      // Re-attach the preserved NodeController so NodeContainer keeps its
      // identity while the new BuilderNode frame is published.
      runtime.attach(existing);
      return existing;
    }
    const host: WebNodeHostController = new WebNodeHostController(tabId);
    runtime.attach(host);
    this.hostControllers.set(tabId, host);
    return host;
  }

  private attachHostIfMissing(tabId: TabId): void {
    if (this.hostControllers.get(tabId) === undefined) {
      this.attachHost(tabId);
    }
  }

  private attachCurrentHosts(): void {
    if (this.webTabPool === undefined) {
      return;
    }
    this.runtimePort?.ensureBalanced();
    const runtimeIds: Set<TabId> = new Set(this.webTabPool.runtimeIds());
    for (const entry of this.hostControllers.entries()) {
      const tabId: TabId = entry[0];
      const host: WebNodeHostController = entry[1];
      if (!runtimeIds.has(tabId)) {
        // The pool already detached/destroyed this runtime. Drop the stale
        // host reference so a future tab with a recycled id gets a fresh one.
        host.setFrameNode(null);
        this.hostControllers.delete(tabId);
      }
    }
    // Keep a host for every live tab so a neighbouring Safari transition can
    // reuse the same ArkWeb controller instead of restoring a page snapshot.
    for (const tab of this.tabStore.tabs) {
      this.attachHost(tab.id);
    }
  }

  /**
   * Re-attach native BuilderNode frames after ArkUI commits a host-slot
   * change. Creating or activating a tab updates the data tree immediately,
   * while the NodeContainer is published on the following UI turn. A second
   * attach on the next frame (and one after the native settle) makes the
   * renderer binding deterministic without replacing the Web controller.
   */
  private scheduleHostReattach(tabId: TabId): void {
    setTimeout(() => {
      if (this.tabStore.activeTabId === tabId && this.overviewProgress === 0) {
        this.attachCurrentHosts();
      }
    }, 0);
    setTimeout(() => {
      if (this.tabStore.activeTabId === tabId && this.overviewProgress === 0) {
        this.attachCurrentHosts();
      }
    }, BROWSER_OVERVIEW_ANIMATION_DURATION_MS);
  }

  private loadAddress(
    value: string,
    reason: string = 'address-submit',
    caller: string = 'BrowserShell.loadAddress'
  ): void {
    // Classify the raw input before normalization. Search-result URLs must not
    // erase the query that the user entered, while an explicitly supplied URL
    // remains editable as its canonical URL even when it points at a search
    // engine.
    const submittedMode: AddressBarPresentationMode = addressBarPresentationForInput(value);
    const submittedQuery: string = submittedMode === AddressBarPresentationMode.SEARCH
      ? searchQueryTextFor(value)
      : '';
    const url: string = normalizeAddressInput(
      submittedMode === AddressBarPresentationMode.SEARCH ? submittedQuery : value,
      this.browserSettings.searchEngine
    );
    const activeId: TabId = this.tabStore.activeTabId;
    const currentUrl: string = this.urlForTab(activeId);
    const preserveEditorForSubmit: boolean = caller === 'submitAddressEditor' && this.addressEditing;
    const submittedSource: AddressBarSource = submittedMode === AddressBarPresentationMode.SEARCH
      ? 'search'
      : 'url';
    this.addressPresentationByTab.set(activeId, submittedMode);
    if (submittedMode === AddressBarPresentationMode.SEARCH) {
      this.searchQueriesByTab.set(activeId, submittedQuery);
      this.pendingSearchNavigationByTab.add(activeId);
      this.searchResultSettledAtByTab.delete(activeId);
    } else {
      this.searchQueriesByTab.delete(activeId);
      this.pendingSearchNavigationByTab.delete(activeId);
      this.searchResultSettledAtByTab.delete(activeId);
    }
    const submittedSearchLabel: string | undefined = submittedMode === AddressBarPresentationMode.SEARCH
      ? this.searchLabelForUrl(url)
      : undefined;
    if (submittedSearchLabel === undefined) {
      this.searchLabelsByTab.delete(activeId);
    } else {
      this.searchLabelsByTab.set(activeId, submittedSearchLabel);
    }
    const submittedTitle: string = submittedSearchLabel ?? '';
    // A newly-created about:blank tab is rendered by the native start page and
    // intentionally has no ArkWeb runtime yet.  The first explicit address
    // submission is the boundary at which that tab becomes a web tab.  Commit
    // the canonical URL before creating the runtime so Web({ src }) mounts the
    // requested page as its initial document. Calling loadUrl() before that
    // NodeContainer is mounted throws synchronously on ArkWeb.
    if (shouldRecreateBlankTabRuntime(currentUrl, url) &&
      this.runtimePort?.controllerFor(activeId) === undefined) {
      if (!this.tabStore.updateTabUrl(
        activeId,
        url,
        submittedTitle,
        submittedSource,
        submittedMode === AddressBarPresentationMode.SEARCH ? submittedQuery : undefined
      )) {
        this.logRejectedLifecycleUrl(activeId, url, currentUrl, caller);
        return;
      }
      this.cardRevision += 1;
      this.bumpTabStateRevision();
      this.pageReady = false;
      this.errorState = undefined;
      this.pageDisplayState = copyPageDisplayState(DEFAULT_PAGE_DISPLAY_STATE);
      this.runtimePort?.ensureTab(activeId);
      this.attachCurrentHosts();
      this.scheduleHostReattach(activeId);
      this.logLoadUrl(
        url,
        'first-navigation-web-src',
        caller,
        false,
        activeId,
        this.runtimePort?.controllerIdFor(activeId) ?? '',
        '',
        'web-src-requested'
      );
      void this.repository?.saveSession(this.tabStore.snapshot());
      this.rememberTabViewState(activeId);
      if (!preserveEditorForSubmit) {
        this.addressEditing = false;
        this.resetAddressDraft();
      }
      return;
    }
    let controller: webview.WebviewController | undefined = this.runtimePort?.controllerFor(activeId);
    if (controller === undefined) {
      this.runtimePort?.ensureTab(activeId);
      controller = this.runtimePort?.controllerFor(activeId);
      this.attachCurrentHosts();
    }
    if (controller === undefined) {
      this.logLoadUrl(
        url,
        'controller-unavailable-no-load',
        caller,
        false,
        activeId,
        '',
        '',
        'controller-unavailable'
      );
      return;
    }
    try {
      // A submit can arrive while the bottom-bar touch stream is still active
      // (the IME owns the final touch-up). Reset the gesture state before
      // handing control back to ArkWeb so the new page remains hit-testable.
      const reset: BrowserGestureState = resetBrowserGestureState();
      this.gestureActive = reset.gestureActive;
      this.addressGestureFinished = reset.addressGestureFinished;
      this.overviewProgress = reset.overviewProgress;
      this.resetTabGestureMotion(false);
      // Keep the already-mounted ArkWeb runtime when a start tab receives its
      // first URL. Releasing and rebuilding the BuilderNode here races the
      // NodeContainer's native surface publication (especially after the tab
      // was created from the overview), so callbacks can report a successful
      // load while the visible renderer remains empty. A normal loadUrl keeps
      // the controller/frame identity stable and lets ArkWeb paint into the
      // surface that is already on screen.
      const loaded: boolean = this.loadValidatedUrl(controller, url, reason, caller, activeId);
      if (!loaded) {
        return;
      }
      if (shouldActivateWebController(url)) {
        try {
          controller.onActive();
        } catch (_error) {
          // A newly-created controller may not be associated until the next
          // frame; its page-end callback and foreground path retry activation.
        }
      }
      if (this.tabStore.updateTabUrl(
        activeId,
        url,
        submittedTitle,
        submittedSource,
        submittedMode === AddressBarPresentationMode.SEARCH ? submittedQuery : undefined
      )) {
        this.bumpTabStateRevision();
      }
      // A start tab intentionally had no live ArkWeb host. Once a real URL is
      // committed, publish the active host before the first page-end callback
      // and retry after the next UI turn so the renderer has a visible frame.
      this.attachCurrentHosts();
      this.scheduleHostReattach(activeId);
      this.errorState = undefined;
      this.pageReady = false;
      this.pageDisplayState = copyPageDisplayState(DEFAULT_PAGE_DISPLAY_STATE);
      this.rememberTabViewState(activeId);
      if (!preserveEditorForSubmit) {
        this.addressEditing = false;
        this.resetAddressDraft();
      }
    } catch (_error) {
      // ArkWeb reports a detached controller through a synchronous error.
      this.logBrowserLifecycle(
        'loadAddress_exception',
        activeId,
        this.urlForTab(activeId),
        0,
        true,
        'address load failed before commit',
        url,
        'preserved-last-valid'
      );
    }
  }

  private async onNewTab(): Promise<void> {
    const tabId: TabId | undefined = await this.dispatcher?.createTab('about:blank', false);
    if (tabId === undefined) {
      return;
    }
    this.logLoadUrl('about:blank', 'explicit-new-tab', 'onNewTab', true, tabId);
      // A new start tab must not inherit the previous page's error overlay.
      // Without clearing this state the native StartPage is mounted behind
      // BrowserErrorView and appears as a blank/error placeholder after
      // creating a tab from the multi-page overview.
      this.resetTabViewState(tabId);
      this.addressEditing = false;
      this.attachCurrentHosts();
    this.scheduleHostReattach(tabId);
    this.resetAddressDraft();
    this.scheduleStartPageThumbnail(tabId);
    this.bumpTabStateRevision();
  }

  /**
   * Commit Safari's end-of-strip action: a left swipe on the last tab opens
   * and activates a normal blank start tab instead of rubber-banding forever.
   */
  private async commitNewStartTabFromEdge(): Promise<void> {
    const transitionToken: number = this.addressTransitionToken;
    const dispatcher: DefaultBrowserCommandDispatcher | undefined = this.dispatcher;
    if (dispatcher === undefined) {
      this.springBackAddressGesture();
      return;
    }
    this.gestureState = TabGestureState.COMMITTING;
    // Mount the handoff layer while the pending plus is still present. The
    // pending plus follows the incoming tab during the settle; after commit,
    // the native handoff crossfades it in place to the full placeholder.
    this.addressHandoffAnimationToken += 1;
    this.addressHandoffActive = true;
    this.addressHandoffProgress = 0;
    this.logAddressGestureState('commit-new-tab', true, false);
    this.getUIContext().animateTo({
      curve: curves.springMotion(),
      onFinish: () => {
        if (isAddressTransitionCurrent(transitionToken, this.addressTransitionToken)) {
          void this.completeNewStartTabFromEdge(transitionToken);
        }
      }
    }, () => {
      this.rawDragX = -this.viewportWidth;
      this.pageTranslateX = -this.viewportWidth;
      this.adjacentTranslateX = 0;
      this.transitionProgress = 1;
      this.overviewProgress = 0;
    });
    await Promise.resolve();
  }

  private async completeNewStartTabFromEdge(transitionToken: number): Promise<void> {
    const dispatcher: DefaultBrowserCommandDispatcher | undefined = this.dispatcher;
    if (dispatcher === undefined || !isAddressTransitionCurrent(transitionToken, this.addressTransitionToken)) {
      return;
    }
    const draft: PendingTabDraft | undefined = this.pendingTabDraft;
    if (draft === undefined) {
      this.springBackAddressGesture();
      return;
    }
    const newTabId: TabId = await dispatcher.commitReservedTab(draft);
    if (!isAddressTransitionCurrent(transitionToken, this.addressTransitionToken)) {
      return;
    }
    // The pending record has now become a real store record with the same
    // stable id. Keep the render-only reference until the transient motion is
    // reset; while previewKind is NEW_TAB it remains outside the visible
    // address slot, so the handoff layer has no empty frame to cover.
    this.attachCurrentHosts();
    this.resetTabViewState(newTabId);
    this.addressEditing = false;
    this.resetAddressDraft();
    this.scheduleStartPageThumbnail(newTabId);
    this.scheduleHostReattach(newTabId);
    this.overviewProgress = 0;
    this.sceneActiveTabId = newTabId;
    this.sceneTabs = this.tabStore.tabs.slice();
    this.sceneActiveTab = this.tabStore.tabs.find(
      (tab: BrowserTabRecord) => tab.id === newTabId
    );
    this.rawDragX = 0;
    this.gestureActive = false;
    this.resetTabGestureMotion(false);
    this.pendingTabDraft = undefined;
    this.bumpTabStateRevision();
    const handoffToken: number = this.addressHandoffAnimationToken + 1;
    this.addressHandoffAnimationToken = handoffToken;
    this.runAddressHandoffPhase(handoffToken, 0);
    this.logAddressGestureState('commit-new-tab-complete', true, false);
  }

  /** Drive only the native plus/placeholder crossfade after the page settles. */
  private runAddressHandoffPhase(handoffToken: number, phase: number): void {
    if (phase !== 0) {
      return;
    }
    this.addressHandoffAnimator?.finish();
    this.addressHandoffProgress = 0;
    const animator: AnimatorResult = this.getUIContext().createAnimator({
      duration: SAFARI_ADDRESS_HANDOFF_CROSSFADE_DURATION_MS,
      easing: 'ease-in-out',
      delay: 0,
      fill: 'forwards',
      direction: 'normal',
      iterations: 1,
      begin: 0,
      end: 1
    });
    this.addressHandoffAnimator = animator;
    animator.onFrame = (value: number) => {
      if (handoffToken === this.addressHandoffAnimationToken &&
        this.addressHandoffAnimator === animator) {
        this.addressHandoffProgress = value;
      }
    };
    animator.onFinish = () => {
      if (handoffToken !== this.addressHandoffAnimationToken ||
        this.addressHandoffAnimator !== animator) {
        return;
      }
      this.addressHandoffProgress = 1;
      this.addressHandoffActive = false;
      this.addressHandoffAnimator = undefined;
    };
    // Keep the pre-crossfade plus-only interval independent from the extended
    // crossfade. The page spring and the address preview fade never consume
    // this duration token.
    setTimeout(() => {
      if (handoffToken !== this.addressHandoffAnimationToken ||
        this.addressHandoffAnimator !== animator) {
        return;
      }
      animator.play();
    }, SAFARI_ADDRESS_HANDOFF_LEAD_IN_MS);
  }

  private async onNewPrivateTab(): Promise<void> {
    const tabId: TabId | undefined = await this.dispatcher?.createTab('about:blank', true);
    if (tabId === undefined) {
      return;
    }
      this.logLoadUrl('about:blank', 'explicit-new-private-tab', 'onNewPrivateTab', true, tabId);
      this.resetTabViewState(tabId);
      this.addressEditing = false;
      this.attachCurrentHosts();
      this.scheduleHostReattach(tabId);
      this.resetAddressDraft();
      this.scheduleStartPageThumbnail(tabId);
      this.bumpTabStateRevision();
  }

  private onFontSize(size: PageFontSize): void {
    this.pageDisplayState = {
      fontSize: size,
      readerMode: this.pageDisplayState.readerMode,
      translated: this.pageDisplayState.translated,
      fullScreen: this.pageDisplayState.fullScreen
    };
    this.rememberTabViewState();
    this.browserSettings = {
      searchEngine: this.browserSettings.searchEngine,
      autoCloseTabs: this.browserSettings.autoCloseTabs,
      contentBlockingEnabled: this.browserSettings.contentBlockingEnabled,
      showFavorites: this.browserSettings.showFavorites,
      showFrequentSites: this.browserSettings.showFrequentSites,
      startPageSectionsConfigured: this.browserSettings.startPageSectionsConfigured,
      startPageBackgroundId: this.browserSettings.startPageBackgroundId,
      startPageAppearance: this.browserSettings.startPageAppearance,
      defaultFontSize: size
    };
    void this.repository?.saveSettings(this.browserSettings);
  }

  private onPageAction(action: PageAction): void {
    if (!this.pageActionsReady()) {
      return;
    }
    if (action === PageAction.READER) {
      void this.toggleReaderMode();
      return;
    }
    if (action === PageAction.TRANSLATE) {
      void this.translateActivePage();
      return;
    }
    if (action === PageAction.BOOKMARK) {
      void this.addActiveBookmark();
      return;
    }
    if (action === PageAction.DESKTOP_SITE) {
      this.togglePageMode();
      return;
    }
    if (action === PageAction.MEDIA_SPEED_HALF) {
      void this.setMediaPlaybackRate(0.5);
      return;
    }
    if (action === PageAction.MEDIA_SPEED_STANDARD) {
      void this.setMediaPlaybackRate(1.0);
      return;
    }
    if (action === PageAction.MEDIA_SPEED_ONE_HALF) {
      void this.setMediaPlaybackRate(1.5);
      return;
    }
    if (action === PageAction.MEDIA_SPEED_DOUBLE) {
      void this.setMediaPlaybackRate(2.0);
      return;
    }
    void this.capturePageForAction();
  }

  /** Apply Safari's video-speed behavior to every media element in the page. */
  private async setMediaPlaybackRate(rate: number): Promise<void> {
    const tab: BrowserTabRecord | undefined = this.activeTab();
    const controller: webview.WebviewController | undefined = tab === undefined
      ? undefined
      : this.runtimePort?.controllerFor(tab.id);
    if (controller === undefined) {
      return;
    }
    const script: string = `(() => {
      const media = Array.from(document.querySelectorAll('video, audio'));
      media.forEach((element) => {
        element.playbackRate = ${rate};
        element.defaultPlaybackRate = ${rate};
      });
      return media.length > 0 ? 'applied' : 'empty';
    })()`;
    try {
      const result: string = await controller.runJavaScript(script);
      void result;
    } catch (_error) {
      return;
    }
  }

  /** Apply a readable article presentation directly to the active ArkWeb page. */
  private async toggleReaderMode(): Promise<void> {
    const tab: BrowserTabRecord | undefined = this.activeTab();
    const controller: webview.WebviewController | undefined = tab === undefined
      ? undefined
      : this.runtimePort?.controllerFor(tab.id);
    if (controller === undefined) {
      return;
    }
    const enabled: boolean = !this.pageDisplayState.readerMode;
    const script: string = enabled
      ? `(() => {
          const id = 'safari-hm-reader-style';
          let style = document.getElementById(id);
          if (!style) {
            style = document.createElement('style');
            style.id = id;
            document.head.appendChild(style);
          }
          style.textContent = 'html,body{background:#fff!important;color:#1d1d1f!important;}body{max-width:720px!important;margin:0 auto!important;padding:24px!important;font-size:118%!important;line-height:1.75!important;}nav,header,footer,aside,iframe,video,form,[role="banner"],[role="navigation"]{display:none!important;}img{max-width:100%!important;height:auto!important;}';
          document.documentElement.setAttribute('data-safari-hm-reader', '1');
          return 'on';
        })()`
      : `(() => {
          const style = document.getElementById('safari-hm-reader-style');
          if (style) style.remove();
          document.documentElement.removeAttribute('data-safari-hm-reader');
          return 'off';
        })()`;
    try {
      const result: string = await controller.runJavaScript(script);
      if ((enabled && result === 'on') || (!enabled && result === 'off')) {
        this.pageDisplayState = {
          fontSize: this.pageDisplayState.fontSize,
          readerMode: enabled,
          translated: this.pageDisplayState.translated,
          fullScreen: this.pageDisplayState.fullScreen
        };
        this.rememberTabViewState();
      } else {
        return;
      }
    } catch (_error) {
      return;
    }
  }

  /** Open a translated copy through a normal ArkWeb navigation. */
  private async translateActivePage(): Promise<void> {
    const tab: BrowserTabRecord | undefined = this.activeTab();
    if (tab === undefined || tab.url === 'about:blank') {
      return;
    }
    const target: string = `https://translate.google.com/translate?sl=auto&tl=zh-CN&u=${encodeURIComponent(tab.url)}`;
    this.loadAddress(target, 'translate-active-page', 'translateActivePage');
    this.pageDisplayState = {
      fontSize: this.pageDisplayState.fontSize,
      readerMode: this.pageDisplayState.readerMode,
      translated: true,
      fullScreen: this.pageDisplayState.fullScreen
    };
    this.rememberTabViewState();
  }

  /** Invoke HarmonyOS system sharing for the active page URL. */
  private async shareActivePage(): Promise<void> {
    const tab: BrowserTabRecord | undefined = this.activeTab();
    if (tab === undefined || tab.url === 'about:blank') {
      return;
    }
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined) {
      return;
    }
    try {
      const data: systemShare.SharedData = new systemShare.SharedData({
        utd: 'general.hyperlink',
        content: tab.url,
        title: tab.title.length > 0 ? tab.title : tab.url,
        label: 'HYPERLINK',
        description: tab.url
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(data);
      await controller.show(hostContext as common.UIAbilityContext, {
        previewMode: systemShare.SharePreviewMode.DEFAULT
      });
    } catch (_error) {
      return;
    }
  }

  private closeSnapshot(): void {
    this.pageSnapshot = undefined;
    this.pageDisplayState = {
      fontSize: this.pageDisplayState.fontSize,
      readerMode: this.pageDisplayState.readerMode,
      translated: this.pageDisplayState.translated,
      fullScreen: false
    };
    this.rememberTabViewState();
  }

  private async addActiveBookmark(): Promise<void> {
    const tab: BrowserTabRecord | undefined = this.activeTab();
    if (tab === undefined || tab.isPrivate) {
      return;
    }
    const repository: BrowserRepository | undefined = this.repository;
    if (repository === undefined) {
      return;
    }
    const record: BookmarkRecord | undefined = bookmarkRecordForPage(
      lastValidUrlForTab(tab),
      tab.title,
      Date.now()
    );
    if (record === undefined) {
      return;
    }
    const before: BookmarkRecord[] = await repository.listBookmarks();
    if (before.some((item: BookmarkRecord) => item.url === record.url)) {
      return;
    }
    await repository.addBookmark(record, false);
    this.bookmarkItems = await repository.listBookmarks();
  }

  private applyUserAgentMode(
    tabId: TabId,
    controller: webview.WebviewController,
    reload: boolean
  ): boolean {
    const controllerKey: string = `${tabId}:${this.runtimePort?.controllerIdFor(tabId) ?? ''}`;
    if (this.desktopAppliedControllerIds.has(controllerKey)) {
      return true;
    }
    try {
      const desktopUserAgent: string = desktopUserAgentFor(controller.getUserAgent());
      if (desktopUserAgent.length === 0) {
        return false;
      }
      const tab: BrowserTabRecord | undefined = this.tabStore.tabs.find(
        (item: BrowserTabRecord) => item.id === tabId
      );
      if (tab === undefined) {
        return false;
      }
      if (this.desktopModeByTab.get(tabId) === true) {
        let mobileUserAgent: string | undefined = this.mobileUserAgentByTab.get(tabId);
        if (mobileUserAgent === undefined) {
          mobileUserAgent = controller.getUserAgent().trim();
          if (mobileUserAgent.length > 0) {
            this.mobileUserAgentByTab.set(tabId, mobileUserAgent);
          }
        }
        const desktopUserAgent: string = desktopUserAgentFor(mobileUserAgent ?? '');
        if (desktopUserAgent.length === 0) {
          return false;
        }
        controller.setCustomUserAgent(desktopUserAgent);
      } else {
        // Restoring the exact UA observed before the first desktop switch
        // keeps the device's real phone identity instead of guessing a new
        // mobile string or leaving the desktop UA latched on the tab.
        controller.setCustomUserAgent(this.mobileUserAgentByTab.get(tabId) ?? '');
      }
      if (reload) {
        controller.loadUrl(lastValidUrlForTab(tab));
      }
      this.desktopAppliedControllerIds.add(controllerKey);
      return true;
    } catch (_error) {
      return false;
    }
  }

  private togglePageMode(): void {
    const tab: BrowserTabRecord | undefined = this.activeTab();
    if (tab === undefined || tab.isPrivate || lastValidUrlForTab(tab) === 'about:blank') {
      return;
    }
    const controller: webview.WebviewController | undefined = this.runtimePort?.controllerFor(tab.id);
    if (controller === undefined) {
      return;
    }
    const canonicalUrl: string = lastValidUrlForTab(tab);
    const wasDesktop: boolean = this.desktopModeByTab.get(tab.id) === true;
    if (!wasDesktop && this.mobileUserAgentByTab.get(tab.id) === undefined) {
      try {
        const mobileUserAgent: string = controller.getUserAgent().trim();
        if (mobileUserAgent.length > 0) {
          this.mobileUserAgentByTab.set(tab.id, mobileUserAgent);
        }
      } catch (_error) {
        return;
      }
    }
    try {
      this.desktopModeByTab.set(tab.id, !wasDesktop);
      const controllerKey: string = `${tab.id}:${this.runtimePort?.controllerIdFor(tab.id) ?? ''}`;
      this.desktopAppliedControllerIds.delete(controllerKey);
      if (!this.applyUserAgentMode(tab.id, controller, false)) {
        if (wasDesktop) {
          this.desktopModeByTab.set(tab.id, true);
        } else {
          this.desktopModeByTab.delete(tab.id);
        }
        return;
      }
      this.pageReady = false;
      this.pageReadyByTab.set(tab.id, false);
      controller.loadUrl(canonicalUrl);
    } catch (_error) {
      this.desktopModeByTab.set(tab.id, wasDesktop);
    }
  }

  private async capturePageForAction(): Promise<void> {
    const activeTabId: TabId = this.tabStore.activeTabId;
    let pixel: image.PixelMap | undefined = await this.captureMountedSnapshot(activeTabId);
    if (pixel === undefined) {
      const tab: BrowserTabRecord | undefined = this.activeTab();
      const controller: webview.WebviewController | undefined = tab === undefined
        ? undefined
        : this.runtimePort?.controllerFor(tab.id);
      if (tab !== undefined && controller !== undefined) {
        pixel = await this.captureArkWebSnapshot(tab.id, controller);
      }
    }
    this.pageSnapshot = pixel;
    this.pageDisplayState = {
      fontSize: this.pageDisplayState.fontSize,
      readerMode: this.pageDisplayState.readerMode,
      translated: this.pageDisplayState.translated,
      // A screenshot is an overlay action; it must not put the Web component
      // into full-screen mode or hide the browser chrome on failure.
      fullScreen: this.pageDisplayState.fullScreen
    };
  }

  private customizeStartPage(): void {
    this.startPageCustomizeDismissProgress = 0;
    this.startPageCustomizeDismissRequested = false;
    this.showStartPageCustomize = true;
    this.showLibrary = false;
    this.closeDownloadManager();
  }

  private beginStartPageCustomizeDismissAnimation(): void {
    if (this.startPageCustomizeDismissRequested) {
      return;
    }
    this.startPageCustomizeDismissRequested = true;
    this.getUIContext().animateTo({
      curve: curves.springMotion(
        START_PAGE_CUSTOMIZE_DISMISS_SPRING_RESPONSE,
        START_PAGE_CUSTOMIZE_DISMISS_SPRING_DAMPING,
        START_PAGE_CUSTOMIZE_DISMISS_SPRING_OVERLAP
      ),
      onFinish: () => {
        this.startPageCustomizeDismissProgress = 0;
      }
    }, () => {
      this.startPageCustomizeDismissProgress = 1;
    });
  }

  private closeStartPageCustomize(): void {
    if (!this.showStartPageCustomize) {
      return;
    }
    this.beginStartPageCustomizeDismissAnimation();
    this.showStartPageCustomize = false;
    this.startPageCustomizeDismissRequested = false;
  }

  private updateStartPageSettings(settings: BrowserSettings): void {
    this.browserSettings = copyBrowserSettings(settings);
    void this.repository?.saveSettings(this.browserSettings);
  }

  private async chooseStartPageBackground(): Promise<void> {
    const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    try {
      const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      const result: photoAccessHelper.PhotoSelectResult = await picker.select(options);
      const selectedUri: string = result.photoUris[0] ?? '';
      if (selectedUri.trim().length === 0) {
        hilog.info(BROWSER_WEB_DOMAIN, BROWSER_WEB_TAG, 'start_page_background_picker_cancelled');
        return;
      }
      const next: BrowserSettings = copyBrowserSettings(this.browserSettings);
      next.startPageBackgroundId = selectedUri;
      this.updateStartPageSettings(next);
      hilog.info(BROWSER_WEB_DOMAIN, BROWSER_WEB_TAG,
        'start_page_background_selected uriLength=%{public}d', selectedUri.length);
    } catch (_error) {
      hilog.warn(BROWSER_WEB_DOMAIN, BROWSER_WEB_TAG, 'start_page_background_picker_failed');
    }
  }

  private updateStartPageItems(items: StartPageItem[]): void {
    this.startPageItems = items.map((item: StartPageItem) => copyStartPageItem(item));
    void this.repository?.saveStartPageItems(this.startPageItems);
  }

  private addActiveFavorite(): void {
    const tab: BrowserTabRecord | undefined = this.activeTab();
    if (tab === undefined || tab.isPrivate || tab.url === 'about:blank') {
      return;
    }
    if (this.startPageItems.some((item: StartPageItem) => item.type === StartPageItemType.FAVORITE && item.url === tab.url)) {
      return;
    }
    const item: StartPageItem = {
      id: `favorite-${Date.now()}`,
      type: StartPageItemType.FAVORITE,
      title: tab.title.length > 0 ? tab.title : tab.url,
      url: tab.url,
      order: this.startPageItems.filter((entry: StartPageItem) => entry.type === StartPageItemType.FAVORITE).length,
      updatedAt: Date.now()
    };
    this.startPageItems = [...this.startPageItems, item];
    void this.repository?.saveStartPageItems(this.startPageItems);
  }

  private async openLibrary(): Promise<void> {
    this.closeDownloadManager();
    const repository: BrowserRepository | undefined = this.repository;
    if (repository !== undefined) {
      this.historyItems = await repository.listHistory();
      this.bookmarkItems = await repository.listBookmarks();
    }
    this.showStartPageCustomize = false;
    this.showLibrary = true;
  }

  private closeLibrary(): void {
    this.showLibrary = false;
  }

  private async removeBookmark(url: string): Promise<void> {
    const repository: BrowserRepository | undefined = this.repository;
    if (repository === undefined) {
      return;
    }
    await repository.removeBookmark(url);
    this.bookmarkItems = await repository.listBookmarks();
  }

  private async removeHistory(url: string): Promise<void> {
    const repository: BrowserRepository | undefined = this.repository;
    if (repository === undefined) {
      return;
    }
    await repository.removeHistory(url);
    this.historyItems = await repository.listHistory();
    this.syncFrequentSites(this.historyItems);
  }

  private async removeHistoryRange(range: HistoryDeleteRange): Promise<void> {
    const repository: BrowserRepository | undefined = this.repository;
    if (repository === undefined) {
      return;
    }
    if (range === HistoryDeleteRange.ALL) {
      await repository.clearHistory();
    } else {
      const cutoff: number | undefined = historyDeleteCutoff(range, Date.now());
      if (cutoff === undefined) {
        return;
      }
      await repository.removeHistoryFrom(cutoff);
    }
    this.historyItems = await repository.listHistory();
    this.syncFrequentSites(this.historyItems);
  }

  private openLibraryEntry(url: string): void {
    this.showLibrary = false;
    this.showStartPageCustomize = false;
    this.closeDownloadManager();
    this.loadAddress(url, 'library-entry', 'openLibraryEntry');
  }

  private async closeAllTabs(): Promise<void> {
    const tabs: BrowserTabRecord[] = this.tabStore.tabs.slice();
    for (const tab of tabs) {
      if (!tab.isPrivate && tab.url !== 'about:blank') {
        this.closedTabStack.push(closedTabFromRecord(tab, Date.now()));
      }
      await this.dispatcher?.closeTab(tab.id);
      this.removeTabViewState(tab.id);
    }
    this.attachCurrentHosts();
    this.resetTabViewState(this.tabStore.activeTabId);
    this.bumpTabStateRevision();
    await this.repository?.saveClosedTabs(this.closedTabStack.snapshot());
  }

  /** Close every tab from the overview and return to the replacement blank tab. */
  private async closeAllTabsFromOverview(): Promise<void> {
    await this.closeAllTabs();
    this.closeTabOverview();
  }

  private async reopenClosedTab(): Promise<void> {
    const record = this.closedTabStack.pop();
    if (record === undefined || this.dispatcher === undefined) {
      return;
    }
    const id: TabId = await this.dispatcher.createTab(record.url, false);
    this.tabStore.updateTabUrl(id, record.url, record.title, 'url');
    this.resetTabViewState(id);
    this.logLoadUrl(record.url, 'reopen-closed-tab', 'reopenClosedTab', true, id);
    this.attachCurrentHosts();
    this.bumpTabStateRevision();
    await this.repository?.saveSession(this.tabStore.snapshot());
    await this.repository?.saveClosedTabs(this.closedTabStack.snapshot());
  }

  private toggleTabOverview(): void {
    if (this.overviewProgress > 0) {
      this.closeTabOverview();
      return;
    }
    this.openTabOverview();
  }

  private openTabOverview(releaseVelocityY: number = 0): void {
    // An upward bar swipe mounts the overview at an interactive progress
    // between 0 and 1. Only a settled overview should short-circuit here;
    // otherwise the panel remains translucent at the release position.
    if (isOverviewSettled(this.overviewProgress)) {
      return;
    }
    this.overviewSearchProgress = 0;
    this.overviewClosing = false;
    this.rememberTabViewState();
    const currentIndex: number = this.activeTabIndex();
    const currentTabId: TabId = this.tabStore.activeTabId;
    const currentUrl: string = this.activeAddress();
    this.overviewVisualTabId = currentTabId;

    // A tab button tap must terminate an in-flight strip animation before the
    // overview starts.  No settling state is allowed to leak into the sheet.
    this.addressTransitionToken += 1;
    this.addressGestureFinished = true;
    this.addressGestureEngine.cancel();
    this.pendingTabDraft = undefined;
    this.gestureActive = false;
    this.overviewEntryAnimation = this.overviewProgress <= 0;
    this.resetTabGestureMotion(false);
    this.logTabOverview(
      true,
      currentIndex,
      currentIndex,
      currentTabId,
      currentUrl,
      currentUrl,
      currentTabId,
      false,
      this.thumbnailFor(currentTabId) !== undefined,
      'overview-opened-existing-tabs'
    );
    this.requestTabSnapshots();
    this.settleOverview(1, () => {
      this.overviewEntryAnimation = false;
    }, BROWSER_OVERVIEW_TRANSITION_DURATION_MS, releaseVelocityY);
  }

  private reattachTabController(tabId: TabId, caller: string): boolean {
    const savedUrl: string = this.urlForTab(tabId);
    const validation = validateBrowserUrl(savedUrl);
    if (!validation.valid) {
      this.logRejectedLifecycleUrl(tabId, savedUrl, 'about:blank', caller);
      return false;
    }
    let controller: webview.WebviewController | undefined = this.runtimePort?.controllerFor(tabId);
    let recoveredFromSavedUrl: boolean = false;
    if (controller === undefined) {
      // The pool may have been trimmed by a lifecycle callback. Recreate this
      // tab from its own saved URL; never substitute the search-engine home.
      this.runtimePort?.ensureTab(tabId);
      controller = this.runtimePort?.controllerFor(tabId);
      recoveredFromSavedUrl = controller !== undefined;
      this.logLoadUrl(
        savedUrl,
        recoveredFromSavedUrl ? 'tab-url-fallback-controller-unavailable' : 'tab-url-recovery-unavailable',
        caller,
        false,
        tabId,
        this.runtimePort?.controllerIdFor(tabId) ?? '',
        '',
        recoveredFromSavedUrl ? 'web-src-recovered-from-last-valid-url' : 'restore-controller-unavailable'
      );
    }
    if (controller === undefined) {
      return false;
    }
    this.applyUserAgentMode(tabId, controller, true);
    let active: boolean = false;
    try {
      controller.onActive();
      active = true;
    } catch (_error) {
      // The BuilderNode may still be publishing its frame. The scheduled
      // attach below retries without replacing the controller.
    }
    this.scheduleHostReattach(tabId);
    this.logBrowserLifecycle(
      'webview_reattach',
      tabId,
      savedUrl,
      0,
      true,
      '',
      savedUrl,
      recoveredFromSavedUrl ? 'reattached-from-last-valid-url' : 'reattached-existing-controller'
    );
    return active;
  }

  private closeTabOverview(): void {
    if (this.overviewProgress <= 0) {
      // A second bubbled close request can arrive after the target progress
      // has been published but before the reverse animation finishes. Do not
      // clear the animation flags in that window.
      if (!this.overviewClosing) {
        this.overviewAnimationClosing = false;
      }
      return;
    }
    const currentIndexBefore: number = this.activeTabIndex();
    const currentUrlBefore: string = this.activeAddress();
    const selectedTabId: TabId = this.overviewVisualTabIdForRender();
    this.addressTransitionToken += 1;
    this.addressGestureFinished = true;
    this.addressGestureEngine.cancel();
    this.gestureActive = false;
    this.resetTabGestureMotion(false);
    this.overviewClosing = true;
    this.settleOverview(0, () => {
      this.overviewEntryAnimation = false;
      this.overviewSearchProgress = 0;
      this.overviewClosing = false;
      this.overviewAnimationClosing = false;
      // Keep the selected card as the visual scene until the reverse spring
      // has finished. Committing TabStore here would publish a new page and a
      // new address capsule one render turn before the shared morph ends.
      const targetTabId: TabId = this.tabStore.tabs.some(
        (tab: BrowserTabRecord) => tab.id === selectedTabId
      ) ? selectedTabId : this.tabStore.activeTabId;
      this.restoreTabViewState(targetTabId);
      const webViewReattached: boolean = this.reattachTabControllerIfMissing(
        targetTabId,
        'closeTabOverview'
      );
      this.attachHostIfMissing(targetTabId);
      const pageSnapshotRestored: boolean = this.thumbnailFor(targetTabId) !== undefined;
      void this.finishOverviewClose(
        targetTabId,
        currentIndexBefore,
        currentUrlBefore,
        webViewReattached,
        pageSnapshotRestored
      );
    }, BROWSER_OVERVIEW_TRANSITION_DURATION_MS);
  }

  /**
   * Commit the selected overview card only after its reverse morph has
   * reached the full-page origin. The scene remains on targetTabId while the
   * asynchronous dispatcher update settles, so the last frame cannot flash
   * back to the previously active page.
   */
  private async finishOverviewClose(
    targetTabId: TabId,
    currentIndexBefore: number,
    currentUrlBefore: string,
    webViewReattached: boolean,
    pageSnapshotRestored: boolean
  ): Promise<void> {
    if (this.dispatcher === undefined) {
      this.overviewVisualTabId = '';
      this.bumpTabStateRevision();
      return;
    }
    if (this.tabStore.activeTabId !== targetTabId) {
      await this.dispatcher.activateTab(targetTabId);
    }
    this.sceneActiveTabId = targetTabId;
    this.sceneTabs = this.tabStore.tabs.slice();
    this.sceneActiveTab = this.tabStore.tabs.find(
      (tab: BrowserTabRecord) => tab.id === targetTabId
    );
    this.restoreTabViewState(targetTabId);
    this.resetAddressDraft();
    this.refreshNavigationState();
    this.gestureActive = false;
    this.overviewVisualTabId = '';
    this.bumpTabStateRevision();
    this.logTabOverview(
      false,
      currentIndexBefore,
      this.activeTabIndex(),
      targetTabId,
      currentUrlBefore,
      this.activeAddress(),
      targetTabId,
      webViewReattached,
      pageSnapshotRestored,
      webViewReattached ? 'overview-closed-selected-tab-recovered' : 'overview-closed-selected-tab'
    );
  }

  /**
   * Keep the tab overview mounted while a new start tab is being created. The
   * old implementation dismissed the overview immediately, racing the
   * runtime attach and leaving the newly-created tab non-interactive. A token
   * lets a pull-down/back gesture interrupt that pending transition safely.
   */
  private async createNewTabFromOverview(isPrivate: boolean): Promise<void> {
    const token: number = this.overviewTabRequestToken + 1;
    this.overviewTabRequestToken = token;
    if (shouldDismissOverviewBeforeCreatingTab(this.overviewProgress)) {
      this.closeTabOverview();
      await new Promise<void>((resolve: () => void) => {
        setTimeout(() => resolve(), BROWSER_OVERVIEW_TRANSITION_DURATION_MS);
      });
      if (token !== this.overviewTabRequestToken) {
        return;
      }
    }
    if (isPrivate) {
      await this.onNewPrivateTab();
    } else {
      await this.onNewTab();
    }
  }

  private dismissOverview(): void {
    this.overviewTabRequestToken += 1;
    this.closeTabOverview();
  }

  /**
   * Consume system back while an app-owned overlay is visible. Sheets close
   * first, then the multi-page overview is dismissed; normal web navigation
   * still falls through to the page/ability default behavior.
   */
  private onSystemBackPress(): boolean {
    hilog.info(
      BROWSER_WEB_DOMAIN,
      BROWSER_WEB_TAG,
      'event=system_back overview=%{public}d library=%{public}s downloads=%{public}s pageBack=%{public}s',
      this.overviewProgress,
      this.showLibrary ? 'true' : 'false',
      this.showDownloadManager ? 'true' : 'false',
      this.canNavigateBack ? 'true' : 'false'
    );
    if (this.showDownloadManager) {
      this.closeDownloadManager();
      return true;
    }
    if (this.barMode !== 'collapsed' || this.inputExpandProgress > 0) {
      this.closeAddressEditor();
      return true;
    }
    if (this.showStartPageCustomize) {
      this.closeStartPageCustomize();
      return true;
    }
    if (this.showLibrary) {
      this.closeLibrary();
      return true;
    }
    if (this.overviewProgress <= 0) {
      if (this.canNavigateBack && (this.dispatcher?.goBack() ?? false)) {
        this.refreshNavigationState();
        return true;
      }
      return false;
    }
    this.gestureActive = false;
    this.addressGestureFinished = true;
    this.addressGestureEngine.cancel();
    this.closeTabOverview();
    return true;
  }

  /** Keep only explicit favorites on the start page; history is library-only. */
  private syncFrequentSites(_history: HistoryRecord[]): void {
    const favorites: StartPageItem[] = this.startPageItems
      .filter((item: StartPageItem) => item.type === StartPageItemType.FAVORITE)
      .map((item: StartPageItem, index: number): StartPageItem => ({
        id: item.id,
        type: item.type,
        title: item.title,
        url: item.url,
        order: index,
        updatedAt: item.updatedAt
      }));
    this.startPageItems = favorites;
    void this.repository?.saveStartPageItems(this.startPageItems);
  }

  private onReload(): void {
    this.dispatcher?.reloadActiveTab();
  }

  private thumbnailFor(tabId: TabId): image.PixelMap | undefined {
    const cached: image.PixelMap | undefined = this.thumbnails.get(tabId);
    if (cached !== undefined) {
      return cached;
    }
    const tab: BrowserTabRecord | undefined = this.tabStore.tabs.find(
      (item: BrowserTabRecord) => item.id === tabId
    );
    // All blank start tabs share the real native start-page snapshot. This
    // avoids showing a synthetic placeholder while a newly-created tab is
    // waiting for its first capture.
    return tab?.url === 'about:blank' ? this.startPageThumbnail : undefined;
  }

  private scheduleSnapshot(tabId: TabId, controller: webview.WebviewController): void {
    if (this.gestureActive) {
      return;
    }
    const tab: BrowserTabRecord | undefined = this.tabStore.tabs.find((item: BrowserTabRecord) => item.id === tabId);
    if (tab !== undefined && this.tabStore.activeTabId === tabId) {
      void this.recordPageVisit(tab);
    }
    const generation: number = (this.snapshotGenerations.get(tabId) ?? 0) + 1;
    this.snapshotGenerations.set(tabId, generation);
    setTimeout(() => {
      if (this.snapshotGenerations.get(tabId) !== generation || this.gestureActive) {
        return;
      }
      void this.captureTabSnapshot(tabId, controller, generation);
    }, 80);
  }

  private async recordPageVisit(tab: BrowserTabRecord): Promise<void> {
    const repository: BrowserRepository | undefined = this.repository;
    if (repository === undefined || tab.isPrivate || tab.url === 'about:blank') {
      return;
    }
    await repository.recordHistory({
      url: tab.url,
      title: tab.title.length > 0 ? tab.title : tab.url,
      visitedAt: Date.now()
    }, false);
    this.historyItems = await repository.listHistory();
    this.syncFrequentSites(this.historyItems);
  }

  private async captureMountedSnapshot(tabId: TabId): Promise<image.PixelMap | undefined> {
    const snapshot = this.getUIContext().getComponentSnapshot();
    try {
      // BrowserTransitionScene owns the live Web node now. The previous
      // single-host id is retained as a compatibility fallback for a frame
      // that is still completing its native-tree migration.
      return await snapshot.get(`native-tab-web-${tabId}`, {
        scale: 1,
        waitUntilRenderFinished: false
      });
    } catch (_error) {
      try {
        return await snapshot.get('web-tab-host', {
          scale: 1,
          waitUntilRenderFinished: false
        });
      } catch (_fallbackError) {
        return undefined;
      }
    }
  }

  private async captureStartPageSnapshot(): Promise<image.PixelMap | undefined> {
    try {
      return await this.getUIContext().getComponentSnapshot().get('start-page', {
        scale: 1,
        waitUntilRenderFinished: false
      });
    } catch (_error) {
      // The start page is hosted inside BrowserTransitionScene. On the first
      // frame after launch its nested id may not be available to the snapshot
      // service yet; capture the already-mounted native scene instead of
      // dropping the shared hero track for the first overview entry.
      try {
        return await this.getUIContext().getComponentSnapshot().get('transition-current-page-scene', {
          scale: 1,
          waitUntilRenderFinished: false
        });
      } catch (_fallbackError) {
        return undefined;
      }
    }
  }

  private scheduleStartPageThumbnail(tabId: TabId): void {
    setTimeout(() => {
      if (this.gestureActive || this.tabStore.activeTabId !== tabId) {
        return;
      }
      const tab: BrowserTabRecord | undefined = this.tabStore.tabs.find((item: BrowserTabRecord) => item.id === tabId);
      const controller: webview.WebviewController | undefined = this.runtimePort?.controllerFor(tabId);
      if (tab === undefined || tab.url !== 'about:blank') {
        return;
      }
      if (controller === undefined) {
        void this.captureStartPageThumbnail(tabId);
        return;
      }
      const generation: number = (this.snapshotGenerations.get(tabId) ?? 0) + 1;
      this.snapshotGenerations.set(tabId, generation);
      void this.captureTabSnapshot(tabId, controller, generation);
    }, 120);
  }

  private async captureArkWebSnapshot(
    tabId: TabId,
    controller: webview.WebviewController
  ): Promise<image.PixelMap | undefined> {
    return await new Promise<image.PixelMap | undefined>((resolve: (value: image.PixelMap | undefined) => void) => {
      try {
        controller.webPageSnapshot({
          id: `tab-${tabId}`,
          size: { width: 720, height: 720 }
        }, (error, result) => {
          if (error || result === undefined || result.status !== true || result.imagePixelMap === undefined) {
            resolve(undefined);
            return;
          }
          resolve(result.imagePixelMap);
        });
      } catch (_error) {
        resolve(undefined);
      }
    });
  }

  private async encodeSnapshot(pixel: image.PixelMap): Promise<Uint8Array | undefined> {
    try {
      const packer = image.createImagePacker();
      const encoded: ArrayBuffer = await packer.packToData(pixel, {
        format: 'image/jpeg',
        quality: 80
      });
      return new Uint8Array(encoded);
    } catch (_error) {
      return undefined;
    }
  }

  private async captureTabSnapshot(
    tabId: TabId,
    controller: webview.WebviewController,
    generation: number,
    attempt: number = 0
  ): Promise<void> {
    if (this.snapshotInFlight.has(tabId) || this.gestureActive ||
      this.snapshotGenerations.get(tabId) !== generation) {
      return;
    }
    const tab: BrowserTabRecord | undefined = this.tabStore.tabs.find((item: BrowserTabRecord) => item.id === tabId);
    if (tab === undefined) {
      return;
    }
    this.snapshotInFlight.add(tabId);
    // A capture started before the finger moved represents a stable page
    // frame. It is safe to publish that frame even if the gesture becomes
    // active while ArkWeb finishes its asynchronous snapshot callback.
    const startedBeforeGesture: boolean = !this.gestureActive;
    try {
      let pixel: image.PixelMap | undefined;
      if (this.tabStore.activeTabId === tabId) {
        pixel = tab.url === 'about:blank'
          ? await this.captureStartPageSnapshot()
          : await this.captureMountedSnapshot(tabId);
      }
      if (pixel === undefined && tab.url === 'about:blank' && this.startPageThumbnail !== undefined) {
        pixel = this.startPageThumbnail;
      }
      if (pixel === undefined && !this.gestureActive) {
        pixel = await this.captureArkWebSnapshot(tabId, controller);
      }
      if (pixel === undefined) {
        if (shouldRetryTabSnapshot(true, attempt) && !this.gestureActive &&
          this.snapshotGenerations.get(tabId) === generation) {
          const delay: number = TAB_SNAPSHOT_RETRY_DELAYS_MS[attempt] ?? 640;
          setTimeout(() => {
            if (!this.gestureActive && this.snapshotGenerations.get(tabId) === generation) {
              void this.captureTabSnapshot(tabId, controller, generation, attempt + 1);
            }
          }, delay);
        }
        return;
      }
      if ((this.gestureActive && !startedBeforeGesture) ||
        this.snapshotGenerations.get(tabId) !== generation) {
        return;
      }
      const encoded: Uint8Array | undefined = await this.encodeSnapshot(pixel);
      if (encoded === undefined || (this.gestureActive && !startedBeforeGesture) ||
        this.snapshotGenerations.get(tabId) !== generation) {
        return;
      }
      const stored: boolean = await this.snapshotCache.capture(
        tabId,
        tab.isPrivate,
        async () => encoded
      );
      if (stored && (!this.gestureActive || startedBeforeGesture)) {
        this.thumbnails.set(tabId, pixel);
        if (tab.url === 'about:blank') {
          this.startPageThumbnail = pixel;
        }
        this.tabStore.updateThumbnailKey(tabId, `thumbnail-${tabId}`);
        this.cardRevision += 1;
      }
    } finally {
      this.snapshotInFlight.delete(tabId);
    }
  }

  /** Capture the native blank-tab page even when that tab has no ArkWeb host. */
  private async captureStartPageThumbnail(tabId: TabId): Promise<void> {
    if (this.gestureActive || this.tabStore.activeTabId !== tabId) {
      return;
    }
    const pixel: image.PixelMap | undefined = await this.captureStartPageSnapshot();
    if (pixel === undefined || this.gestureActive || this.tabStore.activeTabId !== tabId) {
      return;
    }
    this.startPageThumbnail = pixel;
    this.thumbnails.set(tabId, pixel);
    this.tabStore.updateThumbnailKey(tabId, `thumbnail-${tabId}`);
    this.cardRevision += 1;
  }

  private requestTabSnapshots(): void {
    if (this.gestureActive) {
      return;
    }
    for (const tab of this.tabStore.tabs) {
      const controller: webview.WebviewController | undefined = this.runtimePort?.controllerFor(tab.id);
      if (controller === undefined) {
        if (tab.id === this.tabStore.activeTabId && tab.url === 'about:blank') {
          void this.captureStartPageThumbnail(tab.id);
        }
        continue;
      }
      const generation: number = (this.snapshotGenerations.get(tab.id) ?? 0) + 1;
      this.snapshotGenerations.set(tab.id, generation);
      void this.captureTabSnapshot(tab.id, controller, generation);
    }
  }

  private cardProgressFor(tabId: TabId): number {
    return this.cardProgress.get(tabId) ?? 0;
  }

  private cardOffsetFor(tabId: TabId): number {
    return this.cardOffsets.get(tabId) ?? 0;
  }

  private cardHorizontalOffsetFor(tabId: TabId): number {
    return this.cardHorizontalOffsets.get(tabId) ?? 0;
  }

  private cardWidth(): number {
    return tabOverviewCardWidth(this.viewportWidth);
  }

  private cardEngineFor(tabId: TabId): GestureDecisionEngine {
    const existing: GestureDecisionEngine | undefined = this.cardEngines.get(tabId);
    if (existing !== undefined) {
      return existing;
    }
    const created: GestureDecisionEngine = new GestureDecisionEngine();
    this.cardEngines.set(tabId, created);
    return created;
  }

  private beginCardClose(tabId: TabId): void {
    if (this.closingCards.has(tabId) || this.reorderingCards.has(tabId)) {
      return;
    }
    this.cardFinished.delete(tabId);
    this.cardEngineFor(tabId).begin();
    this.cardProgress.set(tabId, 0);
    this.cardOffsets.set(tabId, 0);
    this.cardHorizontalOffsets.set(tabId, 0);
    this.cardRevision += 1;
  }

  private updateCardClose(tabId: TabId, sample: GestureSample): void {
    if (this.closingCards.has(tabId) || this.reorderingCards.has(tabId) || this.cardFinished.has(tabId)) {
      return;
    }
    const decision: GestureDecision = this.cardEngineFor(tabId).updateCardClose(sample, this.cardWidth());
    this.cardProgress.set(tabId, decision.progress);
    this.cardHorizontalOffsets.set(tabId, decision.visualOffset);
    this.cardOffsets.set(tabId, 0);
    this.cardRevision += 1;
  }

  private settleCardToOrigin(tabId: TabId): void {
    this.getUIContext().animateTo({
      duration: DEFAULT_GESTURE_PROFILE.settleDurationMs,
      curve: Curve.Friction
    }, () => {
      this.cardProgress.set(tabId, 0);
      this.cardOffsets.set(tabId, 0);
      this.cardHorizontalOffsets.set(tabId, 0);
      this.cardRevision += 1;
    });
  }

  private triggerLightHapticOnce(tabId: TabId): void {
    if (this.hapticTriggered.has(tabId)) {
      return;
    }
    // Haptic permission and device support are optional in this MVP. Keeping
    // this one-shot boundary means a later vibrator adapter cannot run once
    // per update frame or turn a successful close into an error.
    this.hapticTriggered.add(tabId);
  }

  private animateCardClosed(tabId: TabId): void {
    this.getUIContext().animateTo({
      duration: DEFAULT_GESTURE_PROFILE.settleDurationMs,
      curve: Curve.Friction
    }, () => {
      this.cardProgress.set(tabId, 1);
      this.cardOffsets.set(tabId, 0);
      this.cardHorizontalOffsets.set(tabId, -this.cardWidth());
      this.cardRevision += 1;
    });
  }

  private async commitCardClose(tabId: TabId): Promise<void> {
    if (this.closingCards.has(tabId)) {
      return;
    }
    this.closingCards.add(tabId);
    try {
      const closingTab: BrowserTabRecord | undefined = this.tabStore.tabs.find((tab: BrowserTabRecord) => tab.id === tabId);
      if (closingTab !== undefined && !closingTab.isPrivate && closingTab.url !== 'about:blank') {
        this.closedTabStack.push(closedTabFromRecord(closingTab, Date.now()));
      }
      await new Promise<void>((resolve: () => void) => {
        setTimeout(() => resolve(), DEFAULT_GESTURE_PROFILE.settleDurationMs);
      });
      await this.snapshotCache.remove(tabId);
      this.thumbnails.delete(tabId);
      this.snapshotGenerations.delete(tabId);
      if (this.dispatcher !== undefined) {
        await this.dispatcher.closeTab(tabId);
        this.removeTabViewState(tabId);
        this.attachCurrentHosts();
        this.bumpTabStateRevision();
      }
      await this.repository?.saveClosedTabs(this.closedTabStack.snapshot());
      this.cardProgress.delete(tabId);
      this.cardOffsets.delete(tabId);
      this.cardHorizontalOffsets.delete(tabId);
      this.cardEngines.delete(tabId);
      this.cardFinished.delete(tabId);
      this.reorderingCards.delete(tabId);
      this.cardRevision += 1;
    } finally {
      this.closingCards.delete(tabId);
    }
  }

  private finishCardClose(tabId: TabId, sample: GestureSample): void {
    if (this.cardFinished.has(tabId) || this.closingCards.has(tabId) || this.reorderingCards.has(tabId)) {
      return;
    }
    this.cardFinished.add(tabId);
    const decision: GestureDecision = this.cardEngineFor(tabId).endCardClose(sample, this.cardWidth());
    if (decision.outcome === GestureOutcome.CLOSE_TAB) {
      this.triggerLightHapticOnce(tabId);
      this.animateCardClosed(tabId);
      void this.commitCardClose(tabId);
      return;
    }
    this.settleCardToOrigin(tabId);
  }

  private cancelCardClose(tabId: TabId): void {
    if (this.cardFinished.has(tabId) || this.closingCards.has(tabId) || this.reorderingCards.has(tabId)) {
      return;
    }
    this.cardFinished.add(tabId);
    this.cardEngineFor(tabId).cancel();
    this.settleCardToOrigin(tabId);
  }

  private closeCardFromButton(tabId: TabId): void {
    // A cancelled pan marks the current gesture as finished, but that marker
    // must not disable the independent caption close button (or the native
    // long-press menu's “关闭此标签” action) when the overview is reopened.
    if (this.closingCards.has(tabId)) {
      return;
    }
    this.cardFinished.delete(tabId);
    this.cardFinished.add(tabId);
    this.triggerLightHapticOnce(tabId);
    this.animateCardClosed(tabId);
    void this.commitCardClose(tabId);
  }

  private openCard(tabId: TabId): void {
    if (this.closingCards.has(tabId) || this.dispatcher === undefined) {
      return;
    }
    const targetTab: BrowserTabRecord | undefined = this.tabStore.tabs.find(
      (tab: BrowserTabRecord) => tab.id === tabId
    );
    if (targetTab === undefined) {
      return;
    }
    const currentIndexBefore: number = this.activeTabIndex();
    const currentTabIdBefore: TabId = this.tabStore.activeTabId;
    const currentUrlBefore: string = this.activeAddress();
    this.rememberTabViewState();
    // Publish the selected card as the visual scene first. TabStore stays on
    // the committed tab until the reverse spring finishes, so the page,
    // address capsule, and toolbar can expand from one stable card entity.
    this.overviewVisualTabId = tabId;
    this.sceneActiveTabId = tabId;
    this.sceneTabs = this.tabStore.tabs.slice();
    this.sceneActiveTab = targetTab;
    this.restoreTabViewState(tabId);
    const webViewReattached: boolean = this.reattachTabControllerIfMissing(tabId, 'openCard');
    this.attachHostIfMissing(tabId);
    this.gestureActive = false;
    this.logTabSelection(
      currentIndexBefore,
      this.tabStore.tabs.findIndex((tab: BrowserTabRecord) => tab.id === tabId),
      currentTabIdBefore,
      currentUrlBefore,
      this.urlForTab(tabId),
      tabId,
      webViewReattached,
      webViewReattached ? 'overview-card-recovered-from-last-valid-url' : 'overview-card-controller-retained'
    );
    this.closeTabOverview();
  }

  private beginCardReorder(tabId: TabId): void {
    if (this.closingCards.has(tabId)) {
      return;
    }
    this.reorderingCards.add(tabId);
    this.cardProgress.set(tabId, 0);
    this.cardOffsets.set(tabId, 0);
    this.cardRevision += 1;
  }

  private reorderCard(tabId: TabId, targetIndex: number): void {
    if (!this.reorderingCards.has(tabId)) {
      return;
    }
    const fromIndex: number = this.tabStore.tabs.findIndex((tab: BrowserTabRecord) => tab.id === tabId);
    const moved: boolean = this.tabStore.reorder(fromIndex, targetIndex);
    this.reorderingCards.delete(tabId);
    if (moved) {
      this.attachCurrentHosts();
      this.bumpTabStateRevision();
      void this.repository?.saveSession(this.tabStore.snapshot());
    }
    this.cardRevision += 1;
  }

  private gestureSample(event?: GestureEvent): GestureSample {
    return {
      dx: event?.offsetX ?? 0,
      dy: event?.offsetY ?? 0,
      velocityX: event?.velocityX ?? 0,
      velocityY: event?.velocityY ?? 0
    };
  }

  private hasPreviousTab(): boolean {
    return this.tabStore.adjacentTabId(TabDirection.PREVIOUS) !== undefined;
  }

  private hasNextTab(): boolean {
    return this.tabStore.adjacentTabId(TabDirection.NEXT) !== undefined;
  }

  private updateViewport(width: number, height: number): void {
    const validWidth: boolean = Number.isFinite(width) && width > 0;
    const validHeight: boolean = Number.isFinite(height) && height > 0;
    const shouldRefresh: boolean = validWidth && shouldRefreshHostsForViewport(
      this.measuredHostViewportWidth,
      width,
      this.overviewProgress
    );
    if (validWidth && this.viewportWidth !== width) {
      this.viewportWidth = width;
      this.measuredHostViewportWidth = width;
    }
    if (validHeight && this.viewportHeight !== height) {
      this.viewportHeight = height;
    }
    // The first onAreaChange callback is the earliest point at which the
    // BuilderNode has a real frame. Re-attaching here repairs a host that was
    // created during the overview's unmount/remount window without releasing
    // the controller or interrupting the native transition.
    if (shouldRefresh) {
      this.attachCurrentHosts();
      const activeId: TabId = this.tabStore.activeTabId;
      setTimeout(() => {
        if (this.overviewProgress === 0 && this.tabStore.activeTabId === activeId) {
          this.attachCurrentHosts();
        }
      }, 0);
    }
  }

  private updateAddressBarWidth(_width: number): void {
    // The address bar is intentionally narrower than the Web viewport. Using
    // its measured floating width for tab translations leaves a visible
    // strip of the adjacent ArkWeb surface after a tab is created or opened.
    // The address strip owns the gesture geometry; keep this callback only for
    // component compatibility with the address editor.
  }

  private updateAddressStripRect(x: number, y: number, width: number, height: number): void {
    this.addressStripRectX = x;
    this.addressStripRectY = y;
    this.addressStripRectWidth = width;
    this.addressStripRectHeight = height;
  }

  private onAddressStripTouchStart(x: number, y: number, startInAddressStrip: boolean,
    owner: TouchOwner, buttonId: string): void {
    this.gestureStartX = x;
    this.gestureStartY = y;
    this.startInAddressStrip = startInAddressStrip;
    this.touchOwner = owner;
    this.touchButtonId = buttonId;
    this.touchHitTestMode = 'BLOCK_HIERARCHY';
    this.gestureStartIndex = this.activeTabIndex();
    if (!startInAddressStrip) {
      // Defensive branch for a bubbled/parent stream. The normal path is the
      // exact AddressTabStrip bounds, but an invalid start must be rejected
      // before DRAGGING can ever be entered.
      this.gestureState = TabGestureState.CANCELLING;
      this.logAddressGestureState('touch-rejected-outside-address-strip', false, true);
      this.gestureState = TabGestureState.IDLE;
      return;
    }
    this.logAddressGestureState('touch-start');
  }

  private logAddressGestureState(
    phase: string,
    commit: boolean = false,
    cancel: boolean = false,
    sample?: GestureSample
  ): void {
    const rawX: number = sample?.dx ?? this.rawDragX;
    const velocityX: number = sample?.velocityX ?? this.lastGestureVelocityX;
    const activeIndex: number = this.activeTabIndex();
    const frame = safariTransitionFrame(
      rawX,
      this.viewportWidth,
      this.addressItemStride(),
      activeIndex,
      this.tabStore.tabs.length
    );
    const pendingTabId: string = this.pendingTabDraft?.tab.id ?? '';
    const toolbarLocked: boolean = this.gestureActive || this.isDragging ||
      this.gestureState === TabGestureState.SETTLING ||
      this.gestureState === TabGestureState.COMMITTING ||
      this.gestureState === TabGestureState.CANCELLING;
    const asText = (value: number): string => value.toFixed(2);
    hilog.info(
      BROWSER_WEB_DOMAIN,
      BROWSER_WEB_TAG,
      'phase=%{public}s gestureStartX=%{public}s gestureStartY=%{public}s ' +
        'addressStripRect=%{public}s startInAddressStrip=%{public}s gestureState=%{public}s ' +
        'transitionToken=%{public}s rawDragX=%{public}s normalizedProgress=%{public}s ' +
        'activeIndex=%{public}s targetIndex=%{public}s previewKind=%{public}s pendingTabId=%{public}s ' +
        'currentPageX=%{public}s targetPageX=%{public}s currentAddressX=%{public}s targetAddressX=%{public}s ' +
        'toolbarLocked=%{public}s commit=%{public}s cancel=%{public}s tabsCount=%{public}s ' +
        'controllerId=%{public}s targetControllerId=%{public}s touchOwner=%{public}s hitTestMode=%{public}s ' +
        'buttonId=%{public}s pagePlus=%{public}s addressPlus=%{public}s velocityX=%{public}s',
      phase,
      asText(this.gestureStartX),
      asText(this.gestureStartY),
      `[${asText(this.addressStripRectX)},${asText(this.addressStripRectY)},${asText(this.addressStripRectWidth)},${asText(this.addressStripRectHeight)}]`,
      this.startInAddressStrip ? 'true' : 'false',
      String(this.gestureState),
      String(this.addressTransitionToken),
      asText(this.rawDragX),
      asText(rawX / Math.max(1, this.viewportWidth)),
      String(activeIndex),
      String(frame.targetIndex),
      String(this.previewKind),
      pendingTabId,
      asText(frame.currentPageX),
      asText(frame.targetPageX),
      asText(frame.currentAddressX),
      asText(frame.targetAddressX),
      toolbarLocked ? 'true' : 'false',
      commit ? 'true' : 'false',
      cancel ? 'true' : 'false',
      String(this.tabStore.tabs.length),
      this.runtimePort?.controllerIdFor(this.tabStore.activeTabId) ?? '',
      frame.previewKind === TabPreviewKind.EXISTING_TAB && this.previewIndex >= 0
        ? this.runtimePort?.controllerIdFor(this.tabStore.tabs[this.previewIndex]?.id ?? '') ?? ''
        : '',
      this.touchOwner,
      this.touchHitTestMode,
      this.touchButtonId,
      '0',
      frame.previewKind === TabPreviewKind.NEW_TAB && pendingTabId.length > 0 ? '1' : '0',
      asText(velocityX)
    );
  }

  private beginAddressGesture(startX: number = this.gestureStartX,
    startY: number = this.gestureStartY,
    startInAddressStrip: boolean = this.startInAddressStrip): void {
    this.gestureStartX = startX;
    this.gestureStartY = startY;
    this.startInAddressStrip = startInAddressStrip;
    if (this.addressHandoffProgress < 1) {
      this.logAddressGestureState('ignored-address-handoff', false, true);
      return;
    }
    hilog.info(BROWSER_WEB_DOMAIN, BROWSER_WEB_TAG,
      'bar-gesture-attempt mode=%{public}s progress=%{public}s focused=%{public}s active=%{public}s',
      this.barMode, this.inputExpandProgress.toFixed(2),
      this.addressInputFocused ? 'true' : 'false', this.gestureActive ? 'true' : 'false');
    if (!canStartAddressStripGesture(
      this.startInAddressStrip,
      this.barMode,
      this.inputExpandProgress,
      this.addressEditing
    )) {
      this.logAddressGestureState('ignored-outside-address-strip', false, true);
      return;
    }
    if (this.gestureActive || this.gestureState !== TabGestureState.IDLE) {
      return;
    }
    if (shouldPrimeFinalTabPreview(this.activeTabIndex(), this.tabStore.tabs.length) &&
      this.pendingTabDraft === undefined && this.dispatcher !== undefined) {
      this.pendingTabDraft = this.dispatcher.reserveTab('about:blank', false);
    }
    // Prime every existing tab while the current page is still stationary.
    // ArkWeb's webPageSnapshot callback is asynchronous; starting it only
    // after gestureActive=true makes the target preview miss its frame.
    this.requestTabSnapshots();
    this.gestureStartIndex = this.activeTabIndex();
    this.addressTransitionToken += 1;
    this.addressGestureEngine.begin();
    this.addressGestureFinished = false;
    this.gestureActive = true;
    this.gestureState = TabGestureState.DRAGGING;
    this.lastGestureVelocityX = 0;
    this.lastGestureDy = 0;
    this.resetTabGestureMotion(true);
    this.logAddressGestureState('start');
  }

  private updateAddressGesture(event?: GestureEvent): void {
    if (this.addressGestureFinished) {
      return;
    }
    const sample: GestureSample = this.gestureSample(event);
    this.lastGestureVelocityX = sample.velocityX;
    this.lastGestureDy = sample.dy;
    const decision: GestureDecision = this.addressGestureEngine.updateBottomBar(
      sample,
      this.viewportWidth,
      this.viewportHeight,
      this.hasPreviousTab(),
      this.hasNextTab()
    );
    if (decision.axis === GestureAxis.VERTICAL) {
      this.gestureState = TabGestureState.DRAGGING;
      this.overviewProgress = decision.progress;
      // The upward reveal is a vertical page-to-overview transition. Do not
      // carry diagonal finger drift into rawDragX: AddressTabStrip uses that
      // value for horizontal tab placement, which would make the capsule
      // slide sideways while it should stay pinned to the page bottom.
      this.applyTabGestureMotion(verticalOverviewGestureMotion());
    } else if (decision.axis === GestureAxis.HORIZONTAL) {
      this.gestureState = TabGestureState.DRAGGING;
      const motion: TabGestureMotionState = tabGestureMotion(
        sample.dx,
        this.viewportWidth,
        this.activeTabIndex(),
        this.tabStore.tabs.length
      );
      if (motion.previewKind === TabPreviewKind.NEW_TAB && this.pendingTabDraft === undefined) {
        this.pendingTabDraft = this.dispatcher?.reserveTab('about:blank', false);
      }
      this.applyTabGestureMotion(motion);
      this.overviewProgress = 0;
    }
    this.logAddressGestureState('update', false, false, sample);
  }

  private settleOverview(
    progress: number,
    onFinish: () => void = () => undefined,
    durationMs: number = BROWSER_OVERVIEW_TRANSITION_DURATION_MS,
    releaseVelocityY: number = 0
  ): void {
    if (progress > 0.5) {
      this.requestTabSnapshots();
    }
    const animationToken: number = this.overviewAnimationToken + 1;
    this.overviewAnimationToken = animationToken;
    this.cancelOverviewReleaseAnimation();
    // Drive the complete transform from one native frame timeline. The
    // interpolating-spring easing inherits the release velocity while the
    // shared progress value keeps the live page and overview grid together.
    this.overviewAnimationClosing = progress === 0;
    const finish: () => void = () => {
      if (animationToken !== this.overviewAnimationToken) {
        return;
      }
      this.overviewAnimationClosing = false;
      onFinish();
    };
    if (durationMs <= 0) {
      this.overviewProgress = progress;
      this.resetTabGestureMotion(false);
      finish();
      return;
    }
    const startProgress: number = Number.isFinite(this.overviewProgress)
      ? Math.max(0, Math.min(1, this.overviewProgress))
      : 0;
    const springEasing: string = tabOverviewSpringEasing(
      startProgress,
      progress,
      releaseVelocityY,
      this.viewportHeight
    );
    const startedAt: number = Date.now();
    const animator: AnimatorResult = this.getUIContext().createAnimator({
      duration: durationMs,
      easing: springEasing,
      delay: 0,
      fill: 'forwards',
      direction: 'normal',
      iterations: 1,
      begin: 0,
      end: 1
    });
    this.overviewReleaseAnimator = animator;
    animator.onFrame = (value: number) => {
      if (animationToken !== this.overviewAnimationToken ||
        this.overviewReleaseAnimator !== animator) {
        return;
      }
      // A spring curve may briefly evaluate outside [0, 1]. Keep the visual
      // track bounded so a fast release cannot expose a second overshoot.
      const normalized: number = Number.isFinite(value) ? value : 1;
      const bounded: number = Math.max(0, Math.min(1, normalized));
      const nextProgress: number = startProgress + (progress - startProgress) * bounded;
      this.overviewProgress = nextProgress;
      hilog.info(BROWSER_WEB_DOMAIN, BROWSER_WEB_TAG,
        'phase=overview-spring-frame elapsedMs=%{public}s progress=%{public}s target=%{public}s ' +
          'velocityY=%{public}s easing=%{public}s durationMs=%{public}s',
        String(Math.max(0, Date.now() - startedAt)), nextProgress.toFixed(3),
        progress.toFixed(3), releaseVelocityY.toFixed(2), springEasing, String(durationMs));
    };
    animator.onFinish = () => {
      if (animationToken !== this.overviewAnimationToken ||
        this.overviewReleaseAnimator !== animator) {
        return;
      }
      this.overviewReleaseAnimator = undefined;
      this.overviewProgress = progress;
      this.resetTabGestureMotion(false);
      finish();
    };
    animator.play();
  }

  private cancelOverviewReleaseAnimation(): void {
    const animator: AnimatorResult | undefined = this.overviewReleaseAnimator;
    this.overviewReleaseAnimator = undefined;
    if (animator !== undefined) {
      animator.finish();
    }
  }

  private updateOverviewSearchProgress(progress: number): void {
    if (!Number.isFinite(progress)) {
      this.overviewSearchProgress = 0;
      return;
    }
    this.overviewSearchProgress = Math.max(0, Math.min(1, progress));
  }

  private springBackAddressGesture(): void {
    const transitionToken: number = this.addressTransitionToken;
    const returnPreviewX: number = this.previewKind === TabPreviewKind.EXISTING_TAB
      ? (this.adjacentTranslateX < 0 ? -this.viewportWidth : this.viewportWidth)
      : (this.previewKind === TabPreviewKind.NEW_TAB ? this.viewportWidth : 0);
    this.gestureState = TabGestureState.CANCELLING;
    this.logAddressGestureState('spring-back', false, true);
    this.getUIContext().animateTo({
      curve: curves.springMotion(),
      onFinish: () => {
        if (isAddressTransitionCurrent(transitionToken, this.addressTransitionToken)) {
          // Restore the normal address layer before releasing the pending
          // record. This prevents a cancelled final-edge pull from exposing
          // an empty capsule for one frame.
          this.addressHandoffAnimationToken += 1;
          this.addressHandoffActive = false;
          this.addressHandoffProgress = 1;
          this.pendingTabDraft = undefined;
          this.addressTransitionToken += 1;
          this.resetTabGestureMotion(false);
          this.gestureActive = false;
          this.logAddressGestureState('cancel-complete', false, true);
        }
      }
    }, () => {
      // Keep both scenes mounted for the whole spring transaction. The
      // preview leaves the clipped viewport only when the animation finishes.
      this.rawDragX = 0;
      this.pageTranslateX = 0;
      this.adjacentTranslateX = returnPreviewX;
      this.transitionProgress = 0;
      this.isDragging = true;
      this.overviewProgress = 0;
    });
  }

  private async commitAdjacent(direction: TabDirection): Promise<void> {
    const transitionToken: number = this.addressTransitionToken;
    // Read the target before animation; the active index must not change mid-drag.
    const targetId: TabId | undefined = this.tabStore.adjacentTabId(direction);
    if (targetId === undefined || this.dispatcher === undefined) {
      this.springBackAddressGesture();
      return;
    }
    // A final-tab preview is only valid for the left edge action. Existing
    // neighbour commits must not retain its render-only draft.
    this.pendingTabDraft = undefined;
    this.gestureState = TabGestureState.COMMITTING;
    this.logAddressGestureState('commit-adjacent', true, false);
    const exitOffset: number = direction === TabDirection.PREVIOUS
      ? this.viewportWidth
      : -this.viewportWidth;
    this.getUIContext().animateTo({
      curve: curves.springMotion(),
      onFinish: () => {
        if (!isAddressTransitionCurrent(transitionToken, this.addressTransitionToken)) {
          return;
        }
        void this.completeAdjacentCommit(targetId, transitionToken);
      }
    }, () => {
      this.rawDragX = exitOffset;
      this.pageTranslateX = exitOffset;
      this.adjacentTranslateX = 0;
      this.transitionProgress = 1;
      this.overviewProgress = 0;
    });
    await Promise.resolve();
  }

  private async completeAdjacentCommit(targetId: TabId, transitionToken: number): Promise<void> {
    if (!isAddressTransitionCurrent(transitionToken, this.addressTransitionToken)) {
      return;
    }
    if (this.dispatcher === undefined) {
      return;
    }
    this.rememberTabViewState();
    await this.dispatcher.activateTab(targetId);
    if (!isAddressTransitionCurrent(transitionToken, this.addressTransitionToken)) {
      return;
    }
    hilog.info(
      BROWSER_WEB_DOMAIN,
      BROWSER_WEB_TAG,
      'tab-transition-commit targetId=%{public}s activeId=%{public}s activeIndex=%{public}s targetUrl=%{public}s',
      targetId,
      this.tabStore.activeTabId,
      String(this.activeTabIndex()),
      this.urlForTab(targetId)
    );
    // Rebase the stable page/address tracks while the settled target is still
    // mounted at the visible origin. The raw drag is reset before the preview
    // marker is cleared, so the target's derived offset remains zero.
    this.sceneActiveTabId = targetId;
    this.sceneTabs = this.tabStore.tabs.slice();
    this.sceneActiveTab = this.tabStore.tabs.find(
      (tab: BrowserTabRecord) => tab.id === targetId
    );
    this.rawDragX = 0;
    this.transitionProgress = 0;
    this.logAddressGestureState('rebase', true, false);
    this.restoreTabViewState(targetId);
    this.resetAddressDraft();
    this.refreshNavigationState();
    this.overviewProgress = 0;
    this.gestureActive = false;
    this.resetTabGestureMotion(false);
    this.requestTabSnapshots();
    this.bumpTabStateRevision();
  }

  private async finishAddressGesture(event?: GestureEvent): Promise<void> {
    if (this.addressGestureFinished) {
      return;
    }
    this.addressGestureFinished = true;
    this.gestureState = TabGestureState.SETTLING;
    const sample: GestureSample = event === undefined
      ? {
        dx: this.rawDragX,
        dy: this.lastGestureDy,
        velocityX: this.lastGestureVelocityX,
        velocityY: 0
      }
      : this.gestureSample(event);
    const decision: GestureDecision = this.addressGestureEngine.endBottomBar(
      sample,
      this.viewportWidth,
      this.viewportHeight,
      this.hasPreviousTab(),
      this.hasNextTab()
    );
    if (decision.axis === GestureAxis.HORIZONTAL) {
      const finalMotion: TabGestureMotionState = tabGestureMotion(
        sample.dx,
        this.viewportWidth,
        this.activeTabIndex(),
        this.tabStore.tabs.length
      );
      this.applyTabGestureMotion(finalMotion);
    }
    const committing: boolean = decision.outcome === GestureOutcome.PREVIOUS_TAB ||
      decision.outcome === GestureOutcome.NEXT_TAB ||
      decision.outcome === GestureOutcome.NEW_START_TAB;
    this.logAddressGestureState('settle', committing, !committing, sample);
    this.logAddressGestureState(`end-${String(decision.outcome)}`, committing, !committing, sample);
    if (decision.outcome === GestureOutcome.SHOW_OVERVIEW) {
      this.gestureActive = false;
      this.openTabOverview(sample.velocityY);
    } else if (decision.outcome === GestureOutcome.PREVIOUS_TAB) {
      await this.commitAdjacent(TabDirection.PREVIOUS);
    } else if (decision.outcome === GestureOutcome.NEXT_TAB) {
      await this.commitAdjacent(TabDirection.NEXT);
    } else if (decision.outcome === GestureOutcome.NEW_START_TAB) {
      await this.commitNewStartTabFromEdge();
    } else {
      this.springBackAddressGesture();
    }
  }

  private cancelAddressGesture(): void {
    if (this.addressGestureFinished && !this.isDragging) {
      return;
    }
    this.addressTransitionToken += 1;
    this.addressGestureFinished = true;
    this.addressGestureEngine.cancel();
    this.gestureState = TabGestureState.CANCELLING;
    this.logAddressGestureState('cancel', false, true);
    this.springBackAddressGesture();
  }

  private bottomBrowserBarHeight(): number {
    return SAFARI_BOTTOM_CHROME_BASE_HEIGHT_VP + Math.max(0, this.bottomAvoidInset);
  }

  private startPageCustomizeSqueezePhase(): number {
    const progress: number = Math.max(0, Math.min(1, this.startPageCustomizeDismissProgress));
    return Math.sin(Math.PI * progress);
  }

  private startPageCustomizeSqueezeScaleX(): number {
    return 1 + this.startPageCustomizeSqueezePhase() * 0.014;
  }

  private startPageCustomizeSqueezeScaleY(): number {
    return 1 - this.startPageCustomizeSqueezePhase() * 0.10;
  }

  private startPageCustomizeSqueezeTranslateY(): number {
    return (1 - this.startPageCustomizeSqueezeScaleY()) * this.bottomBrowserBarHeight() * 0.5;
  }

  private shouldRenderBottomBrowserBar(): boolean {
    return shouldMountBottomBrowserBar(this.pageDisplayState.fullScreen);
  }

  private overviewVisualTabIdForRender(): TabId {
    if (this.overviewVisualTabId.length > 0 && this.tabStore.tabs.some(
      (tab: BrowserTabRecord) => tab.id === this.overviewVisualTabId)) {
      return this.overviewVisualTabId;
    }
    return this.tabStore.activeTabId;
  }

  private overviewPageFrameForRender(): TabOverviewPageFrame {
    return tabOverviewPageFrame(
      this.overviewProgress,
      this.viewportWidth,
      this.viewportHeight,
      this.tabStore.tabs.findIndex((tab: BrowserTabRecord) =>
        tab.id === this.overviewVisualTabIdForRender()),
      this.topAvoidInset,
      this.overviewSearchProgress
    );
  }

  private overviewChromeFrameForRender(): TabOverviewChromeFrame {
    return tabOverviewChromeFrame(
      this.overviewProgress,
      this.overviewClosing || this.overviewAnimationClosing,
      this.viewportWidth,
      this.viewportHeight,
      this.bottomBrowserBarHeight(),
      this.overviewPageFrameForRender()
    );
  }

  @Builder
  private buildAddressTransitionLayer() {
    // At the settled overview endpoint the live page caption is the card's
    // address/title surface. Keep the shared strip mounted but transparent;
    // its stable identity is required when a short upward drag springs back
    // before the overview has fully opened.
    if (shouldMountAddressTransitionLayer(this.pageDisplayState.fullScreen)) {
      Stack() {
        AddressTabStrip({
        tabs: this.sceneTabs,
        pendingTab: this.pendingTabForRender(),
        activeIndex: this.sceneActiveTabIndex(),
        rawDragX: this.rawDragX,
        viewportWidth: this.viewportWidth,
        interactionLocked: this.overviewProgress > 0 || this.gestureActive || this.isDragging ||
          this.showStartPageCustomize || this.showLibrary || this.showDownloadManager,
        address: this.sceneAddress(),
        searchQuery: this.sceneSearchQuery(),
        addressDraft: this.draftForSceneTab(),
        isPrivate: this.sceneTabForRender()?.isPrivate ?? false,
        pageTitle: this.sceneActiveTab === undefined ? '' : this.sceneActiveTab.title,
        previewKind: this.previewKind,
        newTabProgress: this.newTabProgress,
        addressHandoffMounted: this.addressHandoffActive,
        addressHandoffProgress: this.addressHandoffProgress,
        inputExpandProgress: this.inputExpandProgress,
        barMode: this.barMode,
        addressEditing: this.addressEditing,
        inputMounted: this.addressInputMounted,
        activeInputIdentity: this.sceneInputIdentity(),
        addressInputFocusEnabled: this.addressInputFocusEnabled,
        inputFocusRequestToken: this.addressFocusRequestToken,
        selectedFontSize: this.pageDisplayState.fontSize,
        readerMode: this.pageDisplayState.readerMode,
        webReady: this.pageActionsReady(),
        desktopMode: this.desktopModeByTab.get(this.sceneActiveTabId) ?? false,
        downloadProgress: this.downloadProgressForTab(this.sceneActiveTabId),
        overviewTransitionActive: this.overviewProgress > 0 || this.overviewClosing ||
          this.overviewAnimationClosing,
        overviewChromeFrame: this.overviewChromeFrameForRender(),
        onNavigate: (value: string) => this.loadAddress(value, 'tabbar-address',
          'AddressTransitionLayer.onNavigate'),
        onReload: () => this.onReload(),
        onOpenAddress: () => this.openAddressEditor(),
        onAddressChange: (value: string) => this.updateAddressDraft(value),
        onInputFocusChange: (focused: boolean) => this.updateAddressInputFocus(focused),
        onAddressSubmit: (value: string) => this.submitAddressEditor(value),
        onAddressCancel: () => this.closeAddressEditor(),
        onFontSize: (size: PageFontSize) => this.onFontSize(size),
        onPageAction: (action: PageAction) => this.onPageAction(action),
        onNewTab: () => { void this.onNewTab(); },
        onNewPrivateTab: () => { void this.onNewPrivateTab(); },
        onGestureTouchStart: (x: number, y: number, startInAddressStrip: boolean,
          owner: TouchOwner, buttonId: string) =>
          this.onAddressStripTouchStart(x, y, startInAddressStrip, owner, buttonId),
        onGestureRectChange: (x: number, y: number, width: number, height: number) =>
          this.updateAddressStripRect(x, y, width, height),
        onGestureStart: (x: number, y: number) =>
          this.beginAddressGesture(x, y, this.startInAddressStrip),
        onGestureUpdate: (event: GestureEvent) => this.updateAddressGesture(event),
        onGestureEnd: (event: GestureEvent) => { void this.finishAddressGesture(event); },
        onGestureCancel: () => this.cancelAddressGesture()
        })
          // The parent Stack is bottom-aligned for the browser chrome. The
          // shared address layer instead uses viewport coordinates, so pin its
          // layout origin to the top-left before applying the frame position.
          .align(Alignment.TopStart);
      }
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
        .hitTestBehavior(HitTestMode.Transparent)
        .id('floating-address-transition-layer')
        .zIndex(tabOverviewAddressLayerZIndex());
    }
  }

  build() {
    if (ENABLE_GESTURE_LAB) {
      Column() {
        GestureLab()
      }
      .width('100%')
      .height('100%')
    } else {
      Stack({ alignContent: Alignment.Bottom }) {
        // Keep the transition scene and its native NodeContainer mounted under
        // the overview. The mounted page is transformed into the active card;
        // no second page snapshot is used for the entry animation.
      BrowserTransitionScene({
            settings: this.browserSettings,
            viewportWidth: this.viewportWidth,
            viewportHeight: this.viewportHeight,
            topContentInset: this.topAvoidInset,
            currentX: this.pageTranslateX,
            previewX: this.adjacentTranslateX,
            currentHost: this.hostControllers.get(this.sceneActiveTabId),
            previewHost: this.previewHost(),
            currentThumbnail: this.sceneAddress() === 'about:blank'
              ? undefined
              : this.thumbnailFor(this.sceneActiveTabId),
            previewThumbnail: this.previewThumbnail(),
            currentIsStartPage: this.sceneAddress() === 'about:blank' && this.errorState === undefined,
            previewIsStartPage: this.previewKind === TabPreviewKind.NEW_TAB ||
              this.previewTab()?.url === 'about:blank',
            previewKind: this.previewKind,
            showPreview: this.isDragging || this.gestureState !== TabGestureState.IDLE,
            // Keep one page-layer tree mounted before and during overview.
            // Progress zero is the identity frame; switching to the card
            // frame must not reparent the ArkWeb NodeContainer.
            overviewFrame: this.overviewPageFrameForRender(),
            overviewCaptionTitle: this.sceneActiveTab === undefined ? '' : tabOverviewTitleFor(
              lastValidUrlForTab(this.sceneActiveTab),
              this.sceneActiveTab.title
            ),
            // Crossfade the shared address strip into the card caption during
            // the final handoff instead of leaving a tiny address field under
            // an already-settled card.
            overviewCaptionVisible: this.overviewProgress > 0,
            overviewCaptionHandoffOpacity: tabOverviewCaptionHandoffOpacity(
              this.overviewProgress,
              this.overviewClosing || this.overviewAnimationClosing
            ),
            showOverviewPageBorder: tabOverviewBorderOwner(
              this.overviewProgress,
              this.overviewClosing || this.overviewAnimationClosing
            ) === 'live-page',
            interactionLocked: this.overviewProgress > 0 || this.gestureActive || this.isDragging ||
              this.showStartPageCustomize || this.showLibrary || this.showDownloadManager,
            currentItems: this.startPageItems,
            errorState: this.errorState,
            onOpen: (url: string) => this.loadAddress(url, 'start-page-entry', 'BrowserTransitionScene.onOpen'),
            onAddFavorite: () => this.addActiveFavorite(),
            onCustomize: () => this.customizeStartPage(),
            onNavigate: (value: string) => this.loadAddress(value, 'start-page-address', 'BrowserTransitionScene.onNavigate'),
            onFontSize: (size: PageFontSize) => this.onFontSize(size),
            onPageAction: (action: PageAction) => this.onPageAction(action),
            onRetry: () => this.retryBrowserError(),
            onBack: () => this.backFromBrowserError(),
            onViewportChange: (width: number, height: number) => this.updateViewport(width, height)
          })
            .id('browser-transition-instance')
            .layoutWeight(1)
            .width('100%')
            .height('100%')
            .zIndex(this.overviewClosing ? 20 : 0)

        if (this.shouldRenderBottomBrowserBar()) {
          // One fixed floating TabBar. It is a sibling of the full-window
          // BrowserContent and never participates in page translation. The
          // full-height parent is positioning-only; BottomBrowserBar itself
          // paints the capsule and owns the exact touch surface.
          // Keep the positioning node the same size as the visible capsule.
          // A full-window parent can become a hit-test participant after the
          // overview unmounts, leaving ArkWeb visible but non-interactive.
          // The capsule itself remains the only event receiver and still owns
          // the Block hierarchy hit-test.
          Stack() {
            BottomBrowserBar({
              tabs: this.sceneTabs,
              pendingTab: this.pendingTabForRender(),
              address: this.sceneAddress(),
              searchQuery: this.sceneSearchQuery(),
              pageTitle: this.sceneActiveTab === undefined ? '' : this.sceneActiveTab.title,
              addressDraft: this.draftForSceneTab(),
              tabCount: this.tabStore.tabs.length,
              isPrivate: this.sceneTabForRender()?.isPrivate ?? false,
              rawDragX: this.rawDragX,
              viewportWidth: this.viewportWidth,
              interactionLocked: this.overviewProgress > 0 || this.gestureActive || this.isDragging ||
                this.showStartPageCustomize || this.showLibrary || this.showDownloadManager,
              bottomInset: this.bottomAvoidInset,
              canGoBack: this.canNavigateBack,
              canGoForward: this.canNavigateForward,
              navigationStateRevision: this.navigationStateRevision,
              inputExpandProgress: this.inputExpandProgress,
              barMode: this.barMode,
              addressEditing: this.addressEditing,
              inputMounted: this.addressInputMounted,
              activeInputIdentity: this.sceneInputIdentity(),
              addressInputFocusEnabled: this.addressInputFocusEnabled,
              inputFocusRequestToken: this.addressFocusRequestToken,
              currentIndex: this.sceneActiveTabIndex(),
              previewKind: this.previewKind,
              newTabProgress: this.newTabProgress,
              addressHandoffMounted: this.addressHandoffActive,
              addressHandoffProgress: this.addressHandoffProgress,
              downloadProgress: this.downloadProgressForTab(this.sceneActiveTabId),
              renderAddress: false,
              gestureState: String(this.gestureState),
              onOpenAddress: () => this.openAddressEditor(),
              onAddressChange: (value: string) => this.updateAddressDraft(value),
              onInputFocusChange: (focused: boolean) => this.updateAddressInputFocus(focused),
              onAddressSubmit: (value: string) => this.submitAddressEditor(value),
              onAddressCancel: () => this.closeAddressEditor(),
              onPageAction: (action: PageAction) => this.onPageAction(action),
              onBarTouchStart: (x: number, y: number, startInAddressStrip: boolean,
                owner: TouchOwner, buttonId: string) =>
                this.onAddressStripTouchStart(x, y, startInAddressStrip, owner, buttonId),
              onBarRectChange: (x: number, y: number, width: number, height: number) =>
                this.updateAddressStripRect(x, y, width, height),
              onBarGestureStart: (x: number, y: number) =>
                this.beginAddressGesture(x, y, this.startInAddressStrip),
              onBarGestureUpdate: (event: GestureEvent) => this.updateAddressGesture(event),
              onBarGestureEnd: (event: GestureEvent) => { void this.finishAddressGesture(event); },
              onBarGestureCancel: () => this.cancelAddressGesture(),
              onNavigate: (value: string) => this.loadAddress(value, 'tabbar-address', 'BottomBrowserBar.onNavigate'),
              onReload: () => this.onReload(),
              onNewTab: () => { void this.onNewTab(); },
              onNewPrivateTab: () => { void this.onNewPrivateTab(); },
              onShare: () => { void this.shareActivePage(); },
              onShowLibrary: () => { void this.openLibrary(); },
              webReady: this.pageActionsReady(),
              desktopMode: this.desktopModeByTab.get(this.sceneActiveTabId) ?? false,
              canAddBookmark: libraryBookmarkActionEnabled(
                this.pageActionsReady(),
                this.activeTab()?.isPrivate ?? false,
                this.activeAddress()
              ),
              onAddBookmark: () => { void this.addActiveBookmark(); },
              onCloseAllTabs: () => { void this.closeAllTabs(); },
              onReopenClosedTab: () => { void this.reopenClosedTab(); },
              onShowOverview: () => this.toggleTabOverview(),
              onBack: () => {
                if (this.canNavigateBack && (this.dispatcher?.goBack() ?? false)) {
                  this.refreshNavigationState();
                }
              },
              onForward: () => {
                if (this.canNavigateForward && (this.dispatcher?.goForward() ?? false)) {
                  this.refreshNavigationState();
                }
              }
            })
              .id('floating-tab-bar')
              .width('100%')
              .height(SAFARI_BOTTOM_CHROME_BASE_HEIGHT_VP + this.bottomAvoidInset)
              .zIndex(10);
          }
            .id('floating-tab-bar-position-layer')
            .width('100%')
            .height(this.bottomBrowserBarHeight())
            .align(Alignment.Bottom)
            // The overview release animator drives this transform through the
            // same progress as the live page. Entry moves the bar downward;
            // reverse expansion brings it back from the bottom edge.
            .opacity(this.overviewChromeFrameForRender().toolbarOpacity)
            .scale({
              x: this.overviewChromeFrameForRender().toolbarScaleX * this.startPageCustomizeSqueezeScaleX(),
              y: this.overviewChromeFrameForRender().toolbarScaleY * this.startPageCustomizeSqueezeScaleY(),
              z: 1
            })
            .translate({
              x: 0,
              y: this.overviewChromeFrameForRender().toolbarTranslateY +
                this.startPageCustomizeSqueezeTranslateY(),
              z: 0
            })
            // The fixed surface stays mounted at the settled overview
            // endpoint to avoid a final-frame unmount flash. It is already
            // fully transparent and below the viewport there; disable the
            // parent hit target while the overview owns the interaction.
            .hitTestBehavior(
              this.overviewProgress > 0 || this.overviewClosing || this.overviewAnimationClosing
                ? HitTestMode.None
                : HitTestMode.Default
            )
            .zIndex(tabOverviewBottomChromeZIndex(
              this.overviewClosing || this.overviewAnimationClosing
            ));
        }

        if (this.overviewProgress > 0) {
          TabOverview({
            tabs: this.tabStore.tabs.slice(),
            activeTabId: this.overviewVisualTabIdForRender(),
            overviewProgress: this.overviewProgress,
            interactiveReveal: !this.overviewEntryAnimation,
            overviewClosing: this.overviewClosing || this.overviewAnimationClosing,
            livePageTransform: true,
            revision: this.cardRevision,
            topInset: this.topAvoidInset,
            onSearchProgress: (progress: number) => this.updateOverviewSearchProgress(progress),
            cardProgressFor: (tabId: TabId) => this.cardProgressFor(tabId),
            cardOffsetFor: (tabId: TabId) => this.cardOffsetFor(tabId),
            cardHorizontalOffsetFor: (tabId: TabId) => this.cardHorizontalOffsetFor(tabId),
            thumbnailFor: (tabId: TabId) => this.thumbnailFor(tabId),
            showSearch: true,
            bottomInset: this.bottomAvoidInset,
            onOpen: (tabId: TabId) => { void this.openCard(tabId); },
            onNewTab: () => { void this.createNewTabFromOverview(false); },
            onCloseAllTabs: () => {
              void this.closeAllTabsFromOverview();
            },
            onDismiss: () => this.dismissOverview(),
            onCloseStart: (tabId: TabId) => this.beginCardClose(tabId),
            onCloseUpdate: (tabId: TabId, sample: GestureSample) => this.updateCardClose(tabId, sample),
            onCloseEnd: (tabId: TabId, sample: GestureSample) => this.finishCardClose(tabId, sample),
            onCloseCancel: (tabId: TabId) => this.cancelCardClose(tabId),
            onCloseTap: (tabId: TabId) => this.closeCardFromButton(tabId),
            onReorderStart: (tabId: TabId) => this.beginCardReorder(tabId),
            onReorder: (tabId: TabId, targetIndex: number) => this.reorderCard(tabId, targetIndex)
          })
            // The page transform is driven by overviewProgress on the mounted
            // BrowserTransitionScene. Do not add a second mount transition to
            // the card grid or it will drift away from the live page.
            .transition(TransitionEffect.IDENTITY)
        }

        // The address capsule remains one mounted node while it leaves the
        // bottom chrome, tracks the live page, and merges back on dismissal.
        // Keeping it outside BottomBrowserBar prevents the toolbar surface
        // from clipping the shared-page handoff.
        this.buildAddressTransitionLayer();

        if (this.showLibrary && !this.showDownloadManager && this.overviewProgress === 0) {
          LibrarySheet({
            history: this.historyItems,
            bookmarks: this.bookmarkItems,
            topInset: this.topAvoidInset,
            bottomInset: this.bottomAvoidInset,
            onOpen: (url: string) => this.openLibraryEntry(url),
            onRemoveBookmark: (url: string) => { void this.removeBookmark(url); },
            onRemoveHistory: (url: string) => { void this.removeHistory(url); },
            onDeleteHistoryRange: (range: HistoryDeleteRange) => { void this.removeHistoryRange(range); },
            onClose: () => this.closeLibrary()
          })
            .align(Alignment.Bottom)
            .zIndex(20)
            .transition(
              TransitionEffect.asymmetric(
                TransitionEffect.move(TransitionEdge.BOTTOM)
                  .combine(TransitionEffect.OPACITY)
                  .animation({ curve: curves.springMotion() }),
                TransitionEffect.move(TransitionEdge.BOTTOM)
                  .combine(TransitionEffect.OPACITY)
                  .animation({
                    curve: curves.springMotion(
                      START_PAGE_CUSTOMIZE_DISMISS_SPRING_RESPONSE,
                      START_PAGE_CUSTOMIZE_DISMISS_SPRING_DAMPING,
                      START_PAGE_CUSTOMIZE_DISMISS_SPRING_OVERLAP
                    )
                  })
              )
            )
        }

        if (this.showStartPageCustomize && !this.showDownloadManager && this.overviewProgress === 0) {
          StartPageCustomizeSheet({
            settings: this.browserSettings,
            items: this.startPageItems,
            topInset: this.topAvoidInset,
            bottomInset: this.bottomAvoidInset,
            onSettingsChange: (settings: BrowserSettings) => this.updateStartPageSettings(settings),
            onItemsChange: (items: StartPageItem[]) => this.updateStartPageItems(items),
            onSelectBackground: () => { void this.chooseStartPageBackground(); },
            onClose: () => this.closeStartPageCustomize(),
            onDismissStart: () => this.beginStartPageCustomizeDismissAnimation()
          })
            .align(Alignment.Bottom)
            // The customize sheet is a modal surface. Keep the whole sheet,
            // including its bottom safe-area region, above the fixed browser
            // chrome instead of letting the toolbar's zIndex cover it.
            .zIndex(20)
            .transition(
              TransitionEffect.asymmetric(
                // Keep the entrance on the existing responsive spring. Only
                // the disappearance gets the relaxed curve below.
                TransitionEffect.move(TransitionEdge.BOTTOM)
                  .combine(TransitionEffect.OPACITY)
                  .animation({ curve: curves.springMotion() }),
                TransitionEffect.move(TransitionEdge.BOTTOM)
                  .combine(TransitionEffect.OPACITY)
                  .animation({
                    curve: curves.springMotion(
                      START_PAGE_CUSTOMIZE_DISMISS_SPRING_RESPONSE,
                      START_PAGE_CUSTOMIZE_DISMISS_SPRING_DAMPING,
                      START_PAGE_CUSTOMIZE_DISMISS_SPRING_OVERLAP
                    )
                  })
              )
            )
        }

        if (this.pageSnapshot !== undefined && this.overviewProgress === 0 &&
          !this.showLibrary && !this.showStartPageCustomize && !this.showDownloadManager) {
          Stack() {
            Column() {
              Row() {
                Text('网页截图')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#1D1D1F')
                  .layoutWeight(1)
                  .textAlign(TextAlign.Center);
                Button({ type: ButtonType.Normal, stateEffect: false }) {
                  SymbolGlyph($r('sys.symbol.xmark'))
                    .fontSize(18)
                    .fontColor(['#6B7280']);
                }
                  .id('page-snapshot-close-button')
                  .width(44)
                  .height(44)
                  .padding(0)
                  .backgroundColor(Color.Transparent)
                  .stateEffect(false)
                  .onClick(() => this.closeSnapshot());
              }
                .width('100%')
                .height(52)
                .padding({ left: 12, right: 8 });
              Image(this.pageSnapshot)
                .width('100%')
                .layoutWeight(1)
                .objectFit(ImageFit.Contain)
                .backgroundColor('#F2F2F7');
            }
              .width('100%')
              .height('100%');
          }
            .id('page-snapshot-overlay')
            .width('92%')
            .height('72%')
            .align(Alignment.Center)
            .backgroundColor(Color.White)
            .borderRadius(HARMONY_RADIUS_CARD)
            .shadow({ radius: 18, color: '#55000000', offsetX: 0, offsetY: 6 });
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.White)
    }
  }
}
