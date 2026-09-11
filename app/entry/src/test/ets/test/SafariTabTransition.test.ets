import { describe, expect, it } from '@ohos/hypium';
import { newTabPullProgress, TabPreviewKind } from '../../../main/ets/browser/model/TabGestureMotion';
import {
  addressItemLeft,
  addressOffsetForIndex,
  newTabPreviewVisual,
  safariTransitionFrame,
  sceneOffsetForIndex,
  shouldPrimeFinalTabPreview,
  shouldRenderAddressItem,
  tabSceneKeys,
  nativeTabIndexForId,
  tabTransitionSceneVisualState
} from '../../../main/ets/browser/model/SafariTabTransition';

export default function safariTabTransitionTest() {
  describe('SafariTabTransition', () => {
    it('moves page and address tracks with one normalized progress', 0, () => {
      const frame = safariTransitionFrame(-100, 400, 338, 1, 3);
      expect(frame.progress).assertEqual(-0.25);
      expect(frame.currentPageX).assertEqual(-100);
      expect(frame.targetPageX).assertEqual(300);
      expect(frame.currentAddressX).assertEqual(-84.5);
      expect(frame.targetAddressX).assertEqual(253.5);
      expect(frame.targetIndex).assertEqual(2);
      expect(frame.previewKind).assertEqual(TabPreviewKind.EXISTING_TAB);
    });

    it('keeps both native page layers moving until the transition settles', 0, () => {
      const visual = tabTransitionSceneVisualState(
        -120,
        280,
        TabPreviewKind.EXISTING_TAB,
        true
      );
      expect(visual.currentX).assertEqual(-120);
      expect(visual.previewX).assertEqual(280);
      expect(visual.showPreview).assertTrue();

      const settled = tabTransitionSceneVisualState(
        0,
        0,
        TabPreviewKind.NONE,
        false
      );
      expect(settled.showPreview).assertFalse();
    });

    it('keeps the new-tab plus in address chrome, never on the page layer', 0, () => {
      const visual = tabTransitionSceneVisualState(
        -120,
        280,
        TabPreviewKind.NEW_TAB,
        true
      );
      expect(visual.showPagePlus).assertFalse();
    });

    it('rebases a committed target without changing its visible position', 0, () => {
      const before = sceneOffsetForIndex(2, 1, 400, -400);
      const after = sceneOffsetForIndex(2, 2, 400, 0);
      expect(before).assertEqual(0);
      expect(after).assertEqual(0);
    });

    it('uses a pending slot after the final tab', 0, () => {
      const frame = safariTransitionFrame(-80, 400, 338, 2, 3);
      expect(frame.targetIndex).assertEqual(3);
      expect(frame.previewKind).assertEqual(TabPreviewKind.NEW_TAB);
      expect(frame.targetPageX).assertEqual(320);
      expect(frame.targetAddressX).assertEqual(270.4);
    });

    it('keeps signed frame progress separate from positive new-tab visual progress', 0, () => {
      const frame = safariTransitionFrame(-80, 400, 338, 2, 3);
      const visual = newTabPreviewVisual(newTabPullProgress(-80));
      expect(frame.progress).assertEqual(-0.2);
      expect(visual.showAddressPlus).assertTrue();
      expect(visual.addressPlusOpacity > 0).assertTrue();
    });

    it('owns the new-tab plus only in the address strip', 0, () => {
      const visual = newTabPreviewVisual(0.75);
      expect(visual.showPagePlus).assertFalse();
      expect(visual.showAddressPlus).assertTrue();
      expect(visual.addressPlusOpacity).assertEqual(0.75);
      for (const progress of [0, 0.25, 0.5, 0.75, 1]) {
        expect(newTabPreviewVisual(progress).showPagePlus).assertFalse();
      }
    });

    it('keeps stable and pending scene keys unique', 0, () => {
      const keys = tabSceneKeys(['a', 'b'], 'pending-c');
      expect(keys.join(',')).assertEqual('a,b,pending-c');
      expect(new Set(keys).size).assertEqual(3);
    });

    it('maps only committed tab ids to native page indexes', 0, () => {
      const committedIds: string[] = ['tab-a', 'tab-b'];
      expect(nativeTabIndexForId(committedIds, 'tab-b')).assertEqual(1);
      expect(nativeTabIndexForId(committedIds, 'pending-c')).assertEqual(-1);
    });

    it('maps the address stride independently from page width', 0, () => {
      expect(addressOffsetForIndex(2, 1, 338, -100, 400)).assertEqual(253.5);
    });

    it('centers address capsules before applying page-linked motion', 0, () => {
      expect(addressItemLeft(1, 1, 328, 10, 0, 400)).assertEqual(36);
      expect(addressItemLeft(1, 1, 328, 10, -200, 400)).assertEqual(-133);
      expect(addressItemLeft(2, 1, 328, 10, -200, 400)).assertEqual(205);
      expect(addressItemLeft(2, 1, 328, 10, -400, 400)).assertEqual(36);
      expect(addressItemLeft(2, 2, 328, 10, 0, 400)).assertEqual(36);
    });

    it('primes a render-only pending tab before a final-tab gesture moves', 0, () => {
      expect(shouldPrimeFinalTabPreview(2, 3)).assertTrue();
      expect(shouldPrimeFinalTabPreview(1, 3)).assertFalse();
      expect(shouldPrimeFinalTabPreview(0, 0)).assertFalse();
    });

    it('renders only the active capsule at rest and the intended target while dragging', 0, () => {
      expect(shouldRenderAddressItem(1, 1, 0, 3)).assertTrue();
      expect(shouldRenderAddressItem(0, 1, 0, 3)).assertFalse();
      expect(shouldRenderAddressItem(2, 1, 0, 3)).assertFalse();
      expect(shouldRenderAddressItem(2, 1, -80, 3)).assertTrue();
      expect(shouldRenderAddressItem(0, 1, 80, 3)).assertTrue();
      expect(shouldRenderAddressItem(2, 1, -80, 2)).assertFalse();
    });

  });
}
