import { describe, expect, it } from '@ohos/hypium';
import {
  TAB_BAR_TOUCH_TOLERANCE_VP,
  TabBarRect,
  isPointInTabBar
} from '../../../main/ets/browser/gesture/TabBarGestureGate';

export default function tabBarGestureGateTest() {
  describe('TabBarGestureGate', () => {
    const rect: TabBarRect = { x: 100, y: 700, width: 240, height: 48 };

    it('accepts a point inside the measured TabBar capsule', 0, () => {
      expect(isPointInTabBar(220, 724, rect)).assertTrue();
    });

    it('rejects page and edge points outside the TabBar capsule', 0, () => {
      const outsidePoints: Array<[number, number]> = [
        [220, 100],  // page top
        [220, 400],  // page middle
        [220, 680],  // page bottom above the TabBar
        [220, rect.y - TAB_BAR_TOUCH_TOLERANCE_VP - 1],
        [220, rect.y + rect.height + TAB_BAR_TOUCH_TOLERANCE_VP + 1]
      ];
      outsidePoints.forEach((point: [number, number]) => {
        expect(isPointInTabBar(point[0], point[1], rect)).assertFalse();
      });
    });

    it('keeps the optional tolerance smaller than page content', 0, () => {
      expect(isPointInTabBar(220, rect.y - TAB_BAR_TOUCH_TOLERANCE_VP, rect)).assertTrue();
      expect(isPointInTabBar(220, rect.y - TAB_BAR_TOUCH_TOLERANCE_VP - 0.1, rect)).assertFalse();
    });

    it('rejects an unmeasured rectangle instead of opening a full-screen gate', 0, () => {
      expect(isPointInTabBar(220, 724, { x: 0, y: 0, width: 0, height: 0 })).assertFalse();
    });
  });
}
