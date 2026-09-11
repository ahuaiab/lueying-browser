import { describe, expect, it } from '@ohos/hypium';
import { DownloadBackend, DownloadStatus, DownloadTaskRecord } from
  '../../../main/ets/browser/model/DownloadModels';
import {
  BrowserDownloadLifecycle,
  BrowserDownloadServicePort
} from '../../../main/ets/browser/components/BrowserShell';

class FakeDownloadService implements BrowserDownloadServicePort {
  readonly events: string[] = [];
  readonly actionEvents: string[] = [];
  records: DownloadTaskRecord[] = [];
  restoreShouldReject: boolean = false;
  private listener: ((tasks: DownloadTaskRecord[]) => void) | undefined = undefined;

  async restore(): Promise<void> {
    this.events.push('restore');
    if (this.restoreShouldReject) {
      throw new Error('restore query failed');
    }
    this.listener?.(this.records);
  }

  markUiLoaded(): void {
    this.events.push('ui-loaded');
  }

  snapshot(): DownloadTaskRecord[] {
    return this.records;
  }

  async pause(id: string): Promise<void> {
    this.actionEvents.push(`pause:${id}`);
  }

  async resume(id: string): Promise<void> {
    this.actionEvents.push(`resume:${id}`);
  }

  async cancel(id: string): Promise<void> {
    this.actionEvents.push(`cancel:${id}`);
  }

  async retry(id: string): Promise<void> {
    this.actionEvents.push(`retry:${id}`);
  }

  setListener(listener: (tasks: DownloadTaskRecord[]) => void): void {
    this.events.push('listener');
    this.listener = listener;
  }

  clearListener(listener: (tasks: DownloadTaskRecord[]) => void): void {
    this.events.push('clear-listener');
    if (this.listener === listener) {
      this.listener = undefined;
    }
  }

  emitSnapshot(): void {
    this.listener?.(this.records);
  }
}

function liveTask(): DownloadTaskRecord {
  return {
    id: 'download-1',
    agentTaskId: 'agent-1',
    reconcileKey: 'download-1',
    tabId: 'tab-1',
    url: 'https://example.com/archive.zip',
    filename: 'archive.zip',
    backend: DownloadBackend.REQUEST_AGENT,
    status: DownloadStatus.RUNNING,
    receivedBytes: 25,
    totalBytes: 100,
    percent: 25,
    createdAt: 1,
    updatedAt: 2,
    isPrivate: false
  };
}

export default function browserDownloadLifecycleTest() {
  describe('BrowserDownloadLifecycle', () => {
    it('publishes a copied restored snapshot after marking the UI loaded', 0, async () => {
      const service: FakeDownloadService = new FakeDownloadService();
      service.records = [liveTask()];
      let published: DownloadTaskRecord[] = [];
      const lifecycle: BrowserDownloadLifecycle = new BrowserDownloadLifecycle(
        service,
        (tasks: DownloadTaskRecord[]) => {
          published = tasks;
        },
        (_visible: boolean) => undefined
      );

      await lifecycle.start();

      expect(service.events.join('|')).assertEqual('listener|ui-loaded|restore');
      expect(published.length).assertEqual(1);
      expect(published[0].id).assertEqual('download-1');
      expect(published === service.records).assertFalse();
    });

    it('does not stop a live task when the shell is hidden', 0, async () => {
      const service: FakeDownloadService = new FakeDownloadService();
      service.records = [liveTask()];
      const lifecycle: BrowserDownloadLifecycle = new BrowserDownloadLifecycle(
        service,
        (_tasks: DownloadTaskRecord[]) => undefined,
        (_visible: boolean) => undefined
      );
      await lifecycle.start();

      lifecycle.onHidden();

      expect(service.actionEvents.length).assertEqual(0);
      expect(service.records[0].status).assertEqual(DownloadStatus.RUNNING);
    });

    it('opens the manager without requiring page actions to be ready', 0, () => {
      const service: FakeDownloadService = new FakeDownloadService();
      let managerVisible: boolean = false;
      const lifecycle: BrowserDownloadLifecycle = new BrowserDownloadLifecycle(
        service,
        (_tasks: DownloadTaskRecord[]) => undefined,
        (visible: boolean) => {
          managerVisible = visible;
        }
      );
      const pageActionsReady: boolean = false;

      expect(lifecycle.openDownloadManager(pageActionsReady)).assertTrue();
      expect(managerVisible).assertTrue();
    });

    it('detaches an old shell without clearing a rebound shell listener', 0, async () => {
      const service: FakeDownloadService = new FakeDownloadService();
      let oldUpdates: number = 0;
      let newUpdates: number = 0;
      const oldLifecycle: BrowserDownloadLifecycle = new BrowserDownloadLifecycle(
        service,
        (_tasks: DownloadTaskRecord[]) => oldUpdates += 1,
        (_visible: boolean) => undefined
      );
      const newLifecycle: BrowserDownloadLifecycle = new BrowserDownloadLifecycle(
        service,
        (_tasks: DownloadTaskRecord[]) => newUpdates += 1,
        (_visible: boolean) => undefined
      );

      await oldLifecycle.start();
      await newLifecycle.start();
      oldUpdates = 0;
      newUpdates = 0;
      oldLifecycle.stop();
      service.emitSnapshot();

      expect(oldUpdates).assertEqual(0);
      expect(newUpdates).assertEqual(1);
    });

    it('publishes the service snapshot when restore rejects', 0, async () => {
      const service: FakeDownloadService = new FakeDownloadService();
      service.records = [liveTask()];
      service.restoreShouldReject = true;
      let published: DownloadTaskRecord[] = [];
      const lifecycle: BrowserDownloadLifecycle = new BrowserDownloadLifecycle(
        service,
        (tasks: DownloadTaskRecord[]) => published = tasks,
        (_visible: boolean) => undefined
      );

      await lifecycle.start();

      expect(published.length).assertEqual(1);
      expect(published[0].id).assertEqual('download-1');
    });
  });
}
