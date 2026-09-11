/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BrowserLifecycleRegistry } from '../browser/lifecycle/BrowserLifecyclePort';
import {
  clearPendingExternalUrl,
  setPendingExternalUrl
} from '../browser/model/BrowserLaunchState';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    void launchParam;
    this.forwardExternalUrl(want);
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    void launchParam;
    this.forwardExternalUrl(want);
  }

  private forwardExternalUrl(want: Want): void {
    const externalUrl: string | undefined = typeof want.uri === 'string'
      ? setPendingExternalUrl(want.uri)
      : undefined;
    if (externalUrl !== undefined && BrowserLifecycleRegistry.onExternalUrl(externalUrl)) {
      clearPendingExternalUrl();
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    const loadBrowserContent = (): void => {
      windowStage.loadContent('pages/Index', (err) => {
        if (err.code) {
          hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
          return;
        }
        hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
      });
    };

    // Configure the window before creating the ArkUI tree. BrowserContent is
    // edge-to-edge; its background covers the cutout while BrowserTransitionScene
    // applies the live TYPE_SYSTEM/TYPE_CUTOUT inset only to WebView scenes.
    windowStage.getMainWindow((err, mainWindow) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to obtain the main window. Cause: %{public}s', JSON.stringify(err));
        loadBrowserContent();
        return;
      }
      void mainWindow.setWindowLayoutFullScreen(true)
        .then(() => mainWindow.setWindowSystemBarProperties({
          statusBarColor: '#00000000',
          statusBarContentColor: '#FF1D1D1F',
          navigationBarColor: '#00000000',
          navigationBarContentColor: '#FF1D1D1F',
          isStatusBarLightIcon: false,
          isNavigationBarLightIcon: false
        }))
        .then(() => {
          loadBrowserContent();
        })
        .catch((windowError: BusinessError) => {
          hilog.error(DOMAIN, 'testTag', 'Failed to configure immersive system bars. Cause: %{public}s',
            JSON.stringify(windowError));
          // A window configuration failure must not prevent the browser from
          // starting; BrowserShell still reads the current avoid areas.
          loadBrowserContent();
        });
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    BrowserLifecycleRegistry.onForeground();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    void BrowserLifecycleRegistry.onBackground();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }

  onMemoryLevel(level: number): void {
    BrowserLifecycleRegistry.onMemoryPressure(level);
    hilog.info(DOMAIN, 'testTag', 'Ability memory level %{public}d', level);
  }
}
