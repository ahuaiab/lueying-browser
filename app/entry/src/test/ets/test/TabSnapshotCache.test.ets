import { describe, expect, it } from '@ohos/hypium';
import { SnapshotStorage, TabSnapshotCache } from '../../../main/ets/browser/snapshot/TabSnapshotCache';

class FakeSnapshotStorage implements SnapshotStorage {
  readonly values: Map<string, Uint8Array> = new Map();
  writes: number = 0;

  async read(key: string): Promise<Uint8Array | undefined> {
    const value: Uint8Array | undefined = this.values.get(key);
    return value === undefined ? undefined : new Uint8Array(value);
  }

  async write(key: string, bytes: Uint8Array): Promise<void> {
    this.writes += 1;
    this.values.set(key, new Uint8Array(bytes));
  }

  async remove(key: string): Promise<void> {
    this.values.delete(key);
  }
}

function bytes(value: number, count: number): Uint8Array {
  const result: Uint8Array = new Uint8Array(count);
  result.fill(value);
  return result;
}

export default function tabSnapshotCacheTest() {
  describe('TabSnapshotCache', () => {
    it('evicts the least recently used ordinary snapshot at the byte limit', 0, async () => {
      const storage: FakeSnapshotStorage = new FakeSnapshotStorage();
      let clock: number = 1;
      const cache: TabSnapshotCache = new TabSnapshotCache(storage, 100, () => clock++);
      await cache.put('a', bytes(1, 60), false);
      await cache.put('b', bytes(2, 60), false);
      expect(await cache.get('a')).assertUndefined();
      expect(await cache.get('b')).assertDeepEquals(bytes(2, 60));
    });

    it('refreshes LRU order when an ordinary snapshot is read', 0, async () => {
      const storage: FakeSnapshotStorage = new FakeSnapshotStorage();
      let clock: number = 1;
      const cache: TabSnapshotCache = new TabSnapshotCache(storage, 100, () => clock++);
      await cache.put('a', bytes(1, 60), false);
      await cache.put('b', bytes(2, 30), false);
      expect(await cache.get('a')).assertDeepEquals(bytes(1, 60));
      await cache.put('c', bytes(3, 30), false);
      expect(await cache.get('a')).assertDeepEquals(bytes(1, 60));
      expect(await cache.get('b')).assertUndefined();
      expect(await cache.get('c')).assertDeepEquals(bytes(3, 30));
    });

    it('keeps private snapshots in memory without storage writes', 0, async () => {
      const storage: FakeSnapshotStorage = new FakeSnapshotStorage();
      const cache: TabSnapshotCache = new TabSnapshotCache(storage, 1, () => 1);
      await cache.put('private', bytes(7, 40), true);
      expect(storage.writes).assertEqual(0);
      expect(storage.values.has('private')).assertFalse();
      expect(await cache.get('private')).assertDeepEquals(bytes(7, 40));
    });

    it('does not persist an empty capture', 0, async () => {
      const storage: FakeSnapshotStorage = new FakeSnapshotStorage();
      const cache: TabSnapshotCache = new TabSnapshotCache(storage, 100, () => 1);
      const captured: boolean = await cache.capture('empty', false, async () => new Uint8Array(0));
      expect(captured).assertFalse();
      expect(storage.writes).assertEqual(0);
      expect(await cache.get('empty')).assertUndefined();
    });

    it('replaces an existing key without double counting its bytes', 0, async () => {
      const storage: FakeSnapshotStorage = new FakeSnapshotStorage();
      const cache: TabSnapshotCache = new TabSnapshotCache(storage, 100, () => 1);
      await cache.put('same', bytes(1, 80), false);
      await cache.put('same', bytes(2, 20), false);
      expect(await cache.get('same')).assertDeepEquals(bytes(2, 20));
      expect(storage.values.get('same')?.byteLength).assertEqual(20);
    });
  });
}
