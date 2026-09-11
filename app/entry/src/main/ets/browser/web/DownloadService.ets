import { webview } from '@kit.ArkWeb';
import fs from '@ohos.file.fs';
import { DownloadStore } from '../data/DownloadStore';
import {
  classifyDownload,
  DownloadBackend,
  DownloadStatus,
  DownloadTaskRecord,
  percentForDownload
} from '../model/DownloadModels';
import { TabId } from '../model/BrowserTypes';
import { NotificationPermissionPort } from './DownloadNotificationGateway';
import {
  AgentDownloadConfig,
  AgentDownloadPort,
  AgentTaskHandle,
  AgentTaskSnapshot,
  AgentTaskStatus,
  isAgentQueryNotFound
} from './RequestAgentGateway';
import { WebDownloadHandler } from './WebTabNode';

export interface WebCookiePort {
  fetchCookie(url: string, isPrivate: boolean): Promise<string>;
}

export class DownloadService implements WebDownloadHandler {
  private readonly store: DownloadStore;
  private readonly agent: AgentDownloadPort;
  private readonly notification: NotificationPermissionPort;
  private readonly cookie: WebCookiePort;
  private readonly filesDir: string;
  private readonly now: () => number;
  private readonly pathExists: (path: string) => boolean;
  private listener: ((tasks: DownloadTaskRecord[]) => void) | undefined = undefined;
  private readonly handles: Map<string, AgentTaskHandle> = new Map();
  private readonly nativeItems: Map<string, webview.WebDownloadItem> = new Map();
  private readonly itemIds: Map<webview.WebDownloadItem, string> = new Map();
  private readonly reservedPaths: Set<string> = new Set();
  private readonly intentionalArkWebCancels: Set<string> = new Set();
  private uiLoaded: boolean = false;
  private idSequence: number = 0;
  private operationTail: Promise<void> = Promise.resolve();
  private restorePromise: Promise<void> | undefined = undefined;

  constructor(
    store: DownloadStore,
    agent: AgentDownloadPort,
    notification: NotificationPermissionPort,
    cookie: WebCookiePort,
    filesDir: string,
    now: () => number = () => Date.now(),
    pathExists: ((path: string) => boolean) | undefined = undefined
  ) {
    this.store = store;
    this.agent = agent;
    this.notification = notification;
    this.cookie = cookie;
    this.filesDir = filesDir;
    this.now = now;
    this.pathExists = pathExists ?? ((path: string): boolean => this.fileExists(path));
  }

  restore(): Promise<void> {
    if (this.restorePromise !== undefined) {
      return this.restorePromise;
    }
    const operation: Promise<void> = this.enqueue(() => this.restoreInternal());
    this.restorePromise = operation.then(
      (): void => undefined,
      (): void => this.notify()
    ).catch((): void => undefined);
    return this.restorePromise;
  }

  private async restoreInternal(): Promise<void> {
    await this.store.restore();
    const tasks: DownloadTaskRecord[] = this.store.snapshot();
    const recoveredHandles: Map<string, AgentTaskHandle> = new Map();
    const queryFailures: Set<string> = new Set();
    for (const task of tasks) {
      if (task.backend === DownloadBackend.REQUEST_AGENT && task.agentTaskId.length > 0) {
        let handle: AgentTaskHandle | undefined = undefined;
        try {
          handle = await this.agent.getTask(task.agentTaskId);
        } catch (error) {
          if (!isAgentQueryNotFound(error)) {
            queryFailures.add(task.id);
          }
          handle = undefined;
        }
        if (handle !== undefined) {
          recoveredHandles.set(task.id, handle);
        }
        let shown: AgentTaskSnapshot | undefined = undefined;
        try {
          shown = await this.agent.show(task.agentTaskId);
        } catch (error) {
          if (!isAgentQueryNotFound(error)) {
            queryFailures.add(task.id);
          }
          shown = undefined;
        }
        if (shown !== undefined) {
          this.mergeAgentSnapshot(task, shown);
        }
      }
    }

    let discovered: AgentTaskSnapshot[] = [];
    let searchFailed: boolean = false;
    try {
      discovered = await this.agent.searchByPrefix('jianyue-download:');
    } catch (_error) {
      searchFailed = true;
    }
    for (const snapshot of discovered) {
      const matching: DownloadTaskRecord | undefined = this.findRecoveredTask(snapshot);
      if (matching === undefined) {
        continue;
      }
      this.mergeAgentSnapshot(matching, snapshot);
    }

    for (const task of this.store.snapshot()) {
      if (task.backend !== DownloadBackend.REQUEST_AGENT || this.isTerminal(task.status)) {
        continue;
      }
      const handle: AgentTaskHandle | undefined = recoveredHandles.get(task.id);
      if (handle !== undefined) {
        this.attachAgentHandle(task.id, handle);
      } else if (searchFailed || queryFailures.has(task.id)) {
        this.store.patch(task.id, {
          error: '后台下载状态查询失败；本地记录已保留。'
        });
      } else {
        this.store.transition(task.id, DownloadStatus.FAILED, {
          error: '后台下载任务不可用；请重试。'
        });
      }
    }
    this.notify();
  }

  markUiLoaded(): void {
    if (this.uiLoaded) {
      return;
    }
    this.uiLoaded = true;
    void this.notification.requestOnce();
  }

  snapshot(): DownloadTaskRecord[] {
    return this.store.snapshot();
  }

  onBeforeDownload(tabId: TabId, item: webview.WebDownloadItem, isPrivate: boolean): void {
    const pending: Promise<void> = this.restore().then(
      (): Promise<void> => this.enqueue(() => this.begin(tabId, item, isPrivate))
    );
    void pending.catch((): void => undefined);
  }

  onDownloadUpdated(_tabId: TabId, item: webview.WebDownloadItem): void {
    const id: string = this.itemId(item);
    this.enqueueEvent((): void => {
      if (this.intentionalArkWebCancels.has(id) || this.isTerminalTask(id)) {
        return;
      }
      const receivedBytes: number = item.getReceivedBytes();
      const totalBytes: number = item.getTotalBytes();
      const percent: number = totalBytes > 0
        ? percentForDownload(receivedBytes, totalBytes)
        : item.getPercentComplete();
      this.store.patch(id, {
        receivedBytes,
        totalBytes,
        percent: percent < 0 ? -1 : Math.min(100, Math.max(0, percent))
      });
      this.notify();
    });
  }

  onDownloadFinish(_tabId: TabId, item: webview.WebDownloadItem): void {
    const id: string = this.itemId(item);
    this.enqueueEvent((): void => {
      if (this.intentionalArkWebCancels.has(id) || this.isTerminalTask(id)) {
        return;
      }
      this.store.transition(id, DownloadStatus.COMPLETED, {
        receivedBytes: item.getReceivedBytes(),
        totalBytes: item.getTotalBytes(),
        percent: 100
      });
      this.nativeItems.delete(id);
      this.notify();
    });
  }

  onDownloadFailed(_tabId: TabId, item: webview.WebDownloadItem): void {
    const id: string = this.itemId(item);
    this.enqueueEvent((): void => {
      if (this.intentionalArkWebCancels.has(id) || this.isTerminalTask(id)) {
        return;
      }
      this.store.transition(id, DownloadStatus.FAILED, {
        error: '网页下载失败；请重试。'
      });
      this.notify();
    });
  }

  async pause(id: string): Promise<void> {
    await this.restore();
    await this.enqueue(() => this.pauseNow(id));
  }

  async resume(id: string): Promise<void> {
    await this.restore();
    await this.enqueue(() => this.resumeNow(id));
  }

  async cancel(id: string): Promise<void> {
    await this.restore();
    await this.enqueue(() => this.cancelNow(id));
  }

  async retry(id: string): Promise<void> {
    await this.restore();
    await this.enqueue(() => this.retryNow(id));
  }

  setListener(listener: (tasks: DownloadTaskRecord[]) => void): void {
    this.listener = listener;
    this.notify();
  }

  clearListener(listener: (tasks: DownloadTaskRecord[]) => void): void {
    if (this.listener === listener) {
      this.listener = undefined;
    }
  }

  private async pauseNow(id: string): Promise<void> {
    const handle: AgentTaskHandle | undefined = await this.handleFor(id);
    if (handle === undefined) {
      return;
    }
    await handle.pause();
    this.store.transition(id, DownloadStatus.PAUSED, {});
    this.notify();
  }

  private async resumeNow(id: string): Promise<void> {
    const handle: AgentTaskHandle | undefined = await this.handleFor(id);
    if (handle === undefined) {
      return;
    }
    await handle.resume();
    this.store.transition(id, DownloadStatus.RUNNING, {});
    this.notify();
  }

  private async cancelNow(id: string): Promise<void> {
    const handle: AgentTaskHandle | undefined = await this.handleFor(id);
    if (handle !== undefined) {
      await handle.cancel();
    } else {
      const item: webview.WebDownloadItem | undefined = this.nativeItems.get(id);
      if (item !== undefined) {
        this.intentionalArkWebCancels.add(id);
        try {
          item.cancel();
        } catch (_error) {
          // The task is still kept as cancelled; the marker prevents a late
          // ArkWeb callback from changing the user-visible terminal state.
        }
      }
    }
    this.store.transition(id, DownloadStatus.CANCELLED, {});
    this.notify();
  }

  private async retryNow(id: string): Promise<void> {
    const task: DownloadTaskRecord | undefined = this.store.snapshot().find(
      (candidate: DownloadTaskRecord) => candidate.id === id
    );
    if (task === undefined) {
      return;
    }
    const item: webview.WebDownloadItem | undefined = this.nativeItems.get(id);
    if (task.backend === DownloadBackend.ARKWEB && item !== undefined) {
      const savePath: string = this.pathFor(task.filename, task.id);
      this.store.transition(id, DownloadStatus.QUEUED, { savePath, error: '' });
      const retryTask: DownloadTaskRecord = this.copyTask(task);
      retryTask.savePath = savePath;
      retryTask.status = DownloadStatus.QUEUED;
      this.startNative(retryTask, item);
      return;
    }
    if (task.backend === DownloadBackend.REQUEST_AGENT && !task.isPrivate) {
      const savePath: string = this.pathFor(task.filename, task.id);
      this.store.transition(id, DownloadStatus.HANDOFF_PENDING, {
        agentTaskId: '',
        savePath,
        error: ''
      });
      const retryTask: DownloadTaskRecord = this.copyTask(task);
      retryTask.agentTaskId = '';
      retryTask.savePath = savePath;
      retryTask.status = DownloadStatus.HANDOFF_PENDING;
      await this.createAgentTask(retryTask, undefined);
    }
  }

  private async begin(tabId: TabId, item: webview.WebDownloadItem, isPrivate: boolean): Promise<void> {
    const id: string = this.itemId(item);
    if (this.store.snapshot().some((task: DownloadTaskRecord) => task.id === id)) {
      return;
    }
    const url: string = item.getUrl();
    const filename: string = this.safeFilename(item.getSuggestedFileName(), id);
    const backend: DownloadBackend = classifyDownload(url, item.getMethod(), isPrivate);
    const savePath: string = this.pathFor(filename, id);
    const task: DownloadTaskRecord = {
      id,
      agentTaskId: '',
      reconcileKey: id,
      tabId,
      url,
      filename,
      backend,
      status: backend === DownloadBackend.REQUEST_AGENT ? DownloadStatus.HANDOFF_PENDING : DownloadStatus.QUEUED,
      receivedBytes: 0,
      totalBytes: -1,
      percent: -1,
      createdAt: this.now(),
      updatedAt: this.now(),
      isPrivate,
      savePath,
      mimeType: item.getMimeType()
    };
    this.store.begin(task);
    await this.store.flush();
    if (backend === DownloadBackend.ARKWEB) {
      this.startNative(task, item);
      return;
    }
    await this.createAgentTask(task, item);
  }

  private async createAgentTask(task: DownloadTaskRecord, item: webview.WebDownloadItem | undefined): Promise<void> {
    let handle: AgentTaskHandle;
    try {
      const cookie: string = await this.cookie.fetchCookie(task.url, task.isPrivate);
      const headers: Record<string, string> = {};
      if (cookie.length > 0) {
        headers['Cookie'] = cookie;
      }
      const config: AgentDownloadConfig = {
        reconcileKey: task.reconcileKey,
        url: task.url,
        savePath: task.savePath ?? this.pathFor(task.filename, task.id),
        title: task.filename,
        description: 'jianyue-download:' + task.reconcileKey,
        headers,
        mimeType: task.mimeType ?? '',
        notificationEnabled: this.uiLoaded
      };
      handle = await this.agent.create(config);
    } catch (_error) {
      if (item === undefined) {
        this.store.transition(task.id, DownloadStatus.FAILED, { error: '后台下载创建失败；请重试。' });
        this.notify();
        return;
      }
      this.startNative(task, item);
      return;
    }

    this.store.patch(task.id, { agentTaskId: handle.taskId });
    await this.store.flush();
    this.attachAgentHandle(task.id, handle);
    if (item !== undefined) {
      this.intentionalArkWebCancels.add(task.id);
      try {
        item.cancel();
      } catch (_error) {
        this.store.transition(task.id, DownloadStatus.RUNNING, {
          error: '后台下载已创建，但网页任务取消未确认；将保留后台任务并可恢复。'
        });
        this.notify();
        return;
      }
    }
    this.store.transition(task.id, DownloadStatus.RUNNING, { error: '' });
    this.notify();
  }

  private startNative(task: DownloadTaskRecord, item: webview.WebDownloadItem): void {
    this.nativeItems.set(task.id, item);
    const savePath: string = task.savePath ?? this.pathFor(task.filename, task.id);
    if (task.savePath === undefined) {
      this.store.patch(task.id, { savePath });
    }
    try {
      item.start(savePath);
    } catch (_error) {
      this.store.transition(task.id, DownloadStatus.FAILED, {
        backend: DownloadBackend.ARKWEB,
        agentTaskId: '',
        error: '网页下载启动失败；请重试。'
      });
      this.notify();
      return;
    }
    this.store.transition(task.id, DownloadStatus.RUNNING, { backend: DownloadBackend.ARKWEB, agentTaskId: '', error: '' });
    this.notify();
  }

  private attachAgentHandle(id: string, handle: AgentTaskHandle): void {
    this.detachAgentHandle(id);
    this.handles.set(id, handle);
    handle.onProgress((snapshot: AgentTaskSnapshot) => {
      this.enqueueAgentEvent(id, handle, (): void => {
        this.store.updateProgress(id, snapshot.receivedBytes, snapshot.totalBytes);
        this.notify();
      });
    });
    handle.onCompleted((snapshot: AgentTaskSnapshot) => {
      this.enqueueAgentEvent(id, handle, (): void => {
        if (this.isTerminalTask(id)) {
          return;
        }
        this.store.transition(id, DownloadStatus.COMPLETED, {
          receivedBytes: snapshot.receivedBytes,
          totalBytes: snapshot.totalBytes,
          percent: 100
        });
        this.intentionalArkWebCancels.delete(id);
        this.detachAgentHandle(id);
        this.notify();
      });
    });
    handle.onFailed((snapshot: AgentTaskSnapshot) => {
      this.enqueueAgentEvent(id, handle, (): void => {
        if (this.isTerminalTask(id)) {
          return;
        }
        this.store.transition(id, DownloadStatus.FAILED, {
          error: snapshot.error ?? '后台下载失败；请重试。'
        });
        this.intentionalArkWebCancels.delete(id);
        this.detachAgentHandle(id);
        this.notify();
      });
    });
  }

  private detachAgentHandle(id: string): void {
    const handle: AgentTaskHandle | undefined = this.handles.get(id);
    if (handle === undefined) {
      return;
    }
    this.handles.delete(id);
    try {
      handle.detach?.();
    } catch (_error) {
      // Detaching callbacks is best effort; the system task continues in the
      // background and identity checks ignore any late callback.
    }
  }

  private enqueueAgentEvent(id: string, handle: AgentTaskHandle, operation: () => void): void {
    const pending: Promise<void> = this.restore().then(
      (): Promise<void> => this.enqueue(async (): Promise<void> => {
        if (this.handles.get(id) !== handle) {
          return;
        }
        operation();
      })
    );
    void pending.catch((): void => undefined);
  }

  private findRecoveredTask(snapshot: AgentTaskSnapshot): DownloadTaskRecord | undefined {
    const reconcileKey: string = this.reconcileKeyFor(snapshot.description);
    return this.store.snapshot().find((task: DownloadTaskRecord) =>
      task.agentTaskId === snapshot.taskId || task.reconcileKey === reconcileKey ||
      (snapshot.savePath !== undefined && snapshot.savePath === (task.savePath ?? this.basePathFor(task.filename, task.id)))
    );
  }

  private mergeAgentSnapshot(task: DownloadTaskRecord, snapshot: AgentTaskSnapshot): void {
    const status: DownloadStatus = this.statusFor(snapshot.status);
    const merged: DownloadTaskRecord = this.copyTask(task);
    merged.agentTaskId = snapshot.taskId;
    merged.status = status;
    merged.receivedBytes = snapshot.receivedBytes;
    merged.totalBytes = snapshot.totalBytes;
    merged.percent = snapshot.percent;
    merged.updatedAt = this.now();
    merged.error = snapshot.error;
    if (snapshot.savePath !== undefined) {
      merged.savePath = snapshot.savePath;
    }
    this.store.mergeRecovered(merged);
  }

  private statusFor(value: AgentTaskStatus): DownloadStatus {
    switch (value) {
      case AgentTaskStatus.COMPLETED:
        return DownloadStatus.COMPLETED;
      case AgentTaskStatus.FAILED:
        return DownloadStatus.FAILED;
      case AgentTaskStatus.PAUSED:
        return DownloadStatus.PAUSED;
      case AgentTaskStatus.CANCELLED:
        return DownloadStatus.CANCELLED;
      case AgentTaskStatus.RUNNING:
      default:
        return DownloadStatus.RUNNING;
    }
  }

  private async handleFor(id: string): Promise<AgentTaskHandle | undefined> {
    const cached: AgentTaskHandle | undefined = this.handles.get(id);
    if (cached !== undefined) {
      return cached;
    }
    const task: DownloadTaskRecord | undefined = this.store.snapshot().find(
      (candidate: DownloadTaskRecord) => candidate.id === id
    );
    if (task === undefined || task.agentTaskId.length === 0) {
      return undefined;
    }
    let recovered: AgentTaskHandle | undefined = undefined;
    try {
      recovered = await this.agent.getTask(task.agentTaskId);
    } catch (_error) {
      recovered = undefined;
    }
    if (recovered !== undefined) {
      this.attachAgentHandle(id, recovered);
    }
    return recovered;
  }

  private itemId(item: webview.WebDownloadItem): string {
    const mapped: string | undefined = this.itemIds.get(item);
    if (mapped !== undefined) {
      return mapped;
    }
    const guid: string = item.getGuid().trim();
    const id: string = guid.length > 0 ? guid : `arkweb-${this.now()}-${this.idSequence++}`;
    this.itemIds.set(item, id);
    return id;
  }

  private safeFilename(suggested: string, id: string): string {
    const sanitized: string = suggested.replace(/[\\/:*?"<>|]/g, '_').trim();
    return sanitized.length > 0 ? sanitized : `download-${id}`;
  }

  private pathFor(filename: string, id: string): string {
    const root: string = `${this.filesDir}/downloads`;
    try {
      fs.mkdirSync(root, true);
    } catch (_error) {
      // The directory may already exist or the Previewer may not expose a file system.
    }
    const safeId: string = id.replace(/[^a-zA-Z0-9._-]/g, '_');
    const baseName: string = `${safeId}-${filename}`;
    let suffix: number = 0;
    let candidate: string = `${root}/${baseName}`;
    while (this.reservedPaths.has(candidate) || this.pathExists(candidate)) {
      suffix += 1;
      candidate = `${root}/${safeId}-${suffix}-${filename}`;
    }
    this.reservedPaths.add(candidate);
    return candidate;
  }

  private basePathFor(filename: string, id: string): string {
    const root: string = `${this.filesDir}/downloads`;
    const safeId: string = id.replace(/[^a-zA-Z0-9._-]/g, '_');
    return `${root}/${safeId}-${filename}`;
  }

  private fileExists(path: string): boolean {
    try {
      fs.statSync(path);
      return true;
    } catch (_error) {
      return false;
    }
  }

  private reconcileKeyFor(description: string | undefined): string {
    const prefix: string = 'jianyue-download:';
    return description?.startsWith(prefix) ? description.slice(prefix.length) : '';
  }

  private isTerminal(status: DownloadStatus): boolean {
    return status === DownloadStatus.COMPLETED || status === DownloadStatus.FAILED ||
      status === DownloadStatus.CANCELLED;
  }

  private isTerminalTask(id: string): boolean {
    const task: DownloadTaskRecord | undefined = this.store.snapshot().find(
      (candidate: DownloadTaskRecord) => candidate.id === id
    );
    return task !== undefined && this.isTerminal(task.status);
  }

  private copyTask(task: DownloadTaskRecord): DownloadTaskRecord {
    return {
      id: task.id,
      agentTaskId: task.agentTaskId,
      reconcileKey: task.reconcileKey,
      tabId: task.tabId,
      url: task.url,
      filename: task.filename,
      backend: task.backend,
      status: task.status,
      receivedBytes: task.receivedBytes,
      totalBytes: task.totalBytes,
      percent: task.percent,
      createdAt: task.createdAt,
      updatedAt: task.updatedAt,
      isPrivate: task.isPrivate,
      savePath: task.savePath,
      mimeType: task.mimeType,
      error: task.error
    };
  }

  private enqueueEvent(operation: () => void): void {
    const pending: Promise<void> = this.restore().then(
      (): Promise<void> => this.enqueue(async (): Promise<void> => operation())
    );
    void pending.catch((): void => undefined);
  }

  private enqueue(operation: () => Promise<void>): Promise<void> {
    const next: Promise<void> = this.operationTail.then(operation, operation);
    this.operationTail = next.then((): void => undefined, (): void => undefined);
    return next;
  }

  private notify(): void {
    const listener: ((tasks: DownloadTaskRecord[]) => void) | undefined = this.listener;
    if (listener === undefined) {
      return;
    }
    try {
      listener(this.store.snapshot());
    } catch (_error) {
      // A shell can be tearing down while a background callback is delivered.
    }
  }
}
