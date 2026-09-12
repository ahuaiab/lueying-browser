import { BrowserTabRecord } from './BrowserTypes';
import { HARMONY_RADIUS_CARD, HARMONY_RADIUS_CONTROL } from './BrowserVisualMetrics';

/** Shared visual metrics for the Safari-like tab overview and its cards. */
export interface TabOverviewLayoutMetrics {
  columns: number;
  horizontalPadding: number;
  cardHeight: number;
  gap: number;
  cardRadius: number;
}

/** Shared rounded-field metrics for the two Safari-style search controls. */
export interface SearchBarStyleMetrics {
  height: number;
  cornerRadius: number;
  horizontalInset: number;
}

/** The tab overview field is a compact rounded rectangle, not a capsule. */
export const TAB_SEARCH_BAR_STYLE: SearchBarStyleMetrics = {
  height: 42,
  cornerRadius: HARMONY_RADIUS_CONTROL,
  horizontalInset: 12
};

/** The home address field matches the 44vp icon control height. */
export const ADDRESS_SEARCH_BAR_STYLE: SearchBarStyleMetrics = {
  height: 44,
  cornerRadius: TAB_SEARCH_BAR_STYLE.cornerRadius,
  horizontalInset: 12
};

/** Move the address pill down so its 12vp corner centers match the 20vp outer surface. */
export const ADDRESS_SEARCH_BAR_TOP_PADDING: number = 8;

/** Visual tokens for the white overview canvas and its gray pull-down field. */
export const TAB_OVERVIEW_BACKGROUND_COLOR: string = '#FFFFFF';
export const TAB_SEARCH_BAR_BACKGROUND_COLOR: string = '#F2F2F7';
export const TAB_SEARCH_BAR_CONTENT_INSET: number = 13;
export const TAB_SEARCH_REVEAL_ANIMATION_DURATION_MS: number = 240;

/** Native menu actions exposed when a tab card is held. */
export const TAB_CARD_MENU_LABELS: string[] = [
  '新建标签',
  '关闭此标签',
  '关闭所有标签'
];

/** Symbol names kept beside the labels so the native menu remains auditable. */
export const TAB_CARD_MENU_SYMBOL_NAMES: string[] = [
  'sys.symbol.plus',
  'sys.symbol.xmark',
  'sys.symbol.xmark_circle'
];

/** Destructive styling applies to both close actions, not the new-tab action. */
export const TAB_CARD_MENU_DESTRUCTIVE_COLOR: string = '#FF3B30';

export function tabCardMenuItemIsDestructive(index: number): boolean {
  return index === 1 || index === 2;
}

/** Pull distance in vp required to reveal and focus the tab search field. */
export const TAB_SEARCH_PULL_THRESHOLD: number = 72;

export function tabSearchPullProgress(offsetY: number): number {
  if (offsetY <= 0) {
    return 0;
  }
  return Math.min(1, offsetY / TAB_SEARCH_PULL_THRESHOLD);
}

/** Clamp pull distance to the progress used by the reveal animation. */
export function tabSearchVisualProgress(offsetY: number): number {
  return tabSearchPullProgress(offsetY);
}

export const TAB_OVERVIEW_LAYOUT: TabOverviewLayoutMetrics = {
  columns: 2,
  horizontalPadding: 16,
  // Keep the preview card tall enough to match the Safari-style portrait
  // preview while the live page remains uniformly scaled and clipped to it.
  cardHeight: 242,
  gap: 12,
  cardRadius: HARMONY_RADIUS_CARD
};

/**
 * Gesture geometry must use the same height that is rendered by TabCard.
 * Keeping this alias next to the layout contract prevents the close threshold
 * from drifting when the card is tuned against the video reference.
 */
export const TAB_OVERVIEW_GESTURE_CARD_HEIGHT: number = TAB_OVERVIEW_LAYOUT.cardHeight;

/** Keep the card grid out of the foreground until the live page reaches its slot. */
export const TAB_OVERVIEW_PAGE_HANDOFF_START_PROGRESS: number = 0.92;

/**
 * Transfer the selection ring with the grid during its final handoff. The
 * card has fixed bounds while the live clip is still interpolating toward
 * them; leaving the live ring enabled until exactly 1.0 makes its bottom edge
 * visibly extend past the card for the last few frames.
 */
export const TAB_OVERVIEW_BORDER_HANDOFF_PROGRESS: number = 0.98;

/** Height of the title/close row that becomes the card's lower tab label. */
export const TAB_OVERVIEW_CAPTION_HEIGHT: number = 32;

/** Compact title size shared by the settled card and the live transition label. */
export const TAB_OVERVIEW_CAPTION_FONT_SIZE: number = 10;

/** Finish revealing the live label while the page is still close to full size. */
export const TAB_OVERVIEW_CAPTION_FADE_IN_END_PROGRESS: number = 0.22;

/** Native interpolating-spring parameters for the overview release. */
export const TAB_OVERVIEW_SPRING_MASS: number = 1;
export const TAB_OVERVIEW_SPRING_STIFFNESS: number = 228;
export const TAB_OVERVIEW_SPRING_DAMPING: number = 30;
export const TAB_OVERVIEW_SPRING_MAX_NORMALIZED_VELOCITY: number = 3;

/** Case-insensitive title/URL search used by the tab overview search field. */
export function filterTabsByQuery(tabs: BrowserTabRecord[], query: string): BrowserTabRecord[] {
  const normalized: string = query.trim().toLocaleLowerCase();
  if (normalized.length === 0) {
    return tabs.slice();
  }
  return tabs.filter((tab: BrowserTabRecord) => tab.title.toLocaleLowerCase().includes(normalized) ||
    tab.displayUrl.toLocaleLowerCase().includes(normalized) ||
    tab.url.toLocaleLowerCase().includes(normalized));
}

/** Keep overlay controls below whichever top system region is larger. */
export function topContentInset(systemInset: number, cutoutInset: number): number {
  return Math.max(0, systemInset, cutoutInset);
}

/**
 * Return the one top spacer owned by the tab grid.
 *
 * The card itself must not add the same offset again: doing so makes the
 * first row look too low and increases every row's measured height.  Once the
 * pull-to-reveal search field is visible, its own margin already owns the
 * system inset, so the grid only needs a compact separation below it.
 */
export function tabOverviewTopPadding(topInset: number, searchRevealed: boolean): number {
  if (searchRevealed) {
    return 6;
  }
  return Math.max(24, topContentInset(topInset, 0) + 8);
}

/** Interpolate grid spacing while the search field is being pulled in/out. */
export function tabOverviewTopPaddingForProgress(topInset: number, progress: number): number {
  const clamped: number = Math.max(0, Math.min(1, progress));
  const hidden: number = tabOverviewTopPadding(topInset, false);
  const shown: number = tabOverviewTopPadding(topInset, true);
  return hidden + (shown - hidden) * clamped;
}

/** Height reserved above the card grid while the native search field is revealed. */
export function tabOverviewSearchSlotHeightForProgress(topInset: number, progress: number): number {
  const clamped: number = Math.max(0, Math.min(1, progress));
  return (10 + Math.max(0, topInset) + TAB_SEARCH_BAR_STYLE.height + 4) * clamped;
}

/** One shared top coordinate for both the card grid and the live page window. */
export function tabOverviewCardTopForProgress(topInset: number, progress: number): number {
  return tabOverviewSearchSlotHeightForProgress(topInset, progress) +
    tabOverviewTopPaddingForProgress(topInset, progress);
}

/** Calculate one card's width from the two-column grid's measured viewport. */
export function tabOverviewCardWidth(viewportWidth: number): number {
  const available: number = Math.max(0,
    viewportWidth - TAB_OVERVIEW_LAYOUT.horizontalPadding * 2 - TAB_OVERVIEW_LAYOUT.gap);
  return Math.max(1, available / TAB_OVERVIEW_LAYOUT.columns);
}

/** Progress of the short visual handoff from the live page to the card grid. */
export function tabOverviewHandoffProgress(progress: number): number {
  const clampedProgress: number = clampOverviewProgress(progress);
  if (clampedProgress <= TAB_OVERVIEW_PAGE_HANDOFF_START_PROGRESS) {
    return 0;
  }
  return (clampedProgress - TAB_OVERVIEW_PAGE_HANDOFF_START_PROGRESS) /
    (1 - TAB_OVERVIEW_PAGE_HANDOFF_START_PROGRESS);
}

/** The grid is revealed only during the final live-page-to-card handoff. */
export function tabOverviewGridOpacityAtProgress(progress: number, hasLivePage: boolean): number {
  return hasLivePage ? tabOverviewHandoffProgress(progress) : 1;
}

/**
 * Opacity of the label that lives inside the same transformed layer as the
 * page. It fades in during the shrink and remains that page's only visible
 * label after landing. Keeping it alive at progress 1 lets the reverse spring
 * expand the exact same node instead of crossfading to a second card label.
 */
export function tabOverviewLiveCaptionOpacity(progress: number): number {
  const clampedProgress: number = clampOverviewProgress(progress);
  if (clampedProgress <= 0) {
    return 0;
  }
  if (clampedProgress < TAB_OVERVIEW_CAPTION_FADE_IN_END_PROGRESS) {
    return clampedProgress / TAB_OVERVIEW_CAPTION_FADE_IN_END_PROGRESS;
  }
  return 1;
}

/**
 * The fixed active card retains its caption layout as the close-button hit
 * target, but the live transformed page owns the pixels. Other cards continue
 * to render their normal caption.
 */
export function tabOverviewCardCaptionVisualOpacity(livePreview: boolean): number {
  return livePreview ? 0 : 1;
}

/**
 * The active live page and its transparent card shell share this close track.
 * Keeping the scalar values here prevents the shell from moving ahead while
 * the page stays behind it during a horizontal close gesture.
 */
export interface TabOverviewLivePageCloseFrame {
  horizontalOffset: number;
  scale: number;
  opacity: number;
}

export function tabOverviewLivePageCloseFrame(
  progress: number,
  horizontalOffset: number
): TabOverviewLivePageCloseFrame {
  const clampedProgress: number = clampOverviewProgress(progress);
  return {
    horizontalOffset: Number.isFinite(horizontalOffset) ? horizontalOffset : 0,
    scale: 1 - 0.06 * clampedProgress,
    opacity: Math.max(0.05, 1 - 0.95 * clampedProgress)
  };
}

/**
 * The live page and its card shell must never paint the selection ring at the
 * same time.  The live page owns the ring while it is moving or expanding
 * back; the card shell takes ownership only after the overview has settled.
 */
export type TabOverviewBorderOwner = 'none' | 'live-page' | 'card';

export function tabOverviewBorderOwner(
  progress: number,
  closing: boolean
): TabOverviewBorderOwner {
  const clampedProgress: number = clampOverviewProgress(progress);
  if (clampedProgress <= 0) {
    return 'none';
  }
  // During reverse expansion the live page must keep ownership so its ring
  // grows with the same frame as the page. During entry, hand ownership to
  // the fixed card in the final grid handoff segment to avoid a taller live
  // clip ring sitting outside the already-settled card bounds.
  if (closing) {
    return 'live-page';
  }
  if (clampedProgress < TAB_OVERVIEW_BORDER_HANDOFF_PROGRESS) {
    return 'live-page';
  }
  return 'card';
}

/**
 * Convert the last vertical gesture velocity into the normalized velocity
 * expected by ArkUI's interpolatingSpring curve.  The value is measured in
 * progress units per second relative to the remaining progress distance.
 */
export function tabOverviewSpringVelocity(
  startProgress: number,
  targetProgress: number,
  velocityY: number,
  viewportHeight: number
): number {
  const start: number = clampOverviewProgress(startProgress);
  const target: number = clampOverviewProgress(targetProgress);
  const distance: number = target - start;
  if (Math.abs(distance) < 0.0001 || !Number.isFinite(velocityY) ||
    !Number.isFinite(viewportHeight) || viewportHeight <= 0) {
    return 0;
  }
  // A negative screen-Y velocity means upward progress. Divide by the
  // signed remaining distance so the result is positive when the gesture is
  // already moving toward the requested spring target.
  const progressVelocity: number = -velocityY / viewportHeight;
  const normalized: number = progressVelocity / distance;
  return Math.max(-TAB_OVERVIEW_SPRING_MAX_NORMALIZED_VELOCITY,
    Math.min(TAB_OVERVIEW_SPRING_MAX_NORMALIZED_VELOCITY, normalized));
}

/** Build the native ArkUI easing string used by the shared frame animator. */
export function tabOverviewSpringEasing(
  startProgress: number,
  targetProgress: number,
  velocityY: number,
  viewportHeight: number
): string {
  const velocity: number = tabOverviewSpringVelocity(
    startProgress,
    targetProgress,
    velocityY,
    viewportHeight
  );
  return `interpolating-spring(${velocity.toFixed(3)}, ${TAB_OVERVIEW_SPRING_MASS}, ` +
    `${TAB_OVERVIEW_SPRING_STIFFNESS}, ${TAB_OVERVIEW_SPRING_DAMPING})`;
}

/**
 * One native transform track for the active live page during overview entry.
 * The frame starts as the full page and finishes at the active card's measured
 * slot. Keeping this geometry pure makes button entry and the upward pull use
 * exactly the same visual target without moving or remounting the WebView.
 */
export interface TabOverviewPageFrame {
  scaleX: number;
  scaleY: number;
  translateX: number;
  translateY: number;
  /** The stationary clip window that receives the live page during handoff. */
  clipLeft: number;
  clipTop: number;
  clipWidth: number;
  clipHeight: number;
  cornerRadius: number;
  /** Border belongs to the same transformed page layer, not the card shell. */
  borderWidth: number;
  /** The live title row uses local coordinates so it inherits this transform. */
  captionOpacity: number;
  captionLocalTop: number;
  captionLocalHeight: number;
  /** Local metric multiplier that resolves to 1 after the parent reaches its target scale. */
  captionContentScale: number;
}

/**
 * Resolve the caption's local radius so that, after the shared page-layer
 * scale is applied, its visible bottom corners match the live page outline.
 * The outline is in screen coordinates while the caption is inside the
 * transformed page layer, so reusing the raw radius directly causes the two
 * corners to diverge during the interactive shrink.
 */
export function tabOverviewCaptionLocalRadius(frame: TabOverviewPageFrame | undefined): number {
  if (frame === undefined || !Number.isFinite(frame.cornerRadius) ||
    !Number.isFinite(frame.scaleX) || frame.scaleX <= 0) {
    return 0;
  }
  return frame.cornerRadius / frame.scaleX;
}

/**
 * Screen-space choreography for the two pieces of browser chrome that must
 * remain visually related to the live page during the overview morph.
 *
 * `addressLeft`/`addressTop`/`addressWidth` describe the unscaled
 * AddressTabStrip layout box.  The visible capsule is exposed separately so
 * tests can assert that it lands on the same card width as the page frame.
 */
export interface TabOverviewChromeFrame {
  addressLeft: number;
  addressTop: number;
  addressWidth: number;
  addressScaleX: number;
  addressScaleY: number;
  addressOpacity: number;
  addressVisualLeft: number;
  addressVisualTop: number;
  addressVisualWidth: number;
  addressVisualHeight: number;
  addressJellyScaleX: number;
  addressJellyScaleY: number;
  addressJellyTranslateY: number;
  toolbarOpacity: number;
  toolbarTranslateY: number;
  toolbarScaleX: number;
  toolbarScaleY: number;
}

/**
 * The bottom chrome is one fixed surface shared by the normal page and the
 * overview transition. Keep that surface mounted through the settled overview
 * endpoint so the final transparent frame cannot trigger an unmount/remount
 * layout flash.
 */
export function shouldMountBottomBrowserBar(fullScreen: boolean): boolean {
  return !fullScreen;
}

/**
 * Keep the shared address capsule alive through the overview handoff. At the
 * settled overview endpoint it is transparent and hit-test disabled, but
 * keeping the node mounted prevents a short reverse drag from losing the
 * first frame when the capsule returns to the bottom chrome.
 */
export function shouldMountAddressTransitionLayer(fullScreen: boolean): boolean {
  return !fullScreen;
}

/**
 * The address layer is a sibling of the bottom chrome and must win every
 * reverse-drag z-order race. Its child remains the only interactive address
 * surface, so the full-window parent does not steal page touches.
 */
export function tabOverviewAddressLayerZIndex(): number {
  return 40;
}

/**
 * During reverse expansion the live page sits above the overview cards at
 * z-index 20. Put the returning toolbar above that page, while keeping the
 * shared address capsule above both layers.
 */
export function tabOverviewBottomChromeZIndex(closing: boolean): number {
  return closing ? 25 : 10;
}

/** Entry starts the toolbar handoff only after the address capsule has split. */
export const TAB_OVERVIEW_TOOLBAR_STRETCH_START_PROGRESS: number = 0.22;
export const TAB_OVERVIEW_TOOLBAR_STRETCH_END_PROGRESS: number = 0.44;
export const TAB_OVERVIEW_TOOLBAR_HIDE_START_PROGRESS: number = 0.42;
export const TAB_OVERVIEW_TOOLBAR_HIDE_END_PROGRESS: number = 0.78;

/** Reverse expansion keeps the toolbar below the page until the address rejoins. */
export const TAB_OVERVIEW_TOOLBAR_RETURN_END_PROGRESS: number = 0.22;
export const TAB_OVERVIEW_ADDRESS_RETURN_JELLY_END_PROGRESS: number = 0.18;

/** Handoff the transient address capsule to the settled card caption. */
export const TAB_OVERVIEW_ADDRESS_HANDOFF_START_PROGRESS: number = 0.82;
export const TAB_OVERVIEW_ADDRESS_HANDOFF_END_PROGRESS: number = 0.90;
export const TAB_OVERVIEW_CAPTION_HANDOFF_START_PROGRESS: number = 0.90;
export const TAB_OVERVIEW_CAPTION_HANDOFF_END_PROGRESS: number = 0.98;

function overviewSegmentProgress(progress: number, start: number, end: number): number {
  if (end <= start) {
    return progress >= end ? 1 : 0;
  }
  return Math.max(0, Math.min(1, (progress - start) / (end - start)));
}

/** A bounded bell keeps the jelly directly driven by the shared progress. */
function overviewJellyProgress(progress: number, start: number, end: number): number {
  const segment: number = overviewSegmentProgress(progress, start, end);
  return Math.sin(Math.PI * segment);
}

/**
 * The live page caption is the settled card label. Fade it in only during the
 * final grid handoff so a miniature address field is not left visible under
 * an already-settled card.
 */
export function tabOverviewCaptionHandoffOpacity(progress: number, _closing: boolean): number {
  const handoff: number = overviewSegmentProgress(
    progress,
    TAB_OVERVIEW_CAPTION_HANDOFF_START_PROGRESS,
    TAB_OVERVIEW_CAPTION_HANDOFF_END_PROGRESS
  );
  // The same track is reversible: progress falls during dismissal, so the
  // caption naturally fades out without a second animation timeline.
  return handoff;
}

/**
 * Build the address/toolbar frame from the same page progress as the live
 * page. The address capsule uses the page frame's target scale and visible
 * width, while its local layout box compensates for ArkUI's center scaling so
 * the rendered capsule remains aligned with the page card.
 */
export function tabOverviewChromeFrame(
  progress: number,
  closing: boolean,
  viewportWidth: number,
  viewportHeight: number,
  chromeHeight: number,
  pageFrame: TabOverviewPageFrame
): TabOverviewChromeFrame {
  const clampedProgress: number = clampOverviewProgress(progress);
  const width: number = Number.isFinite(viewportWidth) && viewportWidth > 0 ? viewportWidth : 1;
  const height: number = Number.isFinite(viewportHeight) && viewportHeight > 0 ? viewportHeight : 1;
  const safeChromeHeight: number = Number.isFinite(chromeHeight) && chromeHeight > 0
    ? chromeHeight
    : 0;
  const pageScale: number = Math.max(0.01, Math.min(1,
    Number.isFinite(pageFrame.scaleX) ? pageFrame.scaleX : 1));
  const pageScaleY: number = Math.max(0.01, Math.min(1,
    Number.isFinite(pageFrame.scaleY) ? pageFrame.scaleY : pageScale));
  const fullLeft: number = 8;
  const fullTop: number = height - safeChromeHeight + ADDRESS_SEARCH_BAR_TOP_PADDING;
  const fullWidth: number = Math.max(1, width - 16);
  const fullHeight: number = ADDRESS_SEARCH_BAR_STYLE.height;

  // `pageFrame` is already evaluated at `clampedProgress`. Do not interpolate
  // from the current frame a second time: doing so makes the address strip
  // lag behind the live page during the gesture and leaves a visible gap
  // between the card bottom and the capsule. Recover the final card geometry
  // once, then place the capsule on the same single progress track.
  const progressForTarget: number = Math.max(0.0001, clampedProgress);
  const targetScaleY: number = clampedProgress > 0
    ? 1 + (pageFrame.scaleY - 1) / progressForTarget
    : 1;
  const targetLeft: number = clampedProgress > 0
    ? pageFrame.clipLeft / progressForTarget
    : 0;
  const targetTop: number = clampedProgress > 0
    ? pageFrame.clipTop / progressForTarget
    : 0;
  const targetWidth: number = clampedProgress > 0
    ? width + (pageFrame.clipWidth - width) / progressForTarget
    : width;
  const targetHeight: number = clampedProgress > 0
    ? height + (pageFrame.clipHeight - height) / progressForTarget
    : height;
  const targetAddressHeight: number = fullHeight * targetScaleY;
  const targetAddressTop: number = targetTop + targetHeight - targetAddressHeight;
  const visualLeft: number = interpolateOverviewValue(
    fullLeft, targetLeft, clampedProgress
  );
  const visualTop: number = interpolateOverviewValue(
    fullTop, targetAddressTop, clampedProgress
  );
  const visualWidth: number = interpolateOverviewValue(
    fullWidth, targetWidth, clampedProgress
  );
  const visualHeight: number = interpolateOverviewValue(
    fullHeight, targetAddressHeight, clampedProgress
  );
  // The live page frame already contains the current scale. Reusing it
  // directly keeps the capsule's transform phase-locked to the page.
  const scaleX: number = pageScale;
  const scaleY: number = pageScaleY;
  const layoutWidth: number = Math.max(16, visualWidth / Math.max(0.01, scaleX) + 16);
  // The strip's active capsule is centered with an 8vp inset in its local box.
  // Compensate for ArkUI's center-based scale before placing that box.
  const addressLeft: number = visualLeft - 8 * scaleX - layoutWidth * (1 - scaleX) / 2;
  const addressTop: number = visualTop - (56 - 56 * scaleY) / 2 -
    ADDRESS_SEARCH_BAR_TOP_PADDING * scaleY;
  const jellyProgress: number = closing
    ? overviewJellyProgress(clampedProgress, 0, TAB_OVERVIEW_ADDRESS_RETURN_JELLY_END_PROGRESS)
    : overviewJellyProgress(
      clampedProgress,
      TAB_OVERVIEW_TOOLBAR_STRETCH_START_PROGRESS,
      TAB_OVERVIEW_TOOLBAR_STRETCH_END_PROGRESS
    );
  const toolbarJellyProgress: number = closing
    ? overviewJellyProgress(clampedProgress, 0, TAB_OVERVIEW_TOOLBAR_RETURN_END_PROGRESS)
    : overviewJellyProgress(
      clampedProgress,
      TAB_OVERVIEW_TOOLBAR_STRETCH_START_PROGRESS,
      TAB_OVERVIEW_TOOLBAR_STRETCH_END_PROGRESS
    );
  const addressHandoff: number = overviewSegmentProgress(
    clampedProgress,
    TAB_OVERVIEW_ADDRESS_HANDOFF_START_PROGRESS,
    TAB_OVERVIEW_ADDRESS_HANDOFF_END_PROGRESS
  );
  const addressOpacity: number = 1 - addressHandoff;
  let toolbarOpacity: number;
  let toolbarTranslateY: number;
  const toolbarJellyAnchorOffset: number = toolbarJellyProgress * safeChromeHeight * 0.05;
  if (closing) {
    const returnProgress: number = 1 - overviewSegmentProgress(
      clampedProgress, 0, TAB_OVERVIEW_TOOLBAR_RETURN_END_PROGRESS
    );
    toolbarOpacity = returnProgress;
    toolbarTranslateY = safeChromeHeight * (1 - returnProgress) -
      toolbarJellyAnchorOffset;
  } else {
    const hideProgress: number = overviewSegmentProgress(
      clampedProgress,
      TAB_OVERVIEW_TOOLBAR_HIDE_START_PROGRESS,
      TAB_OVERVIEW_TOOLBAR_HIDE_END_PROGRESS
    );
    toolbarOpacity = 1 - hideProgress;
    toolbarTranslateY = safeChromeHeight * hideProgress - toolbarJellyAnchorOffset;
  }
  return {
    addressLeft,
    addressTop,
    addressWidth: layoutWidth,
    addressScaleX: scaleX,
    addressScaleY: scaleY,
    addressOpacity,
    addressVisualLeft: visualLeft,
    addressVisualTop: visualTop,
    addressVisualWidth: visualWidth,
    addressVisualHeight: visualHeight,
    addressJellyScaleX: 1 + jellyProgress * (closing ? 0.05 : 0.032),
    addressJellyScaleY: 1 - jellyProgress * (closing ? 0.12 : 0.08),
    addressJellyTranslateY: -jellyProgress * (closing ? 4 : 3),
    toolbarOpacity,
    toolbarTranslateY,
    toolbarScaleX: 1 + toolbarJellyProgress * 0.04,
    // Keep the bottom edge visually anchored while the top edge stretches up.
    toolbarScaleY: 1 + toolbarJellyProgress * 0.10
  };
}

/** Fade the fixed browser chrome with the same progress as the page morph. */
export function tabOverviewChromeOpacity(progress: number): number {
  return 1 - tabOverviewChromeMotionProgress(progress);
}

/** Move the fixed browser chrome below the viewport while overview opens. */
export function tabOverviewChromeTranslateY(progress: number, chromeHeight: number): number {
  if (!Number.isFinite(chromeHeight) || chromeHeight <= 0) {
    return 0;
  }
  return chromeHeight * tabOverviewChromeMotionProgress(progress);
}

// Leave the fixed address field visible only while the page is still in its
// full-screen phase. It must be gone before the live card caption reaches the
// card handoff, otherwise two address labels are visible at once.
const TAB_OVERVIEW_CHROME_FADE_START_PROGRESS: number = 0.18;
const TAB_OVERVIEW_CHROME_FADE_END_PROGRESS: number = 0.56;

function tabOverviewChromeMotionProgress(progress: number): number {
  const clamped: number = clampOverviewProgress(progress);
  if (clamped <= TAB_OVERVIEW_CHROME_FADE_START_PROGRESS) {
    return 0;
  }
  if (clamped >= TAB_OVERVIEW_CHROME_FADE_END_PROGRESS) {
    return 1;
  }
  return (clamped - TAB_OVERVIEW_CHROME_FADE_START_PROGRESS) /
    (TAB_OVERVIEW_CHROME_FADE_END_PROGRESS - TAB_OVERVIEW_CHROME_FADE_START_PROGRESS);
}

function clampOverviewProgress(progress: number): number {
  if (!Number.isFinite(progress)) {
    return 0;
  }
  return Math.max(0, Math.min(1, progress));
}

function interpolateOverviewValue(start: number, end: number, progress: number): number {
  return start + (end - start) * progress;
}

/** Calculate the full-page-to-active-card transform used by the live page. */
export function tabOverviewPageFrame(
  progress: number,
  viewportWidth: number,
  viewportHeight: number,
  activeIndex: number,
  topInset: number,
  searchProgress: number = 0
): TabOverviewPageFrame {
  const identity: TabOverviewPageFrame = {
    scaleX: 1,
    scaleY: 1,
    translateX: 0,
    translateY: 0,
    clipLeft: 0,
    clipTop: 0,
    clipWidth: viewportWidth,
    clipHeight: viewportHeight,
    cornerRadius: 0,
    borderWidth: 0,
    captionOpacity: 0,
    captionLocalTop: Math.max(0, viewportHeight - TAB_OVERVIEW_CAPTION_HEIGHT),
    captionLocalHeight: TAB_OVERVIEW_CAPTION_HEIGHT,
    captionContentScale: 1
  };
  if (!Number.isFinite(viewportWidth) || !Number.isFinite(viewportHeight) ||
    viewportWidth <= 0 || viewportHeight <= 0 || activeIndex < 0) {
    return identity;
  }

  const clampedProgress: number = clampOverviewProgress(progress);
  const cardWidth: number = tabOverviewCardWidth(viewportWidth);
  const cardHeight: number = TAB_OVERVIEW_LAYOUT.cardHeight;
  const column: number = activeIndex % TAB_OVERVIEW_LAYOUT.columns;
  const row: number = Math.floor(activeIndex / TAB_OVERVIEW_LAYOUT.columns);
  const targetLeft: number = TAB_OVERVIEW_LAYOUT.horizontalPadding +
    column * (cardWidth + TAB_OVERVIEW_LAYOUT.gap);
  const targetTop: number = tabOverviewCardTopForProgress(topInset, searchProgress) +
    row * (cardHeight + TAB_OVERVIEW_LAYOUT.gap);
  // Preserve the WebView's aspect ratio.  The card is intentionally shorter
  // than the page, so the page is fitted to the card width and the shared
  // clip window crops the lower part instead of vertically squeezing content.
  const targetScale: number = cardWidth / viewportWidth;
  const scale: number = interpolateOverviewValue(1, targetScale, clampedProgress);
  // ArkUI scales around the layer center. Compensate the center shift so the
  // scaled layer's top-left corner stays aligned with the clip window.
  const targetTranslateX: number = targetLeft - viewportWidth * (1 - targetScale) / 2;
  const targetTranslateY: number = targetTop - viewportHeight * (1 - targetScale) / 2;
  const clipHeight: number = interpolateOverviewValue(viewportHeight, cardHeight, clampedProgress);
  // Keep the label inside the same scaled layer while pinning its rendered
  // bottom edge to the current clip window. Its local height stays fixed, so
  // it shrinks with the page instead of behaving like a detached overlay.
  const captionLocalHeight: number = TAB_OVERVIEW_CAPTION_HEIGHT / targetScale;
  const captionLocalTop: number = Math.max(0, clipHeight / scale - captionLocalHeight);
  return {
    scaleX: scale,
    scaleY: scale,
    translateX: interpolateOverviewValue(0, targetTranslateX, clampedProgress),
    translateY: interpolateOverviewValue(0, targetTranslateY, clampedProgress),
    clipLeft: interpolateOverviewValue(0, targetLeft, clampedProgress),
    clipTop: interpolateOverviewValue(0, targetTop, clampedProgress),
    clipWidth: interpolateOverviewValue(viewportWidth, cardWidth, clampedProgress),
    clipHeight: clipHeight,
    cornerRadius: interpolateOverviewValue(0, TAB_OVERVIEW_LAYOUT.cardRadius, clampedProgress),
    borderWidth: interpolateOverviewValue(0, 2, clampedProgress),
    captionOpacity: tabOverviewLiveCaptionOpacity(clampedProgress),
    captionLocalTop: captionLocalTop,
    captionLocalHeight: captionLocalHeight,
    captionContentScale: 1 / targetScale
  };
}
