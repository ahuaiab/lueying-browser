import { loadableUrlFor } from './BrowserTypes';

let pendingExternalUrl: string | undefined = undefined;

/** Keep an external http(s) URL alive until the browser shell is mounted. */
export function setPendingExternalUrl(value: string): string | undefined {
  const canonicalUrl: string | undefined = loadableUrlFor(value);
  if (canonicalUrl === undefined || canonicalUrl === 'about:blank') {
    return undefined;
  }
  pendingExternalUrl = canonicalUrl;
  return canonicalUrl;
}

export function takePendingExternalUrl(): string | undefined {
  const value: string | undefined = pendingExternalUrl;
  pendingExternalUrl = undefined;
  return value;
}

export function clearPendingExternalUrl(): void {
  pendingExternalUrl = undefined;
}
