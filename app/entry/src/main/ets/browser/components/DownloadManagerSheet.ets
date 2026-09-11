import { curves } from '@kit.ArkUI';
import {
  DownloadBackend,
  DownloadStatus,
  DownloadTaskRecord
} from '../model/DownloadModels';
import {
  HARMONY_RADIUS_COMPACT,
  HARMONY_RADIUS_CARD,
  HARMONY_RADIUS_SHEET,
  LIBRARY_CONTENT_WIDTH_PERCENT
} from '../model/BrowserVisualMetrics';
import { LIBRARY_SHEET_HEIGHT_PERCENT } from '../model/LibraryModels';

export enum DownloadManagerActionKind {
  NONE = 'none',
  PAUSE = 'pause',
  RESUME = 'resume',
  RETRY = 'retry'
}

export function downloadManagerTaskId(id: string): string {
  return `download-task-${id}`;
}

export function downloadManagerStatusLabel(status: DownloadStatus): string {
  if (status === DownloadStatus.QUEUED || status === DownloadStatus.HANDOFF_PENDING ||
    status === DownloadStatus.RUNNING) {
    return '正在下载';
  }
  if (status === DownloadStatus.PAUSED) {
    return '已暂停';
  }
  if (status === DownloadStatus.COMPLETED) {
    return '已完成';
  }
  if (status === DownloadStatus.FAILED) {
    return '下载失败';
  }
  return '已取消';
}

export function downloadManagerProgressLabel(task: DownloadTaskRecord): string {
  if (task.status === DownloadStatus.COMPLETED) {
    return '已完成';
  }
  if (task.status === DownloadStatus.FAILED) {
    return '下载失败';
  }
  if (task.status === DownloadStatus.CANCELLED) {
    return '已取消';
  }
  if (task.percent < 0) {
    return '正在下载';
  }
  return `${Math.max(0, Math.min(100, Math.trunc(task.percent)))}%`;
}

export function downloadManagerActionKindFor(status: DownloadStatus): DownloadManagerActionKind {
  if (status === DownloadStatus.RUNNING) {
    return DownloadManagerActionKind.PAUSE;
  }
  if (status === DownloadStatus.PAUSED) {
    return DownloadManagerActionKind.RESUME;
  }
  if (status === DownloadStatus.FAILED) {
    return DownloadManagerActionKind.RETRY;
  }
  return DownloadManagerActionKind.NONE;
}

export function downloadManagerCancelVisibleFor(status: DownloadStatus): boolean {
  return status === DownloadStatus.QUEUED || status === DownloadStatus.HANDOFF_PENDING ||
    status === DownloadStatus.RUNNING || status === DownloadStatus.PAUSED;
}

function downloadManagerProgressValueFor(task: DownloadTaskRecord): number {
  if (task.percent < 0) {
    return 0;
  }
  return Math.max(0, Math.min(100, Math.trunc(task.percent)));
}

function formatDownloadBytes(bytes: number): string {
  if (bytes < 1024) {
    return `${Math.max(0, Math.trunc(bytes))} B`;
  }
  if (bytes < 1024 * 1024) {
    return `${(bytes / 1024).toFixed(1)} KB`;
  }
  if (bytes < 1024 * 1024 * 1024) {
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
}

function compactError(error: string): string {
  return error.replace(/\s+/g, ' ').trim().slice(0, 80);
}

function downloadManagerDetailLabel(task: DownloadTaskRecord): string {
  if (task.status === DownloadStatus.COMPLETED) {
    return '已保存到应用下载目录';
  }
  if (task.status === DownloadStatus.FAILED && task.error !== undefined && task.error.length > 0) {
    return compactError(task.error);
  }
  if (task.backend === DownloadBackend.ARKWEB) {
    return task.isPrivate ? '隐私下载仅在应用存活期间继续' : '网页下载；应用退出后不会恢复';
  }
  if (task.totalBytes > 0) {
    return `${formatDownloadBytes(task.receivedBytes)} / ${formatDownloadBytes(task.totalBytes)}`;
  }
  return '系统后台下载';
}

@ComponentV2
export struct DownloadManagerSheet {
  @Param tasks: DownloadTaskRecord[] = [];
  @Param topInset: number = 0;
  @Param bottomInset: number = 0;
  @Param onClose: () => void = () => undefined;
  @Param onPause: (id: string) => void = (_id: string) => undefined;
  @Param onResume: (id: string) => void = (_id: string) => undefined;
  @Param onCancel: (id: string) => void = (_id: string) => undefined;
  @Param onRetry: (id: string) => void = (_id: string) => undefined;

  @Local sheetSwipeOffset: number = 0;
  @Local sheetGestureActive: boolean = false;
  private sheetAnimationToken: number = 0;

  private safeBottomInset(): number {
    return Math.max(16, this.bottomInset);
  }

  private topContentInset(): number {
    return Math.max(8, Math.min(this.topInset, 12));
  }

  private beginSheetSwipe(): void {
    this.sheetGestureActive = true;
    this.sheetAnimationToken += 1;
  }

  private updateSheetSwipe(event?: GestureEvent): void {
    if (!this.sheetGestureActive) {
      return;
    }
    this.sheetSwipeOffset = Math.max(0, Math.min(240, event?.offsetY ?? 0));
  }

  private finishSheetSwipe(event?: GestureEvent): void {
    if (!this.sheetGestureActive) {
      return;
    }
    const offset: number = Math.max(0, this.sheetSwipeOffset > 0
      ? this.sheetSwipeOffset
      : (event?.offsetY ?? 0));
    this.sheetGestureActive = false;
    const token: number = this.sheetAnimationToken + 1;
    this.sheetAnimationToken = token;
    if (offset >= 120) {
      this.getUIContext().animateTo({
        curve: curves.springMotion(),
        onFinish: () => {
          if (token === this.sheetAnimationToken) {
            this.sheetSwipeOffset = 0;
            this.onClose();
          }
        }
      }, () => {
        this.sheetSwipeOffset = 240;
      });
      return;
    }
    this.getUIContext().animateTo({ curve: curves.springMotion() }, () => {
      this.sheetSwipeOffset = 0;
    });
  }

  private cancelSheetSwipe(): void {
    if (!this.sheetGestureActive && this.sheetSwipeOffset === 0) {
      return;
    }
    this.sheetGestureActive = false;
    this.sheetAnimationToken += 1;
    this.getUIContext().animateTo({ curve: curves.springMotion() }, () => {
      this.sheetSwipeOffset = 0;
    });
  }

  @Builder
  private actionButton(id: string, label: string, onClick: () => void) {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Text(label)
        .fontSize(13)
        .fontColor('#007AFF');
    }
      .id(id)
      .height(32)
      .padding({ left: 12, right: 12 })
      .backgroundColor('#EAF2FF')
      .borderRadius(HARMONY_RADIUS_CARD)
      .stateEffect(false)
      .onClick(onClick);
  }

  @Builder
  private taskActions(task: DownloadTaskRecord) {
    Row({ space: 8 }) {
      if (downloadManagerActionKindFor(task.status) === DownloadManagerActionKind.PAUSE &&
        task.backend === DownloadBackend.REQUEST_AGENT) {
        this.actionButton(`download-task-pause-${task.id}`, '暂停', () => this.onPause(task.id));
      } else if (downloadManagerActionKindFor(task.status) === DownloadManagerActionKind.RESUME &&
        task.backend === DownloadBackend.REQUEST_AGENT) {
        this.actionButton(`download-task-resume-${task.id}`, '继续', () => this.onResume(task.id));
      } else if (downloadManagerActionKindFor(task.status) === DownloadManagerActionKind.RETRY) {
        this.actionButton(`download-task-retry-${task.id}`, '重试', () => this.onRetry(task.id));
      }
      if (downloadManagerCancelVisibleFor(task.status)) {
        this.actionButton(`download-task-cancel-${task.id}`, '取消', () => this.onCancel(task.id));
      }
    }
      .width('100%')
      .justifyContent(FlexAlign.End);
  }

  @Builder
  private taskRow(task: DownloadTaskRecord) {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        Stack({ alignContent: Alignment.Center }) {
          Text(task.status === DownloadStatus.COMPLETED ? '✓' : '↓')
            .fontSize(20)
            .fontColor(task.status === DownloadStatus.FAILED ? '#FF3B30' : '#007AFF');
        }
          .width(32)
          .height(32)
          .backgroundColor('#EEF5FF')
          .borderRadius(HARMONY_RADIUS_COMPACT);
        Column({ space: 3 }) {
          Text(task.filename.length > 0 ? task.filename : '下载文件')
            .fontSize(15)
            .fontColor('#1D1D1F')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%');
          Text(downloadManagerStatusLabel(task.status))
            .fontSize(12)
            .fontColor(task.status === DownloadStatus.FAILED ? '#FF3B30' : '#6B7280');
        }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start);
        Text(downloadManagerProgressLabel(task))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1D1D1F');
      }
        .width('100%');

      if (task.status === DownloadStatus.QUEUED || task.status === DownloadStatus.HANDOFF_PENDING ||
        task.status === DownloadStatus.RUNNING || task.status === DownloadStatus.PAUSED) {
        Progress({
          value: downloadManagerProgressValueFor(task),
          total: 100,
          type: ProgressType.Linear
        })
          .id(`download-task-progress-${task.id}`)
          .width('100%')
          .height(4)
          .color('#1677FF')
      }

      Text(downloadManagerDetailLabel(task))
        .fontSize(12)
        .fontColor('#8A8A90')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%');
      this.taskActions(task);
      Row()
        .width('100%')
        .height(1)
        .backgroundColor('#E5E5EA');
    }
      .id(downloadManagerTaskId(task.id))
      .width('100%')
      .padding({ top: 12, bottom: 12 });
  }

  @Builder
  private emptyState() {
    Column({ space: 8 }) {
      Text('暂无下载')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#1D1D1F');
      Text('网页下载完成后会显示在这里')
        .fontSize(14)
        .fontColor('#8A8A90');
    }
      .id('download-manager-empty-state')
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center);
  }

  build() {
    Column() {
      Column() {
        Blank()
          .width('100%')
          .height('100%');
      }
        .id('download-manager-backdrop')
        .width('100%')
        .layoutWeight(1)
        .onClick(() => this.onClose());

      Column() {
        Blank()
          .width('100%')
          .height(this.topContentInset());
        Row() {
          Text('下载管理')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1D1D1F')
            .layoutWeight(1)
            .textAlign(TextAlign.Center);
          Button({ type: ButtonType.Normal, stateEffect: false }) {
            Text('×')
              .fontSize(24)
              .fontColor('#6B7280');
          }
            .id('download-manager-close-button')
            .width(44)
            .height(44)
            .padding(0)
            .backgroundColor(Color.Transparent)
            .stateEffect(false)
            .onClick(() => this.onClose());
        }
          .id('download-manager-header')
          .width(`${LIBRARY_CONTENT_WIDTH_PERCENT}%`)
          .alignSelf(ItemAlign.Center)
          .height(52)
          .padding({ left: 0, right: 0 });

        if (this.tasks.length === 0) {
          this.emptyState();
        } else {
          Scroll() {
            Column() {
              ForEach(this.tasks, (task: DownloadTaskRecord) => {
                this.taskRow(task);
              }, (task: DownloadTaskRecord) => task.id);
            }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Start)
              .alignItems(HorizontalAlign.Start);
          }
            .id('download-manager-task-scroll')
            .width(`${LIBRARY_CONTENT_WIDTH_PERCENT}%`)
            .alignSelf(ItemAlign.Center)
            .layoutWeight(1)
            .scrollBar(BarState.Off);
        }

        Blank()
          .id('download-manager-footer-spacer')
          .width('100%')
          .height(this.safeBottomInset());
      }
        .id('download-manager-sheet')
        .width('100%')
        .height(`${LIBRARY_SHEET_HEIGHT_PERCENT}%`)
        .backgroundColor(Color.White)
        .borderRadius({ topLeft: HARMONY_RADIUS_SHEET, topRight: HARMONY_RADIUS_SHEET })
        .shadow({ radius: 12, color: '#55000000', offsetX: 0, offsetY: -3 })
        .clip(true)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        .translate({ x: 0, y: this.sheetSwipeOffset })
        .opacity(1 - Math.min(0.22, this.sheetSwipeOffset / 240 * 0.22))
        .parallelGesture(
          PanGesture({ direction: PanDirection.Vertical, distance: 8 })
            .onActionStart(() => this.beginSheetSwipe())
            .onActionUpdate((event: GestureEvent | undefined) => this.updateSheetSwipe(event))
            .onActionEnd((event: GestureEvent | undefined) => this.finishSheetSwipe(event))
            .onActionCancel(() => this.cancelSheetSwipe())
        );
    }
      .id('download-manager-overlay')
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent);
  }
}
