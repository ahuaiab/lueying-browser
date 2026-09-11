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

export enum AgentTaskStatus {
  RUNNING = 'RUNNING',
  COMPLETED = 'COMPLETED',
  FAILED = 'FAILED',
  PAUSED = 'PAUSED',
  CANCELLED = 'CANCELLED'
}

export interface AgentTaskSnapshot {
  taskId: string;
  status: AgentTaskStatus;
  receivedBytes: number;
  totalBytes: number;
  percent: number;
  description?: string;
  savePath?: string;
  error?: string;
}

/**
 * Converts the numeric request.agent.State enum to the service's stable
 * status vocabulary. The string branch keeps the adapter tolerant of enum
 * names returned by test doubles or platform bridges.
 */
export function canonicalAgentStatus(
  state: request.agent.State | number | string,
  fallback: AgentTaskStatus = AgentTaskStatus.RUNNING
): AgentTaskStatus {
  const normalized: string = String(state).trim().toUpperCase();
  if (normalized.endsWith('COMPLETED')) return AgentTaskStatus.COMPLETED;
  if (normalized.endsWith('FAILED')) return AgentTaskStatus.FAILED;
  if (normalized.endsWith('PAUSED')) return AgentTaskStatus.PAUSED;
  if (normalized.endsWith('STOPPED') || normalized.endsWith('CANCELLED') || normalized.endsWith('CANCELED') ||
    normalized.endsWith('REMOVED')) return AgentTaskStatus.CANCELLED;
  if (normalized.endsWith('RUNNING') || normalized.endsWith('RETRYING') || normalized.endsWith('WAITING') ||
    normalized.endsWith('INITIALIZED')) return AgentTaskStatus.RUNNING;

  switch (Number(state)) {
    case 0x40:
      return AgentTaskStatus.COMPLETED;
    case 0x41:
      return AgentTaskStatus.FAILED;
    case 0x30:
      return AgentTaskStatus.PAUSED;
    case 0x31:
    case 0x50:
      return AgentTaskStatus.CANCELLED;
    case 0x00:
    case 0x10:
    case 0x20:
    case 0x21:
      return AgentTaskStatus.RUNNING;
    default:
      return fallback;
  }
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
  search(): Promise<AgentTaskSnapshot[]>;
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
      this.task.on('progress', (progress: request.agent.Progress) => listener(this.snapshot(progress)));
    } else if (event === 'completed') {
      this.task.on('completed', (progress: request.agent.Progress) =>
        listener(this.snapshot(progress, AgentTaskStatus.COMPLETED)));
    } else if (event === 'failed') {
      this.task.on('failed', (progress: request.agent.Progress) =>
        listener(this.snapshot(progress, AgentTaskStatus.FAILED)));
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

  private snapshot(progress: request.agent.Progress, fallback: AgentTaskStatus = AgentTaskStatus.RUNNING): AgentTaskSnapshot {
    const totalBytes: number = progress.sizes.length === 0 ? -1 : progress.sizes[0];
    return {
      taskId: this.taskId,
      status: canonicalAgentStatus(progress.state, fallback),
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
        visibility: request.agent.VISIBILITY_COMPLETION | request.agent.VISIBILITY_PROGRESS
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

  async search(): Promise<AgentTaskSnapshot[]> {
    const taskIds: string[] = await request.agent.search({
      action: request.agent.Action.DOWNLOAD,
      mode: request.agent.Mode.BACKGROUND
    });
    const snapshots: Array<AgentTaskSnapshot | undefined> = await Promise.all(taskIds.map(
      (taskId: string): Promise<AgentTaskSnapshot | undefined> => this.show(taskId)
    ));
    const available: AgentTaskSnapshot[] = [];
    for (const snapshot of snapshots) {
      if (snapshot !== undefined) {
        available.push(snapshot);
      }
    }
    return available;
  }

  async show(taskId: string): Promise<AgentTaskSnapshot | undefined> {
    try {
      const task: request.agent.TaskInfo = await request.agent.show(taskId);
      return this.snapshotForTaskInfo(task);
    } catch (_error) {
      return undefined;
    }
  }

  private snapshotForTaskInfo(task: request.agent.TaskInfo): AgentTaskSnapshot {
    const totalBytes: number = task.progress.sizes.length === 0 ? -1 : task.progress.sizes[0];
    return {
      taskId: task.tid,
      status: canonicalAgentStatus(task.progress.state),
      receivedBytes: task.progress.processed,
      totalBytes,
      percent: percentForAgent(task.progress.processed, totalBytes),
      description: task.description,
      savePath: task.saveas,
      error: task.reason
    };
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
    const snapshots: AgentTaskSnapshot[] = await this.client.search();
    return snapshots.filter((snapshot: AgentTaskSnapshot): boolean =>
      (snapshot.description ?? '').startsWith(prefix)
    );
  }

  async show(taskId: string): Promise<AgentTaskSnapshot | undefined> {
    return await this.client.show(taskId);
  }
}
