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
import { AgentDownloadPort, AgentTaskHandle, AgentTaskSnapshot } from './RequestAgentGateway';
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
  private listener: ((tasks: DownloadTaskRecord[]) => void) | undefined = undefined;
  private readonly handles: Map<string, AgentTaskHandle> = new Map();
  private readonly nativeItems: Map<string, webview.WebDownloadItem> = new Map();
  private readonly intentionalArkWebCancels: Set<string> = new Set();
  private uiLoaded: boolean = false;
  private pathSequence: number = 0;

  constructor(
    store: DownloadStore,
    agent: AgentDownloadPort,
    notification: NotificationPermissionPort,
    cookie: WebCookiePort,
    filesDir: string,
    now: () => number = () => Date.now()
  ) {
    this.store = store;
    this.agent = agent;
    this.notification = notification;
    this.cookie = cookie;
    this.filesDir = filesDir;
    this.now = now;
  }

  async restore(): Promise<void> {
    await this.store.restore();
    const tasks: DownloadTaskRecord[] = this.store.snapshot();
    const recoveredHandles: Map<string, AgentTaskHandle> = new Map();
    for (const task of tasks) {
      if (task.backend === DownloadBackend.REQUEST_AGENT && task.agentTaskId.length > 0) {
        const handle: AgentTaskHandle | undefined = await this.agent.getTask(task.agentTaskId);
        if (handle !== undefined) {
          recoveredHandles.set(task.id, handle);
        }
      }
    }

    const discovered: AgentTaskSnapshot[] = await this.agent.searchByPrefix('jianyue-download:');
    const discoveredIds: Set<string> = new Set();
    for (const snapshot of discovered) {
      const matching: DownloadTaskRecord | undefined = this.findRecoveredTask(snapshot);
      if (matching === undefined) {
        continue;
      }
      discoveredIds.add(matching.id);
      this.mergeAgentSnapshot(matching, snapshot);
    }

    for (const task of this.store.snapshot()) {
      if (task.backend !== DownloadBackend.REQUEST_AGENT || this.isTerminal(task.status)) {
        continue;
      }
      const handle: AgentTaskHandle | undefined = recoveredHandles.get(task.id);
      if (handle !== undefined) {
        this.attachAgentHandle(task.id, handle);
      } else if (!discoveredIds.has(task.id)) {
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
    void this.begin(tabId, item, isPrivate);
  }

  onDownloadUpdated(_tabId: TabId, item: webview.WebDownloadItem): void {
    const id: string = this.itemId(item);
    if (this.intentionalArkWebCancels.has(id)) {
      return;
    }
    const receivedBytes: number = item.getReceivedBytes();
    const totalBytes: number = item.getTotalBytes();
    const percent: number = totalBytes > 0 ? percentForDownload(receivedBytes, totalBytes) : item.getPercentComplete();
    this.store.patch(id, {
      receivedBytes,
      totalBytes,
      percent: percent < 0 ? -1 : Math.min(100, Math.max(0, percent))
    });
    this.notify();
  }

  onDownloadFinish(_tabId: TabId, item: webview.WebDownloadItem): void {
    const id: string = this.itemId(item);
    if (this.intentionalArkWebCancels.has(id)) {
      return;
    }
    this.store.transition(id, DownloadStatus.COMPLETED, {
      receivedBytes: item.getReceivedBytes(),
      totalBytes: item.getTotalBytes(),
      percent: 100
    });
    this.nativeItems.delete(id);
    this.notify();
  }

  onDownloadFailed(_tabId: TabId, item: webview.WebDownloadItem): void {
    const id: string = this.itemId(item);
    if (this.intentionalArkWebCancels.has(id)) {
      return;
    }
    this.store.transition(id, DownloadStatus.FAILED, {
      error: '网页下载失败；请重试。'
    });
    this.nativeItems.delete(id);
    this.notify();
  }

  async pause(id: string): Promise<void> {
    const handle: AgentTaskHandle | undefined = await this.handleFor(id);
    if (handle === undefined) {
      return;
    }
    await handle.pause();
    this.store.transition(id, DownloadStatus.PAUSED, {});
    this.notify();
  }

  async resume(id: string): Promise<void> {
    const handle: AgentTaskHandle | undefined = await this.handleFor(id);
    if (handle === undefined) {
      return;
    }
    await handle.resume();
    this.store.transition(id, DownloadStatus.RUNNING, {});
    this.notify();
  }

  async cancel(id: string): Promise<void> {
    const handle: AgentTaskHandle | undefined = await this.handleFor(id);
    if (handle !== undefined) {
      await handle.cancel();
    } else {
      this.nativeItems.get(id)?.cancel();
    }
    this.store.transition(id, DownloadStatus.CANCELLED, {});
    this.notify();
  }

  async retry(id: string): Promise<void> {
    const task: DownloadTaskRecord | undefined = this.store.snapshot().find(
      (candidate: DownloadTaskRecord) => candidate.id === id
    );
    if (task === undefined) {
      return;
    }
    const item: webview.WebDownloadItem | undefined = this.nativeItems.get(id);
    if (task.backend === DownloadBackend.ARKWEB && item !== undefined) {
      item.start(this.pathFor(task.filename, task.id));
      this.store.transition(id, DownloadStatus.RUNNING, { error: '' });
      this.notify();
      return;
    }
    if (task.backend === DownloadBackend.REQUEST_AGENT && !task.isPrivate) {
      await this.createAgentTask(task, undefined);
    }
  }

  setListener(listener: (tasks: DownloadTaskRecord[]) => void): void {
    this.listener = listener;
    this.notify();
  }

  private async begin(tabId: TabId, item: webview.WebDownloadItem, isPrivate: boolean): Promise<void> {
    const id: string = this.itemId(item);
    if (this.store.snapshot().some((task: DownloadTaskRecord) => task.id === id)) {
      return;
    }
    const url: string = item.getUrl();
    const filename: string = this.safeFilename(item.getSuggestedFileName(), id);
    const backend: DownloadBackend = classifyDownload(url, item.getMethod(), isPrivate);
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
      mimeType: item.getMimeType()
    };
    this.store.begin(task);
    if (backend === DownloadBackend.ARKWEB) {
      this.startNative(task, item);
      return;
    }
    await this.createAgentTask(task, item);
  }

  private async createAgentTask(task: DownloadTaskRecord, item: webview.WebDownloadItem | undefined): Promise<void> {
    try {
      const cookie: string = await this.cookie.fetchCookie(task.url, task.isPrivate);
      const handle: AgentTaskHandle = await this.agent.create({
        reconcileKey: task.reconcileKey,
        url: task.url,
        savePath: this.pathFor(task.filename, task.id),
        title: task.filename,
        description: 'jianyue-download:' + task.reconcileKey,
        headers: cookie.length === 0 ? {} : { Cookie: cookie },
        mimeType: task.mimeType ?? '',
        notificationEnabled: this.uiLoaded
      });
      this.store.patch(task.id, { agentTaskId: handle.taskId });
      this.attachAgentHandle(task.id, handle);
      if (item !== undefined) {
        this.intentionalArkWebCancels.add(task.id);
        item.cancel();
      }
      this.store.transition(task.id, DownloadStatus.RUNNING, { error: '' });
      this.notify();
    } catch (_error) {
      if (item === undefined) {
        this.store.transition(task.id, DownloadStatus.FAILED, { error: '后台下载创建失败；请重试。' });
        this.notify();
        return;
      }
      this.startNative(task, item);
    }
  }

  private startNative(task: DownloadTaskRecord, item: webview.WebDownloadItem): void {
    this.nativeItems.set(task.id, item);
    item.start(this.pathFor(task.filename, task.id));
    this.store.transition(task.id, DownloadStatus.RUNNING, { backend: DownloadBackend.ARKWEB, agentTaskId: '', error: '' });
    this.notify();
  }

  private attachAgentHandle(id: string, handle: AgentTaskHandle): void {
    this.handles.set(id, handle);
    handle.onProgress((snapshot: AgentTaskSnapshot) => {
      this.store.updateProgress(id, snapshot.receivedBytes, snapshot.totalBytes);
      this.notify();
    });
    handle.onCompleted((snapshot: AgentTaskSnapshot) => {
      this.store.transition(id, DownloadStatus.COMPLETED, {
        receivedBytes: snapshot.receivedBytes,
        totalBytes: snapshot.totalBytes,
        percent: 100
      });
      this.intentionalArkWebCancels.delete(id);
      this.notify();
    });
    handle.onFailed((snapshot: AgentTaskSnapshot) => {
      this.store.transition(id, DownloadStatus.FAILED, {
        error: snapshot.error ?? '后台下载失败；请重试。'
      });
      this.intentionalArkWebCancels.delete(id);
      this.notify();
    });
  }

  private findRecoveredTask(snapshot: AgentTaskSnapshot): DownloadTaskRecord | undefined {
    const reconcileKey: string = this.reconcileKeyFor(snapshot.description);
    return this.store.snapshot().find((task: DownloadTaskRecord) =>
      task.agentTaskId === snapshot.taskId || task.reconcileKey === reconcileKey ||
      (snapshot.savePath !== undefined && snapshot.savePath === this.pathFor(task.filename, task.id))
    );
  }

  private mergeAgentSnapshot(task: DownloadTaskRecord, snapshot: AgentTaskSnapshot): void {
    const status: DownloadStatus = this.statusFor(snapshot.status);
    this.store.mergeRecovered({
      ...task,
      agentTaskId: snapshot.taskId,
      status,
      receivedBytes: snapshot.receivedBytes,
      totalBytes: snapshot.totalBytes,
      percent: snapshot.percent,
      updatedAt: this.now(),
      error: snapshot.error
    });
  }

  private statusFor(value: string): DownloadStatus {
    const status: string = value.toLowerCase();
    if (status.includes('complete')) return DownloadStatus.COMPLETED;
    if (status.includes('fail')) return DownloadStatus.FAILED;
    if (status.includes('pause')) return DownloadStatus.PAUSED;
    if (status.includes('cancel')) return DownloadStatus.CANCELLED;
    return DownloadStatus.RUNNING;
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
    const recovered: AgentTaskHandle | undefined = await this.agent.getTask(task.agentTaskId);
    if (recovered !== undefined) {
      this.attachAgentHandle(id, recovered);
    }
    return recovered;
  }

  private itemId(item: webview.WebDownloadItem): string {
    const guid: string = item.getGuid().trim();
    if (guid.length > 0) {
      return guid;
    }
    this.pathSequence += 1;
    return `arkweb-${this.now()}-${this.pathSequence}`;
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
    return `${root}/${id.replace(/[^a-zA-Z0-9._-]/g, '_')}-${filename}`;
  }

  private reconcileKeyFor(description: string | undefined): string {
    const prefix: string = 'jianyue-download:';
    return description?.startsWith(prefix) ? description.slice(prefix.length) : '';
  }

  private isTerminal(status: DownloadStatus): boolean {
    return status === DownloadStatus.COMPLETED || status === DownloadStatus.FAILED ||
      status === DownloadStatus.CANCELLED;
  }

  private notify(): void {
    this.listener?.(this.store.snapshot());
  }
}
