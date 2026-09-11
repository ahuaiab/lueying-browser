import {
  DownloadProgressSnapshot,
  DownloadStatus,
  DownloadTaskPatch,
  DownloadTaskRecord,
  percentForDownload
} from '../model/DownloadModels';

export interface DownloadRecordStorage {
  load(): Promise<DownloadTaskRecord[]>;
  save(records: DownloadTaskRecord[]): Promise<void>;
}

export class DownloadStore {
  private readonly storage: DownloadRecordStorage;
  private readonly now: () => number;
  private records: DownloadTaskRecord[] = [];

  constructor(storage: DownloadRecordStorage, now: () => number = () => Date.now()) {
    this.storage = storage;
    this.now = now;
  }

  async restore(): Promise<void> {
    const recovered: DownloadTaskRecord[] = await this.storage.load();
    this.records = [];
    recovered.forEach((task: DownloadTaskRecord) => this.mergeRecovered(task, false));
  }

  begin(task: DownloadTaskRecord): void {
    this.records.push(this.copy(task));
    this.persist();
  }

  updateProgress(id: string, receivedBytes: number, totalBytes: number): void {
    const target: DownloadTaskRecord | undefined = this.records.find((task: DownloadTaskRecord) => task.id === id);
    if (target === undefined || this.isTerminal(target.status)) {
      return;
    }
    this.applyPatch(target, {
      receivedBytes,
      totalBytes,
      percent: percentForDownload(receivedBytes, totalBytes)
    });
    this.persist();
  }

  patch(id: string, patch: DownloadTaskPatch): void {
    const target: DownloadTaskRecord | undefined = this.records.find((task: DownloadTaskRecord) => task.id === id);
    if (target === undefined) {
      return;
    }
    this.applyPatch(target, patch);
    this.persist();
  }

  transition(id: string, status: DownloadStatus, patch: DownloadTaskPatch): void {
    const target: DownloadTaskRecord | undefined = this.records.find((task: DownloadTaskRecord) => task.id === id);
    if (target === undefined) {
      return;
    }
    this.applyPatch(target, patch);
    target.status = status;
    target.updatedAt = this.now();
    this.persist();
  }

  mergeRecovered(task: DownloadTaskRecord, persist: boolean = true): void {
    const existing: DownloadTaskRecord | undefined = this.records.find(
      (candidate: DownloadTaskRecord) => candidate.agentTaskId === task.agentTaskId ||
        candidate.reconcileKey === task.reconcileKey
    );
    if (existing === undefined) {
      this.records.push(this.copy(task));
    } else if (task.updatedAt > existing.updatedAt) {
      const index: number = this.records.indexOf(existing);
      this.records[index] = this.copy(task);
    }
    if (persist) {
      this.persist();
    }
  }

  remove(id: string): void {
    this.records = this.records.filter((task: DownloadTaskRecord) => task.id !== id);
    this.persist();
  }

  snapshot(): DownloadTaskRecord[] {
    return this.records.map((task: DownloadTaskRecord) => this.copy(task));
  }

  activeForTab(tabId: string): DownloadProgressSnapshot | undefined {
    const active: DownloadTaskRecord[] = this.records.filter(
      (task: DownloadTaskRecord) => task.tabId === tabId && !this.isTerminal(task.status)
    );
    if (active.length === 0) {
      return undefined;
    }
    const newest: DownloadTaskRecord = active.reduce(
      (current: DownloadTaskRecord, task: DownloadTaskRecord) => task.updatedAt > current.updatedAt ? task : current
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

  private applyPatch(target: DownloadTaskRecord, patch: DownloadTaskPatch): void {
    if (patch.agentTaskId !== undefined) target.agentTaskId = patch.agentTaskId;
    if (patch.reconcileKey !== undefined) target.reconcileKey = patch.reconcileKey;
    if (patch.tabId !== undefined) target.tabId = patch.tabId;
    if (patch.url !== undefined) target.url = patch.url;
    if (patch.filename !== undefined) target.filename = patch.filename;
    if (patch.backend !== undefined) target.backend = patch.backend;
    if (patch.receivedBytes !== undefined) target.receivedBytes = patch.receivedBytes;
    if (patch.totalBytes !== undefined) target.totalBytes = patch.totalBytes;
    if (patch.percent !== undefined) target.percent = patch.percent;
    if (patch.error !== undefined) target.error = patch.error;
    if (patch.mimeType !== undefined) target.mimeType = patch.mimeType;
    if (patch.isPrivate !== undefined) target.isPrivate = patch.isPrivate;
    target.updatedAt = this.now();
  }

  private isTerminal(status: DownloadStatus): boolean {
    return status === DownloadStatus.COMPLETED || status === DownloadStatus.FAILED ||
      status === DownloadStatus.CANCELLED;
  }

  private persist(): void {
    this.storage.save(this.snapshot());
  }

  private copy(task: DownloadTaskRecord): DownloadTaskRecord {
    const copy: DownloadTaskRecord = {
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
      isPrivate: task.isPrivate
    };
    if (task.mimeType !== undefined) copy.mimeType = task.mimeType;
    if (task.error !== undefined) copy.error = task.error;
    return copy;
  }
}
