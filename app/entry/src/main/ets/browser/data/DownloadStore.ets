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
  private persistenceTail: Promise<void> = Promise.resolve();

  constructor(storage: DownloadRecordStorage, now: () => number = () => Date.now()) {
    this.storage = storage;
    this.now = now;
  }

  async restore(): Promise<void> {
    let recovered: DownloadTaskRecord[] = [];
    let loaded: boolean = true;
    try {
      recovered = await this.storage.load();
    } catch (_error) {
      loaded = false;
    }
    // A download can arrive while storage is suspended in load(). Preserve
    // the live in-memory records before replacing the recovered view; the
    // service-level restore gate also keeps this merge from racing begin().
    const liveRecords: DownloadTaskRecord[] = this.records.map(
      (task: DownloadTaskRecord): DownloadTaskRecord => this.copy(task)
    );
    this.records = [];
    recovered.forEach((task: DownloadTaskRecord) => this.mergeRecovered(task, false));
    liveRecords.forEach((task: DownloadTaskRecord) => {
      const existing: DownloadTaskRecord | undefined = this.records.find(
        (candidate: DownloadTaskRecord): boolean => candidate.id === task.id
      );
      if (existing === undefined) {
        this.records.push(this.copy(task));
      } else {
        const index: number = this.records.indexOf(existing);
        this.records[index] = this.copy(task);
      }
    });
    if (liveRecords.length > 0 || (loaded && recovered.length > 0)) {
      this.persist();
    }
  }

  async flush(): Promise<void> {
    await this.persistenceTail;
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
    const hasAgentTaskId: boolean = task.agentTaskId.trim().length > 0;
    const agentMatch: DownloadTaskRecord | undefined = hasAgentTaskId
      ? this.records.find((candidate: DownloadTaskRecord) => candidate.agentTaskId === task.agentTaskId)
      : undefined;
    const existing: DownloadTaskRecord | undefined = agentMatch ??
      (task.reconcileKey.trim().length > 0
        ? this.records.find((candidate: DownloadTaskRecord) => candidate.reconcileKey === task.reconcileKey)
        : undefined);
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
    if (patch.savePath !== undefined) target.savePath = patch.savePath;
    target.updatedAt = this.now();
  }

  private isTerminal(status: DownloadStatus): boolean {
    return status === DownloadStatus.COMPLETED || status === DownloadStatus.FAILED ||
      status === DownloadStatus.CANCELLED;
  }

  private persist(): void {
    const snapshot: DownloadTaskRecord[] = this.snapshot();
    const save: () => Promise<void> = (): Promise<void> => this.storage.save(snapshot);
    this.persistenceTail = this.persistenceTail.then(save, save).catch((): void => undefined);
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
    if (task.savePath !== undefined) copy.savePath = task.savePath;
    if (task.mimeType !== undefined) copy.mimeType = task.mimeType;
    if (task.error !== undefined) copy.error = task.error;
    return copy;
  }
}
