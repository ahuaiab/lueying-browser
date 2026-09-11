import { BrowserSearchEngine } from './BrowserSettings';

export type TabId = string;
export type AddressBarSource = 'search' | 'url';

export enum TabResidency {
  HOT = 'hot',
  WARM = 'warm',
  COLD = 'cold'
}

export enum TabDirection {
  PREVIOUS = -1,
  NEXT = 1
}

export interface BrowserTabRecord {
  id: TabId;
  /** Canonical full URL kept for backwards-compatible session consumers. */
  url: string;
  /** Last URL that passed the browser load policy; never a display label. */
  lastValidUrl: string;
  /** Host-only value used by tab cards and error presentation. */
  displayUrl: string;
  /** Stable key for the cached page snapshot/thumbnail shown in tab overview. */
  pageSnapshot: string;
  title: string;
  isPrivate: boolean;
  createdAt: number;
  lastAccessedAt: number;
  thumbnailKey: string;
  residency: TabResidency;
  /** Source of the current address-editor presentation. Older sessions omit it. */
  addressSource?: AddressBarSource;
  /** Original search input, retained while a search provider redirects. */
  addressQuery?: string;
}

export interface PendingTabDraft {
  tab: BrowserTabRecord;
}

export interface BrowserSessionSnapshot {
  version: 1;
  activeTabId: TabId;
  tabs: BrowserTabRecord[];
}

export interface HistoryRecord {
  url: string;
  title: string;
  visitedAt: number;
}

export interface BookmarkRecord {
  url: string;
  title: string;
  createdAt: number;
}

export enum BrowserErrorKind {
  NETWORK = 'network',
  SSL = 'ssl',
  RENDERER_EXITED = 'renderer_exited'
}

export interface BrowserErrorState {
  kind: BrowserErrorKind;
  code: number;
  host: string;
  message: string;
}

export interface BrowserUrlValidation {
  rawUrl: string;
  normalizedUrl: string;
  urlScheme: string;
  valid: boolean;
  reason: string;
}

export enum AddressSecurityState {
  SECURE = 'secure',
  INSECURE = 'insecure'
}

export interface CloseTabResult {
  closed: boolean;
  activeTabId: TabId;
  createdReplacement: boolean;
}

export enum GestureAxis {
  UNDECIDED = 'undecided',
  VERTICAL = 'vertical',
  HORIZONTAL = 'horizontal'
}

export enum GestureOutcome {
  NONE = 'none',
  SHOW_OVERVIEW = 'show_overview',
  PREVIOUS_TAB = 'previous_tab',
  NEXT_TAB = 'next_tab',
  NEW_START_TAB = 'new_start_tab',
  CLOSE_TAB = 'close_tab',
  CANCELLED = 'cancelled'
}

export interface GestureSample {
  dx: number;
  dy: number;
  velocityX: number;
  velocityY: number;
}

export interface GestureDecision {
  axis: GestureAxis;
  progress: number;
  visualOffset: number;
  outcome: GestureOutcome;
}

export function searchEngineLabel(engine: BrowserSearchEngine): string {
  if (engine === BrowserSearchEngine.YAHOO) {
    return '雅虎';
  }
  if (engine === BrowserSearchEngine.BAIDU) {
    return '百度';
  }
  if (engine === BrowserSearchEngine.GOOGLE) {
    return '谷歌';
  }
  if (engine === BrowserSearchEngine.DUCKDUCKGO) {
    return 'DuckDuckGo';
  }
  if (engine === BrowserSearchEngine.SOGOU) {
    return '搜狗';
  }
  return '必应';
}

export function searchUrlForEngine(engine: BrowserSearchEngine, query: string): string {
  const encoded: string = encodeURIComponent(query);
  if (engine === BrowserSearchEngine.YAHOO) {
    return `https://search.yahoo.com/search?p=${encoded}`;
  }
  if (engine === BrowserSearchEngine.BAIDU) {
    return `https://www.baidu.com/s?wd=${encoded}`;
  }
  if (engine === BrowserSearchEngine.GOOGLE) {
    return `https://www.google.com/search?q=${encoded}`;
  }
  if (engine === BrowserSearchEngine.DUCKDUCKGO) {
    return `https://duckduckgo.com/?q=${encoded}`;
  }
  if (engine === BrowserSearchEngine.SOGOU) {
    return `https://www.sogou.com/web?query=${encoded}`;
  }
  return `https://cn.bing.com/search?q=${encoded}`;
}

interface SearchResultDescriptor {
  engine: BrowserSearchEngine;
  queryParameter: string;
}

function searchResultDescriptorFor(url: string): SearchResultDescriptor | undefined {
  const normalized: string = url.trim().toLowerCase();
  const withoutScheme: string = normalized.replace(/^[a-z][a-z0-9+.-]*:\/\//i, '');
  const pathStart: number = withoutScheme.indexOf('/');
  if (pathStart < 0) {
    return undefined;
  }
  const host: string = withoutScheme.slice(0, pathStart);
  const path: string = withoutScheme.slice(pathStart);
  if ((host === 'cn.bing.com' || host === 'www.bing.com' || host === 'bing.com') &&
    (path.startsWith('/search?') || path.startsWith('/?'))) {
    return { engine: BrowserSearchEngine.BING, queryParameter: 'q' };
  }
  if (host === 'search.yahoo.com' && path.startsWith('/search?')) {
    return { engine: BrowserSearchEngine.YAHOO, queryParameter: 'p' };
  }
  if ((host === 'www.baidu.com' || host === 'baidu.com') && path.startsWith('/s?')) {
    return { engine: BrowserSearchEngine.BAIDU, queryParameter: 'wd' };
  }
  if ((host === 'www.google.com' || host === 'google.com') && path.startsWith('/search?')) {
    return { engine: BrowserSearchEngine.GOOGLE, queryParameter: 'q' };
  }
  if ((host === 'duckduckgo.com' || host === 'www.duckduckgo.com') && path.startsWith('/?')) {
    return { engine: BrowserSearchEngine.DUCKDUCKGO, queryParameter: 'q' };
  }
  if ((host === 'www.sogou.com' || host === 'sogou.com') && path.startsWith('/web?')) {
    return { engine: BrowserSearchEngine.SOGOU, queryParameter: 'query' };
  }
  return undefined;
}

function decodedQueryComponent(value: string): string {
  const withSpaces: string = value.replace(/\+/g, ' ');
  try {
    return decodeURIComponent(withSpaces).trim();
  } catch (_error) {
    return withSpaces.trim();
  }
}

/** Remove only a matching outer quote pair from a search phrase. */
export function searchQueryTextFor(value: string): string {
  let normalized: string = value.trim();
  if (normalized.length < 2) {
    return normalized;
  }
  const first: string = normalized.slice(0, 1);
  const last: string = normalized.slice(-1);
  const matchingQuotes: boolean = (first === '"' && last === '"') ||
    (first === '\u201c' && last === '\u201d') ||
    (first === '\u300c' && last === '\u300d') ||
    (first === '\u2018' && last === '\u2019');
  if (matchingQuotes) {
    normalized = normalized.slice(1, -1).trim();
  }
  return normalized;
}

function queryParameterFor(url: string, parameterName: string): string {
  const queryStart: number = url.indexOf('?');
  if (queryStart < 0 || queryStart >= url.length - 1) {
    return '';
  }
  const fragmentStart: number = url.indexOf('#', queryStart + 1);
  const query: string = fragmentStart < 0
    ? url.slice(queryStart + 1)
    : url.slice(queryStart + 1, fragmentStart);
  const fields: string[] = query.split('&');
  for (let index: number = 0; index < fields.length; index += 1) {
    const field: string = fields[index];
    const separator: number = field.indexOf('=');
    const rawName: string = separator < 0 ? field : field.slice(0, separator);
    if (decodedQueryComponent(rawName).toLowerCase() !== parameterName) {
      continue;
    }
    return separator < 0 ? '' : decodedQueryComponent(field.slice(separator + 1));
  }
  return '';
}

/**
 * Build the title shown by the tab overview without changing the navigable URL.
 * Search result pages use the stable `query-engine` form even before ArkWeb
 * publishes a document title; ordinary pages keep their existing page title.
 */
export function tabOverviewTitleFor(url: string, title: string): string {
  const descriptor: SearchResultDescriptor | undefined = searchResultDescriptorFor(url);
  if (descriptor !== undefined) {
    const query: string = searchQueryTextFor(queryParameterFor(url, descriptor.queryParameter));
    if (query.length > 0) {
      return `${query}-${descriptor.engine}`;
    }
  }
  if (url.trim() === 'about:blank' && (title.length === 0 || title === 'about:blank')) {
    return '起始页';
  }
  return title.length > 0 ? title : '起始页';
}

/** Recover a search-origin draft from a restored search-result URL. */
export function searchQueryForUrl(url: string): string | undefined {
  const descriptor: SearchResultDescriptor | undefined = searchResultDescriptorFor(url);
  if (descriptor === undefined) {
    return undefined;
  }
  const query: string = queryParameterFor(url, descriptor.queryParameter);
  const normalizedQuery: string = searchQueryTextFor(query);
  return normalizedQuery.length > 0 ? normalizedQuery : undefined;
}

/**
 * Text shown by the collapsed address bar. Search results keep the query;
 * ordinary pages use the shortened URL authority so the compact chrome does
 * not expose a long path or fall back to a generic page title.
 */
export function addressBarLabelFor(url: string, title: string): string {
  const normalizedUrl: string = url.trim();
  if (normalizedUrl.length === 0 || normalizedUrl === 'about:blank') {
    return '搜索或输入网站';
  }
  const searchQuery: string | undefined = searchQueryForUrl(normalizedUrl);
  if (searchQuery !== undefined) {
    return searchQuery;
  }
  return displayUrlFor(normalizedUrl);
}

/** Build a bookmark from the page identity, never from display-only chrome text. */
export function bookmarkRecordForPage(
  url: string,
  title: string,
  createdAt: number
): BookmarkRecord | undefined {
  const canonicalUrl: string | undefined = loadableUrlFor(url);
  if (canonicalUrl === undefined || canonicalUrl === 'about:blank') {
    return undefined;
  }
  const normalizedTitle: string = title.trim();
  const overviewTitle: string = tabOverviewTitleFor(canonicalUrl, normalizedTitle);
  const pageTitle: string = overviewTitle === '起始页' ? canonicalUrl : overviewTitle;
  return {
    url: canonicalUrl,
    title: pageTitle,
    createdAt
  };
}

const URL_SCHEME_PATTERN: RegExp = /^[a-z][a-z0-9+.-]*:/i;
const LOADABLE_HTTP_URL_PATTERN: RegExp = /^https?:\/\/[^\s/?#]+(?:[/?#][^\s]*)?$/i;

/** Extract only the scheme prefix. A hostname such as start.weixin has none. */
export function urlSchemeFor(value: string): string {
  const normalized: string = value.trim();
  const colonIndex: number = normalized.indexOf(':');
  if (colonIndex <= 0) {
    return '';
  }
  const candidate: string = normalized.slice(0, colonIndex);
  return URL_SCHEME_PATTERN.test(`${candidate}:`) ? candidate.toLowerCase() : '';
}

/** HTTPS is the only address state represented as encrypted in the chrome. */
export function addressSecurityStateFor(value: string): AddressSecurityState {
  return urlSchemeFor(value) === 'https'
    ? AddressSecurityState.SECURE
    : AddressSecurityState.INSECURE;
}

/**
 * Validate a URL before it becomes either Web.src or WebviewController.loadUrl.
 * Recovery paths deliberately accept only HTTP(S) and the native blank page;
 * a display label must never be promoted into a navigation target.
 */
export function validateBrowserUrl(value: string): BrowserUrlValidation {
  const normalized: string = value.trim();
  const scheme: string = urlSchemeFor(normalized);
  if (normalized.length === 0) {
    return { rawUrl: value, normalizedUrl: '', urlScheme: scheme, valid: false, reason: 'empty' };
  }
  if (normalized === 'about:blank') {
    return { rawUrl: value, normalizedUrl: normalized, urlScheme: 'about', valid: true, reason: 'blank' };
  }
  if (scheme !== 'http' && scheme !== 'https') {
    return {
      rawUrl: value,
      normalizedUrl: normalized,
      urlScheme: scheme,
      valid: false,
      reason: scheme.length === 0 ? 'missing-scheme' : 'unsupported-scheme'
    };
  }
  if (!LOADABLE_HTTP_URL_PATTERN.test(normalized)) {
    return {
      rawUrl: value,
      normalizedUrl: normalized,
      urlScheme: scheme,
      valid: false,
      reason: 'malformed-http-url'
    };
  }
  return { rawUrl: value, normalizedUrl: normalized, urlScheme: scheme, valid: true, reason: 'valid' };
}

/** Return a URL safe for Web.src/loadUrl, or undefined for display-only text. */
export function loadableUrlFor(value: string): string | undefined {
  const validation: BrowserUrlValidation = validateBrowserUrl(value);
  return validation.valid ? validation.normalizedUrl : undefined;
}

/** Keep the address shown in the UI separate from the URL sent to ArkWeb. */
export function displayUrlFor(value: string): string {
  const normalized: string = value.trim();
  if (normalized === 'about:blank' || normalized.length === 0) {
    return '起始页';
  }
  const withoutScheme: string = normalized.replace(/^[a-z][a-z0-9+.-]*:\/\//i, '');
  const authority: string = withoutScheme.split('/')[0].split('?')[0].split('#')[0];
  return authority.length > 0 ? authority : normalized;
}

/** Resolve a tab's canonical URL while accepting sessions written before the split fields existed. */
export function lastValidUrlForTab(tab: BrowserTabRecord): string {
  const explicit: string | undefined = tab.lastValidUrl;
  const explicitUrl: string | undefined = explicit === undefined ? undefined : loadableUrlFor(explicit);
  if (explicitUrl !== undefined) {
    return explicitUrl;
  }
  const legacyUrl: string | undefined = tab.url === undefined ? undefined : loadableUrlFor(tab.url);
  return legacyUrl ?? 'about:blank';
}

/** Reject lifecycle display text without replacing the tab's last valid URL. */
export function committedUrlForTabState(reportedUrl: string, fallbackUrl: string): string {
  const reported: string | undefined = loadableUrlFor(reportedUrl);
  const fallback: string | undefined = loadableUrlFor(fallbackUrl);
  // A runtime created for a blank start tab can deliver its initial
  // about:blank lifecycle callback after controller.loadUrl() has already
  // committed a real page. Treat that callback as stale; otherwise a tab
  // released by the WebTabPool is recreated from the start page instead of
  // from its own last valid URL.
  if (reported === 'about:blank' && fallback !== undefined && fallback !== 'about:blank') {
    return fallback;
  }
  if (reported !== undefined) {
    return reported;
  }
  return fallback ?? 'about:blank';
}

export function normalizeAddressInput(input: string, engine: BrowserSearchEngine = BrowserSearchEngine.BING): string {
  const value: string = input.trim();
  const explicitUrl: string | undefined = loadableUrlFor(value);
  if (explicitUrl !== undefined) {
    return explicitUrl;
  }
  if (!value.includes(' ') && value.includes('.')) {
    const hostnameUrl: string = `https://${value}`;
    if (loadableUrlFor(hostnameUrl) !== undefined) {
      return hostnameUrl;
    }
  }
  return searchUrlForEngine(engine, value);
}
