import { describe, expect, it } from '@ohos/hypium';
import {
  DownloadBackend,
  DownloadStatus,
  DownloadTaskRecord
} from '../../../main/ets/browser/model/DownloadModels';
import { selectDownloadProgressForTab } from '../../../main/ets/browser/components/BrowserShell';

function downloadTask(
  id: string,
  tabId: string,
  updatedAt: number,
  percent: number,
  status: DownloadStatus = DownloadStatus.RUNNING
): DownloadTaskRecord {
  return {
    id,
    agentTaskId: id,
    reconcileKey: `key-${id}`,
    tabId,
    url: `https://example.com/${id}`,
    filename: `${id}.zip`,
    backend: DownloadBackend.REQUEST_AGENT,
    status,
    receivedBytes: percent < 0 ? 20 : percent,
    totalBytes: percent < 0 ? 0 : 100,
    percent,
    createdAt: updatedAt,
    updatedAt,
    isPrivate: false
  };
}

export default function downloadProgressUiTest() {
  describe('DownloadProgressUi', () => {
    it('shows the newest active task percent for its tab', 0, () => {
      const progress = selectDownloadProgressForTab([
        downloadTask('older', 'tab-1', 10, 20),
        downloadTask('newer', 'tab-1', 20, 65)
      ], 'tab-1');

      expect(progress?.id).assertEqual('newer');
      expect(progress?.percent).assertEqual(65);
    });

    it('keeps an active unknown-size task indeterminate', 0, () => {
      const progress = selectDownloadProgressForTab([
        downloadTask('unknown', 'tab-1', 20, -1)
      ], 'tab-1');

      expect(progress?.percent).assertEqual(-1);
    });

    it('hides terminal and other-tab downloads from the current address bar', 0, () => {
      const progress = selectDownloadProgressForTab([
        downloadTask('complete', 'tab-1', 30, 100, DownloadStatus.COMPLETED),
        downloadTask('other-tab', 'tab-2', 40, 50)
      ], 'tab-1');

      expect(progress === undefined).assertTrue();
    });
  });
}
