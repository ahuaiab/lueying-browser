import { describe, expect, it } from '@ohos/hypium';
import { TabPreviewKind } from '../../../main/ets/browser/model/TabGestureMotion';
import {
  shouldPrimeFinalTabPreview,
  shouldRenderAddressItem,
  shouldRenderPendingTabPreview,
  newTabHandoffVisual,
  addressPreviewOpacity
} from '../../../main/ets/browser/model/SafariTabTransition';
import {
  addressEditorText,
  syncAddressDraft,
  canStartAddressStripGesture,
  closedAddressEditorState
} from '../../../main/ets/browser/model/BrowserInteraction';

export default function safariTabTransitionFeedbackTest() {
  describe('SafariTabTransitionFeedback', () => {
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

    it('fades the target address capsule in on the same progress track', 0, () => {
      expect(addressPreviewOpacity(1, 1, -1, 1280)).assertEqual(1);
      expect(addressPreviewOpacity(2, 1, -64, 1280)).assertEqual(0);
      expect(addressPreviewOpacity(2, 1, -256, 1280)).assertEqual(1);
    });

    it('does not render a reserved tab before the new-tab pull is visible', 0, () => {
      expect(shouldRenderPendingTabPreview(TabPreviewKind.NONE, 0.4)).assertFalse();
      expect(shouldRenderPendingTabPreview(TabPreviewKind.EXISTING_TAB, 0.4)).assertFalse();
      expect(shouldRenderPendingTabPreview(TabPreviewKind.NEW_TAB, 0)).assertFalse();
      expect(shouldRenderPendingTabPreview(TabPreviewKind.NEW_TAB, 0.01)).assertTrue();
    });

    it('crossfades the new-tab plus into the full native placeholder', 0, () => {
      const start = newTabHandoffVisual(0);
      expect(start.plusOpacity).assertEqual(1);
      expect(start.placeholderOpacity).assertEqual(0);
      expect(start.plusScale).assertEqual(1);
      expect(start.placeholderScale).assertEqual(1);
      expect(start.placeholderSlideProgress).assertEqual(1);
      const crossfade = newTabHandoffVisual(0.5);
      expect(crossfade.plusOpacity > 0.25).assertTrue();
      expect(crossfade.placeholderOpacity > 0.25).assertTrue();
      expect(crossfade.plusOpacity < 0.75).assertTrue();
      expect(crossfade.placeholderOpacity < 0.75).assertTrue();
      expect(crossfade.plusScale).assertEqual(1);
      expect(crossfade.placeholderScale).assertEqual(1);
      expect(crossfade.placeholderSlideProgress).assertEqual(1);
      const earlyCrossfade = newTabHandoffVisual(0.15);
      expect(earlyCrossfade.plusOpacity < 1).assertTrue();
      expect(earlyCrossfade.placeholderOpacity > 0).assertTrue();
      const crossfadeEnd = newTabHandoffVisual(0.8);
      expect(crossfadeEnd.placeholderOpacity > 0.85).assertTrue();
      expect(crossfadeEnd.plusOpacity < 0.15).assertTrue();
      const finish = newTabHandoffVisual(1);
      expect(finish.plusOpacity).assertEqual(0);
      expect(finish.placeholderOpacity).assertEqual(1);
      expect(finish.plusScale).assertEqual(1);
      expect(finish.placeholderScale).assertEqual(1);
      expect(finish.placeholderSlideProgress).assertEqual(1);
    });

    it('keeps an intentionally empty editor draft empty', 0, () => {
      expect(addressEditorText('https://example.org/', '', true)).assertEqual('');
      expect(addressEditorText('https://example.org/', 'example.com', true))
        .assertEqual('example.com');
      expect(addressEditorText('https://example.org/', '', false))
        .assertEqual('https://example.org/');
    });

    it('synchronizes the native field when the parent closes the editor', 0, () => {
      expect(syncAddressDraft('https://example.org/', '', true)).assertEqual('');
      expect(syncAddressDraft('https://example.org/', '', false))
        .assertEqual('https://example.org/');
    });

    it('allows strip gestures after the editor has visually collapsed', 0, () => {
      expect(canStartAddressStripGesture(true, 'collapsed', 0, false)).assertTrue();
      expect(canStartAddressStripGesture(true, 'collapsing', 0, false)).assertTrue();
      expect(canStartAddressStripGesture(true, 'expanded', 1, true)).assertFalse();
      expect(canStartAddressStripGesture(false, 'collapsed', 0, false)).assertFalse();
    });

    it('returns one canonical interaction state after the address editor closes', 0, () => {
      const state = closedAddressEditorState();
      expect(state.addressDraft).assertEqual('');
      expect(state.addressInputFocused).assertFalse();
      expect(state.addressEditing).assertFalse();
      expect(state.barMode).assertEqual('collapsed');
      expect(state.inputExpandProgress).assertEqual(0);
      expect(state.addressInputFocusEnabled).assertTrue();
    });
  });
}
