import { describe, expect, it } from '@ohos/hypium';
import {
  TouchOwner,
  beginTouchOwnership,
  cancelButtonClickForPan,
  shouldDispatchButtonClick
} from '../../../main/ets/browser/gesture/TouchOwnership';
import { TabBarRect, isPointInTabBar } from '../../../main/ets/browser/gesture/TabBarGestureGate';

export default function touchOwnershipTest() {
  describe('TouchOwnership', () => {
    it('assigns TabBar button ownership before the page can participate', 0, () => {
      const state = beginTouchOwnership(true, 'tab-count-button');
      expect(state.owner).assertEqual(TouchOwner.TAB_BAR_BUTTON);
      expect(state.buttonId).assertEqual('tab-count-button');
      expect(state.startInTabBar).assertTrue();
    });

    it('assigns page ownership outside the measured TabBar', 0, () => {
      const state = beginTouchOwnership(false, '');
      expect(state.owner).assertEqual(TouchOwner.PAGE);
      expect(state.startInTabBar).assertFalse();
    });

    it('promotes a button stream to TabBar pan and suppresses its click', 0, () => {
      const state = beginTouchOwnership(true, 'browser-share-button');
      const panState = cancelButtonClickForPan(state);
      expect(panState.owner).assertEqual(TouchOwner.TAB_BAR_PAN);
      expect(panState.buttonClickCancelled).assertTrue();
      expect(shouldDispatchButtonClick(panState)).assertFalse();
    });

    it('does not dispatch a button click after a cancelled sequence', 0, () => {
      const state = beginTouchOwnership(true, 'browser-library-button');
      const panState = cancelButtonClickForPan(state);
      expect(shouldDispatchButtonClick(panState)).assertFalse();
    });

    it('accepts an address-strip point but rejects a lower-toolbar point', 0, () => {
      const addressStripRect: TabBarRect = { x: 0, y: 100, width: 400, height: 56 };
      expect(isPointInTabBar(200, 128, addressStripRect)).assertTrue();
      expect(isPointInTabBar(200, 180, addressStripRect)).assertFalse();
    });

    it('keeps a passing address-strip touch owned by the tab-bar pan', 0, () => {
      const addressStripRect: TabBarRect = { x: 0, y: 100, width: 400, height: 56 };
      const startsInAddressStrip: boolean = isPointInTabBar(200, 128, addressStripRect);
      const state = beginTouchOwnership(startsInAddressStrip, '');
      expect(state.owner).assertEqual(TouchOwner.TAB_BAR_PAN);
      expect(state.startInTabBar).assertTrue();
    });
  });
}
