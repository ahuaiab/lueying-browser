import tabStoreTest from './TabStore.test';
import videoParityModelsTest from './VideoParityModels.test';
import safariTabTransitionTest from './SafariTabTransition.test';
import downloadAgentPortsTest from './DownloadAgentPorts.test';

export default function testsuite() {
  tabStoreTest();
  videoParityModelsTest();
  safariTabTransitionTest();
  downloadAgentPortsTest();
}
