import {
  BookmarkRecord,
  BrowserSessionSnapshot,
  BrowserTabRecord,
  displayUrlFor,
  HistoryRecord,
  lastValidUrlForTab,
  TabResidency
} from '../model/BrowserTypes';
import {
  BrowserSettings,
  copyBrowserSettings,
  DEFAULT_BROWSER_SETTINGS,
  normalizeBrowserSettings
} from '../model/BrowserSettings';
import {
  StartPageItem,
  sortStartPageItems,
  validStartPageItem
} from '../model/StartPageModels';
import { ClosedTabRecord } from './ClosedTabStack';
import { KeyValueStore } from './KeyValueStore';

const ACTIVE_SLOT_KEY: string = 'session.active';
const SLOT_A_KEY: string = 'session.a';
const SLOT_B_KEY: string = 'session.b';
const HISTORY_KEY: string = 'history.v1';
const BOOKMARKS_KEY: string = 'bookmarks.v1';
const SETTINGS_KEY: string = 'browser.settings.v1';
const START_PAGE_KEY: string = 'start.page.items.v1';
const CLOSED_TABS_KEY: string = 'closed.tabs.v1';
const MAX_HISTORY: number = 2000;
const MAX_CLOSED_TABS: number = 20;

export class BrowserRepository {
  private readonly store: KeyValueStore;

  constructor(store: KeyValueStore) {
    this.store = store;
  }

  async loadSession(): Promise<BrowserSessionSnapshot | undefined> {
    const active: string = await this.store.getString(ACTIVE_SLOT_KEY, 'a');
    const firstKey: string = active === 'b' ? SLOT_B_KEY : SLOT_A_KEY;
    const secondKey: string = firstKey === SLOT_A_KEY ? SLOT_B_KEY : SLOT_A_KEY;
    const first: BrowserSessionSnapshot | undefined = this.parseSession(
      await this.store.getString(firstKey, '')
    );
    if (first !== undefined) {
      return first;
    }
    return this.parseSession(await this.store.getString(secondKey, ''));
  }

  async saveSession(snapshot: BrowserSessionSnapshot): Promise<void> {
    const tabs: BrowserTabRecord[] = snapshot.tabs
      .filter((tab: BrowserTabRecord) => !tab.isPrivate)
      .map((tab: BrowserTabRecord) => this.copyTab(tab));
    if (tabs.length === 0) {
      return;
    }
    const activeTabId: string = tabs.some((tab: BrowserTabRecord) => tab.id === snapshot.activeTabId)
      ? snapshot.activeTabId
      : tabs[0].id;
    const safeSnapshot: BrowserSessionSnapshot = {
      version: 1,
      activeTabId,
      tabs
    };
    const active: string = await this.store.getString(ACTIVE_SLOT_KEY, 'a');
    const targetKey: string = active === 'b' ? SLOT_A_KEY : SLOT_B_KEY;
    const targetMarker: string = targetKey === SLOT_A_KEY ? 'a' : 'b';
    await this.store.putString(targetKey, JSON.stringify(safeSnapshot));
    await this.store.flush();
    await this.store.putString(ACTIVE_SLOT_KEY, targetMarker);
    await this.store.flush();
  }

  async recordHistory(record: HistoryRecord, isPrivate: boolean): Promise<void> {
    if (isPrivate || !this.validHistory(record)) {
      return;
    }
    const history: HistoryRecord[] = await this.listHistory();
    const latest: HistoryRecord | undefined = history[0];
    if (latest !== undefined && latest.url === record.url) {
      history[0] = this.copyHistory(record);
    } else {
      history.unshift(this.copyHistory(record));
    }
    const bounded: HistoryRecord[] = history.slice(0, MAX_HISTORY);
    await this.writeJson(HISTORY_KEY, bounded);
  }

  async listHistory(): Promise<HistoryRecord[]> {
    const raw: string = await this.store.getString(HISTORY_KEY, '[]');
    try {
      const parsed: HistoryRecord[] = JSON.parse(raw) as HistoryRecord[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      return parsed
        .filter((record: HistoryRecord) => this.validHistory(record))
        .map((record: HistoryRecord) => this.copyHistory(record))
        .slice(0, MAX_HISTORY);
    } catch (_error) {
      return [];
    }
  }

  async removeHistory(url: string): Promise<void> {
    const target: string = url.trim();
    if (target.length === 0) {
      return;
    }
    const history: HistoryRecord[] = await this.listHistory();
    const remaining: HistoryRecord[] = history.filter((record: HistoryRecord) => record.url !== target);
    if (remaining.length !== history.length) {
      await this.writeJson(HISTORY_KEY, remaining);
    }
  }

  async removeHistoryBefore(cutoff: number): Promise<void> {
    if (!Number.isFinite(cutoff)) {
      return;
    }
    const history: HistoryRecord[] = await this.listHistory();
    const remaining: HistoryRecord[] = history.filter((record: HistoryRecord) => record.visitedAt >= cutoff);
    if (remaining.length !== history.length) {
      await this.writeJson(HISTORY_KEY, remaining);
    }
  }

  /** Removes records at or after a local-calendar cutoff, used by batch menus. */
  async removeHistoryFrom(cutoff: number): Promise<void> {
    if (!Number.isFinite(cutoff)) {
      return;
    }
    const history: HistoryRecord[] = await this.listHistory();
    const remaining: HistoryRecord[] = history.filter((record: HistoryRecord) => record.visitedAt < cutoff);
    if (remaining.length !== history.length) {
      await this.writeJson(HISTORY_KEY, remaining);
    }
  }

  async clearHistory(): Promise<void> {
    const history: HistoryRecord[] = await this.listHistory();
    if (history.length > 0) {
      await this.writeJson(HISTORY_KEY, []);
    }
  }

  async addBookmark(record: BookmarkRecord, isPrivate: boolean = false): Promise<void> {
    if (isPrivate || !this.validBookmark(record)) {
      return;
    }
    const bookmarks: BookmarkRecord[] = await this.listBookmarks();
    if (bookmarks.some((item: BookmarkRecord) => item.url === record.url)) {
      return;
    }
    bookmarks.push(this.copyBookmark(record));
    await this.writeJson(BOOKMARKS_KEY, bookmarks);
  }

  async removeBookmark(url: string): Promise<void> {
    if (url.length === 0) {
      return;
    }
    const bookmarks: BookmarkRecord[] = await this.listBookmarks();
    const remaining: BookmarkRecord[] = bookmarks.filter((item: BookmarkRecord) => item.url !== url);
    if (remaining.length !== bookmarks.length) {
      await this.writeJson(BOOKMARKS_KEY, remaining);
    }
  }

  async listBookmarks(): Promise<BookmarkRecord[]> {
    const raw: string = await this.store.getString(BOOKMARKS_KEY, '[]');
    try {
      const parsed: BookmarkRecord[] = JSON.parse(raw) as BookmarkRecord[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      return parsed
        .filter((record: BookmarkRecord) => this.validBookmark(record))
        .map((record: BookmarkRecord) => this.copyBookmark(record));
    } catch (_error) {
      return [];
    }
  }

  async loadSettings(): Promise<BrowserSettings> {
    const raw: string = await this.store.getString(SETTINGS_KEY, '');
    if (raw.length === 0) {
      return copyBrowserSettings(DEFAULT_BROWSER_SETTINGS);
    }
    try {
      return normalizeBrowserSettings(JSON.parse(raw) as Object);
    } catch (_error) {
      return copyBrowserSettings(DEFAULT_BROWSER_SETTINGS);
    }
  }

  async saveSettings(settings: BrowserSettings): Promise<void> {
    await this.writeJson(SETTINGS_KEY, copyBrowserSettings(settings));
  }

  async listStartPageItems(): Promise<StartPageItem[]> {
    const raw: string = await this.store.getString(START_PAGE_KEY, '[]');
    return this.parseStartPageItems(raw);
  }

  async saveStartPageItems(items: StartPageItem[]): Promise<void> {
    const valid: StartPageItem[] = items.filter((item: StartPageItem) => validStartPageItem(item));
    await this.writeJson(START_PAGE_KEY, sortStartPageItems(valid));
  }

  async loadClosedTabs(): Promise<ClosedTabRecord[]> {
    const raw: string = await this.store.getString(CLOSED_TABS_KEY, '[]');
    try {
      const parsed: ClosedTabRecord[] = JSON.parse(raw) as ClosedTabRecord[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      return parsed
        .filter((record: ClosedTabRecord) => this.validClosedTab(record))
        .map((record: ClosedTabRecord) => this.copyClosedTab(record))
        .sort((left: ClosedTabRecord, right: ClosedTabRecord) => right.closedAt - left.closedAt)
        .slice(0, MAX_CLOSED_TABS);
    } catch (_error) {
      return [];
    }
  }

  async saveClosedTabs(records: ClosedTabRecord[]): Promise<void> {
    const valid: ClosedTabRecord[] = records
      .filter((record: ClosedTabRecord) => this.validClosedTab(record))
      .filter((record: ClosedTabRecord) => !record.isPrivate)
      .map((record: ClosedTabRecord) => this.copyClosedTab(record))
      .sort((left: ClosedTabRecord, right: ClosedTabRecord) => right.closedAt - left.closedAt)
      .slice(0, MAX_CLOSED_TABS);
    await this.writeJson(CLOSED_TABS_KEY, valid);
  }

  private async writeJson(key: string, value: Object): Promise<void> {
    await this.store.putString(key, JSON.stringify(value));
    await this.store.flush();
  }

  private parseStartPageItems(raw: string): StartPageItem[] {
    try {
      const parsed: StartPageItem[] = JSON.parse(raw) as StartPageItem[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      return sortStartPageItems(parsed.filter((item: StartPageItem) => validStartPageItem(item)));
    } catch (_error) {
      return [];
    }
  }

  private validClosedTab(record: ClosedTabRecord): boolean {
    return record !== undefined && typeof record.id === 'string' && record.id.length > 0 &&
      typeof record.url === 'string' && record.url.length > 0 && typeof record.title === 'string' &&
      typeof record.isPrivate === 'boolean' && typeof record.closedAt === 'number' &&
      Number.isFinite(record.closedAt) && typeof record.thumbnailKey === 'string';
  }

  private copyClosedTab(record: ClosedTabRecord): ClosedTabRecord {
    return {
      id: record.id,
      url: record.url,
      title: record.title,
      isPrivate: record.isPrivate,
      closedAt: record.closedAt,
      thumbnailKey: record.thumbnailKey
    };
  }

  private parseSession(raw: string): BrowserSessionSnapshot | undefined {
    if (raw.length === 0) {
      return undefined;
    }
    try {
      const parsed: BrowserSessionSnapshot = JSON.parse(raw) as BrowserSessionSnapshot;
      if (parsed.version !== 1 || !Array.isArray(parsed.tabs)) {
        return undefined;
      }
      const tabs: BrowserTabRecord[] = parsed.tabs
        .filter((tab: BrowserTabRecord) => this.validNormalTab(tab))
        .map((tab: BrowserTabRecord) => this.copyTab(tab));
      if (tabs.length === 0) {
        return undefined;
      }
      const activeTabId: string = typeof parsed.activeTabId === 'string' &&
        tabs.some((tab: BrowserTabRecord) => tab.id === parsed.activeTabId)
        ? parsed.activeTabId
        : tabs[0].id;
      return {
        version: 1,
        activeTabId,
        tabs
      };
    } catch (_error) {
      return undefined;
    }
  }

  private validNormalTab(tab: BrowserTabRecord): boolean {
    return tab !== undefined && typeof tab.id === 'string' && tab.id.length > 0 &&
      typeof tab.url === 'string' && tab.url.length > 0 && typeof tab.title === 'string' &&
      tab.isPrivate === false && typeof tab.createdAt === 'number' && Number.isFinite(tab.createdAt) &&
      typeof tab.lastAccessedAt === 'number' && Number.isFinite(tab.lastAccessedAt);
  }

  private validHistory(record: HistoryRecord): boolean {
    return record !== undefined && typeof record.url === 'string' && record.url.length > 0 &&
      record.url !== 'about:blank' &&
      typeof record.title === 'string' && typeof record.visitedAt === 'number' &&
      Number.isFinite(record.visitedAt);
  }

  private validBookmark(record: BookmarkRecord): boolean {
    return record !== undefined && typeof record.url === 'string' && record.url.length > 0 &&
      typeof record.title === 'string' && typeof record.createdAt === 'number' &&
      Number.isFinite(record.createdAt);
  }

  private copyTab(tab: BrowserTabRecord): BrowserTabRecord {
    const canonicalUrl: string = lastValidUrlForTab(tab);
    return {
      id: tab.id,
      url: canonicalUrl,
      lastValidUrl: canonicalUrl,
      displayUrl: displayUrlFor(canonicalUrl),
      pageSnapshot: tab.pageSnapshot === undefined ? tab.thumbnailKey : tab.pageSnapshot,
      title: tab.title,
      isPrivate: false,
      createdAt: tab.createdAt,
      lastAccessedAt: tab.lastAccessedAt,
      thumbnailKey: tab.thumbnailKey,
      residency: TabResidency.COLD,
      addressSource: tab.addressSource,
      addressQuery: tab.addressQuery
    };
  }

  private copyHistory(record: HistoryRecord): HistoryRecord {
    return {
      url: record.url,
      title: record.title,
      visitedAt: record.visitedAt
    };
  }

  private copyBookmark(record: BookmarkRecord): BookmarkRecord {
    return {
      url: record.url,
      title: record.title,
      createdAt: record.createdAt
    };
  }
}
