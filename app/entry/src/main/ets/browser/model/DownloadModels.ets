export enum DownloadBackend {
  REQUEST_AGENT = 'request-agent',
  ARKWEB = 'arkweb'
}

export enum DownloadStatus {
  QUEUED = 'queued',
  HANDOFF_PENDING = 'handoff-pending',
  RUNNING = 'running',
  PAUSED = 'paused',
  COMPLETED = 'completed',
  FAILED = 'failed',
  CANCELLED = 'cancelled'
}

export interface DownloadTaskRecord {
  id: string;
  agentTaskId: string;
  reconcileKey: string;
  tabId: string;
  url: string;
  filename: string;
  backend: DownloadBackend;
  status: DownloadStatus;
  receivedBytes: number;
  totalBytes: number;
  percent: number;
  createdAt: number;
  updatedAt: number;
  isPrivate: boolean;
  mimeType?: string;
  error?: string;
}

export interface DownloadTaskPatch {
  agentTaskId?: string;
  reconcileKey?: string;
  tabId?: string;
  url?: string;
  filename?: string;
  backend?: DownloadBackend;
  receivedBytes?: number;
  totalBytes?: number;
  percent?: number;
  error?: string;
  mimeType?: string;
  isPrivate?: boolean;
}

export interface DownloadProgressSnapshot {
  id: string;
  tabId: string;
  status: DownloadStatus;
  receivedBytes: number;
  totalBytes: number;
  percent: number;
  filename: string;
  url: string;
}

export function classifyDownload(url: string, method: string, isPrivate: boolean): DownloadBackend {
  const normalizedUrl: string = url.trim().toLowerCase();
  const normalizedMethod: string = method.trim().toUpperCase();
  if (!isPrivate && normalizedMethod === 'GET' &&
    (normalizedUrl.startsWith('http://') || normalizedUrl.startsWith('https://'))) {
    return DownloadBackend.REQUEST_AGENT;
  }
  return DownloadBackend.ARKWEB;
}

export function percentForDownload(receivedBytes: number, totalBytes: number): number {
  if (totalBytes <= 0) {
    return -1;
  }
  return Math.min(100, Math.max(0, Math.floor(receivedBytes * 100 / totalBytes)));
}
