import { HistoryRecord } from './BrowserTypes';

const START_PAGE_SYSTEM_BACKGROUND_ID: string = 'system-gradient';

/**
 * Converts the persisted background choice into an Image source.
 *
 * The system choice is deliberately represented by undefined so callers can
 * keep the default native page surface without mounting an Image node.
 */
export function startPageBackgroundSource(backgroundId: string): string | undefined {
  const normalized: string = backgroundId.trim();
  if (normalized.length === 0 || normalized === START_PAGE_SYSTEM_BACKGROUND_ID) {
    return undefined;
  }
  return normalized;
}

/** A cached start-page frame is valid only for the background it captured. */
export function startPageThumbnailMatchesBackground(
  thumbnailBackgroundId: string,
  currentBackgroundId: string
): boolean {
  const captured: string = thumbnailBackgroundId.trim();
  const current: string = currentBackgroundId.trim();
  return captured.length > 0 && captured === current;
}

export enum StartPageItemType {
  FAVORITE = 'favorite',
  FREQUENT = 'frequent'
}

/** The favorites section is user-enabled even before its first item exists. */
export function shouldRenderStartPageSection(
  type: StartPageItemType,
  visible: boolean,
  itemCount: number
): boolean {
  return visible && (type === StartPageItemType.FAVORITE || itemCount > 0);
}

export interface StartPageItem {
  id: string;
  type: StartPageItemType;
  title: string;
  url: string;
  order: number;
  updatedAt: number;
}

export function copyStartPageItem(item: StartPageItem): StartPageItem {
  return {
    id: item.id,
    type: item.type,
    title: item.title,
    url: item.url,
    order: item.order,
    updatedAt: item.updatedAt
  };
}

export function sortStartPageItems(items: StartPageItem[]): StartPageItem[] {
  return items.map((item: StartPageItem) => copyStartPageItem(item)).sort((left: StartPageItem, right: StartPageItem) => {
    if (left.order !== right.order) {
      return left.order - right.order;
    }
    if (left.updatedAt !== right.updatedAt) {
      return right.updatedAt - left.updatedAt;
    }
    return left.id.localeCompare(right.id);
  });
}

/**
 * Builds the start-page frequent-site list from history without allowing
 * every search query to become a visually identical destination entry.
 */
export function buildFrequentStartPageItems(history: HistoryRecord[], maxItems: number = 6): StartPageItem[] {
  const limit: number = Math.max(0, Math.floor(maxItems));
  if (limit === 0) {
    return [];
  }
  const seen: Set<string> = new Set();
  const frequent: StartPageItem[] = [];
  for (const record of history) {
    const rawUrl: string = record.url.trim();
    if (rawUrl.length === 0 || rawUrl === 'about:blank') {
      continue;
    }
    const queryIndex: number = rawUrl.indexOf('?');
    const fragmentIndex: number = rawUrl.indexOf('#');
    let endIndex: number = rawUrl.length;
    if (queryIndex >= 0) {
      endIndex = Math.min(endIndex, queryIndex);
    }
    if (fragmentIndex >= 0) {
      endIndex = Math.min(endIndex, fragmentIndex);
    }
    const normalizedUrl: string = rawUrl.slice(0, endIndex);
    const key: string = normalizedUrl.toLowerCase();
    if (normalizedUrl.length === 0 || seen.has(key)) {
      continue;
    }
    seen.add(key);
    frequent.push({
      id: `frequent-${encodeURIComponent(normalizedUrl)}`,
      type: StartPageItemType.FREQUENT,
      title: record.title.trim().length > 0 ? record.title.trim() : normalizedUrl,
      url: normalizedUrl,
      order: frequent.length,
      updatedAt: record.visitedAt
    });
    if (frequent.length >= limit) {
      break;
    }
  }
  return frequent;
}

export function validStartPageItem(item: StartPageItem): boolean {
  return item !== undefined && typeof item.id === 'string' && item.id.length > 0 &&
    (item.type === StartPageItemType.FAVORITE || item.type === StartPageItemType.FREQUENT) &&
    typeof item.title === 'string' &&
    typeof item.url === 'string' && item.url.length > 0 && typeof item.order === 'number' &&
    Number.isFinite(item.order) && typeof item.updatedAt === 'number' && Number.isFinite(item.updatedAt);
}
