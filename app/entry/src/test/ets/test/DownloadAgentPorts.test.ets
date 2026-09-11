import { describe, expect, it } from '@ohos/hypium';
import { Context } from '@kit.AbilityKit';
import {
  AgentTaskSnapshot,
  RequestAgentClient,
  RequestAgentGateway,
  RequestAgentSystemConfig,
  RequestAgentSystemTask
} from '../../../main/ets/browser/web/RequestAgentGateway';
import {
  DownloadNotificationGateway,
  NotificationRequestClient
} from '../../../main/ets/browser/web/DownloadNotificationGateway';

class FakeRequestTask implements RequestAgentSystemTask {
  readonly taskId: string;
  private readonly listeners: Map<string, Array<(snapshot: AgentTaskSnapshot) => void>> = new Map();

  constructor(taskId: string) {
    this.taskId = taskId;
  }

  on(event: string, listener: (snapshot: AgentTaskSnapshot) => void): void {
    const current: Array<(snapshot: AgentTaskSnapshot) => void> = this.listeners.get(event) ?? [];
    current.push(listener);
    this.listeners.set(event, current);
  }

  async pause(): Promise<void> {}
  async resume(): Promise<void> {}
  async cancel(): Promise<void> {}

  emit(event: string, snapshot: AgentTaskSnapshot): void {
    const current: Array<(snapshot: AgentTaskSnapshot) => void> = this.listeners.get(event) ?? [];
    current.forEach((listener: (snapshot: AgentTaskSnapshot) => void) => listener(snapshot));
  }
}

class FakeRequestClient implements RequestAgentClient {
  readonly task: FakeRequestTask = new FakeRequestTask('agent-1');
  createdConfig: RequestAgentSystemConfig | undefined = undefined;

  async create(config: RequestAgentSystemConfig): Promise<RequestAgentSystemTask> {
    this.createdConfig = config;
    return this.task;
  }

  async getTask(taskId: string): Promise<RequestAgentSystemTask | undefined> {
    return taskId === this.task.taskId ? this.task : undefined;
  }

  async search(): Promise<string[]> {
    return [this.task.taskId];
  }

  async show(taskId: string): Promise<AgentTaskSnapshot | undefined> {
    if (taskId !== this.task.taskId) {
      return undefined;
    }
    return { taskId, status: 'RUNNING', receivedBytes: 8, totalBytes: 10, percent: 80, description: 'jianyue-download:key-1' };
  }
}

class FakeNotificationClient implements NotificationRequestClient {
  calls: number = 0;
  shouldReject: boolean = false;

  async requestEnableNotification(_context: Context): Promise<void> {
    this.calls += 1;
    if (this.shouldReject) {
      throw new Error('denied');
    }
  }
}

export default function downloadAgentPortsTest() {
  describe('DownloadAgentPorts', () => {
    it('creates a background private-path task and forwards progress callbacks', 0, async () => {
      const client: FakeRequestClient = new FakeRequestClient();
      const gateway: RequestAgentGateway = new RequestAgentGateway({} as Context, client);
      const handle = await gateway.create({
        reconcileKey: 'key-1',
        url: 'https://example.com/archive.zip',
        savePath: '/data/storage/el2/base/files/downloads/archive.zip',
        title: 'archive.zip',
        description: 'ignored-by-system-description',
        headers: { Cookie: 'session=secret' },
        mimeType: 'application/zip',
        notificationEnabled: true
      });
      let progress: AgentTaskSnapshot | undefined = undefined;
      let completed: AgentTaskSnapshot | undefined = undefined;
      handle.onProgress((snapshot: AgentTaskSnapshot) => progress = snapshot);
      handle.onCompleted((snapshot: AgentTaskSnapshot) => completed = snapshot);
      client.task.emit('progress', { taskId: 'agent-1', status: 'RUNNING', receivedBytes: 4, totalBytes: 10, percent: 40 });
      client.task.emit('completed', { taskId: 'agent-1', status: 'COMPLETED', receivedBytes: 10, totalBytes: 10, percent: 100 });

      expect(client.createdConfig?.action).assertEqual('DOWNLOAD');
      expect(client.createdConfig?.mode).assertEqual('BACKGROUND');
      expect(client.createdConfig?.saveas.startsWith('/data/storage/el2/base/files/')).assertTrue();
      expect(client.createdConfig?.description).assertEqual('jianyue-download:key-1');
      expect(progress?.percent).assertEqual(40);
      expect(completed?.status).assertEqual('COMPLETED');
      expect(JSON.stringify(await gateway.show('agent-1')).includes('session=secret')).assertFalse();
    });

    it('requests notification permission once and returns false after rejection', 0, async () => {
      const client: FakeNotificationClient = new FakeNotificationClient();
      const gateway: DownloadNotificationGateway = new DownloadNotificationGateway({} as Context, client);
      expect(await gateway.requestOnce()).assertTrue();
      expect(await gateway.requestOnce()).assertTrue();
      expect(client.calls).assertEqual(1);

      const rejectedClient: FakeNotificationClient = new FakeNotificationClient();
      rejectedClient.shouldReject = true;
      const rejectedGateway: DownloadNotificationGateway = new DownloadNotificationGateway({} as Context, rejectedClient);
      expect(await rejectedGateway.requestOnce()).assertFalse();
      expect(await rejectedGateway.requestOnce()).assertFalse();
      expect(rejectedClient.calls).assertEqual(1);
    });
  });
}
