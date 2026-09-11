export interface BrowserDownloadRequest {
  url: string;
  suggestedFileName: string;
  mimeType: string;
  isPrivate: boolean;
}

export interface SavePickerPort {
  chooseDestination(fileName: string): Promise<string | undefined>;
}

export interface DownloadStartPort {
  start(request: BrowserDownloadRequest, destination: string): Promise<boolean>;
}

export interface DownloadStatusPort {
  update(request: BrowserDownloadRequest, status: string): void;
}

export function sanitizeDownloadFileName(value: string): string {
  const sanitized: string = value
    .replace(/[\\/:*?"<>|]/g, '_')
    .replace(/[\u0000-\u001F]/g, '')
    .trim();
  return sanitized.length === 0 ? 'download' : sanitized.slice(0, 120);
}

/** Coordinates the safe ordering: picker first, ArkWeb start second. */
export class DownloadCoordinator {
  private readonly picker: SavePickerPort;
  private readonly starter: DownloadStartPort;
  private readonly status: DownloadStatusPort | undefined;

  constructor(picker: SavePickerPort, starter: DownloadStartPort, status: DownloadStatusPort | undefined = undefined) {
    this.picker = picker;
    this.starter = starter;
    this.status = status;
  }

  async handle(request: BrowserDownloadRequest): Promise<boolean> {
    const fileName: string = sanitizeDownloadFileName(request.suggestedFileName);
    const destination: string | undefined = await this.picker.chooseDestination(fileName);
    if (destination === undefined || destination.length === 0) {
      this.status?.update(request, 'cancelled');
      return false;
    }
    this.status?.update(request, 'starting');
    try {
      const started: boolean = await this.starter.start(request, destination);
      this.status?.update(request, started ? 'started' : 'failed');
      return started;
    } catch (_error) {
      this.status?.update(request, 'failed');
      return false;
    }
  }
}
