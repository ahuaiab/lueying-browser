/**
 * The measured visual bounds of the floating TabBar, expressed in window vp.
 * TouchObject.windowX/windowY and Area.globalPosition use the same unit.
 */
export interface TabBarRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

/** Keep edge tolerance below the page content area. */
export const TAB_BAR_TOUCH_TOLERANCE_VP: number = 2;

/**
 * Accept only a point in the measured capsule (plus the small explicit edge
 * tolerance). An invalid or not-yet-measured rectangle must never become a
 * full-screen gesture fallback.
 */
export function isPointInTabBar(
  pointX: number,
  pointY: number,
  rect: TabBarRect,
  tolerance: number = TAB_BAR_TOUCH_TOLERANCE_VP
): boolean {
  if (!Number.isFinite(pointX) || !Number.isFinite(pointY) ||
    !Number.isFinite(rect.x) || !Number.isFinite(rect.y) ||
    !Number.isFinite(rect.width) || !Number.isFinite(rect.height) ||
    rect.width <= 0 || rect.height <= 0) {
    return false;
  }
  const safeTolerance: number = Number.isFinite(tolerance) && tolerance >= 0 ? tolerance : 0;
  return pointX >= rect.x - safeTolerance &&
    pointX <= rect.x + rect.width + safeTolerance &&
    pointY >= rect.y - safeTolerance &&
    pointY <= rect.y + rect.height + safeTolerance;
}
