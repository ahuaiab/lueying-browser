import {
  BrowserTabRecord,
  displayUrlFor,
  lastValidUrlForTab,
  TabId
} from './BrowserTypes';
import {
  DEFAULT_PAGE_DISPLAY_STATE,
  PageDisplayState,
  copyPageDisplayState
} from './PageDisplayState';

/** The immutable tab data captured before the overview becomes visible. */
export interface TabOverviewTabSnapshot {
  id: TabId;
  url: string;
  lastValidUrl: string;
  displayUrl: string;
  controllerId: string;
  pageSnapshotKey: string;
  pageSnapshotAvailable: boolean;
  pageSnapshot: string;
  pageState: PageDisplayState;
}

/**
 * The overview is a presentation of this session, not a second tab session.
 * All lookups after capture are keyed by the stable business TabId.
 */
export interface TabOverviewSession {
  currentIndex: number;
  currentTabId: TabId;
  currentUrl: string;
  tabs: TabOverviewTabSnapshot[];
}

export function captureTabOverviewSession(
  tabs: BrowserTabRecord[],
  activeTabId: TabId,
  controllerIds: Map<TabId, string>,
  pageStates: Map<TabId, PageDisplayState>
): TabOverviewSession {
  const currentIndex: number = tabs.findIndex((tab: BrowserTabRecord) => tab.id === activeTabId);
  const currentTab: BrowserTabRecord | undefined = tabs.find(
    (tab: BrowserTabRecord) => tab.id === activeTabId
  );
  const snapshots: TabOverviewTabSnapshot[] = tabs.map((tab: BrowserTabRecord): TabOverviewTabSnapshot => {
    const canonicalUrl: string = lastValidUrlForTab(tab);
    const snapshotKey: string = tab.pageSnapshot === undefined ? tab.thumbnailKey : tab.pageSnapshot;
    const snapshot: TabOverviewTabSnapshot = {
      id: tab.id,
      url: canonicalUrl,
      lastValidUrl: canonicalUrl,
      displayUrl: displayUrlFor(canonicalUrl),
      controllerId: controllerIds.get(tab.id) ?? '',
      pageSnapshotKey: snapshotKey,
      pageSnapshotAvailable: snapshotKey.length > 0,
      pageSnapshot: snapshotKey,
      pageState: copyPageDisplayState(pageStates.get(tab.id) ?? DEFAULT_PAGE_DISPLAY_STATE)
    };
    return snapshot;
  });
  return {
    currentIndex,
    currentTabId: activeTabId,
    currentUrl: currentTab === undefined ? 'about:blank' : lastValidUrlForTab(currentTab),
    tabs: snapshots
  };
}

export function pageStateForTabOverview(
  session: TabOverviewSession,
  tabId: TabId
): PageDisplayState | undefined {
  const snapshot: TabOverviewTabSnapshot | undefined = session.tabs.find(
    (tab: TabOverviewTabSnapshot) => tab.id === tabId
  );
  return snapshot === undefined ? undefined : copyPageDisplayState(snapshot.pageState);
}

/**
 * Return the saved URL belonging to the requested tab.  There is deliberately
 * no search-engine fallback here: recovery must never silently navigate a
 * different tab to the browser home page.
 */
export function savedUrlForTabOverview(
  session: TabOverviewSession,
  tabId: TabId
): string | undefined {
  return session.tabs.find((tab: TabOverviewTabSnapshot) => tab.id === tabId)?.lastValidUrl;
}
