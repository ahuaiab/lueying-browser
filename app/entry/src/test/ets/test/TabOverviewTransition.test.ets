import { describe, expect, it } from '@ohos/hypium';
import {
  TabOverviewPageFrame,
  tabOverviewPageFrame,
  tabOverviewGridOpacityAtProgress,
  tabOverviewSpringVelocity,
  tabOverviewSpringEasing,
  tabOverviewBorderOwner,
  tabOverviewLiveCaptionOpacity,
  tabOverviewCardCaptionVisualOpacity,
  tabOverviewCaptionLocalRadius,
  tabOverviewChromeFrame,
  TabOverviewChromeFrame,
  tabOverviewCaptionHandoffOpacity,
  tabOverviewChromeOpacity,
  tabOverviewChromeTranslateY,
  shouldMountBottomBrowserBar,
  shouldMountAddressTransitionLayer,
  tabOverviewAddressLayerZIndex,
  tabOverviewBottomChromeZIndex,
  TAB_OVERVIEW_CAPTION_FONT_SIZE
} from '../../../main/ets/browser/model/TabOverviewActions';
import { verticalOverviewGestureMotion } from '../../../main/ets/browser/model/TabGestureMotion';

export default function tabOverviewTransitionTest() {
  describe('TabOverviewTransition', () => {
    it('starts the overview page transform as the full page', 0, () => {
      const frame: TabOverviewPageFrame = tabOverviewPageFrame(0, 400, 800, 0, 0);
      expect(frame.scaleX).assertEqual(1);
      expect(frame.scaleY).assertEqual(1);
      expect(frame.translateX).assertEqual(0);
      expect(frame.translateY).assertEqual(0);
      expect(frame.clipLeft).assertEqual(0);
      expect(frame.clipTop).assertEqual(0);
      expect(frame.clipWidth).assertEqual(400);
      expect(frame.clipHeight).assertEqual(800);
      expect(frame.cornerRadius).assertEqual(0);
      expect(frame.borderWidth).assertEqual(0);
    });

    it('lands the live page on the active two-column card slot', 0, () => {
      const frame: TabOverviewPageFrame = tabOverviewPageFrame(1, 400, 800, 0, 0);
      expect(frame.scaleX.toFixed(6)).assertEqual('0.445000');
      expect(frame.scaleY.toFixed(6)).assertEqual('0.445000');
      expect(frame.translateX.toFixed(6)).assertEqual('-95.000000');
      expect(frame.translateY.toFixed(6)).assertEqual('-198.000000');
      expect(frame.clipLeft.toFixed(6)).assertEqual('16.000000');
      expect(frame.clipTop.toFixed(6)).assertEqual('24.000000');
      expect(frame.clipWidth.toFixed(6)).assertEqual('178.000000');
      expect(frame.clipHeight.toFixed(6)).assertEqual('242.000000');
      expect(frame.cornerRadius).assertEqual(16);
      expect(frame.borderWidth).assertEqual(2);
    });

    it('keeps the card grid hidden until the hero reaches handoff', 0, () => {
      expect(tabOverviewGridOpacityAtProgress(0.5, true)).assertEqual(0);
      expect(tabOverviewGridOpacityAtProgress(0.92, true)).assertEqual(0);
      expect(tabOverviewGridOpacityAtProgress(0.96, true).toFixed(6)).assertEqual('0.500000');
      expect(tabOverviewGridOpacityAtProgress(1, true)).assertEqual(1);
    });

    it('reveals the live page label before it shrinks into the card', 0, () => {
      expect(tabOverviewLiveCaptionOpacity(0)).assertEqual(0);
      expect(tabOverviewLiveCaptionOpacity(0.05) > 0).assertTrue();
      expect(tabOverviewLiveCaptionOpacity(0.22)).assertEqual(1);
      expect(tabOverviewLiveCaptionOpacity(0.7)).assertEqual(1);
      expect(tabOverviewLiveCaptionOpacity(0.92)).assertEqual(1);
      expect(tabOverviewLiveCaptionOpacity(0.98)).assertEqual(1);
      expect(tabOverviewLiveCaptionOpacity(1)).assertEqual(1);
    });

    it('keeps a single visual caption owner while the live page is the card', 0, () => {
      expect(tabOverviewCardCaptionVisualOpacity(true)).assertEqual(0);
      expect(tabOverviewCardCaptionVisualOpacity(false)).assertEqual(1);
    });

    it('uses a compact title size for both overview caption owners', 0, () => {
      expect(TAB_OVERVIEW_CAPTION_FONT_SIZE).assertEqual(10);
    });

    it('keeps the live caption radius equal to the visible page border radius', 0, () => {
      const frame: TabOverviewPageFrame = tabOverviewPageFrame(0.5, 400, 800, 0, 0);
      const localRadius: number = tabOverviewCaptionLocalRadius(frame);
      expect((localRadius * frame.scaleX).toFixed(6)).assertEqual(frame.cornerRadius.toFixed(6));
    });

    it('moves the browser bar down on entry and back up on dismissal', 0, () => {
      expect(tabOverviewChromeOpacity(0)).assertEqual(1);
      expect(tabOverviewChromeOpacity(0.18)).assertEqual(1);
      expect(tabOverviewChromeOpacity(0.37)).assertEqual(0.5);
      expect(tabOverviewChromeOpacity(0.56)).assertEqual(0);
      expect(tabOverviewChromeOpacity(1)).assertEqual(0);
      expect(tabOverviewChromeTranslateY(0, 104)).assertEqual(0);
      expect(tabOverviewChromeTranslateY(0.18, 104)).assertEqual(0);
      expect(tabOverviewChromeTranslateY(0.37, 104).toFixed(6)).assertEqual('52.000000');
      expect(tabOverviewChromeTranslateY(0.56, 104).toFixed(6)).assertEqual('104.000000');
      expect(tabOverviewChromeTranslateY(1, 104).toFixed(6)).assertEqual('104.000000');
    });

    it('keeps the address capsule width on the same track as the live page', 0, () => {
      const page: TabOverviewPageFrame = tabOverviewPageFrame(1, 400, 800, 0, 0);
      const frame: TabOverviewChromeFrame = tabOverviewChromeFrame(
        1, false, 400, 800, 104, page
      );
      expect(frame.addressVisualLeft.toFixed(6)).assertEqual(page.clipLeft.toFixed(6));
      expect(frame.addressVisualWidth.toFixed(6)).assertEqual(page.clipWidth.toFixed(6));
      expect(frame.addressScaleX.toFixed(6)).assertEqual(page.scaleX.toFixed(6));
      expect(frame.toolbarOpacity).assertEqual(0);
      expect(frame.toolbarTranslateY).assertEqual(104);
    });

    it('keeps the fixed bottom chrome mounted through the overview endpoint', 0, () => {
      expect(shouldMountBottomBrowserBar(false)).assertTrue();
      expect(shouldMountBottomBrowserBar(true)).assertFalse();
    });

    it('keeps the address transition node mounted for reverse drag recovery', 0, () => {
      expect(shouldMountAddressTransitionLayer(false)).assertTrue();
      expect(shouldMountAddressTransitionLayer(true)).assertFalse();
    });

    it('keeps the returning bottom chrome above the live page', 0, () => {
      expect(tabOverviewBottomChromeZIndex(false)).assertEqual(10);
      expect(tabOverviewBottomChromeZIndex(true) > 20).assertTrue();
    });

    it('keeps the address capsule above the returning bottom chrome', 0, () => {
      expect(tabOverviewAddressLayerZIndex() > tabOverviewBottomChromeZIndex(true)).assertTrue();
    });

    it('keeps the address capsule on one track during the live shrink', 0, () => {
      const middlePage: TabOverviewPageFrame = tabOverviewPageFrame(0.5, 400, 800, 0, 0);
      const endPage: TabOverviewPageFrame = tabOverviewPageFrame(1, 400, 800, 0, 0);
      const frame: TabOverviewChromeFrame = tabOverviewChromeFrame(
        0.5, false, 400, 800, 104, middlePage
      );
      const expectedTop: number = 704 +
        ((endPage.clipTop + endPage.clipHeight - 44 * endPage.scaleY) - 704) * 0.5;
      const expectedWidth: number = 384 + (endPage.clipWidth - 384) * 0.5;
      expect(frame.addressScaleX.toFixed(6)).assertEqual(middlePage.scaleX.toFixed(6));
      expect(frame.addressVisualTop.toFixed(6)).assertEqual(expectedTop.toFixed(6));
      expect(frame.addressVisualWidth.toFixed(6)).assertEqual(expectedWidth.toFixed(6));
    });

    it('crossfades the address capsule into the settled card caption', 0, () => {
      expect(tabOverviewCaptionHandoffOpacity(0.9, false)).assertEqual(0);
      expect(tabOverviewCaptionHandoffOpacity(0.94, false).toFixed(6)).assertEqual('0.500000');
      expect(tabOverviewCaptionHandoffOpacity(0.98, false)).assertEqual(1);
      expect(tabOverviewCaptionHandoffOpacity(0.94, true).toFixed(6)).assertEqual('0.500000');
      expect(tabOverviewCaptionHandoffOpacity(0.9, true)).assertEqual(0);
    });

    it('hands the address capsule off before the card label appears', 0, () => {
      const early: TabOverviewPageFrame = tabOverviewPageFrame(0.82, 400, 800, 0, 0);
      const middle: TabOverviewPageFrame = tabOverviewPageFrame(0.86, 400, 800, 0, 0);
      const late: TabOverviewPageFrame = tabOverviewPageFrame(0.94, 400, 800, 0, 0);
      const earlyChrome: TabOverviewChromeFrame = tabOverviewChromeFrame(
        0.82, false, 400, 800, 104, early
      );
      const middleChrome: TabOverviewChromeFrame = tabOverviewChromeFrame(
        0.86, false, 400, 800, 104, middle
      );
      const lateChrome: TabOverviewChromeFrame = tabOverviewChromeFrame(
        0.94, false, 400, 800, 104, late
      );
      expect(earlyChrome.addressOpacity).assertEqual(1);
      expect(middleChrome.addressOpacity > 0).assertTrue();
      expect(middleChrome.addressOpacity < 1).assertTrue();
      expect(lateChrome.addressOpacity).assertEqual(0);
    });

    it('gives the chrome a visible jelly response on entry', 0, () => {
      const page: TabOverviewPageFrame = tabOverviewPageFrame(0.33, 400, 800, 0, 0);
      const frame: TabOverviewChromeFrame = tabOverviewChromeFrame(
        0.33, false, 400, 800, 104, page
      );
      expect(frame.addressJellyScaleX > 1).assertTrue();
      expect(frame.addressJellyScaleY < 1).assertTrue();
      expect(frame.addressJellyTranslateY < 0).assertTrue();
      expect(frame.toolbarScaleX > 1).assertTrue();
      expect(frame.toolbarScaleY > 1).assertTrue();
    });

    it('keeps the address track fixed during an upward overview drag', 0, () => {
      const motion = verticalOverviewGestureMotion();
      expect(motion.rawDragX).assertEqual(0);
      expect(motion.normalizedProgress).assertEqual(0);
      expect(motion.pageTranslateX).assertEqual(0);
      expect(motion.adjacentTranslateX).assertEqual(0);
      expect(motion.isDragging).assertTrue();
    });

    it('returns the address capsule and toolbar through one reversible frame', 0, () => {
      const page: TabOverviewPageFrame = tabOverviewPageFrame(0, 400, 800, 0, 0);
      const frame: TabOverviewChromeFrame = tabOverviewChromeFrame(
        0, true, 400, 800, 104, page
      );
      expect(frame.addressVisualLeft).assertEqual(8);
      expect(frame.addressVisualWidth).assertEqual(384);
      expect(frame.addressVisualTop).assertEqual(704);
      expect(frame.toolbarOpacity).assertEqual(1);
      expect(frame.toolbarTranslateY).assertEqual(0);
    });

    it('adds a bounded jelly response while the address capsule merges back', 0, () => {
      const page: TabOverviewPageFrame = tabOverviewPageFrame(0.09, 400, 800, 0, 0);
      const frame: TabOverviewChromeFrame = tabOverviewChromeFrame(
        0.09, true, 400, 800, 104, page
      );
      expect(frame.addressJellyScaleX > 1).assertTrue();
      expect(frame.addressJellyScaleY < 1).assertTrue();
      expect(frame.toolbarOpacity > 0).assertTrue();
      expect(frame.toolbarOpacity < 1).assertTrue();
    });

    it('keeps the live label attached to the shrinking page bottom', 0, () => {
      const early: TabOverviewPageFrame = tabOverviewPageFrame(0.05, 400, 800, 0, 0);
      const middle: TabOverviewPageFrame = tabOverviewPageFrame(0.7, 400, 800, 0, 0);
      const end: TabOverviewPageFrame = tabOverviewPageFrame(1, 400, 800, 0, 0);
      const earlyBottom: number = (early.captionLocalTop + early.captionLocalHeight) * early.scaleY;
      const middleBottom: number = (middle.captionLocalTop + middle.captionLocalHeight) * middle.scaleY;
      expect(earlyBottom.toFixed(6)).assertEqual(early.clipHeight.toFixed(6));
      expect(middleBottom.toFixed(6)).assertEqual(middle.clipHeight.toFixed(6));
      expect(middle.captionLocalHeight * middle.scaleY < early.captionLocalHeight * early.scaleY).assertTrue();
      expect(early.captionContentScale * early.scaleY > middle.captionContentScale * middle.scaleY).assertTrue();
      expect((end.captionContentScale * end.scaleY).toFixed(6)).assertEqual('1.000000');
    });

    it('normalizes release velocity for a native interpolating spring', 0, () => {
      expect(tabOverviewSpringVelocity(0.4, 1, -240, 800).toFixed(3)).assertEqual('0.500');
      expect(tabOverviewSpringVelocity(0.6, 0, 240, 800).toFixed(3)).assertEqual('0.500');
      expect(tabOverviewSpringVelocity(0.4, 1, 240, 800).toFixed(3)).assertEqual('-0.500');
      expect(tabOverviewSpringVelocity(0.4, 1, -10000, 800)).assertEqual(3);
      expect(tabOverviewSpringVelocity(0.4, 1, Number.NaN, 800)).assertEqual(0);
      expect(tabOverviewSpringEasing(0.4, 1, -240, 800))
        .assertEqual('interpolating-spring(0.500, 1, 228, 30)');
    });

    it('keeps exactly one blue border owner through the overview handoff', 0, () => {
      expect(tabOverviewBorderOwner(0, false)).assertEqual('none');
      expect(tabOverviewBorderOwner(0.97, false)).assertEqual('live-page');
      // The grid is already visible in the final handoff segment. Its fixed
      // card bounds must own the ring before the live clip reaches 1.0, or the
      // live frame remains taller than the card for a visible final frame.
      expect(tabOverviewBorderOwner(0.98, false)).assertEqual('card');
      expect(tabOverviewBorderOwner(1, false)).assertEqual('card');
      expect(tabOverviewBorderOwner(1, true)).assertEqual('live-page');
      expect(tabOverviewBorderOwner(0.4, true)).assertEqual('live-page');
    });

    it('shrinks the live page monotonically toward the card slot', 0, () => {
      const start: TabOverviewPageFrame = tabOverviewPageFrame(0, 400, 800, 0, 0);
      const middle: TabOverviewPageFrame = tabOverviewPageFrame(0.5, 400, 800, 0, 0);
      const end: TabOverviewPageFrame = tabOverviewPageFrame(1, 400, 800, 0, 0);
      expect(middle.scaleX < start.scaleX).assertTrue();
      expect(middle.scaleY < start.scaleY).assertTrue();
      expect(end.scaleX < middle.scaleX).assertTrue();
      expect(end.scaleY < middle.scaleY).assertTrue();
      expect(end.scaleX).assertEqual(end.scaleY);
    });

    it('moves the live page with the grid when the tab search field is revealed', 0, () => {
      const hiddenSearch: TabOverviewPageFrame = tabOverviewPageFrame(1, 400, 800, 0, 137, 0);
      const revealedSearch: TabOverviewPageFrame = tabOverviewPageFrame(1, 400, 800, 0, 137, 1);
      expect(hiddenSearch.clipTop).assertEqual(145);
      expect(revealedSearch.clipTop).assertEqual(199);
      expect(revealedSearch.clipTop > hiddenSearch.clipTop).assertTrue();
      expect(revealedSearch.translateY > hiddenSearch.translateY).assertTrue();
    });
  });
}
