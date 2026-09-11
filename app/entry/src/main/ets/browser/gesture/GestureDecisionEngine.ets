import {
  GestureAxis,
  GestureDecision,
  GestureOutcome,
  GestureSample
} from '../model/BrowserTypes';
import { DEFAULT_GESTURE_PROFILE, GestureProfile } from './GestureProfile';
import {
  shouldCommitProjectedSwitch,
  shouldCommitNewTabPull,
  rubberBandDistance
} from '../model/TabGestureMotion';

export class GestureDecisionEngine {
  private axis: GestureAxis = GestureAxis.UNDECIDED;
  private committed: boolean = false;
  private readonly profile: GestureProfile;

  constructor(profile: GestureProfile = DEFAULT_GESTURE_PROFILE) {
    this.profile = profile;
  }

  begin(): void {
    this.axis = GestureAxis.UNDECIDED;
    this.committed = false;
  }

  cancel(): GestureDecision {
    this.committed = true;
    return this.decision(0, 0, GestureOutcome.CANCELLED);
  }

  updateBottomBar(sample: GestureSample, width: number, height: number,
    hasPrevious: boolean, hasNext: boolean): GestureDecision {
    this.lockAxis(sample);
    if (this.axis === GestureAxis.VERTICAL && sample.dy < 0) {
      const progress = this.clamp((-sample.dy) / (height * this.profile.overviewTravelRatio));
      return this.decision(progress, sample.dy, GestureOutcome.NONE);
    }
    if (this.axis === GestureAxis.HORIZONTAL) {
      const hasTarget = sample.dx > 0 ? hasPrevious : hasNext;
      const offset = hasTarget ? sample.dx : rubberBandDistance(sample.dx);
      const progress = this.clamp(Math.abs(sample.dx) / (width * this.profile.tabSwitchTravelRatio));
      return this.decision(progress, offset, GestureOutcome.NONE);
    }
    return this.decision(0, 0, GestureOutcome.NONE);
  }

  endBottomBar(sample: GestureSample, width: number, height: number,
    hasPrevious: boolean, hasNext: boolean): GestureDecision {
    if (this.committed) {
      return this.decision(0, 0, GestureOutcome.CANCELLED);
    }
    const update = this.updateBottomBar(sample, width, height, hasPrevious, hasNext);
    this.committed = true;
    if (update.axis === GestureAxis.VERTICAL && sample.dy < 0 &&
      (update.progress >= this.profile.overviewCommitProgress ||
       sample.velocityY <= -this.profile.overviewCommitVelocityVpS)) {
      return this.decision(1, sample.dy, GestureOutcome.SHOW_OVERVIEW);
    }
    if (update.axis === GestureAxis.HORIZONTAL) {
      const hasTarget = sample.dx > 0 ? hasPrevious : hasNext;
      const velocityCommitted = Math.abs(sample.velocityX) >= this.profile.tabSwitchCommitVelocityVpS;
      const projectedCommitted = shouldCommitProjectedSwitch(
        sample.dx,
        sample.velocityX,
        width,
        this.profile.tabSwitchCommitProgress
      );
      const committed = update.progress >= this.profile.tabSwitchCommitProgress ||
        velocityCommitted || projectedCommitted;
      // Safari creates a fresh start tab when the user keeps swiping left at
      // the end of the tab strip. Keep the right-edge rubber band for the
      // interactive phase, but commit the action once the normal threshold is
      // reached instead of silently cancelling it.
      if (sample.dx < 0 && !hasNext && (committed || shouldCommitNewTabPull(sample.dx, sample.velocityX))) {
        return this.decision(1, sample.dx, GestureOutcome.NEW_START_TAB);
      }
      if (hasTarget && committed) {
        return this.decision(1, sample.dx,
          sample.dx > 0 ? GestureOutcome.PREVIOUS_TAB : GestureOutcome.NEXT_TAB);
      }
    }
    return this.decision(0, 0, GestureOutcome.CANCELLED);
  }

  updateCardClose(sample: GestureSample, cardWidth: number): GestureDecision {
    this.lockAxis(sample);
    if (this.axis !== GestureAxis.HORIZONTAL || sample.dx >= 0) {
      return this.decision(0, 0, GestureOutcome.NONE);
    }
    const progress = this.clamp((-sample.dx) / (cardWidth * this.profile.tabCloseTravelRatio));
    return this.decision(progress, sample.dx, GestureOutcome.NONE);
  }

  endCardClose(sample: GestureSample, cardWidth: number): GestureDecision {
    if (this.committed) {
      return this.decision(0, 0, GestureOutcome.CANCELLED);
    }
    const update = this.updateCardClose(sample, cardWidth);
    this.committed = true;
    if (update.progress >= this.profile.tabCloseCommitProgress ||
      sample.velocityX <= -this.profile.tabCloseCommitVelocityVpS) {
      return this.decision(1, sample.dx, GestureOutcome.CLOSE_TAB);
    }
    return this.decision(0, 0, GestureOutcome.CANCELLED);
  }

  private lockAxis(sample: GestureSample): void {
    if (this.axis !== GestureAxis.UNDECIDED) {
      return;
    }
    const x = Math.abs(sample.dx);
    const y = Math.abs(sample.dy);
    if (Math.max(x, y) < this.profile.activationDistanceVp) {
      return;
    }
    if (y >= x * this.profile.directionLockRatio) {
      this.axis = GestureAxis.VERTICAL;
    } else if (x >= y * this.profile.directionLockRatio) {
      this.axis = GestureAxis.HORIZONTAL;
    }
  }

  private clamp(value: number): number {
    return Math.max(0, Math.min(1, value));
  }

  private decision(progress: number, visualOffset: number, outcome: GestureOutcome): GestureDecision {
    return { axis: this.axis, progress, visualOffset, outcome };
  }
}
