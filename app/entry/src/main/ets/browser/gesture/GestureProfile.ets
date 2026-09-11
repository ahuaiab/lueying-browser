export interface GestureProfile {
  activationDistanceVp: number;
  directionLockRatio: number;
  overviewTravelRatio: number;
  overviewCommitProgress: number;
  overviewCommitVelocityVpS: number;
  tabSwitchTravelRatio: number;
  tabSwitchCommitProgress: number;
  tabSwitchCommitVelocityVpS: number;
  tabCloseTravelRatio: number;
  tabCloseCommitProgress: number;
  tabCloseCommitVelocityVpS: number;
  edgeRubberBandFactor: number;
  reorderLongPressMs: number;
  settleDurationMs: number;
}

export const DEFAULT_GESTURE_PROFILE: GestureProfile = {
  activationDistanceVp: 8,
  directionLockRatio: 1.25,
  overviewTravelRatio: 0.45,
  overviewCommitProgress: 0.32,
  overviewCommitVelocityVpS: 950,
  tabSwitchTravelRatio: 0.80,
  tabSwitchCommitProgress: 0.28,
  tabSwitchCommitVelocityVpS: 850,
  tabCloseTravelRatio: 0.42,
  tabCloseCommitProgress: 0.42,
  tabCloseCommitVelocityVpS: 1100,
  edgeRubberBandFactor: 0.32,
  // Safari-like tab actions should become available after a short, deliberate
  // hold while still allowing ordinary taps and swipes to win beforehand.
  reorderLongPressMs: 300,
  settleDurationMs: 280
};
