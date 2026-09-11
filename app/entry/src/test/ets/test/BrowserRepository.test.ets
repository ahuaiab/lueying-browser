import { describe, expect, it } from '@ohos/hypium';
import {
  BookmarkRecord,
  BrowserSessionSnapshot,
  HistoryRecord,
  TabResidency
} from '../../../main/ets/browser/model/BrowserTypes';
import { BrowserRepository } from '../../../main/ets/browser/data/BrowserRepository';
import { KeyValueStore } from '../../../main/ets/browser/data/KeyValueStore';

class FakeKeyValueStore implements KeyValueStore {
  private readonly values: Map<string, string>;

  constructor(initial: Map<string, string> = new Map()) {
    this.values = initial;
  }

  async getString(key: string, fallback: string): Promise<string> {
    return this.values.get(key) ?? fallback;
  }

  async putString(key: string, value: string): Promise<void> {
    this.values.set(key, value);
  }

  async flush(): Promise<void> {}

  allValues(): string[] {
    return Array.from(this.values.values());
  }
}

function normalSession(): BrowserSessionSnapshot {
  return {
    version: 1,
    activeTabId: 'normal',
    tabs: [{
      id: 'normal',
      url: 'https://normal.example',
      lastValidUrl: 'https://normal.example',
      displayUrl: 'normal.example',
      pageSnapshot: '',
      title: 'Normal',
      isPrivate: false,
      createdAt: 1,
      lastAccessedAt: 1,
      thumbnailKey: '',
      residency: TabResidency.COLD
    }]
  };
}

export default function browserRepositoryTest() {
  describe('BrowserRepository', () => {
    it('falls back to the previous complete session slot', 0, async () => {
      const valid: BrowserSessionSnapshot = normalSession();
      const store: FakeKeyValueStore = new FakeKeyValueStore(new Map([
        ['session.active', 'b'],
        ['session.a', JSON.stringify(valid)],
        ['session.b', '{broken']
      ]));
      const repository: BrowserRepository = new BrowserRepository(store);
      const session: BrowserSessionSnapshot | undefined = await repository.loadSession();
      expect(session?.tabs.length).assertEqual(1);
      expect(session?.activeTabId).assertEqual('normal');
    });

    it('does not persist private tabs or private history', 0, async () => {
      const store: FakeKeyValueStore = new FakeKeyValueStore();
      const repository: BrowserRepository = new BrowserRepository(store);
      const privateSession: BrowserSessionSnapshot = {
        version: 1,
        activeTabId: 'private',
        tabs: [{
          id: 'private',
          url: 'https://private.example',
          lastValidUrl: 'https://private.example',
          displayUrl: 'private.example',
          pageSnapshot: '',
          title: 'Private',
          isPrivate: true,
          createdAt: 1,
          lastAccessedAt: 1,
          thumbnailKey: '',
          residency: TabResidency.COLD
        }]
      };
      const history: HistoryRecord = {
        url: 'https://private.example',
        title: 'Private',
        visitedAt: 1
      };
      await repository.saveSession(privateSession);
      await repository.recordHistory(history, true);
      expect(store.allValues().join('').includes('https://private.example')).assertFalse();
    });

    it('keeps history newest-first, collapses consecutive URLs and bounds it', 0, async () => {
      const repository: BrowserRepository = new BrowserRepository(new FakeKeyValueStore());
      await repository.recordHistory({ url: 'https://same.example', title: 'old', visitedAt: 1 }, false);
      await repository.recordHistory({ url: 'https://same.example', title: 'new', visitedAt: 2 }, false);
      const collapsed: HistoryRecord[] = await repository.listHistory();
      expect(collapsed.length).assertEqual(1);
      expect(collapsed[0].title).assertEqual('new');
      for (let index: number = 0; index < 2001; index += 1) {
        await repository.recordHistory({
          url: `https://host-${index}.example`,
          title: `${index}`,
          visitedAt: index + 3
        }, false);
      }
      const bounded: HistoryRecord[] = await repository.listHistory();
      expect(bounded.length).assertEqual(2000);
      expect(bounded[0].url).assertEqual('https://host-2000.example');
    });

    it('deletes history before, from, and across an empty collection idempotently', 0, async () => {
      const store: FakeKeyValueStore = new FakeKeyValueStore();
      const repository: BrowserRepository = new BrowserRepository(store);
      await repository.recordHistory({ url: 'https://new.example', title: 'New', visitedAt: 30 }, false);
      await repository.recordHistory({ url: 'https://middle.example', title: 'Middle', visitedAt: 20 }, false);
      await repository.recordHistory({ url: 'https://old.example', title: 'Old', visitedAt: 10 }, false);

      await repository.removeHistoryBefore(20);
      let history: HistoryRecord[] = await repository.listHistory();
      expect(history.length).assertEqual(2);
      expect(history.some((record: HistoryRecord) => record.url === 'https://old.example')).assertFalse();

      await repository.removeHistoryFrom(30);
      history = await repository.listHistory();
      expect(history.length).assertEqual(1);
      expect(history[0].url).assertEqual('https://middle.example');

      await repository.removeHistoryFrom(30);
      await repository.clearHistory();
      await repository.clearHistory();
      expect((await repository.listHistory()).length).assertEqual(0);
    });

    it('deduplicates bookmarks while preserving insertion order', 0, async () => {
      const repository: BrowserRepository = new BrowserRepository(new FakeKeyValueStore());
      const first: BookmarkRecord = { url: 'https://a.example', title: 'A', createdAt: 1 };
      const second: BookmarkRecord = { url: 'https://b.example', title: 'B', createdAt: 2 };
      await repository.addBookmark(first);
      await repository.addBookmark(first);
      await repository.addBookmark(second);
      let bookmarks: BookmarkRecord[] = await repository.listBookmarks();
      expect(bookmarks.length).assertEqual(2);
      expect(bookmarks[0].url).assertEqual('https://a.example');
      await repository.removeBookmark(first.url);
      bookmarks = await repository.listBookmarks();
      expect(bookmarks.length).assertEqual(1);
      expect(bookmarks[0].url).assertEqual('https://b.example');
    });

    it('discards malformed rows instead of failing the collection', 0, async () => {
      const store: FakeKeyValueStore = new FakeKeyValueStore(new Map([
        ['history.v1', JSON.stringify([
          { url: 'https://valid.example', title: 'valid', visitedAt: 1 },
          { url: '', title: 'invalid', visitedAt: 2 },
          { url: 'https://bad-time.example', title: 'invalid', visitedAt: 'bad' }
        ])],
        ['bookmarks.v1', JSON.stringify([
          { url: 'https://bookmark.example', title: 'valid', createdAt: 3 },
          { url: 'https://bad.example', title: 'invalid', createdAt: null }
        ])]
      ]));
      const repository: BrowserRepository = new BrowserRepository(store);
      expect((await repository.listHistory()).length).assertEqual(1);
      expect((await repository.listBookmarks()).length).assertEqual(1);
    });
  });
}
