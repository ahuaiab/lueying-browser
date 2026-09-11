export enum PageFontSize {
  SMALL = 'small',
  STANDARD = 'standard',
  LARGE = 'large'
}

export interface PageDisplayState {
  fontSize: PageFontSize;
  readerMode: boolean;
  translated: boolean;
  fullScreen: boolean;
}

export const DEFAULT_PAGE_DISPLAY_STATE: PageDisplayState = {
  fontSize: PageFontSize.STANDARD,
  readerMode: false,
  translated: false,
  fullScreen: false
};

export function copyPageDisplayState(state: PageDisplayState): PageDisplayState {
  return {
    fontSize: state.fontSize,
    readerMode: state.readerMode,
    translated: state.translated,
    fullScreen: state.fullScreen
  };
}

export function normalizePageDisplayState(value: Object | undefined): PageDisplayState {
  if (value === undefined || value === null || typeof value !== 'object') {
    return copyPageDisplayState(DEFAULT_PAGE_DISPLAY_STATE);
  }
  const candidate: Partial<PageDisplayState> = value as Partial<PageDisplayState>;
  const fontSize: PageFontSize = candidate.fontSize === PageFontSize.SMALL ||
    candidate.fontSize === PageFontSize.LARGE
    ? candidate.fontSize
    : PageFontSize.STANDARD;
  return {
    fontSize,
    readerMode: candidate.readerMode === true,
    translated: candidate.translated === true,
    fullScreen: candidate.fullScreen === true
  };
}
