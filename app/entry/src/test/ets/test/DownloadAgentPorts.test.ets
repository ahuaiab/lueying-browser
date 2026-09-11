import { describe, expect, it } from '@ohos/hypium';
import { Context } from '@kit.AbilityKit';
import {
  AgentDownloadConfig,
  AgentTaskSnapshot,
  AgentTaskStatus,
  canonicalAgentStatus,
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

  async search(): Promise<AgentTaskSnapshot[]> {
    return [
      { taskId: this.task.taskId, status: AgentTaskStatus.RUNNING, receivedBytes: 8, totalBytes: 10, percent: 80, description: 'jianyue-download:key-1' },
      { taskId: 'other-agent', status: AgentTaskStatus.RUNNING, receivedBytes: 1, totalBytes: 2, percent: 50, description: 'jianyue-download:key-2' }
    ];
  }

  async show(taskId: string): Promise<AgentTaskSnapshot | undefined> {
    if (taskId !== this.task.taskId) {
      return undefined;
    }
    return { taskId, status: AgentTaskStatus.RUNNING, receivedBytes: 8, totalBytes: 10, percent: 80, description: 'jianyue-download:key-1' };
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
    it('normalizes numeric request-agent states to canonical statuses', 0, () => {
      expect(canonicalAgentStatus(0x20)).assertEqual(AgentTaskStatus.RUNNING);
      expect(canonicalAgentStatus(0x30)).assertEqual(AgentTaskStatus.PAUSED);
      expect(canonicalAgentStatus(0x31)).assertEqual(AgentTaskStatus.CANCELLED);
      expect(canonicalAgentStatus(0x40)).assertEqual(AgentTaskStatus.COMPLETED);
      expect(canonicalAgentStatus(0x41)).assertEqual(AgentTaskStatus.FAILED);
      expect(canonicalAgentStatus(0x50)).assertEqual(AgentTaskStatus.CANCELLED);
    });

    it('creates a background private-path task and forwards progress callbacks', 0, async () => {
      const client: FakeRequestClient = new FakeRequestClient();
      const gateway: RequestAgentGateway = new RequestAgentGateway({} as Context, client);
      const headers: Record<string, string> = {};
      headers['Cookie'] = 'session=secret';
      const config: AgentDownloadConfig = {
        reconcileKey: 'key-1',
        url: 'https://example.com/archive.zip',
        savePath: '/data/storage/el2/base/files/downloads/archive.zip',
        title: 'archive.zip',
        description: 'ignored-by-system-description',
        headers,
        mimeType: 'application/zip',
        notificationEnabled: true
      };
      const handle = await gateway.create(config);
      let progressPercent: number = -1;
      let completedStatus: AgentTaskStatus = AgentTaskStatus.FAILED;
      handle.onProgress((snapshot: AgentTaskSnapshot) => progressPercent = snapshot.percent);
      handle.onCompleted((snapshot: AgentTaskSnapshot) => completedStatus = snapshot.status);
      const progressSnapshot: AgentTaskSnapshot = {
        taskId: 'agent-1', status: AgentTaskStatus.RUNNING, receivedBytes: 4, totalBytes: 10, percent: 40
      };
      const completedSnapshot: AgentTaskSnapshot = {
        taskId: 'agent-1', status: AgentTaskStatus.COMPLETED, receivedBytes: 10, totalBytes: 10, percent: 100
      };
      client.task.emit('progress', progressSnapshot);
      client.task.emit('completed', completedSnapshot);

      expect(client.createdConfig?.action).assertEqual('DOWNLOAD');
      expect(client.createdConfig?.mode).assertEqual('BACKGROUND');
      expect(client.createdConfig?.saveas.startsWith('/data/storage/el2/base/files/')).assertTrue();
      expect(client.createdConfig?.description).assertEqual('jianyue-download:key-1');
      expect(progressPercent).assertEqual(40);
      expect(completedStatus).assertEqual(AgentTaskStatus.COMPLETED);
      expect(JSON.stringify(await gateway.show('agent-1')).includes('session=secret')).assertFalse();
      expect((await gateway.searchByPrefix('jianyue-download:')).length).assertEqual(1);
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
