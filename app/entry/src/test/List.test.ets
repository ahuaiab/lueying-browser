import tabStoreTest from './ets/test/TabStore.test';
import gestureDecisionEngineTest from './ets/test/GestureDecisionEngine.test';
import webTabPoolTest from './ets/test/WebTabPool.test';
import browserCommandDispatcherTest from './ets/test/BrowserCommandDispatcher.test';
import browserTypesTest from './ets/test/BrowserTypes.test';
import tabSnapshotCacheTest from './ets/test/TabSnapshotCache.test';
import browserRepositoryTest from './ets/test/BrowserRepository.test';
import webCoordinatorTest from './ets/test/WebCoordinator.test';
import videoParityModelsTest from './ets/test/VideoParityModels.test';
import tabBarGestureGateTest from './ets/test/TabBarGestureGate.test';
import windowAvoidanceTest from './ets/test/WindowAvoidance.test';
import touchOwnershipTest from './ets/test/TouchOwnership.test';
import safariTabTransitionTest from './ets/test/SafariTabTransition.test';
import browserInteractionTest from './ets/test/BrowserInteraction.test';
import tabOverviewTransitionTest from './ets/test/TabOverviewTransition.test';
import downloadModelsTest from './ets/test/DownloadModels.test';
import downloadServiceTest from './ets/test/DownloadService.test';

export default function testsuite() {
  tabStoreTest();
  gestureDecisionEngineTest();
  webTabPoolTest();
  browserCommandDispatcherTest();
  browserTypesTest();
  tabSnapshotCacheTest();
  browserRepositoryTest();
  webCoordinatorTest();
  videoParityModelsTest();
  tabBarGestureGateTest();
  windowAvoidanceTest();
  touchOwnershipTest();
  safariTabTransitionTest();
  browserInteractionTest();
  tabOverviewTransitionTest();
  downloadModelsTest();
  downloadServiceTest();
}
