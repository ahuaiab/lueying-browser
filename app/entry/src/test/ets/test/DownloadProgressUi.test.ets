import { describe, expect, it } from '@ohos/hypium';
import {
  DownloadBackend,
  DownloadStatus,
  DownloadTaskRecord
} from '../../../main/ets/browser/model/DownloadModels';
import { selectDownloadProgressForTab } from '../../../main/ets/browser/components/BrowserShell';
import {
  addressSearchBarDownloadProps,
  addressLeadingActionVisibleFor,
  addressInputLeftPaddingFor,
  addressInputLayerOrder,
  downloadProgressRingProps
} from '../../../main/ets/browser/components/AddressSearchBar';
import {
  addressTabStripDownloadSnapshotForItem
} from '../../../main/ets/browser/components/AddressTabStrip';
import {
  bottomBrowserBarDownloadSnapshot
} from '../../../main/ets/browser/components/BottomBrowserBar';
import {
  addressLockImageVerticalOffsetFor
} from '../../../main/ets/browser/model/BrowserInteraction';

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

    it('propagates an active snapshot through the shared address path only', 0, () => {
      const shellSnapshot = selectDownloadProgressForTab([
        downloadTask('active', 'tab-1', 50, 65),
        downloadTask('inactive', 'tab-2', 60, 80)
      ], 'tab-1');
      const activeSnapshot = addressTabStripDownloadSnapshotForItem(shellSnapshot, 0, 0);
      const inactiveSnapshot = addressTabStripDownloadSnapshotForItem(shellSnapshot, 1, 0);
      const activeProps = addressSearchBarDownloadProps(activeSnapshot);
      const inactiveProps = addressSearchBarDownloadProps(inactiveSnapshot);

      expect(activeProps.downloadActive).assertTrue();
      expect(activeProps.downloadProgress).assertEqual(65);
      expect(inactiveProps.downloadActive).assertFalse();
      expect(inactiveProps.downloadProgress).assertEqual(0);
    });

    it('propagates the same active snapshot through BottomBrowserBar address path', 0, () => {
      const shellSnapshot = selectDownloadProgressForTab([
        downloadTask('active', 'tab-1', 50, 65)
      ], 'tab-1');
      const bottomSnapshot = bottomBrowserBarDownloadSnapshot(shellSnapshot);
      const activeSnapshot = addressTabStripDownloadSnapshotForItem(bottomSnapshot, 0, 0);
      const inactiveSnapshot = addressTabStripDownloadSnapshotForItem(bottomSnapshot, 1, 0);
      const activeProps = addressSearchBarDownloadProps(activeSnapshot);
      const inactiveProps = addressSearchBarDownloadProps(inactiveSnapshot);

      expect(bottomSnapshot === shellSnapshot).assertTrue();
      expect(activeProps.downloadActive).assertTrue();
      expect(activeProps.downloadProgress).assertEqual(65);
      expect(inactiveProps.downloadActive).assertFalse();
      expect(inactiveProps.downloadProgress).assertEqual(0);
    });

    it('preserves unknown progress through BottomBrowserBar address path', 0, () => {
      const shellSnapshot = selectDownloadProgressForTab([
        downloadTask('unknown', 'tab-1', 50, -1)
      ], 'tab-1');
      const searchProps = addressSearchBarDownloadProps(
        addressTabStripDownloadSnapshotForItem(
          bottomBrowserBarDownloadSnapshot(shellSnapshot),
          0,
          0
        )
      );

      expect(searchProps.downloadActive).assertTrue();
      expect(searchProps.downloadProgress).assertEqual(-1);
    });

    it('does not show a fake spinning ring when total size is unknown', 0, () => {
      const shellSnapshot = selectDownloadProgressForTab([
        downloadTask('unknown', 'tab-1', 50, -1)
      ], 'tab-1');
      const searchProps = addressSearchBarDownloadProps(
        addressTabStripDownloadSnapshotForItem(shellSnapshot, 0, 0)
      );
      const ringProps = downloadProgressRingProps(
        'address-input-tab-1',
        searchProps.downloadActive,
        searchProps.downloadProgress
      );

      expect(searchProps.downloadProgress).assertEqual(-1);
      expect(ringProps.visible).assertFalse();
      expect(ringProps.value).assertEqual(0);
      expect(ringProps.status).assertEqual('PROGRESSING');
    });

    it('keeps the ring outside the lock while preserving the button contract', 0, () => {
      const ringProps = downloadProgressRingProps('address-input-tab-1', true, 65);

      expect(ringProps.id).assertEqual('browser-download-progress-ring-address-input-tab-1');
      expect(ringProps.value).assertEqual(65);
      expect(ringProps.status).assertEqual('PROGRESSING');
      expect(ringProps.color).assertEqual('#1677FF');
      expect(ringProps.buttonSize).assertEqual(32);
      expect(ringProps.lockImageSize).assertEqual(20);
      expect(ringProps.size).assertEqual(28);
      expect(ringProps.strokeWidth).assertEqual(2);
      expect(ringProps.ringOffset).assertEqual(2);
      expect(ringProps.lockImageOffsetX).assertEqual(6);
      expect(ringProps.ringOffset < ringProps.lockImageOffsetX).assertTrue();
      expect(ringProps.ringOffset + ringProps.size >
        ringProps.lockImageOffsetX + ringProps.lockImageSize).assertTrue();
      expect(ringProps.ringOffset + ringProps.size / 2).assertEqual(
        ringProps.lockImageOffsetX + ringProps.lockImageSize / 2
      );
      expect(ringProps.ringOffset + ringProps.size / 2).assertEqual(
        addressLockImageVerticalOffsetFor(ringProps.buttonSize, ringProps.lockImageSize) +
          ringProps.lockImageSize / 2
      );
      expect(ringProps.size - ringProps.strokeWidth * 2 > ringProps.lockImageSize).assertTrue();
    });

    it('hides the leading icon whenever the address input is focused', 0, () => {
      expect(addressLeadingActionVisibleFor(false, true)).assertFalse();
    });

    it('keeps a small caret inset whenever the address input is focused', 0, () => {
      expect(addressInputLeftPaddingFor(false, true) > 0).assertTrue();
    });

    it('keeps the clear-button overlay narrow and above the editor surface', 0, () => {
      const layerOrder = addressInputLayerOrder();
      expect(layerOrder.clearButtonContainerWidth).assertEqual(32);
      expect(layerOrder.editor < layerOrder.clearButtonContainer).assertTrue();
      expect(layerOrder.clearButtonContainer < layerOrder.clearButton).assertTrue();
    });
  });
}
