import { describe, expect, it } from '@ohos/hypium';
import {
  DownloadBackend,
  DownloadStatus,
  DownloadTaskRecord
} from '../../../main/ets/browser/model/DownloadModels';
import {
  pageMenuActions,
  PageAction
} from '../../../main/ets/browser/model/PageActions';
import {
  DownloadManagerActionKind,
  downloadManagerActionKindFor,
  downloadManagerProgressLabel,
  downloadManagerStatusLabel,
  downloadManagerTaskId
} from '../../../main/ets/browser/components/DownloadManagerSheet';

function task(status: DownloadStatus, percent: number): DownloadTaskRecord {
  return {
    id: 'task-1',
    agentTaskId: 'agent-1',
    reconcileKey: 'task-1',
    tabId: 'tab-1',
    url: 'https://example.com/archive.zip',
    filename: 'archive.zip',
    backend: DownloadBackend.REQUEST_AGENT,
    status,
    receivedBytes: 25,
    totalBytes: 100,
    percent,
    createdAt: 1,
    updatedAt: 2,
    isPrivate: false
  };
}

export default function downloadManagerUiTest() {
  describe('DownloadManagerUi', () => {
    it('keeps download management in the shared page menu', 0, () => {
      const beforeReady: PageAction[] = pageMenuActions(false);
      const afterReady: PageAction[] = pageMenuActions(true);

      expect(beforeReady.length).assertEqual(1);
      expect(beforeReady[0]).assertEqual(PageAction.DOWNLOAD_MANAGER);
      expect(afterReady.length).assertEqual(2);
      expect(afterReady[0]).assertEqual(PageAction.DOWNLOAD_MANAGER);
      expect(afterReady[1]).assertEqual(PageAction.DESKTOP_SITE);
    });

    it('maps active and unknown-size tasks to readable progress', 0, () => {
      expect(downloadManagerStatusLabel(DownloadStatus.RUNNING)).assertEqual('正在下载');
      expect(downloadManagerProgressLabel(task(DownloadStatus.RUNNING, 25))).assertEqual('25%');
      expect(downloadManagerProgressLabel(task(DownloadStatus.RUNNING, -1))).assertEqual('正在下载');
      expect(downloadManagerActionKindFor(DownloadStatus.RUNNING)).assertEqual(
        DownloadManagerActionKind.PAUSE
      );
      expect(downloadManagerActionKindFor(DownloadStatus.PAUSED)).assertEqual(
        DownloadManagerActionKind.RESUME
      );
    });

    it('maps terminal states to the matching manager actions', 0, () => {
      expect(downloadManagerStatusLabel(DownloadStatus.COMPLETED)).assertEqual('已完成');
      expect(downloadManagerStatusLabel(DownloadStatus.FAILED)).assertEqual('下载失败');
      expect(downloadManagerStatusLabel(DownloadStatus.CANCELLED)).assertEqual('已取消');
      expect(downloadManagerActionKindFor(DownloadStatus.FAILED)).assertEqual(
        DownloadManagerActionKind.RETRY
      );
      expect(downloadManagerActionKindFor(DownloadStatus.COMPLETED)).assertEqual(
        DownloadManagerActionKind.NONE
      );
      expect(downloadManagerTaskId('task-1')).assertEqual('download-task-task-1');
    });
  });
}
