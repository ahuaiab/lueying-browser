import { GestureSample } from '../model/BrowserTypes';

export const SLOW_OVERVIEW_COMMIT: GestureSample[] = [
  { dx: 0, dy: -10, velocityX: 0, velocityY: -80 },
  { dx: 1, dy: -120, velocityX: 5, velocityY: -420 }
];

export const OVERVIEW_CANCEL: GestureSample[] = [
  { dx: 1, dy: -9, velocityX: 0, velocityY: -40 },
  { dx: 2, dy: -45, velocityX: 0, velocityY: -120 }
];

export const NEXT_TAB_FAST: GestureSample[] = [
  { dx: -10, dy: 1, velocityX: -100, velocityY: 0 },
  { dx: -80, dy: 2, velocityX: -1000, velocityY: 10 }
];

export const CARD_CLOSE_FAST: GestureSample[] = [
  { dx: -12, dy: 0, velocityX: -100, velocityY: 0 },
  { dx: -90, dy: 2, velocityX: -1250, velocityY: 10 }
];
