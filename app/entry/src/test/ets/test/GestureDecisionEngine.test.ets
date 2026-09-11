import { describe, expect, it } from '@ohos/hypium';
import { GestureAxis, GestureOutcome } from '../../../main/ets/browser/model/BrowserTypes';
import { GestureDecisionEngine } from '../../../main/ets/browser/gesture/GestureDecisionEngine';
import { tabGestureMotion } from '../../../main/ets/browser/model/TabGestureMotion';
import {
  CARD_CLOSE_FAST,
  NEXT_TAB_FAST,
  OVERVIEW_CANCEL,
  SLOW_OVERVIEW_COMMIT
} from '../../../main/ets/browser/gesture/GestureTraceFixtures';

export default function gestureDecisionEngineTest() {
  describe('GestureDecisionEngine', () => {
    it('commits overview with a fast upward bottom-bar swipe', 0, () => {
      const engine = new GestureDecisionEngine();
      engine.begin();
      engine.updateBottomBar({ dx: 2, dy: -40, velocityX: 0, velocityY: -100 }, 400, 800, true, true);
      const decision = engine.endBottomBar(
        { dx: 3, dy: -70, velocityX: 20, velocityY: -1200 },
        400,
        800,
        true,
        true
      );
      expect(decision.outcome).assertEqual(GestureOutcome.SHOW_OVERVIEW);
    });

    it('opens a new start tab when swiping beyond the final tab', 0, () => {
      const engine = new GestureDecisionEngine();
      engine.begin();
      const update = engine.updateBottomBar(
        { dx: -100, dy: 2, velocityX: -500, velocityY: 0 },
        400,
        800,
        true,
        false
      );
      expect(update.visualOffset < -34 && update.visualOffset > -36).assertTrue();
      const end = engine.endBottomBar(
        { dx: -120, dy: 2, velocityX: -1200, velocityY: 0 },
        400,
        800,
        true,
        false
      );
      expect(end.outcome).assertEqual(GestureOutcome.NEW_START_TAB);
    });

    it('opens a new start tab when left-swiping beyond the final tab', 0, () => {
      const engine = new GestureDecisionEngine();
      engine.begin();
      const decision = engine.endBottomBar(
        { dx: -160, dy: 0, velocityX: -1200, velocityY: 0 },
        400,
        800,
        true,
        false
      );
      expect(decision.outcome).assertEqual(GestureOutcome.NEW_START_TAB);
    });

    it('commits a slow overview swipe by distance', 0, () => {
      const engine = new GestureDecisionEngine();
      engine.begin();
      engine.updateBottomBar(SLOW_OVERVIEW_COMMIT[0], 400, 800, true, true);
      const decision = engine.endBottomBar(SLOW_OVERVIEW_COMMIT[1], 400, 800, true, true);
      expect(decision.outcome).assertEqual(GestureOutcome.SHOW_OVERVIEW);
    });

    it('cancels an overview swipe below the distance threshold', 0, () => {
      const engine = new GestureDecisionEngine();
      engine.begin();
      engine.updateBottomBar(OVERVIEW_CANCEL[0], 400, 800, true, true);
      const decision = engine.endBottomBar(OVERVIEW_CANCEL[1], 400, 800, true, true);
      expect(decision.outcome).assertEqual(GestureOutcome.CANCELLED);
    });

    it('commits a next-tab swipe by velocity', 0, () => {
      const engine = new GestureDecisionEngine();
      engine.begin();
      engine.updateBottomBar(NEXT_TAB_FAST[0], 400, 800, true, true);
      const decision = engine.endBottomBar(NEXT_TAB_FAST[1], 400, 800, true, true);
      expect(decision.outcome).assertEqual(GestureOutcome.NEXT_TAB);
    });

    it('commits card close by distance', 0, () => {
      const engine = new GestureDecisionEngine();
      engine.begin();
      const update = engine.updateCardClose(CARD_CLOSE_FAST[0], 100);
      expect(update.axis).assertEqual(GestureAxis.HORIZONTAL);
      expect(update.visualOffset).assertEqual(-12);
      expect(update.progress).assertEqual(12 / (100 * 0.42));
      const decision = engine.endCardClose(CARD_CLOSE_FAST[1], 100);
      expect(decision.outcome).assertEqual(GestureOutcome.CLOSE_TAB);
    });

    it('cancels a reversed rightward card swipe', 0, () => {
      const engine = new GestureDecisionEngine();
      engine.begin();
      engine.updateCardClose({ dx: -55, dy: 0, velocityX: -300, velocityY: 0 }, 100);
      const decision = engine.endCardClose(
        { dx: 18, dy: 0, velocityX: 140, velocityY: 0 },
        100
      );
      expect(decision.outcome).assertEqual(GestureOutcome.CANCELLED);
    });

    it('cancels a short undecided gesture', 0, () => {
      const engine = new GestureDecisionEngine();
      engine.begin();
      const decision = engine.endBottomBar(
        { dx: 5, dy: 2, velocityX: 0, velocityY: 0 },
        400,
        800,
        true,
        true
      );
      expect(decision.outcome).assertEqual(GestureOutcome.CANCELLED);
    });

    it('cancels when a committed vertical gesture reverses direction', 0, () => {
      const engine = new GestureDecisionEngine();
      engine.begin();
      engine.updateBottomBar(
        { dx: 0, dy: -20, velocityX: 0, velocityY: -120 },
        400,
        800,
        true,
        true
      );
      const decision = engine.endBottomBar(
        { dx: 0, dy: 18, velocityX: 0, velocityY: 120 },
        400,
        800,
        true,
        true
      );
      expect(decision.outcome).assertEqual(GestureOutcome.CANCELLED);
    });

    it('does not commit twice after an explicit cancel', 0, () => {
      const engine = new GestureDecisionEngine();
      engine.begin();
      expect(engine.cancel().outcome).assertEqual(GestureOutcome.CANCELLED);
      const duplicate = engine.endBottomBar(
        { dx: -160, dy: 0, velocityX: -1200, velocityY: 0 },
        400,
        800,
        true,
        true
      );
      expect(duplicate.outcome).assertEqual(GestureOutcome.CANCELLED);
    });

    it('returns cancelled for duplicate end events', 0, () => {
      const engine = new GestureDecisionEngine();
      engine.begin();
      const first = engine.endBottomBar(
        { dx: -160, dy: 0, velocityX: -1200, velocityY: 0 },
        400,
        800,
        true,
        true
      );
      const duplicate = engine.endBottomBar(
        { dx: -160, dy: 0, velocityX: -1200, velocityY: 0 },
        400,
        800,
        true,
        true
      );
      expect(first.outcome).assertEqual(GestureOutcome.NEXT_TAB);
      expect(duplicate.outcome).assertEqual(GestureOutcome.CANCELLED);
    });

    it('ignores one hundred duplicate end events after a commit', 0, () => {
      const engine: GestureDecisionEngine = new GestureDecisionEngine();
      engine.begin();
      const first = engine.endBottomBar(
        { dx: -160, dy: 0, velocityX: -1200, velocityY: 0 },
        400,
        800,
        true,
        true
      );
      expect(first.outcome).assertEqual(GestureOutcome.NEXT_TAB);
      for (let index: number = 0; index < 100; index += 1) {
        expect(engine.endBottomBar(
          { dx: -160, dy: 0, velocityX: -1200, velocityY: 0 },
          400,
          800,
          true,
          true
        ).outcome).assertEqual(GestureOutcome.CANCELLED);
      }
    });

    it('returns new start only once for repeated final-edge end events', 0, () => {
      const engine: GestureDecisionEngine = new GestureDecisionEngine();
      engine.begin();
      const first = engine.endBottomBar(
        { dx: -160, dy: 0, velocityX: -1200, velocityY: 0 },
        400,
        800,
        true,
        false
      );
      const duplicate = engine.endBottomBar(
        { dx: -160, dy: 0, velocityX: -1200, velocityY: 0 },
        400,
        800,
        true,
        false
      );
      expect(first.outcome).assertEqual(GestureOutcome.NEW_START_TAB);
      expect(duplicate.outcome).assertEqual(GestureOutcome.CANCELLED);
    });

    it('keeps normalized progress signed to match the raw horizontal drag', 0, () => {
      const motion = tabGestureMotion(-100, 400, 0, 2);
      expect(motion.rawDragX).assertEqual(-100);
      expect(motion.normalizedProgress).assertEqual(-0.25);
    });
  });
}
