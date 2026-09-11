import { TabPreviewKind } from './TabGestureMotion';

export interface SafariTransitionFrame {
  progress: number;
  currentPageX: number;
  targetPageX: number;
  currentAddressX: number;
  targetAddressX: number;
  targetIndex: number;
  previewKind: TabPreviewKind;
}

export interface NewTabPreviewVisual {
  showPagePlus: boolean;
  showAddressPlus: boolean;
  addressPlusOpacity: number;
}

export interface NewTabHandoffVisual {
  plusOpacity: number;
  placeholderOpacity: number;
  plusScale: number;
  placeholderScale: number;
  placeholderSlideProgress: number;
}

export interface TabTransitionSceneVisualState {
  currentX: number;
  previewX: number;
  previewKind: TabPreviewKind;
  showPreview: boolean;
  /** The new-tab affordance belongs to AddressTabStrip, never this page scene. */
  showPagePlus: boolean;
}

export function shouldRenderAddressHandoff(active: boolean, progress: number): boolean {
  return active || finite(progress) < 1;
}

function finite(value: number): number {
  return Number.isFinite(value) ? value : 0;
}

function clamp(value: number, lower: number = -1, upper: number = 1): number {
  return Math.max(lower, Math.min(upper, value));
}

/**
 * Keep the two page layers alive for the whole pointer-driven transition.
 * The committed tab model is updated only after the settle animation ends.
 */
export function tabTransitionSceneVisualState(
  currentX: number,
  previewX: number,
  previewKind: TabPreviewKind,
  showPreview: boolean
): TabTransitionSceneVisualState {
  return {
    currentX: finite(currentX),
    previewX: finite(previewX),
    previewKind,
    showPreview: showPreview && previewKind !== TabPreviewKind.NONE,
    showPagePlus: false
  };
}

export function sceneOffsetForIndex(index: number, activeIndex: number, pageWidth: number, dragX: number): number {
  const width: number = Math.max(1, finite(pageWidth));
  return (index - activeIndex) * width + finite(dragX);
}

export function addressOffsetForIndex(index: number, activeIndex: number, addressStride: number,
  dragX: number, pageWidth: number): number {
  const width: number = Math.max(1, finite(pageWidth));
  const stride: number = Math.max(1, finite(addressStride));
  return (index - activeIndex) * stride + clamp(finite(dragX) / width) * stride;
}

export function addressItemLeft(index: number, activeIndex: number, itemWidth: number,
  gap: number, dragX: number, pageWidth: number): number {
  const width: number = Math.max(1, finite(pageWidth));
  const capsuleWidth: number = Math.max(1, finite(itemWidth));
  return (width - capsuleWidth) / 2 + addressOffsetForIndex(index, activeIndex,
    capsuleWidth + gap, dragX, width);
}

/** A final tab can prepare its render-only neighbour before pointer motion. */
export function shouldPrimeFinalTabPreview(activeIndex: number, tabCount: number): boolean {
  const count: number = Math.max(0, Math.trunc(finite(tabCount)));
  const index: number = Math.trunc(finite(activeIndex));
  return count > 0 && index === count - 1;
}

/** Keep the idle strip clean while retaining one target during a horizontal drag. */
export function shouldRenderAddressItem(index: number, activeIndex: number, dragX: number,
  tabCount: number, previewKind: TabPreviewKind = TabPreviewKind.EXISTING_TAB): boolean {
  const count: number = Math.max(0, Math.trunc(finite(tabCount)));
  const item: number = Math.trunc(finite(index));
  const active: number = Math.trunc(finite(activeIndex));
  if (count <= 0 || active < 0 || active >= count || item === active) {
    return count > 0 && item === active;
  }
  if (!Number.isFinite(dragX) || dragX === 0 || previewKind !== TabPreviewKind.EXISTING_TAB) {
    return false;
  }
  const target: number = active + (dragX < 0 ? 1 : -1);
  return target >= 0 && target < count && item === target;
}

/**
 * Keep the target capsule on the same track as the page, but let it emerge
 * after the gesture has established a direction. This removes the instant
 * second-capsule pop at the first PanGesture frame without delaying the
 * settled address value.
 */
export function addressPreviewOpacity(
  index: number,
  activeIndex: number,
  dragX: number,
  pageWidth: number
): number {
  if (Math.trunc(finite(index)) === Math.trunc(finite(activeIndex))) {
    return 1;
  }
  const normalized: number = Math.abs(finite(dragX)) / Math.max(1, finite(pageWidth));
  const fadeStart: number = 0.08;
  const fadeEnd: number = 0.20;
  return clamp((normalized - fadeStart) / (fadeEnd - fadeStart), 0, 1);
}

export function safariTransitionFrame(dragX: number, pageWidth: number, addressStride: number,
  activeIndex: number, tabCount: number): SafariTransitionFrame {
  const count: number = Math.max(0, Math.trunc(tabCount));
  const index: number = Math.max(0, Math.trunc(activeIndex));
  const horizontal: number = finite(dragX);
  const direction: number = horizontal < 0 ? 1 : -1;
  const candidate: number = index + direction;
  const isNewTab: boolean = horizontal < 0 && candidate >= count;
  const hasExistingTarget: boolean = candidate >= 0 && candidate < count;
  const targetIndex: number = isNewTab ? count : (hasExistingTarget ? candidate : index);
  const previewKind: TabPreviewKind = isNewTab ? TabPreviewKind.NEW_TAB
    : (hasExistingTarget ? TabPreviewKind.EXISTING_TAB : TabPreviewKind.NONE);
  return {
    progress: clamp(horizontal / Math.max(1, finite(pageWidth))),
    currentPageX: sceneOffsetForIndex(index, index, pageWidth, horizontal),
    targetPageX: sceneOffsetForIndex(targetIndex, index, pageWidth, horizontal),
    currentAddressX: addressOffsetForIndex(index, index, addressStride, horizontal, pageWidth),
    targetAddressX: addressOffsetForIndex(targetIndex, index, addressStride, horizontal, pageWidth),
    targetIndex,
    previewKind
  };
}

export function newTabPreviewVisual(progress: number): NewTabPreviewVisual {
  const normalized: number = Math.max(0, Math.min(1, finite(progress)));
  return { showPagePlus: false, showAddressPlus: normalized > 0, addressPlusOpacity: normalized };
}

/**
 * The reserved-tab glyph and the native address placeholder occupy the same
 * capsule after a new tab is committed. Animate their handoff together so a
 * new StartPage never exposes a one-frame empty/white replacement.
 */
export function newTabHandoffVisual(progress: number): NewTabHandoffVisual {
  const normalized: number = Math.max(0, Math.min(1, finite(progress)));
  // BrowserShell owns the short plus-only lead-in. The progress supplied here
  // is therefore the dedicated crossfade timeline: every millisecond of its
  // extended duration is used by the two overlaid native layers.
  // There is no visible dot, scale-down, or second leftward slide in this
  // handoff.
  const placeholderProgress: number = smoothHandoffProgress(normalized, 0, 1);
  return {
    plusOpacity: 1 - placeholderProgress,
    placeholderOpacity: placeholderProgress,
    plusScale: 1,
    placeholderScale: 1,
    placeholderSlideProgress: 1
  };
}

function smoothHandoffProgress(progress: number, start: number, end: number): number {
  const span: number = Math.max(0.0001, end - start);
  const normalized: number = Math.max(0, Math.min(1, (progress - start) / span));
  return normalized * normalized * (3 - 2 * normalized);
}

/**
 * A reserved tab is a data-model placeholder, not a visible chrome item.
 * Keep it out of the address strip until the final-tab pull has produced a
 * positive visual progress value.
 */
export function shouldRenderPendingTabPreview(
  previewKind: TabPreviewKind,
  newTabProgress: number
): boolean {
  return previewKind === TabPreviewKind.NEW_TAB && finite(newTabProgress) > 0;
}

export function tabSceneKeys(tabIds: string[], pendingId: string = ''): string[] {
  const keys: string[] = tabIds.slice();
  if (pendingId.length > 0 && !keys.includes(pendingId)) keys.push(pendingId);
  return keys;
}

/** Native Tabs can select only a committed business tab, never a gesture draft. */
export function nativeTabIndexForId(tabIds: string[], tabId: string): number {
  if (tabId.length === 0) {
    return -1;
  }
  return tabIds.indexOf(tabId);
}
