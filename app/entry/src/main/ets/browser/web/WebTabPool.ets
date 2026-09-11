import { NodeController } from '@kit.ArkUI';
import { BrowserTabRecord, TabId, TabResidency, lastValidUrlForTab } from '../model/BrowserTypes';

export interface WebRuntimeHandle {
  readonly tabId: TabId;
  readonly runtimeId: string;
  attach(host: NodeController): void;
  detach(): void;
  destroy(): void;
}

export interface WebRuntimeFactory {
  create(tab: BrowserTabRecord): WebRuntimeHandle;
}

/**
 * Owns one ArkWeb runtime per live tab.  Tab overview is presentation-only;
 * selecting a distant card must never evict the controller that owns its page.
 * A runtime is released only when its tab is explicitly closed or the whole
 * browser session is disposed.
 */
export class WebTabPool {
  private readonly runtimes: Map<TabId, WebRuntimeHandle> = new Map();
  private readonly factory: WebRuntimeFactory;

  constructor(factory: WebRuntimeFactory) {
    this.factory = factory;
  }

  ensureBalanced(tabs: BrowserTabRecord[], activeTabId: TabId): void {
    for (const tab of tabs) {
      // Keep an empty start-page tab native-only until the user navigates.
      // Existing non-empty tabs always get a stable ArkWeb runtime.
      if (lastValidUrlForTab(tab) !== 'about:blank' && !this.runtimes.has(tab.id)) {
        this.runtimes.set(tab.id, this.factory.create(tab));
      }
      if (this.runtimes.has(tab.id)) {
        tab.residency = tab.id === activeTabId ? TabResidency.HOT : TabResidency.WARM;
      } else {
        tab.residency = tab.id === activeTabId ? TabResidency.HOT : TabResidency.COLD;
      }
    }
  }

  get(tabId: TabId): WebRuntimeHandle | undefined {
    return this.runtimes.get(tabId);
  }

  ensureTab(tabs: BrowserTabRecord[], tabId: TabId): void {
    const tab: BrowserTabRecord | undefined = tabs.find(
      (item: BrowserTabRecord) => item.id === tabId
    );
    if (tab !== undefined && !this.runtimes.has(tabId)) {
      this.runtimes.set(tabId, this.factory.create(tab));
    }
  }

  runtimeIds(): TabId[] {
    return Array.from(this.runtimes.keys()).sort();
  }

  runtimeIdFor(tabId: TabId): string {
    return this.runtimes.get(tabId)?.runtimeId ?? '';
  }

  /**
   * Memory pressure can mark state, but it must not silently destroy a live
   * tab's page.  ArkWeb controller lifetime is tied to the stable tab id.
   */
  handleMemoryPressure(_tabs: BrowserTabRecord[], _activeTabId: TabId): void {}

  release(tabId: TabId): void {
    const runtime: WebRuntimeHandle | undefined = this.runtimes.get(tabId);
    if (runtime !== undefined) {
      runtime.detach();
      runtime.destroy();
      this.runtimes.delete(tabId);
    }
  }

  releaseAll(): void {
    const tabIds: TabId[] = Array.from(this.runtimes.keys());
    for (const tabId of tabIds) {
      this.release(tabId);
    }
  }
}
