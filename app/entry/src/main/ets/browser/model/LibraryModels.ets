import { BookmarkRecord, HistoryRecord } from './BrowserTypes';

/** The two native library views retained by the browser. */
export enum LibrarySection {
  HISTORY = 'history',
  BOOKMARKS = 'bookmarks'
}

/** Horizontal travel, in vp, required to commit a section swipe. */
export const LIBRARY_SECTION_SWIPE_THRESHOLD: number = 48;

/**
 * The segmented control is deliberately trackless: the sheet itself is
 * white, the selected segment gets a light gray native-material surface, and
 * the unselected segment remains the same color as the sheet.
 */
export const LIBRARY_SECTION_SELECTED_BACKGROUND: string = '#F2F2F7';
export const LIBRARY_SECTION_UNSELECTED_BACKGROUND: string = '#FFFFFF';

export function librarySectionBackground(selected: boolean): string {
  return selected ? LIBRARY_SECTION_SELECTED_BACKGROUND : LIBRARY_SECTION_UNSELECTED_BACKGROUND;
}

/** Downward drag distance, in vp, required to dismiss the library sheet. */
export const LIBRARY_DISMISS_THRESHOLD: number = 80;

/** Height and pull distance shared by the native library bottom sheet. */
export const LIBRARY_SHEET_HEIGHT_PERCENT: number = 56;
export const LIBRARY_SEARCH_PULL_THRESHOLD: number = 72;
export const LIBRARY_SEARCH_REVEAL_ANIMATION_DURATION_MS: number = 240;

export function librarySearchPullProgress(
  offsetY: number,
  threshold: number = LIBRARY_SEARCH_PULL_THRESHOLD
): number {
  const denominator: number = Math.max(1, threshold);
  return Math.min(1, Math.max(0, offsetY) / denominator);
}

/**
 * Convert a downward drag into a bounded sheet transition progress. The
 * progress reaches its terminal state at the dismiss threshold, while a
 * shorter drag remains reversible and can animate back to its origin.
 */
export function libraryDismissProgress(
  offsetY: number,
  threshold: number = LIBRARY_DISMISS_THRESHOLD
): number {
  const denominator: number = Math.max(1, threshold);
  return Math.min(1, Math.max(0, offsetY) / denominator);
}

export function libraryDismissShouldClose(
  offsetY: number,
  threshold: number = LIBRARY_DISMISS_THRESHOLD
): boolean {
  return offsetY >= Math.max(1, threshold);
}

/**
 * Resolve the section selected by a horizontal drag without mutating UI state.
 * A short drag stays on the current section so an interrupted gesture can
 * animate back to its origin instead of changing the list unexpectedly.
 */
export function librarySectionAfterSwipe(
  section: LibrarySection,
  offsetX: number,
  threshold: number = LIBRARY_SECTION_SWIPE_THRESHOLD
): LibrarySection {
  if (Math.abs(offsetX) < Math.max(1, threshold)) {
    return section;
  }
  if (section === LibrarySection.BOOKMARKS && offsetX < 0) {
    return LibrarySection.HISTORY;
  }
  if (section === LibrarySection.HISTORY && offsetX > 0) {
    return LibrarySection.BOOKMARKS;
  }
  return section;
}

/** Static chrome metadata used by the Safari-like library sheet. */
export const LIBRARY_BOOKMARK_BUTTON_MENU_LABEL: string = '添加书签';

export function libraryBookmarkActionEnabled(
  pageReady: boolean,
  isPrivate: boolean,
  url: string
): boolean {
  return pageReady && !isPrivate && url.trim().length > 0 && url !== 'about:blank';
}

export interface LibrarySectionChrome {
  title: string;
  symbolName: string;
  longPressMenuLabel: string;
}

export function librarySectionChrome(section: LibrarySection): LibrarySectionChrome {
  if (section === LibrarySection.BOOKMARKS) {
    return {
      title: '书签',
      symbolName: 'bookmark',
      longPressMenuLabel: LIBRARY_BOOKMARK_BUTTON_MENU_LABEL
    };
  }
  return { title: '历史记录', symbolName: 'clock', longPressMenuLabel: '' };
}

export enum HistoryTimelineSection {
  TODAY = 'today',
  YESTERDAY = 'yesterday',
  THIS_WEEK = 'this_week',
  EARLIER = 'earlier'
}

export enum HistoryDeleteRange {
  TODAY = 'today',
  THIS_WEEK = 'this_week',
  ALL = 'all'
}

export interface HistoryTimelineGroup {
  section: HistoryTimelineSection;
  title: string;
  entries: LibraryEntry[];
}

export interface LibraryEntry {
  id: string;
  section: LibrarySection;
  title: string;
  url: string;
  timestamp: number;
}

function copyEntry(entry: LibraryEntry): LibraryEntry {
  return {
    id: entry.id,
    section: entry.section,
    title: entry.title,
    url: entry.url,
    timestamp: entry.timestamp
  };
}

function validEntry(entry: LibraryEntry): boolean {
  return entry !== undefined && typeof entry.id === 'string' && entry.id.length > 0 &&
    (entry.section === LibrarySection.HISTORY || entry.section === LibrarySection.BOOKMARKS) &&
    typeof entry.title === 'string' &&
    typeof entry.url === 'string' && entry.url.length > 0 && typeof entry.timestamp === 'number' &&
    Number.isFinite(entry.timestamp);
}

function historyToEntries(records: HistoryRecord[]): LibraryEntry[] {
  return records.map((record: HistoryRecord, index: number): LibraryEntry => ({
    id: `history-${index}-${record.url}`,
    section: LibrarySection.HISTORY,
    title: record.title,
    url: record.url,
    timestamp: record.visitedAt
  }));
}

function bookmarksToEntries(records: BookmarkRecord[]): LibraryEntry[] {
  return records.map((record: BookmarkRecord, index: number): LibraryEntry => ({
    id: `bookmark-${index}-${record.url}`,
    section: LibrarySection.BOOKMARKS,
    title: record.title,
    url: record.url,
    timestamp: record.createdAt
  }));
}

/** Returns defensive copies so the sheet cannot mutate repository state. */
export function libraryEntries(
  section: LibrarySection,
  history: HistoryRecord[],
  bookmarks: BookmarkRecord[]
): LibraryEntry[] {
  let entries: LibraryEntry[] = [];
  if (section === LibrarySection.HISTORY) {
    entries = historyToEntries(history);
  } else if (section === LibrarySection.BOOKMARKS) {
    entries = bookmarksToEntries(bookmarks);
  }
  return entries.filter((entry: LibraryEntry) => validEntry(entry)).map((entry: LibraryEntry) => copyEntry(entry));
}

/** Filter by the same visible fields used by the library search field. */
export function filterLibraryEntries(entries: LibraryEntry[], query: string): LibraryEntry[] {
  const normalized: string = query.trim().toLowerCase();
  if (normalized.length === 0) {
    return entries.map((entry: LibraryEntry) => copyEntry(entry));
  }
  return entries
    .filter((entry: LibraryEntry) =>
      entry.title.toLowerCase().includes(normalized) || entry.url.toLowerCase().includes(normalized))
    .map((entry: LibraryEntry) => copyEntry(entry));
}

function startOfLocalDay(timestamp: number): number {
  const date: Date = new Date(timestamp);
  date.setHours(0, 0, 0, 0);
  return date.getTime();
}

function startOfLocalWeek(timestamp: number): number {
  const date: Date = new Date(timestamp);
  const daysFromMonday: number = (date.getDay() + 6) % 7;
  date.setDate(date.getDate() - daysFromMonday);
  date.setHours(0, 0, 0, 0);
  return date.getTime();
}

export function historyTimelineSection(timestamp: number, now: number): HistoryTimelineSection {
  if (!Number.isFinite(timestamp) || !Number.isFinite(now)) {
    return HistoryTimelineSection.EARLIER;
  }
  const todayStart: number = startOfLocalDay(now);
  const yesterdayStart: number = todayStart - 24 * 60 * 60 * 1000;
  const weekStart: number = startOfLocalWeek(now);
  if (timestamp >= todayStart) {
    return HistoryTimelineSection.TODAY;
  }
  if (timestamp >= yesterdayStart) {
    return HistoryTimelineSection.YESTERDAY;
  }
  if (timestamp >= weekStart) {
    return HistoryTimelineSection.THIS_WEEK;
  }
  return HistoryTimelineSection.EARLIER;
}

function timelineTitle(section: HistoryTimelineSection): string {
  if (section === HistoryTimelineSection.TODAY) {
    return '今天';
  }
  if (section === HistoryTimelineSection.YESTERDAY) {
    return '昨天';
  }
  if (section === HistoryTimelineSection.THIS_WEEK) {
    return '本周';
  }
  return '更早';
}

export function historyTimelineGroups(records: HistoryRecord[], now: number): HistoryTimelineGroup[] {
  const order: HistoryTimelineSection[] = [
    HistoryTimelineSection.TODAY,
    HistoryTimelineSection.YESTERDAY,
    HistoryTimelineSection.THIS_WEEK,
    HistoryTimelineSection.EARLIER
  ];
  const buckets: Map<HistoryTimelineSection, LibraryEntry[]> = new Map();
  order.forEach((section: HistoryTimelineSection) => buckets.set(section, []));
  const entries: LibraryEntry[] = libraryEntries(LibrarySection.HISTORY, records, []);
  entries.forEach((entry: LibraryEntry) => {
    const section: HistoryTimelineSection = historyTimelineSection(entry.timestamp, now);
    buckets.get(section)?.push(copyEntry(entry));
  });
  return order
    .map((section: HistoryTimelineSection): HistoryTimelineGroup => ({
      section,
      title: timelineTitle(section),
      entries: (buckets.get(section) ?? []).map((entry: LibraryEntry) => copyEntry(entry))
    }))
    .filter((group: HistoryTimelineGroup) => group.entries.length > 0);
}

export function historyDeleteCutoff(
  range: HistoryDeleteRange,
  now: number
): number | undefined {
  if (!Number.isFinite(now) || range === HistoryDeleteRange.ALL) {
    return undefined;
  }
  if (range === HistoryDeleteRange.TODAY) {
    return startOfLocalDay(now);
  }
  return startOfLocalWeek(now);
}

export function historyRecordInDeleteRange(
  record: HistoryRecord,
  range: HistoryDeleteRange,
  now: number
): boolean {
  if (record === undefined || !Number.isFinite(record.visitedAt)) {
    return false;
  }
  if (range === HistoryDeleteRange.ALL) {
    return true;
  }
  const cutoff: number | undefined = historyDeleteCutoff(range, now);
  return cutoff !== undefined && record.visitedAt >= cutoff;
}
