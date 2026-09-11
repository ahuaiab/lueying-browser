import { describe, expect, it } from '@ohos/hypium';
import { TabId } from '../../../main/ets/browser/model/BrowserTypes';
import { TabStore } from '../../../main/ets/browser/store/TabStore';
import {
  DefaultBrowserCommandDispatcher,
  SnapshotPort,
  TabRuntimePort,
  SessionPort
} from '../../../main/ets/browser/command/BrowserCommandDispatcher';

class FakeRuntimePort implements TabRuntimePort {
  releaseCalls: number = 0;
  balanceCalls: number = 0;
  backCalls: number = 0;
  forwardCalls: number = 0;
  reloadCalls: number = 0;

  ensureBalanced(): void {
    this.balanceCalls += 1;
  }

  release(_tabId: TabId): void {
    this.releaseCalls += 1;
  }

  goBack(_tabId: TabId): boolean {
    this.backCalls += 1;
    return true;
  }

  goForward(_tabId: TabId): boolean {
    this.forwardCalls += 1;
    return true;
  }

  reload(_tabId: TabId): void {
    this.reloadCalls += 1;
  }
}

class FakeSnapshotPort implements SnapshotPort {
  removeCalls: number = 0;

  async remove(_tabId: TabId): Promise<void> {
    this.removeCalls += 1;
  }
}

class FakeSessionPort implements SessionPort {
  saveCalls: number = 0;

  async save(): Promise<void> {
    this.saveCalls += 1;
  }
}

interface DispatcherFixture {
  store: TabStore;
  runtime: FakeRuntimePort;
  snapshot: FakeSnapshotPort;
  session: FakeSessionPort;
  dispatcher: DefaultBrowserCommandDispatcher;
}

function createDispatcherFixture(ids: string[]): DispatcherFixture {
  const store = new TabStore(() => 1000, ids);
  const runtime = new FakeRuntimePort();
  const snapshot = new FakeSnapshotPort();
  const session = new FakeSessionPort();
  const dispatcher = new DefaultBrowserCommandDispatcher(store, runtime, snapshot, session);
  return { store, runtime, snapshot, session, dispatcher };
}

export default function browserCommandDispatcherTest() {
  describe('BrowserCommandDispatcher', () => {
    it('serializes duplicate close commands', 0, async () => {
      const fixture = createDispatcherFixture(['a', 'replacement']);
      fixture.store.createTab('https://a.example', false);
      await Promise.all([
        fixture.dispatcher.closeTab('a'),
        fixture.dispatcher.closeTab('a')
      ]);
      expect(fixture.runtime.releaseCalls).assertEqual(1);
      expect(fixture.snapshot.removeCalls).assertEqual(1);
      expect(fixture.store.tabs.length).assertEqual(1);
    });

    it('rebalances after a successful activation', 0, async () => {
      const fixture = createDispatcherFixture(['a', 'b']);
      fixture.store.createTab('https://a.example', false);
      fixture.store.createTab('https://b.example', false);
      fixture.runtime.balanceCalls = 0;
      await fixture.dispatcher.activateTab('a');
      expect(fixture.runtime.balanceCalls).assertEqual(1);
      expect(fixture.session.saveCalls).assertEqual(1);
    });

    it('does nothing for a failed activation', 0, async () => {
      const fixture = createDispatcherFixture(['a']);
      fixture.store.createTab('https://a.example', false);
      await fixture.dispatcher.activateTab('missing');
      expect(fixture.runtime.balanceCalls).assertEqual(0);
      expect(fixture.session.saveCalls).assertEqual(0);
    });

    it('selects the right-hand tab before the left-hand tab on close', 0, async () => {
      const fixture = createDispatcherFixture(['a', 'b', 'c']);
      fixture.store.createTab('https://a.example', false);
      fixture.store.createTab('https://b.example', false);
      fixture.store.createTab('https://c.example', false);
      await fixture.dispatcher.activateTab('b');
      await fixture.dispatcher.closeTab('b');
      expect(fixture.store.activeTabId).assertEqual('c');
    });

    it('delegates navigation controls to the active runtime', 0, () => {
      const fixture = createDispatcherFixture(['a']);
      fixture.store.createTab('https://a.example', false);
      expect(fixture.dispatcher.goBack()).assertTrue();
      expect(fixture.dispatcher.goForward()).assertTrue();
      fixture.dispatcher.reloadActiveTab();
      expect(fixture.runtime.backCalls).assertEqual(1);
      expect(fixture.runtime.forwardCalls).assertEqual(1);
      expect(fixture.runtime.reloadCalls).assertEqual(1);
    });

    it('does not persist a render-only tab reservation', 0, async () => {
      const fixture = createDispatcherFixture(['a', 'pending']);
      fixture.store.createTab('https://a.example', false);
      fixture.session.saveCalls = 0;
      const draft = fixture.dispatcher.reserveTab('about:blank', false);
      expect(draft.tab.id).assertEqual('pending');
      expect(fixture.store.tabs.length).assertEqual(1);
      expect(fixture.session.saveCalls).assertEqual(0);
      await fixture.dispatcher.commitReservedTab(draft);
      expect(fixture.store.tabs.length).assertEqual(2);
      expect(fixture.session.saveCalls).assertEqual(1);
    });
  });
}
