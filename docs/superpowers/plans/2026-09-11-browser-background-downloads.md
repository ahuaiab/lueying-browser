# 简悦浏览器下载与下载管理实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为简悦浏览器实现网页下载、系统级双后台续传、锁外蓝色进度环、下载管理面板和长按菜单入口。

**Architecture:** ArkWeb 负责发现下载和提供网页上下文；普通非隐私 HTTP(S) GET 下载转交 request.agent 后台任务，隐私或无法表达的资源回退 ArkWeb 原生路径。两条后端通过 DownloadStore 统一状态、持久化和 UI 快照，BrowserShell 只编排生命周期，地址栏和下载管理面板只消费只读快照。

**Tech Stack:** HarmonyOS 26、ArkTS/ArkUI、ArkWeb WebDownloadDelegate、@kit.BasicServicesKit request.agent、@ohos.data.preferences、Hypium、devecocli。

**Spec:** docs/superpowers/specs/2026-09-11-browser-downloads-design.md

## Global Constraints

- 目标 SDK 和兼容 SDK 固定为 26.0.0，使用 stageMode 工程配置。
- 普通非隐私 http/https GET 下载必须走 request.agent BACKGROUND，以满足应用后台和进程被杀后的继续执行。
- 隐私下载、blob:、data:、自定义 scheme、无法提供请求体的 POST 下载只走 ArkWeb 原生路径，不复制 Cookie 到系统后台任务，也不宣称进程被杀后可恢复。
- 只保留 ohos.permission.INTERNET；不声明 ohos.permission.NOTIFICATION_CONTROLLER 或 ohos.permission.KEEP_BACKGROUND_RUNNING。
- 通知授权只能在 UI 加载完成后调用 notificationManager.requestEnableNotification(context)；拒绝通知不得阻塞下载。
- 地址栏进度环必须与锁图标共圆心，不改变地址胶囊横向内边距、锁按钮命中区域或底栏安全区。
- 任务元数据不持久化 Cookie、Authorization 或请求头；系统任务以 reconcileKey 去重，恢复失败不得自动创建第二个下载。
- 每个实现任务遵循 TDD：先添加会失败的测试，再写最小生产实现，再运行通过验证，最后单独提交。
- 所有 HarmonyOS 构建、设备、模拟器和 UI 检查使用 devecocli；环境变量使用 DEVECO_HOME=C:\PROGRA~1\Huawei\DEVECO~1。
- ArkTS Local Test 使用 D:\.codex\skills\hmos-local-test\scripts\run_local_test.py；每个测试任务在步骤中传入对应的 suite 名，devecocli build 只作为编译门禁。
- 构建得到的 HAP 继续保存到根目录 hap，名称使用 YYYYMMDD-HHmmss-entry-debug.hap。
- 保留当前工作区已有的 README.md 修改和未跟踪的 LICENSE，不将它们加入本功能提交。

---

## 文件结构与职责

### 新增文件

- app/entry/src/main/ets/browser/model/DownloadModels.ets：下载后端、状态、任务记录、进度快照和纯路由/百分比函数。
- app/entry/src/main/ets/browser/data/DownloadStore.ets：状态迁移、终态保护、任务去重和持久化适配器。
- app/entry/src/main/ets/browser/web/RequestAgentGateway.ets：把 request.agent 封装成可测试的后台下载端口。
- app/entry/src/main/ets/browser/web/DownloadNotificationGateway.ets：通知授权的幂等网关。
- app/entry/src/main/ets/browser/web/DownloadService.ets：ArkWeb 下载项到系统后台任务/原生回退路径的编排器。
- app/entry/src/main/ets/browser/components/DownloadManagerSheet.ets：下载管理底部面板。
- app/entry/src/test/ets/test/DownloadModels.test.ets：状态模型和仓库纯逻辑测试。
- app/entry/src/test/ets/test/DownloadService.test.ets：下载路由、Cookie 传递、转交顺序和恢复去重测试。
- app/entry/src/ohosTest/ets/test/DownloadManagerUi.test.ets：菜单、面板和进度环的设备 UI 测试。

### 修改文件

- app/entry/src/main/ets/browser/web/WebTabNode.ets：把下载委托回调扩展为带私有状态和进度的 WebDownloadHandler。
- app/entry/src/main/ets/browser/model/PageActions.ets：增加 DOWNLOAD_MANAGER，调整长按菜单动作列表。
- app/entry/src/main/ets/browser/components/AddressSearchBar.ets：增加下载管理菜单项和锁外蓝色环形进度。
- app/entry/src/main/ets/browser/components/AddressTabStrip.ets：把活动 Tab 的下载进度传入地址栏。
- app/entry/src/main/ets/browser/components/BottomBrowserBar.ets：透传进度快照到地址胶囊。
- app/entry/src/main/ets/browser/components/BrowserShell.ets：创建服务、恢复任务、请求通知、处理菜单动作、挂载面板并绑定快照。
- app/entry/src/test/List.test.ets：注册新增纯逻辑测试套件。
- app/entry/src/ohosTest/ets/test/List.test.ets：注册设备 UI 测试套件。

不修改 app/entry/src/main/module.json5 的权限列表；实现完成后只验证其中保留 ohos.permission.INTERNET。

---

### Task 1: 建立下载状态模型和可持久化仓库

**Files:**
- Create: app/entry/src/main/ets/browser/model/DownloadModels.ets
- Create: app/entry/src/main/ets/browser/data/DownloadStore.ets
- Test: app/entry/src/test/ets/test/DownloadModels.test.ets
- Modify: app/entry/src/test/List.test.ets

**Interfaces:**
- Produces DownloadBackend、DownloadStatus、DownloadTaskRecord、DownloadTaskPatch、DownloadProgressSnapshot。
- Produces classifyDownload(url: string, method: string, isPrivate: boolean): DownloadBackend。
- Produces percentForDownload(receivedBytes: number, totalBytes: number): number，未知总大小返回 -1。
- Produces DownloadRecordStorage.load(): Promise<DownloadTaskRecord[]> and save(records: DownloadTaskRecord[]): Promise<void>。
- Produces DownloadStore.restore(): Promise<void>, begin(task: DownloadTaskRecord): void, updateProgress(id: string, receivedBytes: number, totalBytes: number): void, patch(id: string, patch: DownloadTaskPatch): void, transition(id: string, status: DownloadStatus, patch: DownloadTaskPatch): void, mergeRecovered(task: DownloadTaskRecord): void, remove(id: string): void, snapshot(): DownloadTaskRecord[] and activeForTab(tabId: string): DownloadProgressSnapshot | undefined。

- [ ] Step 1: Write failing model tests.

~~~ts
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
~~~

- [ ] Step 2: Run the test target and verify the new exports fail.

Run from E:\OneDrive\HarmonyOS\jianyue-browser\app:

~~~cmd
set DEVECO_HOME=C:\PROGRA~1\Huawei\DEVECO~1
devecocli build --modules entry@ohosTest --build-mode debug
~~~

Expected: FAIL because DownloadModels.ets and its exports do not exist yet.

Run the failing suite:

~~~cmd
python D:\.codex\skills\hmos-local-test\scripts\run_local_test.py --project-path E:\OneDrive\HarmonyOS\jianyue-browser\.superpowers\worktrees\browser-downloads\app --module entry --no-coverage --scope DownloadModels
~~~

- [ ] Step 3: Implement the pure model.

Use this exact routing rule:

~~~ts
export function classifyDownload(url: string, method: string, isPrivate: boolean): DownloadBackend {
  const normalizedUrl: string = url.trim().toLowerCase();
  const normalizedMethod: string = method.trim().toUpperCase();
  if (!isPrivate && normalizedMethod === 'GET' &&
    (normalizedUrl.startsWith('http://') || normalizedUrl.startsWith('https://'))) {
    return DownloadBackend.REQUEST_AGENT;
  }
  return DownloadBackend.ARKWEB;
}
~~~

DownloadStatus must include QUEUED、HANDOFF_PENDING、RUNNING、PAUSED、COMPLETED、FAILED、CANCELLED；DownloadTaskRecord.percent uses -1 for unknown totals.

- [ ] Step 4: Implement DownloadStore with terminal-state protection.

Store all records as one JSON array through DownloadRecordStorage. updateProgress ignores missing IDs and records already in COMPLETED, FAILED, or CANCELLED. mergeRecovered merges by agentTaskId, then by reconcileKey, and retains the newer updatedAt snapshot. activeForTab returns the newest non-terminal task for the requested Tab.

- [ ] Step 5: Run the model test target again.

~~~cmd
set DEVECO_HOME=C:\PROGRA~1\Huawei\DEVECO~1
devecocli build --modules entry@ohosTest --build-mode debug
~~~

Expected: PASS for the new model test compilation and no regression in existing suites.

Run the passing suite with the same command and require a successful JSON result with zero failed cases:

~~~cmd
python D:\.codex\skills\hmos-local-test\scripts\run_local_test.py --project-path E:\OneDrive\HarmonyOS\jianyue-browser\.superpowers\worktrees\browser-downloads\app --module entry --no-coverage --scope DownloadModels
~~~

- [ ] Step 6: Commit the self-contained model change.

~~~cmd
git add app/entry/src/main/ets/browser/model/DownloadModels.ets app/entry/src/main/ets/browser/data/DownloadStore.ets app/entry/src/test/ets/test/DownloadModels.test.ets app/entry/src/test/List.test.ets
git commit -m download-model-store
~~~

### Task 2: 封装系统后台下载和通知授权

**Files:**
- Create: app/entry/src/main/ets/browser/web/RequestAgentGateway.ets
- Create: app/entry/src/main/ets/browser/web/DownloadNotificationGateway.ets
- Create: app/entry/src/test/ets/test/DownloadAgentPorts.test.ets
- Modify: app/entry/src/test/List.test.ets

**Interfaces:**
- Produces AgentDownloadConfig、AgentTaskSnapshot、AgentTaskHandle and AgentDownloadPort。
- AgentDownloadConfig contains reconcileKey、url、savePath、title、description、headers、mimeType and notificationEnabled。
- AgentTaskHandle exposes taskId: string, onProgress(listener: (snapshot: AgentTaskSnapshot) => void): void, onCompleted(listener: (snapshot: AgentTaskSnapshot) => void): void, onFailed(listener: (snapshot: AgentTaskSnapshot) => void): void, pause(): Promise<void>, resume(): Promise<void> and cancel(): Promise<void>。
- AgentDownloadPort exposes create(config: AgentDownloadConfig): Promise<AgentTaskHandle>, getTask(taskId: string): Promise<AgentTaskHandle | undefined>, searchByPrefix(prefix: string): Promise<AgentTaskSnapshot[]> and show(taskId: string): Promise<AgentTaskSnapshot | undefined>。
- Produces NotificationPermissionPort.requestOnce(): Promise<boolean> and its NotificationPermissionGateway implementation.

- [ ] Step 1: Add failing fake-gateway tests.

Test that a created task uses BACKGROUND download mode, app-private savePath, a reconcileKey in the description, progress/completion callback forwarding, and no persisted Cookie. Test that notification request is called at most once and a rejected request resolves false without throwing.

- [ ] Step 2: Run the failing gateway target.

~~~cmd
set DEVECO_HOME=C:\PROGRA~1\Huawei\DEVECO~1
devecocli build --modules entry@ohosTest --build-mode debug
~~~

Expected: FAIL because the gateway interfaces and adapters do not exist.

- [ ] Step 3: Implement RequestAgentGateway.

Import request from @kit.BasicServicesKit and map the system configuration:

~~~ts
const config: request.agent.Config = {
  action: request.agent.Action.DOWNLOAD,
  url: input.url,
  title: input.title,
  description: 'jianyue-download:' + input.reconcileKey,
  mode: request.agent.Mode.BACKGROUND,
  saveas: input.savePath,
  method: 'GET',
  headers: input.headers,
  gauge: true,
  notification: {
    title: input.title,
    text: '下载中',
    visibility: request.agent.Visibility.VISIBILITY_PROGRESS_AND_COMPLETION
  }
};
~~~

Map task progress、completed and failed events to AgentTaskHandle, and use getTask/search/show during recovery. Never log the headers object.

- [ ] Step 4: Implement DownloadNotificationGateway.

Call notificationManager.requestEnableNotification(context) only from requestOnce, cache the in-flight Promise and final result, and return false when the platform call rejects. Do not add a manifest notification permission.

- [ ] Step 5: Run gateway tests and lint.

~~~cmd
set DEVECO_HOME=C:\PROGRA~1\Huawei\DEVECO~1
devecocli build --modules entry@ohosTest --build-mode debug
devecocli check lint app/entry/src/main/ets/browser/web/RequestAgentGateway.ets app/entry/src/main/ets/browser/web/DownloadNotificationGateway.ets
~~~

Expected: PASS, with only ohos.permission.INTERNET remaining in module.json5.

- [ ] Step 6: Commit the platform adapters.

~~~cmd
git add app/entry/src/main/ets/browser/web/RequestAgentGateway.ets app/entry/src/main/ets/browser/web/DownloadNotificationGateway.ets app/entry/src/test/ets/test/DownloadAgentPorts.test.ets app/entry/src/test/List.test.ets
git commit -m download-agent-gateway
~~~

### Task 3: 接入 ArkWeb 下载委托并完成双后端转交

**Files:**
- Create: app/entry/src/main/ets/browser/web/DownloadService.ets
- Create: app/entry/src/test/ets/test/DownloadService.test.ets
- Modify: app/entry/src/main/ets/browser/web/WebTabNode.ets
- Modify: app/entry/src/test/List.test.ets

**Interfaces:**
- Produces WebDownloadHandler with onBeforeDownload(tabId: TabId, item: webview.WebDownloadItem, isPrivate: boolean): void, onDownloadUpdated(tabId: TabId, item: webview.WebDownloadItem): void, onDownloadFinish(tabId: TabId, item: webview.WebDownloadItem): void and onDownloadFailed(tabId: TabId, item: webview.WebDownloadItem): void。
- DownloadService consumes DownloadStore、AgentDownloadPort、NotificationPermissionPort and WebCookiePort.fetchCookie(url: string, isPrivate: boolean): Promise<string>。
- DownloadService exposes restore(): Promise<void>, markUiLoaded(): void, snapshot(): DownloadTaskRecord[], onBeforeDownload(tabId: TabId, item: webview.WebDownloadItem, isPrivate: boolean): void, onDownloadUpdated(tabId: TabId, item: webview.WebDownloadItem): void, onDownloadFinish(tabId: TabId, item: webview.WebDownloadItem): void, onDownloadFailed(tabId: TabId, item: webview.WebDownloadItem): void, pause(id: string): Promise<void>, resume(id: string): Promise<void>, cancel(id: string): Promise<void>, retry(id: string): Promise<void> and setListener(listener: (tasks: DownloadTaskRecord[]) => void): void。

- [ ] Step 1: Write failing service tests for routing and handoff order.

Use fake WebDownloadItem、agent、Cookie、notification and storage ports. Assert the normal GET sequence is:

~~~text
persist HANDOFF_PENDING -> create request.agent -> persist agentTaskId -> cancel ArkWeb item -> RUNNING
~~~

Assert private and blob items call item.start(savePath), never call the agent, and never pass Cookie to persistence. Assert a failed agent creation before a system task exists falls back to item.start exactly once.

- [ ] Step 2: Run the failing service target.

~~~cmd
set DEVECO_HOME=C:\PROGRA~1\Huawei\DEVECO~1
devecocli build --modules entry@ohosTest --build-mode debug
~~~

Expected: FAIL because DownloadService and the extended WebDownloadHandler do not exist.

- [ ] Step 3: Extend WebTabNode without moving address-bar behavior.

Replace the current download-root-specific delegate with an injected WebDownloadHandler. ArkWebRuntimeFactory receives the handler in its constructor, and createDownloadDelegate(tabId, isPrivate) forwards all four callbacks, including onDownloadUpdated. Keep the delegate undefined when no handler is supplied so Previewer/runtime construction remains safe.

- [ ] Step 4: Implement DownloadService normal-download handoff.

For onBeforeDownload, read getGuid、getUrl、getMethod、getMimeType and getSuggestedFileName, allocate a sanitized collision-free path under filesDir/downloads, and create the task record before any platform transfer. For the agent route, fetch Cookie only in memory, create the background task, save its ID, then call item.cancel(). Mark the cancel callback as an intentional handoff so it cannot overwrite RUNNING or FAILED.

- [ ] Step 5: Implement ArkWeb fallback and progress mapping.

For the native route call item.start(savePath) and keep the ArkWeb GUID. Map getReceivedBytes、getTotalBytes and getPercentComplete from onDownloadUpdated; use percentForDownload when the platform reports an unknown total. Finish and failure callbacks update the store before notifying listeners.

- [ ] Step 6: Implement restore and duplicate prevention.

On restore, load records, call getTask for saved agent IDs, then scan searchByPrefix('jianyue-download:'). Merge by agent ID/reconcile key/path. Reattach callbacks for live tasks, update terminal tasks directly, and mark missing tasks FAILED with a retryable message without creating a new task.

- [ ] Step 7: Run service tests and lint.

~~~cmd
set DEVECO_HOME=C:\PROGRA~1\Huawei\DEVECO~1
devecocli build --modules entry@ohosTest --build-mode debug
devecocli check lint app/entry/src/main/ets/browser/web/DownloadService.ets app/entry/src/main/ets/browser/web/WebTabNode.ets
~~~

Expected: PASS; tests must show no duplicate agent task after restore and no Cookie in persisted records.

- [ ] Step 8: Commit the ArkWeb/service integration.

~~~cmd
git add app/entry/src/main/ets/browser/web/DownloadService.ets app/entry/src/main/ets/browser/web/WebTabNode.ets app/entry/src/test/ets/test/DownloadService.test.ets app/entry/src/test/List.test.ets
git commit -m download-service-handoff
~~~

### Task 4: 把下载服务接入 BrowserShell 生命周期

**Files:**
- Modify: app/entry/src/main/ets/browser/components/BrowserShell.ets
- Create: app/entry/src/test/ets/test/BrowserDownloadLifecycle.test.ets
- Modify: app/entry/src/test/List.test.ets

**Interfaces:**
- BrowserShell owns @Local downloadTasks: DownloadTaskRecord[] and @Local showDownloadManager: boolean。
- BrowserShell creates one DownloadStore with PreferencesKeyValueStore(hostContext), one DownloadService and one snapshot listener during aboutToAppear。
- BrowserShell calls downloadService.restore() after UI context and host context are available, and calls downloadService.markUiLoaded() before the first user-triggered download can request notifications.

- [ ] Step 1: Write the lifecycle test.

Use fake service snapshots to assert that restore populates downloadTasks, a live task does not stop when the shell is hidden, and openDownloadManager() works when pageActionsReady() is false.

- [ ] Step 2: Run the failing lifecycle target.

~~~cmd
set DEVECO_HOME=C:\PROGRA~1\Huawei\DEVECO~1
devecocli build --modules entry@ohosTest --build-mode debug
~~~

Expected: FAIL because BrowserShell has no download state or service wiring.

- [ ] Step 3: Create the service with application preferences.

Use the existing hostContext.filesDir download root and PreferencesKeyValueStore(hostContext); do not create a second safe-area or storage owner. Pass downloadService to ArkWebRuntimeFactory instead of the old raw downloadRoot delegate path.

- [ ] Step 4: Bind snapshots and handle service actions.

Copy listener snapshots into a new array assigned to downloadTasks, expose downloadProgressForTab(tabId), and route pause/resume/cancel/retry callbacks from the sheet to DownloadService. Close the library/start-page sheet before opening the download manager.

- [ ] Step 5: Make system-back and interaction locking aware of the new sheet.

Update onSystemBackPress, address-editor guards, bottom-bar interactionLocked and overlay mount conditions so the download sheet closes first and cannot leave a full-screen hit-test layer over ArkWeb.

- [ ] Step 6: Run lifecycle tests and build the main module.

~~~cmd
set DEVECO_HOME=C:\PROGRA~1\Huawei\DEVECO~1
devecocli build --product default --modules entry --build-mode debug
devecocli check lint app/entry/src/main/ets/browser/components/BrowserShell.ets
~~~

Expected: PASS; the app compiles with the new service and existing address/tab gesture tests remain unchanged.

- [ ] Step 7: Commit lifecycle integration.

~~~cmd
git add app/entry/src/main/ets/browser/components/BrowserShell.ets app/entry/src/test/ets/test/BrowserDownloadLifecycle.test.ets app/entry/src/test/List.test.ets
git commit -m wire-download-service-lifecycle
~~~

### Task 5: 增加锁外蓝色环形进度并保持现有几何

**Files:**
- Modify: app/entry/src/main/ets/browser/components/AddressSearchBar.ets
- Modify: app/entry/src/main/ets/browser/components/AddressTabStrip.ets
- Modify: app/entry/src/main/ets/browser/components/BottomBrowserBar.ets
- Modify: app/entry/src/main/ets/browser/components/BrowserShell.ets
- Create: app/entry/src/test/ets/test/DownloadProgressUi.test.ets
- Modify: app/entry/src/test/List.test.ets

**Interfaces:**
- AddressSearchBar consumes downloadActive: boolean and downloadProgress: number; -1 means indeterminate.
- AddressTabStrip and BottomBrowserBar only pass DownloadProgressSnapshot | undefined; they never receive platform download handles.
- BrowserShell.downloadProgressForTab(tabId) returns the newest non-terminal task for that Tab.

- [ ] Step 1: Write failing progress-selection tests.

Assert that an active task returns its percent, an unknown total returns -1, a completed task returns no visible progress, and a task from another Tab is not shown in the current address bar.

- [ ] Step 2: Run the failing UI-model target.

~~~cmd
set DEVECO_HOME=C:\PROGRA~1\Huawei\DEVECO~1
devecocli build --modules entry@ohosTest --build-mode debug
~~~

Expected: FAIL because the progress props and selector are absent.

- [ ] Step 3: Add the read-only progress props through both address paths.

Pass the active Tab snapshot from both buildAddressTransitionLayer and BottomBrowserBar through AddressTabStrip into only the active AddressSearchBar item. Preserve all existing address draft, focus, handoff and safe-area props.

- [ ] Step 4: Render the ring inside the existing 32vp lock button.

Keep the existing 20vp lock image at its current position. Add a 28vp Progress ring in the same Stack, centered on the same 32vp button center, with blue color and about 2vp stroke. Use the determinate value for 0..100; use the ring's indeterminate mode for -1; place the ring below the lock image and outside its 20vp visual bounds. Do not add width/height to the parent Row or address capsule.

- [ ] Step 5: Run lint and inspect geometry.

~~~cmd
set DEVECO_HOME=C:\PROGRA~1\Huawei\DEVECO~1
devecocli check lint app/entry/src/main/ets/browser/components/AddressSearchBar.ets app/entry/src/main/ets/browser/components/AddressTabStrip.ets app/entry/src/main/ets/browser/components/BottomBrowserBar.ets
devecocli build --product default --modules entry --build-mode debug
~~~

Expected: PASS; the lock button remains 32vp, address capsule bounds do not change, and a zero/unknown progress ring does not move the cursor or lock.

- [ ] Step 6: Commit the progress-ring UI.

~~~cmd
git add app/entry/src/main/ets/browser/components/AddressSearchBar.ets app/entry/src/main/ets/browser/components/AddressTabStrip.ets app/entry/src/main/ets/browser/components/BottomBrowserBar.ets app/entry/src/main/ets/browser/components/BrowserShell.ets app/entry/src/test/ets/test/DownloadProgressUi.test.ets app/entry/src/test/List.test.ets
git commit -m show-download-progress-ring
~~~

### Task 6: 增加长按菜单和下载管理面板

**Files:**
- Modify: app/entry/src/main/ets/browser/model/PageActions.ets
- Modify: app/entry/src/main/ets/browser/components/AddressSearchBar.ets
- Create: app/entry/src/main/ets/browser/components/DownloadManagerSheet.ets
- Modify: app/entry/src/main/ets/browser/components/BrowserShell.ets
- Create: app/entry/src/ohosTest/ets/test/DownloadManagerUi.test.ets
- Modify: app/entry/src/ohosTest/ets/test/List.test.ets

**Interfaces:**
- Adds PageAction.DOWNLOAD_MANAGER。
- pageMenuActions(webReady) returns [PageAction.DOWNLOAD_MANAGER] when not ready and [PageAction.DOWNLOAD_MANAGER, PageAction.DESKTOP_SITE] when ready.
- DownloadManagerSheet consumes tasks、topInset、bottomInset、onClose、onPause、onResume、onCancel and onRetry。

- [ ] Step 1: Write failing menu and sheet UI tests.

Assert that the long-press menu has “下载管理” even when webReady is false, still has the desktop/mobile item when true, and that clicking the first item mounts the download-manager-sheet UI. Add stable IDs for the sheet and task controls before writing the test query.

- [ ] Step 2: Run the failing UI target.

~~~cmd
set DEVECO_HOME=C:\PROGRA~1\Huawei\DEVECO~1
devecocli build --modules entry@ohosTest --build-mode debug
~~~

Expected: FAIL because the new page action, sheet and stable UI IDs do not exist.

- [ ] Step 3: Add the page action and keep desktop-site behavior intact.

Handle DOWNLOAD_MANAGER before the existing pageActionsReady() guard in BrowserShell.onPageAction. Keep DESKTOP_SITE behind that guard and route it to the existing togglePageMode() implementation. Add the “下载管理” MenuItem to the same pageMenu() as the desktop/mobile item.

- [ ] Step 4: Implement DownloadManagerSheet.

Use the LibrarySheet safe-area and dismissal pattern. Render empty, running, paused, completed, failed and cancelled states. Give active tasks pause/continue/cancel actions, failed tasks a retry action, and every row a deterministic download-task-{id} ID. The sheet calls service callbacks and never imports request.agent or WebDownloadItem.

- [ ] Step 5: Mount and dismiss the sheet from BrowserShell.

Make the new sheet mutually exclusive with the library and start-page customization sheet. Mount it above the address transition layer when overviewProgress === 0; close it on background tap and system back; pass topAvoidInset and bottomAvoidInset exactly once.

- [ ] Step 6: Run device UI build and lint.

~~~cmd
set DEVECO_HOME=C:\PROGRA~1\Huawei\DEVECO~1
devecocli check lint app/entry/src/main/ets/browser/model/PageActions.ets app/entry/src/main/ets/browser/components/DownloadManagerSheet.ets
devecocli build --modules entry@ohosTest --build-mode debug
~~~

Expected: PASS; the menu and sheet test target compiles with stable IDs.

- [ ] Step 7: Commit menu and manager UI.

~~~cmd
git add app/entry/src/main/ets/browser/model/PageActions.ets app/entry/src/main/ets/browser/components/AddressSearchBar.ets app/entry/src/main/ets/browser/components/DownloadManagerSheet.ets app/entry/src/main/ets/browser/components/BrowserShell.ets app/entry/src/ohosTest/ets/test/DownloadManagerUi.test.ets app/entry/src/ohosTest/ets/test/List.test.ets
git commit -m add-download-manager-menu
~~~

### Task 7: 运行时权限、后台恢复和模拟器验收

**Files:**
- Verify only: app/entry/src/main/module.json5
- Verify only: app/entry/src/main/ets/entryability/EntryAbility.ets
- Build artifact: hap/YYYYMMDD-HHmmss-entry-debug.hap
- Evidence: emulator screenshots and devecocli log output saved outside source files or in the requested evidence location.

**Interfaces:**
- No new manifest permission is allowed.
- EntryAbility keeps its existing UI load flow; notification permission is requested by the service only after BrowserShell is mounted.

- [ ] Step 1: Run all source and device test builds.

~~~cmd
set DEVECO_HOME=C:\PROGRA~1\Huawei\DEVECO~1
devecocli check lint app/entry/src/main/ets
devecocli build --product default --modules entry --build-mode debug
devecocli build --product default --modules entry@ohosTest --build-mode debug
~~~

Expected: PASS with no new permission declaration and no ArkTS lint error.

- [ ] Step 2: Build and install the debug HAP.

List the generated HAP under the app build output, copy the entry debug HAP into the root hap directory using the current timestamp format, and install/run it with:

~~~cmd
set DEVECO_HOME=C:\PROGRA~1\Huawei\DEVECO~1
devecocli device list
devecocli run --module entry --build-mode debug
~~~

Record the exact HAP path, timestamp, device serial and install result.

- [ ] Step 3: Execute the menu and notification scenarios.

On the emulator, long-press the lock button and verify “下载管理” and “请求桌面网站” share one menu. Verify the manager opens before a page is ready, during a download, after completion and after notification permission is denied.

- [ ] Step 4: Execute both background scenarios.

Start a normal HTTP(S) GET download and record the task/reconcile ID. Send the app to background and verify progress/complete notification. Start a second download, terminate the app process, relaunch it, and verify the same task ID is restored, no second file is created and the manager reaches the correct terminal state.

- [ ] Step 5: Execute privacy and fallback scenarios.

Trigger a private download and an unsupported blob/custom-scheme download. Verify Cookie data does not appear in logs or persisted records, ArkWeb fallback remains usable while the process lives, and the manager labels the process-kill recovery boundary instead of showing an endless ring.

- [ ] Step 6: Capture visual and log evidence.

Capture screenshots for lock-only, active blue ring, unknown-size ring, download manager, completion and failure. Use devecocli log to correlate task IDs and state transitions. Confirm address capsule, left cursor inset, lock center, bottom bar corner and safe-area gap remain unchanged.

- [ ] Step 7: Commit verification metadata only when evidence is complete.

Do not stage screenshots, README.md or LICENSE unless explicitly requested. Report the HAP path, build/install result, test output, runtime cases and unsupported-resource boundary separately from source-level completion.

## Plan Self-Review

- Spec coverage: Task 1 covers model, persistence, state transitions, unknown progress and deduplication; Task 2 covers system background transport and notification authorization; Task 3 covers ArkWeb callbacks, Cookie handoff, fallback and progress; Task 4 covers lifecycle and process restart recovery; Task 5 covers the lock-centered ring and geometry; Task 6 covers the unified long-press menu and manager UI; Task 7 covers permissions, HAP naming, installation, emulator evidence, app background, process kill, notification denial, privacy and fallback.
- Permission check: The plan does not add a manifest permission beyond the existing ohos.permission.INTERNET; the background guarantee comes from request.agent.
- Privacy check: Cookie is an in-memory creation header only; private downloads never enter the recoverable agent route.
- Type check: DownloadService consumes the port types produced by Tasks 1–2, WebTabNode emits the WebDownloadHandler callbacks consumed by Task 3, and UI components consume only DownloadProgressSnapshot/DownloadTaskRecord from the store.
- Placeholder scan: Run a forbidden-placeholder scan over this plan before committing; it must return no matches.
- Dirty-worktree check: Before every commit run git status --short; only the task files may be staged, while README.md and LICENSE remain untouched.
