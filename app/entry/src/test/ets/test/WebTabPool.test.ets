import { describe, expect, it } from '@ohos/hypium';
import { NodeController } from '@kit.ArkUI';
import { BrowserTabRecord, TabId, TabResidency } from '../../../main/ets/browser/model/BrowserTypes';
import { TabStore } from '../../../main/ets/browser/store/TabStore';
import {
  WebRuntimeFactory,
  WebRuntimeHandle,
  WebTabPool
} from '../../../main/ets/browser/web/WebTabPool';

class FakeWebRuntimeHandle implements WebRuntimeHandle {
  readonly tabId: TabId;
  readonly runtimeId: string;
  destroyCalls: number = 0;

  constructor(tabId: TabId) {
    this.tabId = tabId;
    this.runtimeId = `runtime-${tabId}`;
  }

  attach(_host: NodeController): void {}

  detach(): void {}

  destroy(): void {
    this.destroyCalls += 1;
  }
}

class FakeWebRuntimeFactory implements WebRuntimeFactory {
  readonly handles: Map<TabId, FakeWebRuntimeHandle> = new Map();

  create(tab: BrowserTabRecord): WebRuntimeHandle {
    const handle = new FakeWebRuntimeHandle(tab.id);
    this.handles.set(tab.id, handle);
    return handle;
  }
}

export default function webTabPoolTest() {
  describe('WebTabPool', () => {
    it('retains every live tab runtime across distant selection', 0, () => {
      const store = new TabStore(() => 1000, ['a', 'b', 'c', 'd', 'e']);
      for (let index: number = 0; index < 5; index += 1) {
        store.createTab(`https://${index}.example`, false);
      }
      store.activateTab('a');
      const factory = new FakeWebRuntimeFactory();
      const pool = new WebTabPool(factory);
      pool.ensureBalanced(store.tabs, store.activeTabId);
      expect(pool.runtimeIds().join(',')).assertEqual('a,b,c,d,e');
      expect(store.tabs.find((tab: BrowserTabRecord) => tab.id === 'a')?.residency)
        .assertEqual(TabResidency.HOT);

      store.activateTab('e');
      pool.ensureBalanced(store.tabs, store.activeTabId);
      expect(pool.runtimeIds().join(',')).assertEqual('a,b,c,d,e');
      expect(factory.handles.get('a')?.destroyCalls).assertEqual(0);
      expect(factory.handles.get('b')?.destroyCalls).assertEqual(0);
      expect(factory.handles.get('c')?.destroyCalls).assertEqual(0);
      expect(factory.handles.get('d')?.destroyCalls).assertEqual(0);
      expect(store.tabs.find((tab: BrowserTabRecord) => tab.id === 'e')?.residency)
        .assertEqual(TabResidency.HOT);
    });

    it('releases only the explicitly closed tab runtime', 0, () => {
      const store = new TabStore(() => 3000, ['a', 'b', 'c']);
      for (let index: number = 0; index < 3; index += 1) {
        store.createTab(`https://${index}.example`, false);
      }
      store.activateTab('b');
      const factory: FakeWebRuntimeFactory = new FakeWebRuntimeFactory();
      const pool: WebTabPool = new WebTabPool(factory);
      pool.ensureBalanced(store.tabs, store.activeTabId);
      expect(pool.runtimeIds().join(',')).assertEqual('a,b,c');

      pool.release('b');

      expect(pool.runtimeIds().join(',')).assertEqual('a,c');
      expect(factory.handles.get('a')?.destroyCalls).assertEqual(0);
      expect(factory.handles.get('b')?.destroyCalls).assertEqual(1);
      expect(factory.handles.get('c')?.destroyCalls).assertEqual(0);
    });

    it('keeps the runtime registry independent from overview presentation', 0, () => {
      const store: TabStore = new TabStore(() => 3000, ['a', 'b', 'c', 'd', 'e']);
      for (let index: number = 0; index < 5; index += 1) {
        store.createTab(`https://${index}.example`, false);
      }
      store.activateTab('b');
      const factory: FakeWebRuntimeFactory = new FakeWebRuntimeFactory();
      const pool: WebTabPool = new WebTabPool(factory);
      pool.ensureBalanced(store.tabs, store.activeTabId);
      expect(pool.runtimeIds().join(',')).assertEqual('a,b,c,d,e');

      store.activateTab('e');
      pool.ensureBalanced(store.tabs, store.activeTabId);

      expect(pool.runtimeIds().join(',')).assertEqual('a,b,c,d,e');
      expect(factory.handles.get('a')?.destroyCalls).assertEqual(0);
      expect(factory.handles.get('b')?.destroyCalls).assertEqual(0);
      expect(factory.handles.get('c')?.destroyCalls).assertEqual(0);
      expect(store.tabs.find((tab: BrowserTabRecord) => tab.id === 'e')?.residency)
        .assertEqual(TabResidency.HOT);
    });

    it('switching active ids preserves every runtime and destroy count', 0, () => {
      const store = new TabStore(() => 4000, ['a', 'b', 'c']);
      for (let index: number = 0; index < 3; index += 1) {
        store.createTab(`https://${index}.example`, false);
      }
      const factory: FakeWebRuntimeFactory = new FakeWebRuntimeFactory();
      const pool: WebTabPool = new WebTabPool(factory);
      pool.ensureBalanced(store.tabs, 'a');
      const runtimeIdsBefore: string = pool.runtimeIds().join(',');
      store.activateTab('c');
      pool.ensureBalanced(store.tabs, store.activeTabId);
      expect(pool.runtimeIds().join(',')).assertEqual(runtimeIdsBefore);
      expect(factory.handles.get('a')?.destroyCalls).assertEqual(0);
      expect(factory.handles.get('b')?.destroyCalls).assertEqual(0);
      expect(factory.handles.get('c')?.destroyCalls).assertEqual(0);
    });
  });
}
