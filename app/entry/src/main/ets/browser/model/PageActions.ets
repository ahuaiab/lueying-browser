import { PageFontSize } from './PageDisplayState';

export enum PageAction {
  READER = 'reader',
  TRANSLATE = 'translate',
  SCREENSHOT = 'screenshot',
  BOOKMARK = 'bookmark',
  DESKTOP_SITE = 'desktop_site',
  MEDIA_SPEED_HALF = 'media_speed_half',
  MEDIA_SPEED_STANDARD = 'media_speed_standard',
  MEDIA_SPEED_ONE_HALF = 'media_speed_one_half',
  MEDIA_SPEED_DOUBLE = 'media_speed_double'
}

export interface PageActionAvailability {
  enabled: PageAction[];
  reason: string;
}

/** Only the page-mode toggle remains in the long-press page menu. */
export function pageMenuActions(webReady: boolean): PageAction[] {
  return webReady ? [PageAction.DESKTOP_SITE] : [];
}

export function nextFontSize(size: PageFontSize): PageFontSize {
  if (size === PageFontSize.SMALL) {
    return PageFontSize.STANDARD;
  }
  if (size === PageFontSize.STANDARD) {
    return PageFontSize.LARGE;
  }
  return PageFontSize.SMALL;
}

/**
 * ArkWeb does not expose one cross-version reader/translation API. Keep the
 * availability decision explicit so the UI can show a native fallback rather
 * than claiming that an unavailable operation succeeded.
 */
export function availablePageActions(webReady: boolean): PageActionAvailability {
  if (!webReady) {
    return {
      enabled: [],
      reason: '网页尚未完成加载，暂时不能执行页面操作'
    };
  }
  return {
    enabled: pageMenuActions(true),
    reason: ''
  };
}

/** Remove the mobile marker while preserving the current ArkWeb identity. */
export function desktopUserAgentFor(userAgent: string): string {
  const normalized: string = userAgent.trim();
  if (normalized.length === 0) {
    return normalized;
  }
  return normalized.replace(/\bMobile\b/g, '').replace(/\s{2,}/g, ' ').trim();
}

/** Keep the page-mode menu label and native symbol in the same state model. */
export function pageModeMenuLabel(desktopMode: boolean): string {
  return desktopMode ? '请求手机网页' : '请求桌面网页';
}

/**
 * Resolve the symbol from the live device form factor. HarmonyOS exposes
 * foldable phones as `phone`, so model names are intentionally not embedded
 * in the browser UI; the system symbol layer remains the source of the shape.
 */
export function pageModeMenuSymbolName(desktopMode: boolean, deviceType: string = 'phone'): string {
  if (!desktopMode) {
    return 'sys.symbol.display';
  }
  return deviceType.trim().toLowerCase() === 'phone'
    ? 'sys.symbol.rectangle_portrait'
    : 'sys.symbol.display';
}
