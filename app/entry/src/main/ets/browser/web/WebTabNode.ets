import {
  BuilderNode,
  FrameNode,
  NodeController,
  UIContext
} from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { webview } from '@kit.ArkWeb';
import { BrowserTabRecord, lastValidUrlForTab, TabId } from '../model/BrowserTypes';
import { shouldRetryWebHostAttachment } from '../model/BrowserInteraction';
import { WebRuntimeFactory, WebRuntimeHandle } from './WebTabPool';

const BROWSER_WEB_DOMAIN: number = 0x0000;
const BROWSER_WEB_TAG: string = 'BrowserWeb';

export interface WebDownloadHandler {
  onBeforeDownload(tabId: TabId, item: webview.WebDownloadItem, isPrivate: boolean): void;
  onDownloadUpdated(tabId: TabId, item: webview.WebDownloadItem): void;
  onDownloadFinish(tabId: TabId, item: webview.WebDownloadItem): void;
  onDownloadFailed(tabId: TabId, item: webview.WebDownloadItem): void;
}

/**
 * Kept as a compatibility type until BrowserShell switches to DownloadService
 * in Task 4. ArkWebRuntimeFactory no longer uses these callbacks.
 */
export interface WebDownloadObserver {
  onDownloadStart(tabId: TabId, fileName: string): void;
  onDownloadFinish(tabId: TabId, filePath: string): void;
  onDownloadFailed(tabId: TabId): void;
}

export interface WebPageLifecycleObserver {
  onPageBegin(tabId: TabId, controller: webview.WebviewController, url: string): void;
  onPageEnd(tabId: TabId, controller: webview.WebviewController): void;
  onTitleReceive(tabId: TabId, controller: webview.WebviewController, title: string): void;
  onError(tabId: TabId, controller: webview.WebviewController, diagnostic: WebLoadError): void;
  onSslError(tabId: TabId, controller: webview.WebviewController, diagnostic: WebSslError): void;
  onRenderExited(tabId: TabId, controller: webview.WebviewController): boolean;
  onWindowNew(tabId: TabId, controller: webview.WebviewController): boolean;
  onFullScreenEnter(tabId: TabId, controller: webview.WebviewController): void;
  onFullScreenExit(tabId: TabId, controller: webview.WebviewController): void;
}

export type WebRuntimeCreatedObserver = (tabId: TabId, url: string, runtimeId: string) => void;

/** Details emitted by ArkWeb for a failed resource load. */
export interface WebLoadError {
  code: number;
  info: string;
  url: string;
  isMainFrame: boolean;
}

/** Details emitted by ArkWeb for an SSL validation failure. */
export interface WebSslError {
  code: number;
  url: string;
  isMainFrame: boolean;
  isFatal: boolean;
}

class WebBuildData {
  readonly url: string;
  readonly controller: webview.WebviewController;
  readonly isPrivate: boolean;
  readonly onPageBegin: (url: string) => void;
  readonly onPageEnd: () => void;
  readonly onTitleReceive: (title: string) => void;
  readonly onError: (diagnostic: WebLoadError) => void;
  readonly onSslError: (diagnostic: WebSslError) => void;
  readonly onRenderExited: () => boolean;
  readonly onWindowNew: () => boolean;
  readonly onFullScreenEnter: () => void;
  readonly onFullScreenExit: () => void;
  readonly downloadDelegate: webview.WebDownloadDelegate | undefined;
  private downloadDelegateInstalled: boolean = false;

  constructor(
    url: string,
    controller: webview.WebviewController,
    isPrivate: boolean,
    onPageEnd: () => void = () => undefined,
    onTitleReceive: (title: string) => void = (_title: string) => undefined,
    onError: (diagnostic: WebLoadError) => void = (_diagnostic: WebLoadError) => undefined,
    onSslError: (diagnostic: WebSslError) => void = (_diagnostic: WebSslError) => undefined,
    onRenderExited: () => boolean = () => false,
    onWindowNew: () => boolean = () => false,
    onFullScreenEnter: () => void = () => undefined,
    onFullScreenExit: () => void = () => undefined,
    downloadDelegate: webview.WebDownloadDelegate | undefined = undefined,
    onPageBegin: (url: string) => void = (_url: string) => undefined
  ) {
    this.url = url;
    this.controller = controller;
    this.isPrivate = isPrivate;
    this.onPageBegin = onPageBegin;
    this.onPageEnd = onPageEnd;
    this.onTitleReceive = onTitleReceive;
    this.onError = onError;
    this.onSslError = onSslError;
    this.onRenderExited = onRenderExited;
    this.onWindowNew = onWindowNew;
    this.onFullScreenEnter = onFullScreenEnter;
    this.onFullScreenExit = onFullScreenExit;
    this.downloadDelegate = downloadDelegate;
  }

  installDownloadDelegate(): void {
    if (this.downloadDelegateInstalled || this.downloadDelegate === undefined) {
      return;
    }
    try {
      this.controller.setDownloadDelegate(this.downloadDelegate);
      this.downloadDelegateInstalled = true;
    } catch (_error) {
      // The controller may not be associated with Web during Previewer
      // construction; the next page-end callback retries installation.
    }
  }
}

@Builder
function buildWebNode(data: WebBuildData) {
  Web({
    src: data.url,
    controller: data.controller,
    incognitoMode: data.isPrivate
  })
    .width('100%')
    .height('100%')
    .javaScriptAccess(true)
    .domStorageAccess(true)
    .multiWindowAccess(true)
    .onPageBegin((event) => data.onPageBegin(event?.url ?? ''))
    .onRefreshAccessedHistory((event) => data.onPageBegin(event?.url ?? ''))
    .onPageEnd(() => {
      data.installDownloadDelegate();
      data.onPageEnd();
    })
    .onTitleReceive((event) => data.onTitleReceive(event?.title ?? ''))
    .onErrorReceive((event) => {
      const request = event?.request;
      const error = event?.error;
      data.onError({
        code: error?.getErrorCode() ?? 0,
        info: error?.getErrorInfo() ?? '',
        url: request?.getRequestUrl() ?? data.url,
        isMainFrame: request?.isMainFrame() ?? true
      });
      return false;
    })
    .onSslErrorEvent((event) => data.onSslError({
      code: Number(event?.error ?? 0),
      url: event?.url ?? data.url,
      isMainFrame: event?.isMainFrame ?? true,
      isFatal: event?.isFatalError ?? true
    }))
    .onRenderExited(() => data.onRenderExited())
    .onWindowNewExt(() => data.onWindowNew())
    .onFullScreenEnter(() => data.onFullScreenEnter())
    .onFullScreenExit(() => data.onFullScreenExit())
    // Diagnostic-only observer. It does not consume or forward events. The
    // exact TabBar capsule records webViewClick=0 when its Block hierarchy
    // owns the stream; the WebView itself has no root-level onTouch handler.
    .onClick(() => {
      hilog.info(BROWSER_WEB_DOMAIN, BROWSER_WEB_TAG,
        'phase=webview-click touchOwner=page webViewTouchDown=0 webViewClick=1 ' +
          'buttonClick=0 touchCancel=0');
    });
}

export class WebNodeHostController extends NodeController {
  readonly tabId: TabId;
  private frameNode: FrameNode | null = null;

  constructor(tabId: TabId) {
    super();
    this.tabId = tabId;
  }

  setFrameNode(node: FrameNode | null): void {
    this.frameNode = node;
    this.rebuild();
  }

  makeNode(_uiContext: UIContext): FrameNode | null {
    return this.frameNode;
  }
}

export class ArkWebRuntimeHandle implements WebRuntimeHandle {
  readonly tabId: TabId;
  readonly runtimeId: string;
  private controller: webview.WebviewController | null;
  private builderNode: BuilderNode<[WebBuildData]> | null;
  private host: WebNodeHostController | null = null;
  private destroyed: boolean = false;
  private attachGeneration: number = 0;

  constructor(
    tabId: TabId,
    runtimeId: string,
    controller: webview.WebviewController,
    builderNode: BuilderNode<[WebBuildData]>
  ) {
    this.tabId = tabId;
    this.runtimeId = runtimeId;
    this.controller = controller;
    this.builderNode = builderNode;
  }

  attach(host: NodeController): void {
    if (this.destroyed) {
      return;
    }
    const typedHost: WebNodeHostController = host as WebNodeHostController;
    this.host = typedHost;
    this.attachGeneration += 1;
    this.attachFrameWhenReady(this.attachGeneration, 0);
  }

  private attachFrameWhenReady(generation: number, attempt: number): void {
    if (this.destroyed || generation !== this.attachGeneration || this.host === null) {
      return;
    }
    const frameNode: FrameNode | null = this.builderNode?.getFrameNode() ?? null;
    this.host.setFrameNode(frameNode);
    if (shouldRetryWebHostAttachment(frameNode === null, attempt)) {
      setTimeout(() => this.attachFrameWhenReady(generation, attempt + 1), 60);
    }
  }

  detach(): void {
    this.attachGeneration += 1;
    if (this.host !== null) {
      this.host.setFrameNode(null);
      this.host = null;
    }
  }

  destroy(): void {
    if (this.destroyed) {
      return;
    }
    this.destroyed = true;
    this.attachGeneration += 1;
    this.detach();
    this.builderNode?.dispose();
    this.builderNode = null;
    this.controller = null;
  }

  getController(): webview.WebviewController | undefined {
    return this.controller ?? undefined;
  }
}

export class ArkWebRuntimeFactory implements WebRuntimeFactory {
  private readonly uiContext: UIContext;
  private readonly observer: WebPageLifecycleObserver | undefined;
  private readonly downloadHandler: WebDownloadHandler | undefined;
  private readonly runtimeCreatedObserver: WebRuntimeCreatedObserver | undefined;
  private runtimeSequence: number = 0;

  constructor(uiContext: UIContext, observer: WebPageLifecycleObserver | undefined = undefined,
    downloadHandler: WebDownloadHandler | string | undefined = undefined,
    runtimeCreatedObserver: WebRuntimeCreatedObserver | undefined = undefined) {
    this.uiContext = uiContext;
    this.observer = observer;
    this.downloadHandler = typeof downloadHandler === 'string' ? undefined : downloadHandler;
    this.runtimeCreatedObserver = runtimeCreatedObserver;
  }

  create(tab: BrowserTabRecord): WebRuntimeHandle {
    this.runtimeSequence += 1;
    const runtimeId: string = `webview-controller-${tab.id}-${this.runtimeSequence}`;
    const sourceUrl: string = lastValidUrlForTab(tab);
    const controller: webview.WebviewController = new webview.WebviewController();
    const builderNode: BuilderNode<[WebBuildData]> = new BuilderNode(this.uiContext);
    const onPageBegin: (url: string) => void = (url: string) => {
      this.observer?.onPageBegin(tab.id, controller, url);
    };
    const onPageEnd: () => void = () => {
      this.observer?.onPageEnd(tab.id, controller);
    };
    const onTitleReceive: (title: string) => void = (title: string) => {
      this.observer?.onTitleReceive(tab.id, controller, title);
    };
    const onError: (diagnostic: WebLoadError) => void = (diagnostic: WebLoadError) => {
      this.observer?.onError(tab.id, controller, diagnostic);
    };
    const onSslError: (diagnostic: WebSslError) => void = (diagnostic: WebSslError) => {
      this.observer?.onSslError(tab.id, controller, diagnostic);
    };
    const onRenderExited: () => boolean = () => {
      return this.observer?.onRenderExited(tab.id, controller) ?? false;
    };
    const onWindowNew: () => boolean = () => {
      return this.observer?.onWindowNew(tab.id, controller) ?? false;
    };
    const onFullScreenEnter: () => void = () => {
      this.observer?.onFullScreenEnter(tab.id, controller);
    };
    const onFullScreenExit: () => void = () => {
      this.observer?.onFullScreenExit(tab.id, controller);
    };
    const downloadDelegate: webview.WebDownloadDelegate | undefined = this.createDownloadDelegate(tab.id, tab.isPrivate);
    builderNode.build(
      wrapBuilder<[WebBuildData]>(buildWebNode),
      new WebBuildData(sourceUrl, controller, tab.isPrivate, onPageEnd, onTitleReceive, onError, onSslError,
        onRenderExited, onWindowNew, onFullScreenEnter, onFullScreenExit, downloadDelegate, onPageBegin)
    );
    this.runtimeCreatedObserver?.(tab.id, sourceUrl, runtimeId);
    return new ArkWebRuntimeHandle(tab.id, runtimeId, controller, builderNode);
  }

  private createDownloadDelegate(tabId: TabId, isPrivate: boolean): webview.WebDownloadDelegate | undefined {
    if (this.downloadHandler === undefined) {
      return undefined;
    }
    const delegate: webview.WebDownloadDelegate = new webview.WebDownloadDelegate();
    delegate.onBeforeDownload((item: webview.WebDownloadItem) => {
      this.downloadHandler?.onBeforeDownload(tabId, item, isPrivate);
    });
    delegate.onDownloadUpdated((item: webview.WebDownloadItem) => {
      this.downloadHandler?.onDownloadUpdated(tabId, item);
    });
    delegate.onDownloadFinish((item: webview.WebDownloadItem) => {
      this.downloadHandler?.onDownloadFinish(tabId, item);
    });
    delegate.onDownloadFailed((item: webview.WebDownloadItem) => {
      this.downloadHandler?.onDownloadFailed(tabId, item);
    });
    return delegate;
  }
}
