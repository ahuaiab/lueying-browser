import { Context } from '@kit.AbilityKit';
import { request } from '@kit.BasicServicesKit';

export interface AgentDownloadConfig {
  reconcileKey: string;
  url: string;
  savePath: string;
  title: string;
  description: string;
  headers: Record<string, string>;
  mimeType: string;
  notificationEnabled: boolean;
}

export interface AgentTaskSnapshot {
  taskId: string;
  status: string;
  receivedBytes: number;
  totalBytes: number;
  percent: number;
  description?: string;
  savePath?: string;
  error?: string;
}

export interface AgentTaskHandle {
  taskId: string;
  onProgress(listener: (snapshot: AgentTaskSnapshot) => void): void;
  onCompleted(listener: (snapshot: AgentTaskSnapshot) => void): void;
  onFailed(listener: (snapshot: AgentTaskSnapshot) => void): void;
  pause(): Promise<void>;
  resume(): Promise<void>;
  cancel(): Promise<void>;
}

export interface AgentDownloadPort {
  create(config: AgentDownloadConfig): Promise<AgentTaskHandle>;
  getTask(taskId: string): Promise<AgentTaskHandle | undefined>;
  searchByPrefix(prefix: string): Promise<AgentTaskSnapshot[]>;
  show(taskId: string): Promise<AgentTaskSnapshot | undefined>;
}

export interface RequestAgentSystemConfig {
  action: string;
  url: string;
  title: string;
  description: string;
  mode: string;
  saveas: string;
  method: string;
  headers: Record<string, string>;
  mimeType: string;
  gauge: boolean;
}

export interface RequestAgentSystemTask {
  taskId: string;
  on(event: string, listener: (snapshot: AgentTaskSnapshot) => void): void;
  pause(): Promise<void>;
  resume(): Promise<void>;
  cancel(): Promise<void>;
}

export interface RequestAgentClient {
  create(config: RequestAgentSystemConfig): Promise<RequestAgentSystemTask>;
  getTask(taskId: string): Promise<RequestAgentSystemTask | undefined>;
  search(): Promise<string[]>;
  show(taskId: string): Promise<AgentTaskSnapshot | undefined>;
}

function percentForAgent(receivedBytes: number, totalBytes: number): number {
  if (totalBytes <= 0) {
    return -1;
  }
  return Math.min(100, Math.max(0, Math.floor(receivedBytes * 100 / totalBytes)));
}

class HarmonyRequestAgentTask implements RequestAgentSystemTask {
  readonly taskId: string;
  private readonly task: request.agent.Task;

  constructor(task: request.agent.Task) {
    this.task = task;
    this.taskId = task.tid;
  }

  on(event: string, listener: (snapshot: AgentTaskSnapshot) => void): void {
    if (event === 'progress') {
      this.task.on('progress', (progress: request.agent.Progress) => listener(this.snapshot('RUNNING', progress)));
    } else if (event === 'completed') {
      this.task.on('completed', (progress: request.agent.Progress) => listener(this.snapshot('COMPLETED', progress)));
    } else if (event === 'failed') {
      this.task.on('failed', (progress: request.agent.Progress) => listener(this.snapshot('FAILED', progress)));
    }
  }

  async pause(): Promise<void> {
    await this.task.pause();
  }

  async resume(): Promise<void> {
    await this.task.resume();
  }

  async cancel(): Promise<void> {
    await request.agent.remove(this.taskId);
  }

  private snapshot(status: string, progress: request.agent.Progress): AgentTaskSnapshot {
    const totalBytes: number = progress.sizes.length === 0 ? -1 : progress.sizes[0];
    return {
      taskId: this.taskId,
      status,
      receivedBytes: progress.processed,
      totalBytes,
      percent: percentForAgent(progress.processed, totalBytes)
    };
  }
}

class HarmonyRequestAgentClient implements RequestAgentClient {
  private readonly context: Context;

  constructor(context: Context) {
    this.context = context;
  }

  async create(input: RequestAgentSystemConfig): Promise<RequestAgentSystemTask> {
    const config: request.agent.Config = {
      action: request.agent.Action.DOWNLOAD,
      url: input.url,
      title: input.title,
      description: input.description,
      mode: request.agent.Mode.BACKGROUND,
      saveas: input.saveas,
      method: 'GET',
      headers: input.headers,
      gauge: input.gauge,
      notification: {
        title: input.title,
        text: '下载中',
        visibility: request.agent.Visibility.VISIBILITY_PROGRESS_AND_COMPLETION
      }
    };
    return new HarmonyRequestAgentTask(await request.agent.create(this.context, config));
  }

  async getTask(taskId: string): Promise<RequestAgentSystemTask | undefined> {
    try {
      return new HarmonyRequestAgentTask(await request.agent.getTask(this.context, taskId));
    } catch (_error) {
      return undefined;
    }
  }

  async search(): Promise<string[]> {
    return await request.agent.search({
      action: request.agent.Action.DOWNLOAD,
      mode: request.agent.Mode.BACKGROUND
    });
  }

  async show(taskId: string): Promise<AgentTaskSnapshot | undefined> {
    try {
      const task: request.agent.TaskInfo = await request.agent.show(taskId);
      const totalBytes: number = task.progress.sizes.length === 0 ? -1 : task.progress.sizes[0];
      return {
        taskId: task.tid,
        status: String(task.state),
        receivedBytes: task.progress.processed,
        totalBytes,
        percent: percentForAgent(task.progress.processed, totalBytes),
        description: task.description,
        savePath: task.saveas,
        error: task.reason
      };
    } catch (_error) {
      return undefined;
    }
  }
}

class GatewayTaskHandle implements AgentTaskHandle {
  readonly taskId: string;
  private readonly task: RequestAgentSystemTask;

  constructor(task: RequestAgentSystemTask) {
    this.task = task;
    this.taskId = task.taskId;
  }

  onProgress(listener: (snapshot: AgentTaskSnapshot) => void): void {
    this.task.on('progress', listener);
  }

  onCompleted(listener: (snapshot: AgentTaskSnapshot) => void): void {
    this.task.on('completed', listener);
  }

  onFailed(listener: (snapshot: AgentTaskSnapshot) => void): void {
    this.task.on('failed', listener);
  }

  async pause(): Promise<void> {
    await this.task.pause();
  }

  async resume(): Promise<void> {
    await this.task.resume();
  }

  async cancel(): Promise<void> {
    await this.task.cancel();
  }
}

export class RequestAgentGateway implements AgentDownloadPort {
  private readonly client: RequestAgentClient;

  constructor(context: Context, client: RequestAgentClient | undefined = undefined) {
    this.client = client ?? new HarmonyRequestAgentClient(context);
  }

  async create(input: AgentDownloadConfig): Promise<AgentTaskHandle> {
    const task: RequestAgentSystemTask = await this.client.create({
      action: 'DOWNLOAD',
      url: input.url,
      title: input.title,
      description: 'jianyue-download:' + input.reconcileKey,
      mode: 'BACKGROUND',
      saveas: input.savePath,
      method: 'GET',
      headers: input.headers,
      mimeType: input.mimeType,
      gauge: input.notificationEnabled
    });
    return new GatewayTaskHandle(task);
  }

  async getTask(taskId: string): Promise<AgentTaskHandle | undefined> {
    const task: RequestAgentSystemTask | undefined = await this.client.getTask(taskId);
    return task === undefined ? undefined : new GatewayTaskHandle(task);
  }

  async searchByPrefix(prefix: string): Promise<AgentTaskSnapshot[]> {
    const taskIds: string[] = await this.client.search();
    const snapshots: Array<AgentTaskSnapshot | undefined> = await Promise.all(
      taskIds.map((taskId: string) => this.show(taskId))
    );
    return snapshots.filter((snapshot: AgentTaskSnapshot | undefined): snapshot is AgentTaskSnapshot =>
      snapshot !== undefined && (snapshot.description ?? '').startsWith(prefix)
    );
  }

  async show(taskId: string): Promise<AgentTaskSnapshot | undefined> {
    return await this.client.show(taskId);
  }
}
