import { describe, expect, it } from '@ohos/hypium';
import {
  DownloadBackend,
  DownloadStatus,
  DownloadTaskRecord,
  classifyDownload,
  percentForDownload
} from '../../../main/ets/browser/model/DownloadModels';
import { DownloadRecordStorage, DownloadStore } from '../../../main/ets/browser/data/DownloadStore';

class MemoryDownloadStorage implements DownloadRecordStorage {
  records: DownloadTaskRecord[] = [];

  async load(): Promise<DownloadTaskRecord[]> {
    return this.records;
  }

  async save(records: DownloadTaskRecord[]): Promise<void> {
    this.records = records;
  }
}

function record(id: string, updatedAt: number, status: DownloadStatus = DownloadStatus.RUNNING): DownloadTaskRecord {
  return {
    id,
    agentTaskId: id,
    reconcileKey: `key-${id}`,
    tabId: 'tab-1',
    url: `https://example.com/${id}`,
    filename: `${id}.zip`,
    backend: DownloadBackend.REQUEST_AGENT,
    status,
    receivedBytes: 0,
    totalBytes: 100,
    percent: 0,
    createdAt: updatedAt,
    updatedAt,
    isPrivate: false
  };
}

export default function downloadModelsTest() {
  describe('DownloadModels', () => {
    it('routes only normal http get downloads to request agent', 0, () => {
      expect(classifyDownload('https://example.com/a.zip', 'GET', false))
        .assertEqual(DownloadBackend.REQUEST_AGENT);
      expect(classifyDownload('https://example.com/a.zip', 'GET', true))
        .assertEqual(DownloadBackend.ARKWEB);
      expect(classifyDownload('blob:https://example.com/id', 'GET', false))
        .assertEqual(DownloadBackend.ARKWEB);
    });

    it('uses indeterminate progress when total bytes are unknown', 0, () => {
      expect(percentForDownload(42, 0)).assertEqual(-1);
      expect(percentForDownload(50, 100)).assertEqual(50);
      expect(percentForDownload(120, 100)).assertEqual(100);
    });

    it('protects terminal records from later progress updates', 0, () => {
      const store = new DownloadStore(new MemoryDownloadStorage(), () => 20);
      store.begin(record('done', 10, DownloadStatus.COMPLETED));
      store.updateProgress('done', 80, 100);
      expect(store.snapshot()[0].receivedBytes).assertEqual(0);
      expect(store.snapshot()[0].status).assertEqual(DownloadStatus.COMPLETED);
    });

    it('merges recovered records by agent id and keeps the newer snapshot', 0, () => {
      const store = new DownloadStore(new MemoryDownloadStorage(), () => 30);
      store.begin(record('same', 10));
      const recovered: DownloadTaskRecord = record('same', 20);
      recovered.receivedBytes = 50;
      recovered.percent = 50;
      store.mergeRecovered(recovered);
      expect(store.snapshot().length).assertEqual(1);
      expect(store.snapshot()[0].receivedBytes).assertEqual(50);
    });

    it('returns the newest active task for a tab', 0, () => {
      const store = new DownloadStore(new MemoryDownloadStorage(), () => 30);
      store.begin(record('old', 10));
      store.begin(record('new', 20));
      expect(store.activeForTab('tab-1')?.id).assertEqual('new');
      store.transition('new', DownloadStatus.COMPLETED, {});
      expect(store.activeForTab('tab-1')?.id).assertEqual('old');
    });
  });
}
