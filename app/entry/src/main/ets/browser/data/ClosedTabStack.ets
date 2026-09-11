import { BrowserTabRecord, lastValidUrlForTab } from '../model/BrowserTypes';

export interface ClosedTabRecord {
  id: string;
  url: string;
  title: string;
  isPrivate: boolean;
  closedAt: number;
  thumbnailKey: string;
}

function copyClosedTab(record: ClosedTabRecord): ClosedTabRecord {
  return {
    id: record.id,
    url: record.url,
    title: record.title,
    isPrivate: record.isPrivate,
    closedAt: record.closedAt,
    thumbnailKey: record.thumbnailKey
  };
}

export function closedTabFromRecord(tab: BrowserTabRecord, closedAt: number): ClosedTabRecord {
  const canonicalUrl: string = lastValidUrlForTab(tab);
  return {
    id: tab.id,
    url: canonicalUrl,
    title: tab.title,
    isPrivate: tab.isPrivate,
    closedAt,
    thumbnailKey: tab.thumbnailKey
  };
}

/** In-memory LIFO stack matching Safari's recently closed tab affordance. */
export class ClosedTabStack {
  private readonly limit: number;
  private records: ClosedTabRecord[] = [];

  constructor(limit: number = 20) {
    this.limit = Math.max(1, Math.floor(limit));
  }

  push(record: ClosedTabRecord): void {
    if (record.isPrivate || record.id.length === 0 || record.url.length === 0) {
      return;
    }
    this.records = [copyClosedTab(record), ...this.records].slice(0, this.limit);
  }

  pop(): ClosedTabRecord | undefined {
    const record: ClosedTabRecord | undefined = this.records.shift();
    return record === undefined ? undefined : copyClosedTab(record);
  }

  peek(): ClosedTabRecord | undefined {
    const record: ClosedTabRecord | undefined = this.records[0];
    return record === undefined ? undefined : copyClosedTab(record);
  }

  clear(): void {
    this.records = [];
  }

  size(): number {
    return this.records.length;
  }

  snapshot(): ClosedTabRecord[] {
    return this.records.map((record: ClosedTabRecord) => copyClosedTab(record));
  }
}
