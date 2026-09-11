import { PendingTabDraft, TabId } from '../model/BrowserTypes';
import { TabStore } from '../store/TabStore';

export interface TabRuntimePort {
  ensureBalanced(): void;
  release(tabId: TabId): void;
  goBack(tabId: TabId): boolean;
  goForward(tabId: TabId): boolean;
  reload(tabId: TabId): void;
}

export interface SnapshotPort {
  remove(tabId: TabId): Promise<void>;
}

export interface SessionPort {
  save(): Promise<void>;
}

export class NoopSnapshotPort implements SnapshotPort {
  async remove(_tabId: TabId): Promise<void> {}
}

export class NoopSessionPort implements SessionPort {
  async save(): Promise<void> {}
}

export class DefaultBrowserCommandDispatcher {
  private tail: Promise<void> = Promise.resolve();
  private readonly closing: Set<TabId> = new Set();
  private readonly store: TabStore;
  private readonly runtime: TabRuntimePort;
  private readonly snapshots: SnapshotPort;
  private readonly session: SessionPort;

  constructor(
    store: TabStore,
    runtime: TabRuntimePort,
    snapshots: SnapshotPort,
    session: SessionPort
  ) {
    this.store = store;
    this.runtime = runtime;
    this.snapshots = snapshots;
    this.session = session;
  }

  activateTab(tabId: TabId): Promise<void> {
    return this.enqueue(async () => {
      if (this.store.activateTab(tabId)) {
        this.runtime.ensureBalanced();
        await this.session.save();
      }
    });
  }

  createTab(url: string, isPrivate: boolean): Promise<TabId> {
    return this.enqueue(async () => {
      const tabId: TabId = this.store.createTab(url, isPrivate);
      this.runtime.ensureBalanced();
      await this.session.save();
      return tabId;
    });
  }

  reserveTab(url: string, isPrivate: boolean): PendingTabDraft {
    return this.store.reserveTab(url, isPrivate);
  }

  commitReservedTab(draft: PendingTabDraft): Promise<TabId> {
    return this.enqueue(async () => {
      const tabId: TabId = this.store.commitReservedTab(draft);
      this.runtime.ensureBalanced();
      await this.session.save();
      return tabId;
    });
  }

  closeTab(tabId: TabId): Promise<void> {
    if (this.closing.has(tabId)) {
      return this.tail;
    }
    this.closing.add(tabId);
    return this.enqueue(async () => {
      try {
        const result = this.store.closeTab(tabId);
        if (!result.closed) {
          return;
        }
        this.runtime.release(tabId);
        await this.snapshots.remove(tabId);
        this.runtime.ensureBalanced();
        await this.session.save();
      } finally {
        this.closing.delete(tabId);
      }
    });
  }

  goBack(): boolean {
    return this.store.activeTabId !== '' && this.runtime.goBack(this.store.activeTabId);
  }

  goForward(): boolean {
    return this.store.activeTabId !== '' && this.runtime.goForward(this.store.activeTabId);
  }

  reloadActiveTab(): void {
    if (this.store.activeTabId !== '') {
      this.runtime.reload(this.store.activeTabId);
    }
  }

  private enqueue<T>(operation: () => Promise<T>): Promise<T> {
    const next: Promise<T> = this.tail.then(operation, operation);
    this.tail = next.then(() => undefined, () => undefined);
    return next;
  }
}
