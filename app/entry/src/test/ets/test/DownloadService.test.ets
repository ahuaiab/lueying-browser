import { describe, expect, it } from '@ohos/hypium';
import { webview } from '@kit.ArkWeb';
import { DownloadStore, DownloadRecordStorage } from '../../../main/ets/browser/data/DownloadStore';
import { DownloadTaskRecord } from '../../../main/ets/browser/model/DownloadModels';
import {
  AgentDownloadConfig,
  AgentDownloadPort,
  AgentTaskHandle,
  AgentTaskSnapshot,
  AgentTaskStatus
} from '../../../main/ets/browser/web/RequestAgentGateway';
import { NotificationPermissionPort } from '../../../main/ets/browser/web/DownloadNotificationGateway';
import { DownloadService, WebCookiePort } from '../../../main/ets/browser/web/DownloadService';
import { WebDownloadHandler } from '../../../main/ets/browser/web/WebTabNode';

class MemoryStorage implements DownloadRecordStorage {
  records: DownloadTaskRecord[] = [];
  readonly events: string[] = [];

  async load(): Promise<DownloadTaskRecord[]> {
    return this.records;
  }

  async save(records: DownloadTaskRecord[]): Promise<void> {
    this.records = records;
    this.events.push(`persist:${records[0]?.status ?? 'empty'}:${records[0]?.agentTaskId ?? ''}`);
  }
}

class FakeAgentTask implements AgentTaskHandle {
  readonly taskId: string;
  private progressListener: ((snapshot: AgentTaskSnapshot) => void) | undefined = undefined;
  private completedListener: ((snapshot: AgentTaskSnapshot) => void) | undefined = undefined;
  private failedListener: ((snapshot: AgentTaskSnapshot) => void) | undefined = undefined;

  constructor(taskId: string) {
    this.taskId = taskId;
  }

  onProgress(listener: (snapshot: AgentTaskSnapshot) => void): void {
    this.progressListener = listener;
  }

  onCompleted(listener: (snapshot: AgentTaskSnapshot) => void): void {
    this.completedListener = listener;
  }

  onFailed(listener: (snapshot: AgentTaskSnapshot) => void): void {
    this.failedListener = listener;
  }

  async pause(): Promise<void> {}
  async resume(): Promise<void> {}
  async cancel(): Promise<void> {}

  progress(snapshot: AgentTaskSnapshot): void {
    this.progressListener?.(snapshot);
  }
}

class FakeAgent implements AgentDownloadPort {
  readonly events: string[];
  readonly task: FakeAgentTask = new FakeAgentTask('agent-1');
  createCalls: number = 0;
  showCalls: number = 0;
  shouldFailCreate: boolean = false;
  recovered: AgentTaskHandle | undefined = undefined;
  showSnapshot: AgentTaskSnapshot | undefined = undefined;

  constructor(events: string[]) {
    this.events = events;
  }

  async create(config: AgentDownloadConfig): Promise<AgentTaskHandle> {
    this.createCalls += 1;
    this.events.push(`agent.create:${config.headers.Cookie ?? ''}`);
    if (this.shouldFailCreate) {
      throw new Error('agent unavailable');
    }
    return this.task;
  }

  async getTask(_taskId: string): Promise<AgentTaskHandle | undefined> {
    return this.recovered;
  }

  async searchByPrefix(_prefix: string): Promise<AgentTaskSnapshot[]> {
    return [];
  }

  async show(_taskId: string): Promise<AgentTaskSnapshot | undefined> {
    this.showCalls += 1;
    return this.showSnapshot;
  }
}

class FakeCookiePort implements WebCookiePort {
  calls: number = 0;

  async fetchCookie(_url: string, _isPrivate: boolean): Promise<string> {
    this.calls += 1;
    return 'session=secret';
  }
}

class FakeNotificationPort implements NotificationPermissionPort {
  async requestOnce(): Promise<boolean> {
    return true;
  }
}

class FakeItem {
  readonly events: string[];
  readonly url: string;
  readonly method: string;
  readonly guid: string;
  starts: string[] = [];
  cancelCalls: number = 0;
  shouldThrowStart: boolean = false;
  shouldThrowCancel: boolean = false;

  constructor(events: string[], url: string = 'https://example.com/archive.zip', method: string = 'GET',
    guid: string = 'web-guid-1') {
    this.events = events;
    this.url = url;
    this.method = method;
    this.guid = guid;
  }

  getGuid(): string { return this.guid; }
  getUrl(): string { return this.url; }
  getMethod(): string { return this.method; }
  getMimeType(): string { return 'application/zip'; }
  getSuggestedFileName(): string { return 'archive.zip'; }
  getReceivedBytes(): number { return 25; }
  getTotalBytes(): number { return 100; }
  getPercentComplete(): number { return 25; }
  start(path: string): void {
    this.starts.push(path);
    this.events.push('item.start');
    if (this.shouldThrowStart) {
      throw new Error('native start failed');
    }
  }
  cancel(): void {
    this.cancelCalls += 1;
    this.events.push('item.cancel');
    if (this.shouldThrowCancel) {
      throw new Error('ArkWeb cancel failed');
    }
  }
}

async function flush(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
}

function itemAsWebDownloadItem(item: FakeItem): webview.WebDownloadItem {
  return item as unknown as webview.WebDownloadItem;
}

function createService(events: string[], pathExists: ((path: string) => boolean) | undefined = undefined):
  { service: DownloadService, storage: MemoryStorage, agent: FakeAgent, cookie: FakeCookiePort } {
  const storage: MemoryStorage = new MemoryStorage();
  const agent: FakeAgent = new FakeAgent(events);
  const cookie: FakeCookiePort = new FakeCookiePort();
  return {
    service: new DownloadService(new DownloadStore(storage, () => 100), agent, new FakeNotificationPort(), cookie,
      '/data/storage/el2/base/files', () => 100, pathExists),
    storage,
    agent,
    cookie
  };
}

export default function downloadServiceTest() {
  describe('DownloadService', () => {
    it('persists the agent handoff before cancelling ArkWeb', 0, async () => {
      const events: string[] = [];
      const setup = createService(events);
      const item: FakeItem = new FakeItem(events);
      const handler: WebDownloadHandler = setup.service;

      handler.onBeforeDownload('tab-1', itemAsWebDownloadItem(item), false);
      await flush();

      expect(events.join('|')).assertEqual(
        'persist:handoff-pending:|agent.create:session=secret|persist:handoff-pending:agent-1|item.cancel|persist:running:agent-1'
      );
      expect(JSON.stringify(setup.storage.records).includes('session=secret')).assertFalse();
    });

    it('uses ArkWeb without Cookie for private and blob downloads', 0, async () => {
      const privateEvents: string[] = [];
      const privateSetup = createService(privateEvents);
      const privateItem: FakeItem = new FakeItem(privateEvents);
      privateSetup.service.onBeforeDownload('tab-1', itemAsWebDownloadItem(privateItem), true);
      await flush();

      const blobEvents: string[] = [];
      const blobSetup = createService(blobEvents);
      const blobItem: FakeItem = new FakeItem(blobEvents, 'blob:https://example.com/1');
      blobSetup.service.onBeforeDownload('tab-1', itemAsWebDownloadItem(blobItem), false);
      await flush();

      expect(privateItem.starts.length).assertEqual(1);
      expect(privateSetup.agent.createCalls).assertEqual(0);
      expect(privateSetup.cookie.calls).assertEqual(0);
      expect(blobItem.starts.length).assertEqual(1);
      expect(blobSetup.agent.createCalls).assertEqual(0);
      expect(JSON.stringify(privateSetup.storage.records).includes('session=secret')).assertFalse();
      expect(JSON.stringify(blobSetup.storage.records).includes('session=secret')).assertFalse();
    });

    it('falls back exactly once when agent creation fails before a system task exists', 0, async () => {
      const events: string[] = [];
      const setup = createService(events);
      setup.agent.shouldFailCreate = true;
      const item: FakeItem = new FakeItem(events);

      setup.service.onBeforeDownload('tab-1', itemAsWebDownloadItem(item), false);
      await flush();

      expect(item.starts.length).assertEqual(1);
      expect(item.cancelCalls).assertEqual(0);
      expect(setup.service.snapshot()[0].status).assertEqual('running');
    });

    it('does not create a duplicate agent task while restoring a saved task', 0, async () => {
      const events: string[] = [];
      const setup = createService(events);
      setup.storage.records = [{
        id: 'web-guid-1', agentTaskId: 'agent-1', reconcileKey: 'web-guid-1', tabId: 'tab-1',
        url: 'https://example.com/archive.zip', filename: 'archive.zip', backend: 'request-agent',
        status: 'running', receivedBytes: 0, totalBytes: -1, percent: -1, createdAt: 1, updatedAt: 1,
        isPrivate: false
      } as DownloadTaskRecord];
      setup.agent.recovered = setup.agent.task;

      await setup.service.restore();

      expect(setup.agent.createCalls).assertEqual(0);
      expect(setup.service.snapshot().length).assertEqual(1);
    });

    it('merges the shown terminal agent state before deciding whether to attach', 0, async () => {
      const events: string[] = [];
      const setup = createService(events);
      setup.storage.records = [{
        id: 'web-guid-1', agentTaskId: 'agent-1', reconcileKey: 'web-guid-1', tabId: 'tab-1',
        url: 'https://example.com/archive.zip', filename: 'archive.zip', backend: 'request-agent',
        status: 'running', receivedBytes: 2, totalBytes: 100, percent: 2, createdAt: 1, updatedAt: 1,
        isPrivate: false
      } as DownloadTaskRecord];
      setup.agent.recovered = setup.agent.task;
      setup.agent.showSnapshot = {
        taskId: 'agent-1', status: AgentTaskStatus.COMPLETED, receivedBytes: 100, totalBytes: 100, percent: 100
      };

      await setup.service.restore();
      setup.agent.task.progress({
        taskId: 'agent-1', status: AgentTaskStatus.RUNNING, receivedBytes: 3, totalBytes: 100, percent: 3
      });

      expect(setup.agent.showCalls).assertEqual(1);
      expect(setup.service.snapshot()[0].status).assertEqual('completed');
      expect(setup.service.snapshot()[0].receivedBytes).assertEqual(100);
    });

    it('keeps the agent backend when ArkWeb cancellation throws after handoff', 0, async () => {
      const events: string[] = [];
      const setup = createService(events);
      const item: FakeItem = new FakeItem(events);
      item.shouldThrowCancel = true;

      setup.service.onBeforeDownload('tab-1', itemAsWebDownloadItem(item), false);
      await flush();

      expect(item.starts.length).assertEqual(0);
      expect(setup.agent.createCalls).assertEqual(1);
      expect(setup.service.snapshot()[0].agentTaskId).assertEqual('agent-1');
      expect(setup.service.snapshot()[0].status).assertEqual('running');
      expect((setup.service.snapshot()[0].error ?? '').length > 0).assertTrue();
    });

    it('marks native start errors as retryable failures', 0, async () => {
      const events: string[] = [];
      const setup = createService(events);
      const item: FakeItem = new FakeItem(events, 'blob:https://example.com/1');
      item.shouldThrowStart = true;

      setup.service.onBeforeDownload('tab-1', itemAsWebDownloadItem(item), false);
      await flush();

      expect(setup.service.snapshot()[0].status).assertEqual('failed');
      expect((setup.service.snapshot()[0].error ?? '').length > 0).assertTrue();
    });

    it('allocates a distinct path when the base target already exists and on retry', 0, async () => {
      const existing: Set<string> = new Set();
      const pathExists: (path: string) => boolean = (path: string): boolean => existing.has(path);
      const events: string[] = [];
      const setup = createService(events, pathExists);
      const item: FakeItem = new FakeItem(events, 'blob:https://example.com/1');
      existing.add('/data/storage/el2/base/files/downloads/web-guid-1-archive.zip');

      setup.service.onBeforeDownload('tab-1', itemAsWebDownloadItem(item), false);
      await flush();
      const firstPath: string = item.starts[0];
      existing.add(firstPath);
      setup.service.onDownloadFailed('tab-1', itemAsWebDownloadItem(item));
      await setup.service.retry('web-guid-1');

      expect(firstPath.endsWith('-archive.zip')).assertTrue();
      expect(item.starts.length).assertEqual(2);
      expect(item.starts[1] === firstPath).assertFalse();
    });

    it('reuses one generated id for empty-guid update, finish and failure callbacks', 0, async () => {
      const events: string[] = [];
      const setup = createService(events);
      const item: FakeItem = new FakeItem(events, 'blob:https://example.com/1', 'GET', '');

      setup.service.onBeforeDownload('tab-1', itemAsWebDownloadItem(item), false);
      await flush();
      const id: string = setup.service.snapshot()[0].id;
      setup.service.onDownloadUpdated('tab-1', itemAsWebDownloadItem(item));
      expect(setup.service.snapshot()[0].id).assertEqual(id);
      setup.service.onDownloadFinish('tab-1', itemAsWebDownloadItem(item));
      setup.service.onDownloadFailed('tab-1', itemAsWebDownloadItem(item));

      expect(setup.service.snapshot().length).assertEqual(1);
      expect(setup.service.snapshot()[0].id).assertEqual(id);
      expect(setup.service.snapshot()[0].status).assertEqual('completed');
    });
  });
}
