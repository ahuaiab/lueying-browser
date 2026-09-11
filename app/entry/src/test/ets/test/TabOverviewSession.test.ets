import { describe, expect, it } from '@ohos/hypium';
import { BrowserTabRecord, TabId } from '../../../main/ets/browser/model/BrowserTypes';
import {
  PageDisplayState,
  PageFontSize
} from '../../../main/ets/browser/model/PageDisplayState';
import { TabStore } from '../../../main/ets/browser/store/TabStore';
import {
  captureTabOverviewSession,
  pageStateForTabOverview,
  savedUrlForTabOverview,
  TabOverviewSession
} from '../../../main/ets/browser/model/TabOverviewSession';

function displayState(fontSize: PageFontSize): PageDisplayState {
  return {
    fontSize,
    readerMode: true,
    translated: false,
    fullScreen: false
  };
}

export default function tabOverviewSessionTest() {
  describe('TabOverviewSession', () => {
    it('captures every existing tab by stable id without creating or replacing tabs', 0, () => {
      const store: TabStore = new TabStore(() => 1000, ['article', 'second']);
      const firstId: TabId = store.createTab('https://article.example/page', false);
      const secondId: TabId = store.createTab('https://second.example/page', false);
      store.activateTab(firstId);
      const controllers: Map<TabId, string> = new Map([
        [firstId, 'controller-article'],
        [secondId, 'controller-second']
      ]);
      const states: Map<TabId, PageDisplayState> = new Map([
        [firstId, displayState(PageFontSize.LARGE)],
        [secondId, displayState(PageFontSize.SMALL)]
      ]);

      const session: TabOverviewSession = captureTabOverviewSession(
        store.tabs,
        store.activeTabId,
        controllers,
        states
      );

      expect(store.tabs.length).assertEqual(2);
      expect(session.currentIndex).assertEqual(0);
      expect(session.currentTabId).assertEqual(firstId);
      expect(session.currentUrl).assertEqual('https://article.example/page');
      expect(session.tabs.length).assertEqual(2);
      expect(session.tabs[0].id).assertEqual(firstId);
      expect(session.tabs[0].controllerId).assertEqual('controller-article');
      expect(session.tabs[1].id).assertEqual(secondId);
      expect(session.tabs[1].url).assertEqual('https://second.example/page');
      expect(pageStateForTabOverview(session, secondId)?.fontSize).assertEqual(PageFontSize.SMALL);
    });

    it('returns only the selected tab saved URL when its controller is unavailable', 0, () => {
      const store: TabStore = new TabStore(() => 2000, ['article']);
      const tabId: TabId = store.createTab('https://article.example/keep', false);
      const session: TabOverviewSession = captureTabOverviewSession(
        store.tabs,
        tabId,
        new Map<TabId, string>(),
        new Map<TabId, PageDisplayState>()
      );

      expect(savedUrlForTabOverview(session, tabId)).assertEqual('https://article.example/keep');
      expect(savedUrlForTabOverview(session, 'missing')).assertEqual(undefined);
    });
  });
}
