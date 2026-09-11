# Task 4 Report: Browser download lifecycle integration

## Status

Implemented and committed Task 4 on `codex-browser-background-downloads`.

Implementation commit: `5254333d758f2cfe978fc0b2829c2ec54ca3d881` (`feat:wire-download-service-lifecycle`)

Review repair commit: `1f08c9d8b06915c9292992abb87eb33e677e2c2d` (`fix-download-lifecycle-recovery`)

## Changed files

- `app/entry/src/main/ets/browser/components/BrowserShell.ets`
  - Owns one `DownloadStore`, `DownloadService`, and snapshot listener.
  - Marks the UI loaded and restores persisted/system tasks before download interaction.
  - Injects `DownloadService` into `ArkWebRuntimeFactory`.
  - Adds live task state, manager visibility/actions, back handling, and overlay/gesture locks.
  - Keeps background tasks alive when the shell is hidden.
- `app/entry/src/test/ets/test/BrowserDownloadLifecycle.test.ets`
  - Covers startup ordering and copied restored state, background preservation, and manager opening without page readiness.
- `app/entry/src/test/List.test.ets`
  - Registers the focused Task 4 lifecycle tests.
- `app/entry/src/main/ets/browser/web/DownloadService.ets`
  - Replaces object spreads/untyped request configuration with strict-ArkTS-compatible explicit records so the required main build can compile Task 1-3 code.
- `app/entry/src/main/ets/browser/web/RequestAgentGateway.ets`
  - Uses the SDK-declared `search(): Promise<string[]>` result and explicit filtering.
- `app/entry/src/main/ets/browser/web/DownloadNotificationGateway.ets`
  - Narrows the platform notification call to `UIAbilityContext` while preserving the existing testable port.

`README.md` and `LICENSE` were not modified.

## Commands and results

1. TDD red check:
   - `devecocli build --product default --modules entry@ohosTest --build-mode debug`
   - Result: build passed but did not compile `src/test`, so it was rejected as red-test evidence.
   - The local-test compiler then failed on the intentionally missing `BrowserDownloadLifecycle` and `BrowserDownloadServicePort` exports before implementation; those Task 4 errors disappeared after implementation.

2. Main compile gate:
   - `set DEVECO_HOME=C:\PROGRA~1\Huawei\DEVECO~1&&devecocli build --product default --modules entry --build-mode debug`
   - Result: `BUILD SUCCESSFUL in 4 s 84 ms`; 33 tasks, 18 executed, 15 up-to-date.
   - Warnings remain for existing system-capability/throw handling, IME permission analysis, and missing signing configuration.

3. ohosTest compile gate:
   - `set DEVECO_HOME=C:\PROGRA~1\Huawei\DEVECO~1&&devecocli build --product default --modules entry@ohosTest --build-mode debug`
   - Result: `BUILD SUCCESSFUL in 16 s 581 ms`; 35 tasks, 18 executed, 17 up-to-date.
   - Existing `BrowserGesture.test.ets` throw-handling warnings and missing signing configuration remain.

4. Planned hmos-local-test command:
   - Initial environment result: could not start because `hvigorw` was not on `PATH` (`[WinError 2] The system cannot find the file specified`). The inherited `DEVECO_HOME` and `DEVECO_SDK_HOME` also pointed to unavailable `D:` locations.
   - Retried with DevEco's bundled hvigor and SDK:
     `set DEVECO_HOME=C:\PROGRA~1\Huawei\DEVECO~1&&set DEVECO_SDK_HOME=C:\PROGRA~1\Huawei\DEVECO~1\sdk&&set PATH=C:\PROGRA~1\Huawei\DEVECO~1\tools\hvigor\bin;%PATH%&&python D:\.codex\skills\hmos-local-test\scripts\run_local_test.py --project-path E:\OneDrive\HarmonyOS\jianyue-browser\.superpowers\worktrees\browser-downloads\app --module entry --no-coverage --scope BrowserDownloadLifecycle`
   - Result: command executed, but `UnitTestArkTS` stopped before running tests with `COMPILE RESULT:FAIL {ERROR:8 WARN:22}`.
   - Exact source blockers are pre-existing Task 1-3 test fixture strictness errors:
     - `DownloadAgentPorts.test.ets:95` and `:101`: `arkts-no-untyped-obj-literals`.
     - `DownloadAgentPorts.test.ets:116` and `:117`: callback variables narrowed to `never`.
     - `DownloadService.test.ets:161`: `arkts-no-any-unknown`.
     - `DownloadService.test.ets:165`: `arkts-no-obj-literals-as-types`.
     - `DownloadService.test.ets:169`: `arkts-no-untyped-obj-literals`.
   - No compiler error was reported in `BrowserDownloadLifecycle.test.ets` on the final committed tree.

5. Repository checks:
   - `git diff --check`: passed; only Git's LF-to-CRLF working-copy notices.
   - `git diff -- README.md LICENSE`: empty.

## Concerns

- The initial repair-round local-test attempt exposed strict UnitTestArkTS fixture errors; those fixtures were corrected in the repair commit. The final focused local run reached runtime and passed all 17 tests.
- Task 4 wires manager state and actions but intentionally does not add the manager sheet UI; that component belongs to Task 6 in the plan.
- Runtime notification permission, request-agent restoration, and real background continuation still require device validation in the later end-to-end task.

## Review repair round: Important 1-3

The repair commit adds a service-level restore gate and serialized operation queue, makes `DownloadStore` merge live records and serialize persistence across restore/begin, detaches old agent listeners on rebind while leaving system tasks running, and makes request-agent search/get/show failures resolve into a retained, published local snapshot. `BrowserDownloadLifecycle` now detaches its identity-bound UI listener on stop and safely republishes the service snapshot when restore fails.

### Changed files in repair commit

- `app/entry/src/main/ets/browser/components/BrowserShell.ets`
- `app/entry/src/main/ets/browser/data/DownloadStore.ets`
- `app/entry/src/main/ets/browser/web/DownloadService.ets`
- `app/entry/src/main/ets/browser/web/RequestAgentGateway.ets`
- `app/entry/src/test/ets/test/BrowserDownloadLifecycle.test.ets`
- `app/entry/src/test/ets/test/DownloadAgentPorts.test.ets`
- `app/entry/src/test/ets/test/DownloadService.test.ets`

### Final commands and results

- `set DEVECO_HOME=C:\PROGRA~1\Huawei\DEVECO~1&&devecocli build --product default --modules entry --build-mode debug`
  - `BUILD SUCCESSFUL in 12 s 622 ms`; 33 tasks, 27 executed, 6 up-to-date.
- `set DEVECO_HOME=C:\PROGRA~1\Huawei\DEVECO~1&&devecocli build --product default --modules entry@ohosTest --build-mode debug`
  - `BUILD SUCCESSFUL in 2 s 834 ms`; 35 tasks, 18 executed, 17 up-to-date.
- `set DEVECO_HOME=C:\PROGRA~1\Huawei\DEVECO~1&&set DEVECO_SDK_HOME=C:\PROGRA~1\Huawei\DEVECO~1\sdk&&set PATH=C:\PROGRA~1\Huawei\DEVECO~1\tools\hvigor\bin;%PATH%&&python D:\.codex\skills\hmos-local-test\scripts\run_local_test.py --project-path E:\OneDrive\HarmonyOS\jianyue-browser\.superpowers\worktrees\browser-downloads\app --module entry --no-coverage --scope BrowserDownloadLifecycle,DownloadService`
  - Command exit code 0; result file reports `Tests run: 17, Failure: 0, Error: 0, Pass: 17, Ignore: 0`.
  - Exact non-blocking warning: `Failed to parse build-profile.json5 for srcPath lookup: json5 is required because no 'module' parameter was provided ... Result file paths will fall back to <project_path>/<module_name>.` The explicit `--module entry` run still produced and validated the result file.
- `git diff --check`
  - Passed; Git only reported existing LF-to-CRLF working-copy notices.
- `git diff -- README.md LICENSE`
  - Empty; neither file was modified.

### Remaining concerns

- No device/emulator runtime validation was available in this round; notification permission and real request-agent background continuation remain end-to-end concerns.
- Both compile gates retain the existing no-signing-config warning; the main build also reports existing system-capability/throw-handling warnings.
