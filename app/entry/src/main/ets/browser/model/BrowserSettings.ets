/** User-facing browser settings mirrored from the video, kept independent of ArkWeb. */
export enum BrowserSearchEngine {
  YAHOO = 'yahoo',
  BING = 'bing',
  BAIDU = 'baidu',
  GOOGLE = 'google',
  DUCKDUCKGO = 'duckduckgo',
  SOGOU = 'sogou'
}

export enum AutoCloseTabsPolicy {
  NEVER = 'never',
  AFTER_ONE_DAY = 'after_one_day',
  AFTER_ONE_WEEK = 'after_one_week',
  AFTER_ONE_MONTH = 'after_one_month'
}

/** Retained for persisted-settings compatibility; the app follows system appearance. */
export enum StartPageAppearance {
  LIGHT = 'light',
  FOLLOW_SYSTEM = 'follow_system'
}

export interface BrowserSettings {
  searchEngine: BrowserSearchEngine;
  autoCloseTabs: AutoCloseTabsPolicy;
  contentBlockingEnabled: boolean;
  showFavorites: boolean;
  showFrequentSites: boolean;
  /** True after the user has explicitly visited/changed the start-page switches. */
  startPageSectionsConfigured: boolean;
  startPageBackgroundId: string;
  startPageAppearance: StartPageAppearance;
  defaultFontSize: string;
}

export const DEFAULT_BROWSER_SETTINGS: BrowserSettings = {
  searchEngine: BrowserSearchEngine.BING,
  autoCloseTabs: AutoCloseTabsPolicy.NEVER,
  contentBlockingEnabled: false,
  showFavorites: false,
  showFrequentSites: false,
  startPageSectionsConfigured: false,
  startPageBackgroundId: 'system-gradient',
  startPageAppearance: StartPageAppearance.FOLLOW_SYSTEM,
  defaultFontSize: 'standard'
};

export function copyBrowserSettings(settings: BrowserSettings): BrowserSettings {
  return {
    searchEngine: settings.searchEngine,
    autoCloseTabs: settings.autoCloseTabs,
    contentBlockingEnabled: settings.contentBlockingEnabled,
    showFavorites: settings.showFavorites,
    showFrequentSites: settings.showFrequentSites,
    startPageSectionsConfigured: settings.startPageSectionsConfigured,
    startPageBackgroundId: settings.startPageBackgroundId,
    // Appearance is no longer user-configurable; migrate old in-memory values too.
    startPageAppearance: StartPageAppearance.FOLLOW_SYSTEM,
    defaultFontSize: settings.defaultFontSize
  };
}

export function normalizeBrowserSettings(value: Object | undefined): BrowserSettings {
  if (value === undefined || value === null || typeof value !== 'object') {
    return copyBrowserSettings(DEFAULT_BROWSER_SETTINGS);
  }
  const candidate: Partial<BrowserSettings> = value as Partial<BrowserSettings>;
  const searchEngine: BrowserSearchEngine = candidate.searchEngine === BrowserSearchEngine.YAHOO ||
    candidate.searchEngine === BrowserSearchEngine.BAIDU ||
    candidate.searchEngine === BrowserSearchEngine.GOOGLE ||
    candidate.searchEngine === BrowserSearchEngine.DUCKDUCKGO ||
    candidate.searchEngine === BrowserSearchEngine.SOGOU
    ? candidate.searchEngine
    : BrowserSearchEngine.BING;
  const autoCloseTabs: AutoCloseTabsPolicy = candidate.autoCloseTabs === AutoCloseTabsPolicy.AFTER_ONE_DAY ||
    candidate.autoCloseTabs === AutoCloseTabsPolicy.AFTER_ONE_WEEK ||
    candidate.autoCloseTabs === AutoCloseTabsPolicy.AFTER_ONE_MONTH
    ? candidate.autoCloseTabs
    : AutoCloseTabsPolicy.NEVER;
  // Before start-page switches were user-configurable, persisted settings
  // contained both flags as true without a marker. Treat that shape as the
  // old default so an upgrade starts with only the Edit action visible.
  const sectionsConfigured: boolean = candidate.startPageSectionsConfigured === true;
  const startPageAppearance: StartPageAppearance = StartPageAppearance.FOLLOW_SYSTEM;
  return {
    searchEngine,
    autoCloseTabs,
    contentBlockingEnabled: candidate.contentBlockingEnabled === true,
    showFavorites: sectionsConfigured && candidate.showFavorites === true,
    showFrequentSites: sectionsConfigured && candidate.showFrequentSites === true,
    startPageSectionsConfigured: sectionsConfigured,
    startPageBackgroundId: typeof candidate.startPageBackgroundId === 'string' &&
      candidate.startPageBackgroundId.length > 0
      ? candidate.startPageBackgroundId
      : DEFAULT_BROWSER_SETTINGS.startPageBackgroundId,
    startPageAppearance,
    defaultFontSize: typeof candidate.defaultFontSize === 'string' && candidate.defaultFontSize.length > 0
      ? candidate.defaultFontSize
      : DEFAULT_BROWSER_SETTINGS.defaultFontSize
  };
}
