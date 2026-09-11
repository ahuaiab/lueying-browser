/**
 * Transient geometry for the Safari-style address-bar tab gesture.
 *
 * The tab store is deliberately not touched here.  These values are only
 * render state: the current page, an adjacent preview and the browser chrome
 * can follow the pointer on every PanGesture update without committing a tab
 * switch until the gesture settles.
 */
export interface TabGestureMotionState {
  rawDragX: number;
  /** Signed normalized drag used by diagnostics and SafariTabTransition. */
  normalizedProgress: number;
  /** The value actually applied to the moving root scene. */
  displayDragX: number;
  pageTranslateX: number;
  adjacentTranslateX: number;
  /** A single normalized progress shared by page and address-bar scenes. */
  transitionProgress: number;
  swipeProgress: number;
  overscrollProgress: number;
  newTabProgress: number;
  previewIndex: number;
  previewKind: TabPreviewKind;
  isDragging: boolean;
}

/** The target scene prepared beside the committed current scene. */
export enum TabPreviewKind {
  NONE = 'none',
  EXISTING_TAB = 'existingTab',
  NEW_TAB = 'newTab'
}

/** Lifecycle of one interruptible root-scene transition. */
export enum TabGestureState {
  IDLE = 'idle',
  DRAGGING = 'dragging',
  SETTLING = 'settling',
  COMMITTING = 'committing',
  CANCELLING = 'cancelling'
}

/**
 * Values consumed by the transition scene for one render frame.
 *
 * Keeping this boundary explicit prevents gesture diagnostics from looking
 * correct while the scene silently ignores the offsets.  The current page
 * and the preview are both kept mounted and receive these translations on
 * every drag/settling frame.
 */
export interface TabTransitionVisualState {
  currentTranslateX: number;
  previewTranslateX: number;
  showPreview: boolean;
  previewKind: TabPreviewKind;
  newTabProgress: number;
}

export const TAB_RUBBER_BAND_MAX_PULL: number = 52;
export const TAB_RUBBER_BAND_FACTOR: number = 90;
export const TAB_SWITCH_COMMIT_RATIO: number = 0.28;
export const TAB_GESTURE_PROJECTION_SECONDS: number = 0.12;
export const NEW_TAB_PULL_START: number = 25;
export const NEW_TAB_PLUS_FULL_DISTANCE: number = 70;
export const NEW_TAB_PULL_READY_DISTANCE: number = 105;

function clamp(value: number, lower: number = 0, upper: number = 1): number {
  return Math.max(lower, Math.min(upper, value));
}

function finiteOrZero(value: number): number {
  return Number.isFinite(value) ? value : 0;
}

/** Normalize gesture geometry before it is applied to ArkUI scene nodes. */
export function tabTransitionVisualState(
  currentX: number,
  previewX: number,
  showPreview: boolean,
  previewKind: TabPreviewKind,
  newTabProgress: number
): TabTransitionVisualState {
  return {
    currentTranslateX: finiteOrZero(currentX),
    previewTranslateX: finiteOrZero(previewX),
    showPreview: showPreview && previewKind !== TabPreviewKind.NONE,
    previewKind,
    newTabProgress: clamp(finiteOrZero(newTabProgress))
  };
}

/**
 * Non-linear custom pull resistance.  It is monotonic and approaches, but
 * never abruptly hits, the configured maximum distance.
 */
export function rubberBandDistance(
  distance: number,
  maxPull: number = TAB_RUBBER_BAND_MAX_PULL,
  factor: number = TAB_RUBBER_BAND_FACTOR
): number {
  if (!Number.isFinite(distance) || distance === 0) {
    return 0;
  }
  const safeMax: number = Math.max(0, maxPull);
  const safeFactor: number = Math.max(1, factor);
  const magnitude: number = safeMax * (1 - Math.exp(-Math.abs(distance) / safeFactor));
  return distance < 0 ? -magnitude : magnitude;
}

/** Project a fling a short distance beyond the final pointer position. */
export function projectedOffset(
  offsetX: number,
  velocityX: number,
  projectionSeconds: number = TAB_GESTURE_PROJECTION_SECONDS
): number {
  return offsetX + velocityX * Math.max(0, projectionSeconds);
}

/** Decide an adjacent-tab commit using both distance and release velocity. */
export function shouldCommitProjectedSwitch(
  offsetX: number,
  velocityX: number,
  viewportWidth: number,
  commitRatio: number = TAB_SWITCH_COMMIT_RATIO
): boolean {
  const width: number = Math.max(1, viewportWidth);
  return Math.abs(projectedOffset(offsetX, velocityX)) >= width * clamp(commitRatio, 0, 1);
}

/** Progress used by the end-of-strip plus affordance. */
export function newTabPullProgress(distance: number): number {
  const magnitude: number = Math.abs(distance);
  if (magnitude <= NEW_TAB_PULL_START) {
    return 0;
  }
  return clamp((magnitude - NEW_TAB_PULL_START) /
    (NEW_TAB_PULL_READY_DISTANCE - NEW_TAB_PULL_START));
}

/** Background enters later than the plus glyph, matching the reference. */
export function newTabBackgroundProgress(distance: number): number {
  const magnitude: number = Math.abs(distance);
  if (magnitude <= NEW_TAB_PLUS_FULL_DISTANCE) {
    return 0;
  }
  return clamp((magnitude - NEW_TAB_PLUS_FULL_DISTANCE) /
    (NEW_TAB_PULL_READY_DISTANCE - NEW_TAB_PLUS_FULL_DISTANCE));
}

export function shouldCommitNewTabPull(
  offsetX: number,
  velocityX: number,
  readyDistance: number = NEW_TAB_PULL_READY_DISTANCE
): boolean {
  const projected: number = projectedOffset(offsetX, velocityX);
  return Math.abs(offsetX) >= readyDistance || Math.abs(projected) >= readyDistance;
}

/**
 * Compute all render-only values for one horizontal address-bar sample.
 * `currentIndex` remains the real active index and is never changed here.
 */
export function tabGestureMotion(
  rawDragX: number,
  viewportWidth: number,
  currentIndex: number,
  tabCount: number
): TabGestureMotionState {
  const width: number = Math.max(1, viewportWidth);
  const index: number = Math.max(0, currentIndex);
  const count: number = Math.max(0, tabCount);
  const hasPrevious: boolean = index > 0 && count > 0;
  const hasNext: boolean = index + 1 < count;
  const horizontal: number = Number.isFinite(rawDragX) ? rawDragX : 0;
  const base: TabGestureMotionState = {
    rawDragX: horizontal,
    normalizedProgress: horizontal / width,
    displayDragX: 0,
    pageTranslateX: 0,
    adjacentTranslateX: 0,
    transitionProgress: 0,
    swipeProgress: 0,
    overscrollProgress: 0,
    newTabProgress: 0,
    previewIndex: -1,
    previewKind: TabPreviewKind.NONE,
    isDragging: true
  };
  if (horizontal === 0) {
    return base;
  }

  if (horizontal > 0 && !hasPrevious) {
    const pull: number = rubberBandDistance(horizontal);
    base.displayDragX = pull;
    base.pageTranslateX = pull * 0.6;
    // The fixed bottom action row remains stationary; the moving root scene
    // uses the authoritative raw drag for both page and address-bar layers.
    base.transitionProgress = clamp(Math.abs(pull) / TAB_RUBBER_BAND_MAX_PULL);
    base.overscrollProgress = clamp(Math.abs(pull) / TAB_RUBBER_BAND_MAX_PULL);
    return base;
  }

  if (horizontal < 0 && !hasNext) {
    // The last tab is not a dead edge. It owns an ephemeral target scene that
    // enters from the right with the same 1:1 displacement as the current
    // scene. Rubber-band resistance is reserved for a direction with no
    // target scene (the first-tab right pull above).
    base.displayDragX = horizontal;
    base.pageTranslateX = horizontal;
    base.adjacentTranslateX = width + horizontal;
    base.transitionProgress = clamp(Math.abs(horizontal) / width);
    base.newTabProgress = newTabPullProgress(horizontal);
    base.previewKind = TabPreviewKind.NEW_TAB;
    return base;
  }

  base.displayDragX = horizontal;
  base.pageTranslateX = horizontal;
  base.adjacentTranslateX = horizontal < 0 ? width + horizontal : -width + horizontal;
  base.transitionProgress = clamp(Math.abs(horizontal) / width);
  base.swipeProgress = clamp(Math.abs(horizontal) / width);
  base.previewIndex = horizontal < 0 ? index + 1 : index - 1;
  base.previewKind = TabPreviewKind.EXISTING_TAB;
  return base;
}

export function toolbarScaleXForPull(overscrollProgress: number, newTabProgress: number): number {
  return 1 + 0.02 * clamp(Math.max(overscrollProgress, newTabProgress));
}

export function toolbarScaleYForPull(overscrollProgress: number, newTabProgress: number): number {
  return 1 - 0.01 * clamp(Math.max(overscrollProgress, newTabProgress));
}

/** Reset render-only state without mutating the real tab selection. */
export function emptyTabGestureMotion(): TabGestureMotionState {
  return {
    rawDragX: 0,
    normalizedProgress: 0,
    displayDragX: 0,
    pageTranslateX: 0,
    adjacentTranslateX: 0,
    transitionProgress: 0,
    swipeProgress: 0,
    overscrollProgress: 0,
    newTabProgress: 0,
    previewIndex: -1,
    previewKind: TabPreviewKind.NONE,
    isDragging: false
  };
}

/**
 * Vertical overview reveal keeps the horizontal address track at its origin.
 * A small diagonal drift from the finger must not be reused by the capsule's
 * tab-spacing calculation while the page is moving upward.
 */
export function verticalOverviewGestureMotion(): TabGestureMotionState {
  const state: TabGestureMotionState = emptyTabGestureMotion();
  state.isDragging = true;
  return state;
}
