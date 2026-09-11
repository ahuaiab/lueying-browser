import { TabId } from '../model/BrowserTypes';

/** Storage boundary kept separate so production can use the app cache and
 * local tests can use a deterministic fake without touching the filesystem. */
export interface SnapshotStorage {
  read(key: string): Promise<Uint8Array | undefined>;
  write(key: string, bytes: Uint8Array): Promise<void>;
  remove(key: string): Promise<void>;
}

interface SnapshotEntry {
  key: string;
  bytes: number;
  lastUsedAt: number;
  isPrivate: boolean;
  privateBytes?: Uint8Array;
}

/** Simple storage implementation used until the repository layer supplies a
 * file-backed cache. It still exercises the same ordinary/private boundary. */
export class MemorySnapshotStorage implements SnapshotStorage {
  private readonly values: Map<string, Uint8Array> = new Map();

  async read(key: string): Promise<Uint8Array | undefined> {
    const value: Uint8Array | undefined = this.values.get(key);
    return value === undefined ? undefined : new Uint8Array(value);
  }

  async write(key: string, bytes: Uint8Array): Promise<void> {
    this.values.set(key, new Uint8Array(bytes));
  }

  async remove(key: string): Promise<void> {
    this.values.delete(key);
  }
}

export class TabSnapshotCache {
  private readonly entries: Map<string, SnapshotEntry> = new Map();
  private readonly storage: SnapshotStorage;
  private readonly maxBytes: number;
  private readonly now: () => number;
  private ordinaryBytes: number = 0;

  constructor(
    storage: SnapshotStorage,
    maxBytes: number = 64 * 1024 * 1024,
    now: () => number = () => Date.now()
  ) {
    this.storage = storage;
    this.maxBytes = Math.max(0, maxBytes);
    this.now = now;
  }

  async put(key: TabId, bytes: Uint8Array, isPrivate: boolean): Promise<void> {
    if (key.length === 0) {
      return;
    }
    await this.removeExisting(key);
    const copy: Uint8Array = new Uint8Array(bytes);
    const entry: SnapshotEntry = {
      key,
      bytes: isPrivate ? 0 : copy.byteLength,
      lastUsedAt: this.now(),
      isPrivate,
      privateBytes: isPrivate ? copy : undefined
    };
    if (isPrivate) {
      // Private thumbnails never cross the storage boundary.
      this.entries.set(key, entry);
      return;
    }
    await this.storage.write(key, copy);
    this.entries.set(key, entry);
    this.ordinaryBytes += copy.byteLength;
    await this.trim();
  }

  async capture(
    key: TabId,
    isPrivate: boolean,
    provider?: () => Promise<Uint8Array | undefined>
  ): Promise<boolean> {
    if (provider === undefined) {
      return false;
    }
    try {
      const bytes: Uint8Array | undefined = await provider();
      if (bytes === undefined || bytes.byteLength === 0) {
        return false;
      }
      await this.put(key, bytes, isPrivate);
      return true;
    } catch (_error) {
      return false;
    }
  }

  async get(key: TabId): Promise<Uint8Array | undefined> {
    const entry: SnapshotEntry | undefined = this.entries.get(key);
    if (entry === undefined) {
      return undefined;
    }
    entry.lastUsedAt = this.now();
    if (entry.isPrivate) {
      return entry.privateBytes === undefined ? undefined : new Uint8Array(entry.privateBytes);
    }
    const stored: Uint8Array | undefined = await this.storage.read(key);
    if (stored === undefined) {
      this.entries.delete(key);
      this.ordinaryBytes = Math.max(0, this.ordinaryBytes - entry.bytes);
      return undefined;
    }
    return new Uint8Array(stored);
  }

  async remove(key: TabId): Promise<void> {
    await this.removeExisting(key);
  }

  async trim(): Promise<void> {
    while (this.ordinaryBytes > this.maxBytes) {
      const oldest: SnapshotEntry | undefined = this.oldestOrdinaryEntry();
      if (oldest === undefined) {
        this.ordinaryBytes = 0;
        return;
      }
      await this.storage.remove(oldest.key);
      this.entries.delete(oldest.key);
      this.ordinaryBytes = Math.max(0, this.ordinaryBytes - oldest.bytes);
    }
  }

  private oldestOrdinaryEntry(): SnapshotEntry | undefined {
    let oldest: SnapshotEntry | undefined = undefined;
    for (const entry of this.entries.values()) {
      if (entry.isPrivate) {
        continue;
      }
      if (oldest === undefined || entry.lastUsedAt < oldest.lastUsedAt) {
        oldest = entry;
      }
    }
    return oldest;
  }

  private async removeExisting(key: string): Promise<void> {
    const existing: SnapshotEntry | undefined = this.entries.get(key);
    if (existing === undefined) {
      return;
    }
    this.entries.delete(key);
    if (existing.isPrivate) {
      return;
    }
    await this.storage.remove(key);
    this.ordinaryBytes = Math.max(0, this.ordinaryBytes - existing.bytes);
  }
}
