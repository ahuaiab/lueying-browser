import {
  AddressBarSource,
  BrowserSessionSnapshot,
  BrowserTabRecord,
  CloseTabResult,
  displayUrlFor,
  lastValidUrlForTab,
  loadableUrlFor,
  PendingTabDraft,
  TabDirection,
  TabId,
  TabResidency
} from '../model/BrowserTypes';

@ObservedV2
export class TabStore {
  @Trace tabs: BrowserTabRecord[] = [];
  @Trace activeTabId: TabId = '';
  private readonly now: () => number;
  private readonly deterministicIds: string[];
  private sequence: number = 0;

  constructor(now: () => number = () => Date.now(), ids: string[] = []) {
    this.now = now;
    this.deterministicIds = ids.slice();
  }

  private nextId(): string {
    const supplied = this.deterministicIds.shift();
    if (supplied !== undefined) {
      return supplied;
    }
    this.sequence += 1;
    return `tab-${this.now()}-${this.sequence}`;
  }

  private copyWithResidency(tab: BrowserTabRecord, residency: TabResidency): BrowserTabRecord {
    const canonicalUrl: string = lastValidUrlForTab(tab);
    return {
      id: tab.id,
      url: canonicalUrl,
      lastValidUrl: canonicalUrl,
      displayUrl: displayUrlFor(canonicalUrl),
      pageSnapshot: tab.pageSnapshot === undefined ? tab.thumbnailKey : tab.pageSnapshot,
      // Older sessions may have persisted ArkWeb's `about:blank` title for
      // the local start page. Restore the Safari-facing name so it remains
      // discoverable from the tab overview search field.
      title: canonicalUrl === 'about:blank' && tab.title === 'about:blank' ? '起始页' : tab.title,
      isPrivate: tab.isPrivate,
      createdAt: tab.createdAt,
      lastAccessedAt: tab.lastAccessedAt,
      thumbnailKey: tab.thumbnailKey,
      residency,
      addressSource: tab.addressSource,
      addressQuery: tab.addressQuery
    };
  }

  private newTabRecord(url: string, isPrivate: boolean): BrowserTabRecord {
    const id = this.nextId();
    const timestamp = this.now();
    const canonicalUrl: string = loadableUrlFor(url) ?? 'about:blank';
    return {
      id,
      url: canonicalUrl,
      lastValidUrl: canonicalUrl,
      displayUrl: displayUrlFor(canonicalUrl),
      pageSnapshot: '',
      title: canonicalUrl === 'about:blank' ? '起始页' : canonicalUrl,
      isPrivate,
      createdAt: timestamp,
      lastAccessedAt: timestamp,
      thumbnailKey: '',
      residency: TabResidency.COLD
    };
  }

  createTab(url: string = 'about:blank', isPrivate: boolean = false): TabId {
    return this.commitReservedTab(this.reserveTab(url, isPrivate));
  }

  reserveTab(url: string = 'about:blank', isPrivate: boolean = false): PendingTabDraft {
    return { tab: this.newTabRecord(url, isPrivate) };
  }

  commitReservedTab(draft: PendingTabDraft): TabId {
    const existing: BrowserTabRecord | undefined = this.tabs.find(
      (tab: BrowserTabRecord) => tab.id === draft.tab.id
    );
    if (existing === undefined) {
      this.tabs.push(draft.tab);
    }
    this.activateTab(draft.tab.id);
    return draft.tab.id;
  }

  activateTab(id: TabId): boolean {
    const target = this.tabs.find((tab: BrowserTabRecord) => tab.id === id);
    if (target === undefined) {
      return false;
    }
    this.activeTabId = id;
    target.lastAccessedAt = this.now();
    return true;
  }

  updateTabUrl(
    id: TabId,
    url: string,
    title: string = url,
    addressSource: AddressBarSource | undefined = undefined,
    addressQuery: string | undefined = undefined
  ): boolean {
    const target: BrowserTabRecord | undefined = this.tabs.find((tab: BrowserTabRecord) => tab.id === id);
    if (target === undefined) {
      return false;
    }
    const canonicalUrl: string | undefined = loadableUrlFor(url);
    if (canonicalUrl === undefined) {
      return false;
    }
    this.tabs = this.tabs.map((tab: BrowserTabRecord) => tab.id === id ? {
      id: tab.id,
      url: canonicalUrl,
      lastValidUrl: canonicalUrl,
      displayUrl: displayUrlFor(canonicalUrl),
      pageSnapshot: target.pageSnapshot === undefined ? target.thumbnailKey : target.pageSnapshot,
      title,
      isPrivate: tab.isPrivate,
      createdAt: tab.createdAt,
      lastAccessedAt: tab.lastAccessedAt,
      thumbnailKey: tab.thumbnailKey,
      residency: tab.residency,
      addressSource: addressSource ?? target.addressSource,
      addressQuery: (addressSource ?? target.addressSource) === 'search'
        ? addressQuery ?? target.addressQuery
        : undefined
    } : tab);
    return true;
  }

  updateTabTitle(id: TabId, title: string): boolean {
    const target: BrowserTabRecord | undefined = this.tabs.find((tab: BrowserTabRecord) => tab.id === id);
    if (target === undefined) {
      return false;
    }
    this.tabs = this.tabs.map((tab: BrowserTabRecord) => tab.id === id ? {
      id: tab.id,
      url: tab.url,
      lastValidUrl: lastValidUrlForTab(tab),
      displayUrl: displayUrlFor(lastValidUrlForTab(tab)),
      pageSnapshot: tab.pageSnapshot === undefined ? tab.thumbnailKey : tab.pageSnapshot,
      title,
      isPrivate: tab.isPrivate,
      createdAt: tab.createdAt,
      lastAccessedAt: tab.lastAccessedAt,
      thumbnailKey: tab.thumbnailKey,
      residency: tab.residency,
      addressSource: target.addressSource,
      addressQuery: target.addressQuery
    } : tab);
    return true;
  }

  updateThumbnailKey(id: TabId, thumbnailKey: string): boolean {
    const target: BrowserTabRecord | undefined = this.tabs.find((tab: BrowserTabRecord) => tab.id === id);
    if (target === undefined) {
      return false;
    }
    this.tabs = this.tabs.map((tab: BrowserTabRecord) => tab.id === id ? {
      id: tab.id,
      url: tab.url,
      lastValidUrl: lastValidUrlForTab(tab),
      displayUrl: displayUrlFor(lastValidUrlForTab(tab)),
      pageSnapshot: thumbnailKey,
      title: tab.title,
      isPrivate: tab.isPrivate,
      createdAt: tab.createdAt,
      lastAccessedAt: tab.lastAccessedAt,
      thumbnailKey,
      residency: tab.residency,
      addressSource: target.addressSource,
      addressQuery: target.addressQuery
    } : tab);
    return true;
  }

  adjacentTabId(direction: TabDirection): TabId | undefined {
    const index = this.tabs.findIndex((tab: BrowserTabRecord) => tab.id === this.activeTabId);
    const targetIndex = index + direction;
    if (index < 0 || targetIndex < 0 || targetIndex >= this.tabs.length) {
      return undefined;
    }
    return this.tabs[targetIndex].id;
  }

  closeTab(id: TabId): CloseTabResult {
    const index = this.tabs.findIndex((tab: BrowserTabRecord) => tab.id === id);
    if (index < 0) {
      return { closed: false, activeTabId: this.activeTabId, createdReplacement: false };
    }
    const wasActive = this.activeTabId === id;
    this.tabs.splice(index, 1);
    if (this.tabs.length === 0) {
      const replacement = this.createTab('about:blank', false);
      return { closed: true, activeTabId: replacement, createdReplacement: true };
    }
    if (wasActive) {
      const nextIndex = Math.min(index, this.tabs.length - 1);
      this.activateTab(this.tabs[nextIndex].id);
    }
    return { closed: true, activeTabId: this.activeTabId, createdReplacement: false };
  }

  reorder(fromIndex: number, toIndex: number): boolean {
    if (fromIndex < 0 || toIndex < 0 || fromIndex >= this.tabs.length || toIndex >= this.tabs.length) {
      return false;
    }
    const moved = this.tabs.splice(fromIndex, 1)[0];
    if (moved === undefined) {
      return false;
    }
    this.tabs.splice(toIndex, 0, moved);
    return true;
  }

  restore(snapshot: BrowserSessionSnapshot): void {
    this.tabs = snapshot.tabs.map((tab: BrowserTabRecord) => this.copyWithResidency(tab, TabResidency.COLD));
    this.activeTabId = this.tabs.some((tab: BrowserTabRecord) => tab.id === snapshot.activeTabId)
      ? snapshot.activeTabId
      : (this.tabs[0]?.id ?? '');
    if (this.tabs.length === 0) {
      this.createTab('about:blank', false);
    }
  }

  snapshot(): BrowserSessionSnapshot {
    const normalTabs = this.tabs.filter((tab: BrowserTabRecord) => !tab.isPrivate)
      .map((tab: BrowserTabRecord) => this.copyWithResidency(tab, TabResidency.COLD));
    return {
      version: 1,
      activeTabId: normalTabs.some((tab: BrowserTabRecord) => tab.id === this.activeTabId)
        ? this.activeTabId
        : (normalTabs[0]?.id ?? ''),
      tabs: normalTabs
    };
  }
}
