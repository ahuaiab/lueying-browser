# 简悦浏览器下载与下载管理设计

## 1. 目标与范围

本次改动为简悦浏览器增加完整的网页下载能力，并满足以下产品目标：

1. 网页触发下载后，地址栏锁图标外侧显示蓝色环形下载进度；环形进度与锁图标保持同一圆心，不改变地址胶囊、锁按钮和光标的既有几何。
2. 下载使用系统下载代理，应用切到后台后仍能继续执行，并由系统通知反馈进度和完成状态。
3. 普通下载在应用进程被系统杀死或用户关闭应用后仍能继续；应用再次启动时能够恢复任务状态，不重复创建下载。
4. 地址栏锁按钮的长按菜单同时提供“下载管理”和“请求桌面网站”。“下载管理”打开原生下载管理界面；“请求桌面网站”继续执行已有的桌面版/手机版切换。
5. 下载管理界面能够显示进行中、暂停、完成、失败和取消的任务，并提供与当前下载状态匹配的操作。

这里的“双后台下载”明确为两种场景：应用进入后台继续下载，以及应用进程退出/被杀后由系统服务继续下载并在下次启动时恢复。后台能力针对普通、非隐私的 HTTP(S) GET 下载提供完整保证；隐私下载和无法转换为系统下载任务的网页资源保留 ArkWeb 原生路径，并在界面和文档中明确其不提供进程被杀后的恢复保证。

## 2. 现有工程边界

当前工程已经具备一部分下载接入点，但还没有任务生命周期和管理界面：

- `WebTabNode.ets` 已创建 `WebDownloadDelegate`，只处理开始、完成和失败；当前直接将文件写入应用 `filesDir/downloads`，没有进度回调、暂停/恢复或任务持久化。
- `DownloadCoordinator.ets` 已有保存文件名、目标选择和启动器的抽象，可复用其文件名清理规则，但它不是完整的下载任务仓库。
- `BrowserShell.ets` 已创建下载目录并注入网页生命周期观察者，但下载回调目前为空实现。
- `AddressSearchBar.ets` 的长按菜单当前只有“请求桌面网页”；`PageActions.ets` 中尚无下载管理动作。
- `BrowserShell` 已有 `LibrarySheet` 等底部原生面板，可沿用其安全区、背景遮罩、拖拽和动效模式。
- 工程目标 SDK 为 HarmonyOS 26，模块当前只声明 `ohos.permission.INTERNET`。

已有地址栏锁图标和安全区布局属于已验收的视觉约束。本功能只能在锁图标所在的固定按钮内部叠加进度环，不能重新计算地址胶囊的左右内边距，也不能让环形进度占据新的横向布局空间。

## 3. 方案选择

### 3.1 备选方案

**方案 A：只使用 ArkWeb `WebDownloadItem`。**

优点是网页 Cookie、重定向和网页请求上下文天然一致，实现简单。缺点是它的生命周期绑定 ArkWeb/应用进程，不能为普通下载提供进程被杀后的系统级续传保证，也不适合可靠地显示系统通知。

**方案 B：只使用 `request.agent`。**

优点是任务由系统下载服务管理，支持后台执行、通知和跨进程恢复。缺点是无法无条件复刻所有网页请求上下文；`blob:`、`data:`、部分自定义协议、POST 下载和需要特殊网页请求头的资源不能直接转换，隐私 Cookie 也不应被复制到持久化后台任务。

**方案 C：ArkWeb 接入 + `request.agent` 后台传输的混合方案（采用）。**

ArkWeb 负责发现下载、提供文件名/URL/MIME/隐私状态等网页上下文；普通、非隐私、HTTP(S) GET 下载优先转交系统 `request.agent`；隐私下载和不支持转换的资源继续由 ArkWeb 原生下载。两条路径统一写入一个任务仓库和一个管理界面，前台进度统一映射到地址栏蓝色环形进度。

采用混合方案的原因是同时满足“应用后台继续”和“进程被杀后恢复”，又不为了后台能力破坏私密网页的 Cookie 边界或强行支持系统下载代理无法表达的请求。

## 4. 模块和数据边界

### 4.1 任务模型

新增独立的下载模型文件，例如 `app/entry/src/main/ets/browser/model/DownloadModels.ets`，只放平台无关的类型、状态和显示数据：

```text
DownloadBackend = REQUEST_AGENT | ARKWEB
DownloadStatus = QUEUED | HANDOFF_PENDING | RUNNING | PAUSED | COMPLETED | FAILED | CANCELLED

DownloadTaskRecord {
  id: string                    // 简悦生成的稳定任务 ID
  reconcileKey: string          // 用于进程重启时识别孤儿 request.agent 任务
  backend: DownloadBackend
  agentTaskId?: string
  arkWebGuid?: string
  tabId?: string
  fileName: string
  mimeType: string
  savePath: string
  sourceUrl?: string            // 仅用于非隐私任务重试；不展示在 UI
  receivedBytes: number
  totalBytes: number            // 未知时为 0
  percent: number               // 未知时为 -1
  status: DownloadStatus
  isPrivate: boolean
  errorCode?: number
  errorMessage?: string
  createdAt: number
  updatedAt: number
  completedAt?: number
}
```

任务模型不保存 Cookie、Authorization 等请求头，不在日志中输出完整 URL、Cookie 或下载内容。隐私任务只保留进程内的必要句柄和 UI 状态，不写入可用于进程重启恢复的后台任务记录。

### 4.2 `DownloadStore`

新增纯状态层 `DownloadStore`，不直接依赖 ArkWeb、`request.agent` 或 ArkUI。职责包括：

- 创建任务、更新字节数/百分比、完成、失败、取消和删除记录。
- 对同一 `reconcileKey` 或后台任务 ID 去重，防止应用重启时重复显示或重复创建任务。
- 为地址栏计算当前 Tab 最近一个非终态任务的进度；多个任务同时存在时，下载管理界面显示全部任务。
- 将非隐私任务元数据持久化到应用私有存储，并在启动时读取。
- 用不可变快照通知 `BrowserShell` 和下载管理面板，避免 ArkWeb 回调直接修改 UI 状态。

状态层要有明确的非法迁移保护，例如 `COMPLETED` 不再接受进度更新，`CANCELLED` 不因迟到的系统回调重新变为 `RUNNING`。回调可能重复或乱序，必须以任务 ID 和更新时间/终态判断为准。

### 4.3 `DownloadService`

新增平台适配层 `DownloadService`，由 `BrowserShell` 在获得 `Context` 后创建。它是唯一同时接触 ArkWeb 下载回调、`request.agent` 和 `DownloadStore` 的模块，向上暴露：

- `handleWebDownload(item, tabId, isPrivate)`：接管 ArkWeb 的 `onBeforeDownload`。
- `onWebDownloadUpdated(item)`、`onWebDownloadFinish(item)`、`onWebDownloadFailed(item)`：映射 ArkWeb 原生任务状态。
- `pause(id)`、`resume(id)`、`cancel(id)`、`retry(id)`：统一控制两种后端。
- `restore()`：应用启动时读取本地记录，按已保存的后台任务 ID 重新绑定 `request.agent` 任务，并扫描带有简悦 `reconcileKey` 的后台任务以补偿进程杀死时尚未落库的任务。
- `observe(snapshot)`：向 `BrowserShell` 提供节流后的任务快照。

`DownloadService` 不把下载实现塞进 `BrowserShell`，`BrowserShell` 只负责生命周期、面板状态和 UI 回调。

### 4.4 后台代理配置

对普通非隐私 HTTP(S) GET 下载，创建 `request.agent` `BACKGROUND` 任务：

- `action` 为下载，`saveas` 指向应用私有 `filesDir/downloads` 下经过清理和冲突处理的文件名。
- `title`、`description` 带有简悦任务识别前缀和 `reconcileKey`，用于重启后的去重扫描；不放 Cookie 或完整敏感 URL。
- 开启进度通知和完成通知；系统通知是应用后台期间的主要反馈渠道。
- 从 `WebCookieManager.fetchCookie(url, isPrivate)` 获取当前网页 Cookie，只在创建任务时作为内存中的请求头使用，创建完成后立即丢弃，不持久化、不写日志。
- 对 URL scheme、HTTP 方法、隐私模式和必要请求上下文进行路由判断。`http`/`https` 的 GET 才进入系统代理主路径；`blob`、`data`、自定义 scheme、无法提供请求体的 POST 等进入 ArkWeb 原生路径。

### 4.5 下载管理面板

新增 `DownloadManagerSheet.ets`，复用 `LibrarySheet` 的底部面板结构、安全区和背景遮罩，但只依赖 `DownloadStore` 的快照和 `DownloadService` 的控制回调。界面至少包含：

- 进行中/暂停任务：文件名、百分比或“正在下载”、已接收/总大小、暂停/继续、取消。
- 完成任务：文件名、完成状态和本地路径摘要。
- 失败任务：失败原因摘要和重试入口。
- 无任务时的空状态。

面板只负责展示和发出动作，不直接持有 `request.agent.Task` 或 `WebDownloadItem`。首次版本不扩展公共 Downloads 目录、跨设备传输或复杂文件预览。

## 5. 关键交互与数据流

### 5.1 下载发现和后台转交

1. ArkWeb `onBeforeDownload` 收到下载项后，生成安全文件名、目标路径、任务 ID 和 `reconcileKey`，先将任务写为 `QUEUED/HANDOFF_PENDING` 等待转交。
2. 若任务是普通非隐私 HTTP(S) GET，读取网页 Cookie 并创建 `request.agent` 后台任务。拿到系统任务 ID 后，先将系统任务 ID 和目标路径持久化，再取消 ArkWeb 原始下载项，最后把任务置为 `RUNNING`。这样即使取消回调迟到，也不会被误判为失败。
3. 若系统任务创建失败、请求不满足转换条件，调用 ArkWeb `item.start(targetPath)`，保存 ArkWeb GUID，任务进入 `RUNNING`。该路径仍支持应用存活期间的前后台切换，但不承诺进程被杀后的恢复。
4. 后台代理或 ArkWeb 的进度回调更新 `DownloadStore`。回调需要节流，避免每个字节变化都触发 ArkUI 重绘；建议以约 100–250ms 的节奏更新可见快照。
5. 完成、失败、取消都要先更新任务仓库，再通知 UI；系统代理的迟到事件不能覆盖已确认的终态。

为避免转交过程中的重复下载，转交顺序必须是“生成识别键并落库 → 创建系统任务 → 落库系统任务 ID → 取消 ArkWeb 项目”。系统任务配置中的识别键用于补偿进程在第三步和第四步之间被杀死的情况。

### 5.2 应用进入后台

系统代理任务由 HarmonyOS 下载服务持有，不依赖应用进程保持前台，也不使用普通网页下载不需要的长时间后台运行权限。应用进入后台后：

- 系统继续下载并按配置发布通知。
- 应用进程仍存活时，现有回调可以继续更新仓库；回到前台后再次调用 `show`/查询接口做一次权威同步。
- 地址栏进度环只属于可见页面 UI；应用不在前台时由系统通知替代。

### 5.3 应用进程退出或被杀

1. 系统代理任务继续运行，任务 ID、目标路径和识别键已经在进程退出前持久化。
2. `EntryAbility` 完成 UI 加载后，`BrowserShell.aboutToAppear` 创建 `DownloadService` 并调用 `restore()`。
3. `restore()` 先按已保存的 `agentTaskId` 获取任务，再按简悦识别前缀扫描近期后台任务；以 `agentTaskId`、`reconcileKey` 和目标路径去重合并。
4. 对仍在运行的任务重新注册进度/完成/失败观察；对已经完成或失败的任务直接同步终态；对找不到的任务标记为可重试失败，不自动重新下载，防止重复写文件。
5. 恢复后，下载管理面板显示完整状态；如果当前 Tab 仍存在，对应地址栏重新显示进度环。

隐私下载不会复制 Cookie 到系统后台代理，也不写入可跨进程恢复的任务记录。它只走 ArkWeb 原生路径，面板必须用状态文案区分“应用存活期间可继续”和“进程退出后不会恢复”。

### 5.4 地址栏蓝色环形进度

在 `AddressSearchBar` 的锁按钮内部增加固定尺寸的叠层：

- 环形进度与锁图标共用同一中心点，锁图标仍位于上层，触摸命中区域和视觉位置不变。
- 进度环使用蓝色主题色，采用约 28vp 外环和约 2vp 线宽；锁图标继续保持约 20vp，外环不参与地址胶囊横向布局。
- `percent` 为 0–100 时显示确定性环；总大小未知时显示蓝色不确定进度，不伪造百分比。
- 当前活动 Tab 有非终态任务时显示；任务完成、失败、取消后隐藏，下载管理面板仍保留历史状态。
- 同一 Tab 有多个任务时选择最近创建且未终态的任务作为地址栏代表；切换 Tab 时重新选择对应任务。

需要通过 `AddressTabStrip` 和 `BrowserShell` 传递最小的只读进度数据，不能把平台下载句柄下传给地址栏。

### 5.5 长按菜单和面板打开

扩展 `PageAction`：

- `DOWNLOAD_MANAGER`：始终可用，触发 `BrowserShell` 将下载管理面板置为显示。
- `DESKTOP_SITE`：保留当前逻辑，仅在网页已准备好时可用，继续切换请求桌面网页/请求手机网页。

`AddressSearchBar.pageMenu()` 按固定顺序显示“下载管理”和当前模式对应的桌面/手机网页项。下载管理项不依赖 `webReady`，即使当前页面尚未完成加载也可以打开空状态或已有任务列表。两个菜单项使用同一个长按菜单，不增加新的锁按钮或覆盖层。

## 6. 权限、通知和安全

- 继续使用现有 `ohos.permission.INTERNET`；系统 `request.agent` 下载不新增应用不可申请的后台常驻权限。
- 不声明 `ohos.permission.NOTIFICATION_CONTROLLER`，因为它是系统级权限，不属于普通应用可请求权限。
- 不为普通下载加入 `ohos.permission.KEEP_BACKGROUND_RUNNING`；系统下载服务已是正确的长时间传输入口。
- 首次真实下载、且 UI 已加载后，调用 `notificationManager.requestEnableNotification(context)` 请求通知授权；只请求一次并记录结果。用户拒绝后下载仍可继续，管理面板仍正常显示。
- 系统通知配置为进行中进度和完成通知。通知授权被拒绝时不崩溃、不阻塞下载，并在管理面板保留状态。
- 文件始终写入应用私有下载目录，文件名经过清理、空名兜底和同名冲突处理。
- Cookie、Authorization、完整敏感 URL 不进入日志和持久化的请求头；隐私任务不进入系统后台代理。

## 7. 异常处理

以下情况必须进入管理面板的可解释状态，而不是静默丢失：

- Cookie 获取失败或会话过期：按系统代理失败处理，保留错误码，允许用户从页面重新触发下载。
- `request.agent` 创建失败：在尚未创建系统任务时回退到 ArkWeb 原生下载；若系统任务已创建后失败，不自动再创建第二份任务，提供重试。
- 不支持的 URL scheme、POST 请求体、`blob:`/`data:` 资源：走 ArkWeb 路径并标明不支持进程杀死恢复。
- 网络断开、磁盘空间不足、系统任务消失：任务变为 `FAILED`，保留可重试状态，不自动重复写入同一路径。
- 通知被拒绝：只关闭通知通道，不影响任务和 UI 状态。
- 应用恢复时发现本地记录对应的系统任务不存在：标记为“任务已中断，可重试”，不得凭空重新发起下载。

## 8. 测试和验收

### 8.1 单元测试

先为纯逻辑写失败测试，再实现生产代码，至少覆盖：

- 文件名清理、空文件名、同名冲突和目标路径生成。
- 普通 HTTP(S) GET、隐私任务、`blob:`/`data:`/自定义协议、POST 的路由选择。
- `DownloadStore` 的状态迁移、重复回调、终态保护和同一任务去重。
- 进程重启时按系统任务 ID、识别键、目标路径合并任务，不重复创建。
- 未知总大小时的 `percent = -1` 和 UI 显示数据。
- Cookie 只进入内存中的后台任务配置，不进入持久化记录和日志模型。
- `PageAction.DOWNLOAD_MANAGER` 与 `DESKTOP_SITE` 的菜单生成和启用条件。

### 8.2 ArkUI/组件测试

- 有活动下载时锁外显示蓝色环，无活动下载时不显示。
- 环形进度和锁图标共圆心，环形尺寸不改变地址胶囊的左右边界。
- 0%、中间百分比、100% 和未知大小四种显示状态。
- 长按菜单同时显示两个菜单项；点击下载管理打开面板，点击桌面网页保持原有切换。
- 面板在空列表、进行中、暂停、完成、失败、取消和多任务状态下显示正确操作。

### 8.3 模拟器验收

每次实现完成后使用 `devecocli` 构建、安装并在模拟器上留存证据：

1. 普通 HTTP(S) GET 下载：地址栏显示蓝色环，下载管理显示进度，完成后显示完成状态和通知。
2. 下载过程中切到后台：任务继续，系统通知出现，回到前台进度与系统状态一致。
3. 下载过程中结束/杀死应用：任务继续或完成；重新启动应用后任务列表恢复，不能生成第二份文件。
4. 拒绝通知授权：下载不崩溃，管理面板仍能显示并控制任务。
5. 隐私下载：不复制 Cookie 到系统代理；应用存活时可下载，进程退出后明确显示不可恢复边界。
6. 不支持转换的资源：回退 ArkWeb 路径，完成/失败回调可见，不能出现无限转圈。
7. 验证地址栏锁、进度环、地址胶囊和底部栏的截图几何；验证 HAP 产物按 `hap/YYYYMMDD-HHmmss-entry-debug.hap` 时间命名并记录安装路径、日志和截图。

## 9. 非目标

本次不实现公共 Downloads 目录导出、跨设备同步、断点续传协议的自定义实现、复杂文件预览、下载历史云同步或隐私下载的进程杀死恢复。上述能力若后续需要，应在当前统一任务模型上单独设计，不通过扩大权限或复制 Cookie 规避系统限制。

## 10. 完成标准

只有同时满足以下条件才视为完成：

- 下载任务模型、系统后台代理、ArkWeb 回退路径、通知请求、恢复去重和下载管理 UI 均已实现。
- 先有失败测试，再有实现；相关单元测试和 ArkUI 测试通过。
- `devecocli` 构建成功，最新 HAP 已按时间命名写入根目录 `hap` 文件夹并安装到模拟器。
- 模拟器证据覆盖应用后台和进程被杀两种场景，且能区分源代码、构建产物、安装结果、截图和运行日志。
- 本次功能不覆盖用户现有的未提交 `README.md` 修改和未跟踪 `LICENSE` 文件。
