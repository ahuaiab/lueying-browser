import { describe, expect, it } from '@ohos/hypium';
import {
  availableContentHeight,
  avoidRectBottom,
  topContentInsetFromAvoidRects
} from '../../../main/ets/browser/model/WindowAvoidance';

export default function windowAvoidanceTest() {
  describe('WindowAvoidance', () => {
    it('uses the rectangle bottom edge instead of height alone', 0, () => {
      expect(avoidRectBottom(12, 36)).assertEqual(48);
    });

    it('uses the larger system or cutout bottom edge', 0, () => {
      expect(topContentInsetFromAvoidRects(8, 24, 0, 48)).assertEqual(48);
      expect(topContentInsetFromAvoidRects(12, 36, 0, 24)).assertEqual(48);
    });

    it('clamps invalid or negative rectangles to zero', 0, () => {
      expect(avoidRectBottom(-20, 4)).assertEqual(0);
      expect(avoidRectBottom(0, -4)).assertEqual(0);
      expect(avoidRectBottom(Number.NaN, 40)).assertEqual(0);
      expect(topContentInsetFromAvoidRects(-20, 4, Number.NaN, 40)).assertEqual(0);
    });

    it('keeps the web content height equal to the remaining viewport', 0, () => {
      expect(availableContentHeight(800, 64)).assertEqual(736);
      expect(availableContentHeight(800, 0)).assertEqual(800);
      expect(availableContentHeight(40, 64)).assertEqual(1);
    });
  });
}
