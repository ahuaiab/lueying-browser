import { describe, expect, it } from '@ohos/hypium';
import {
  BrowserSessionSnapshot,
  TabDirection,
  TabResidency
} from '../../../main/ets/browser/model/BrowserTypes';
import { TabStore } from '../../../main/ets/browser/store/TabStore';

export default function tabStoreTest() {
  describe('TabStore', () => {
    it('activates adjacent tabs without wrapping', 0, () => {
      const store = new TabStore(() => 1000, ['a', 'b', 'c']);
      store.createTab('https://a.example', false);
      store.createTab('https://b.example', false);
      store.createTab('https://c.example', false);
      store.activateTab('b');
      expect(store.adjacentTabId(TabDirection.PREVIOUS)).assertEqual('a');
      expect(store.adjacentTabId(TabDirection.NEXT)).assertEqual('c');
      store.activateTab('c');
      expect(store.adjacentTabId(TabDirection.NEXT)).assertUndefined();
    });

    it('creates a start tab after closing the final normal tab', 0, () => {
      const store = new TabStore(() => 1000, ['only', 'replacement']);
      store.createTab('https://a.example', false);
      const result = store.closeTab('only');
      expect(result.closed).assertTrue();
      expect(result.createdReplacement).assertTrue();
      expect(store.tabs.length).assertEqual(1);
      expect(store.activeTabId).assertEqual('replacement');
    });

    it('reorders tabs without changing the active tab', 0, () => {
      const store = new TabStore(() => 1000, ['a', 'b', 'c']);
      store.createTab('https://a.example', false);
      store.createTab('https://b.example', false);
      store.createTab('https://c.example', false);
      store.activateTab('b');
      expect(store.reorder(0, 2)).assertTrue();
      expect(store.tabs[0].id).assertEqual('b');
      expect(store.tabs[2].id).assertEqual('a');
      expect(store.activeTabId).assertEqual('b');
      expect(store.reorder(-1, 0)).assertFalse();
    });

    it('restores a valid active tab and cold residency', 0, () => {
      const store = new TabStore(() => 1000, ['replacement']);
      const snapshot: BrowserSessionSnapshot = {
        version: 1,
        activeTabId: 'b',
        tabs: [
          {
            id: 'a',
            url: 'https://a.example',
            lastValidUrl: 'https://a.example',
            displayUrl: 'a.example',
            pageSnapshot: 'a',
            title: 'A',
            isPrivate: false,
            createdAt: 1,
            lastAccessedAt: 2,
            thumbnailKey: 'a',
            residency: TabResidency.HOT
          },
          {
            id: 'b',
            url: 'https://b.example',
            lastValidUrl: 'https://b.example',
            displayUrl: 'b.example',
            pageSnapshot: 'b',
            title: 'B',
            isPrivate: false,
            createdAt: 3,
            lastAccessedAt: 4,
            thumbnailKey: 'b',
            residency: TabResidency.WARM
          }
        ]
      };
      store.restore(snapshot);
      expect(store.activeTabId).assertEqual('b');
      expect(store.tabs[0].residency).assertEqual(TabResidency.COLD);
      expect(store.tabs[1].residency).assertEqual(TabResidency.COLD);
    });

    it('excludes private tabs from persisted snapshots', 0, () => {
      const store = new TabStore(() => 1000, ['normal', 'private']);
      store.createTab('https://normal.example', false);
      store.createTab('https://private.example', true);
      const snapshot = store.snapshot();
      expect(snapshot.tabs.length).assertEqual(1);
      expect(snapshot.tabs[0].id).assertEqual('normal');
      expect(snapshot.activeTabId).assertEqual('normal');
    });

    it('reserves a start tab without mutating the live session', 0, () => {
      const store = new TabStore(() => 1000, ['a', 'pending']);
      store.createTab('https://a.example', false);
      const activeBefore = store.activeTabId;
      const draft = store.reserveTab('about:blank', false);
      expect(draft.tab.id).assertEqual('pending');
      expect(store.tabs.length).assertEqual(1);
      expect(store.activeTabId).assertEqual(activeBefore);
    });

    it('commits a reserved tab exactly once and preserves its id', 0, () => {
      const store = new TabStore(() => 1000, ['a', 'pending']);
      store.createTab('https://a.example', false);
      const draft = store.reserveTab('about:blank', false);
      expect(store.commitReservedTab(draft)).assertEqual('pending');
      expect(store.commitReservedTab(draft)).assertEqual('pending');
      expect(store.tabs.length).assertEqual(2);
      expect(store.activeTabId).assertEqual('pending');
    });
  });
}
