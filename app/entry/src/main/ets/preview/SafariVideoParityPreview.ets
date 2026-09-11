import { BottomBrowserBar } from '../browser/components/BottomBrowserBar';
import { uiMaterial } from '@kit.ArkUI';
import { AddressSearchBar } from '../browser/components/AddressSearchBar';
import { LibrarySheet } from '../browser/components/LibrarySheet';
import { PageDisplayMenu } from '../browser/components/PageDisplayMenu';
import { StartPage } from '../browser/components/StartPage';
import { StartPageCustomizeSheet } from '../browser/components/StartPageCustomizeSheet';
import { TabOverview } from '../browser/components/TabOverview';
import { PageAction } from '../browser/model/PageActions';
import { BrowserSettings, copyBrowserSettings, DEFAULT_BROWSER_SETTINGS } from '../browser/model/BrowserSettings';
import { PageFontSize } from '../browser/model/PageDisplayState';
import {
  BrowserTabRecord,
  BookmarkRecord,
  GestureSample,
  HistoryRecord,
  TabResidency
} from '../browser/model/BrowserTypes';
import { StartPageItem, StartPageItemType } from '../browser/model/StartPageModels';
import { HARMONY_RADIUS_SHEET } from '../browser/model/BrowserVisualMetrics';

const PREVIEW_SETTINGS: BrowserSettings = copyBrowserSettings(DEFAULT_BROWSER_SETTINGS);
const PREVIEW_TABS: BrowserTabRecord[] = [
  {
    id: 'preview-tab-1',
    title: '如何花掉十个亿 - Google 搜索',
    url: 'https://zhihu.com/question/preview-1',
    isPrivate: false,
    createdAt: 1,
    lastAccessedAt: 2,
    thumbnailKey: '',
    residency: TabResidency.COLD
  },
  {
    id: 'preview-tab-2',
    title: '长得太帅如何与人相处 - Google 搜索',
    url: 'https://zhihu.com/question/preview-2',
    isPrivate: false,
    createdAt: 2,
    lastAccessedAt: 3,
    thumbnailKey: '',
    residency: TabResidency.COLD
  },
  {
    id: 'preview-tab-3',
    title: '异性缘太好怎么办 - Google 搜索',
    url: 'https://zhihu.com/question/preview-3',
    isPrivate: false,
    createdAt: 3,
    lastAccessedAt: 4,
    thumbnailKey: '',
    residency: TabResidency.COLD
  },
  {
    id: 'preview-tab-4',
    title: '爱幻想是一种病吗 - Google 搜索',
    url: 'https://www.toutiao.com/search/preview-4',
    isPrivate: false,
    createdAt: 4,
    lastAccessedAt: 5,
    thumbnailKey: '',
    residency: TabResidency.COLD
  }
];
const PREVIEW_HISTORY: HistoryRecord[] = [
  { url: 'https://developer.huawei.com', title: 'HarmonyOS 开发者', visitedAt: 1 }
];
const PREVIEW_BOOKMARKS: BookmarkRecord[] = [
  { url: 'https://developer.huawei.com/consumer/cn/', title: 'HarmonyOS 开发者', createdAt: 3 },
  { url: 'https://www.apple.com/safari/', title: 'Safari', createdAt: 2 }
];
const PREVIEW_START_PAGE_ITEMS: StartPageItem[] = [
  {
    id: 'preview-favorite-1',
    type: StartPageItemType.FAVORITE,
    title: 'HarmonyOS',
    url: 'https://developer.huawei.com',
    order: 0,
    updatedAt: 1
  },
  {
    id: 'preview-favorite-2',
    type: StartPageItemType.FAVORITE,
    title: 'Safari',
    url: 'https://www.apple.com/safari/',
    order: 1,
    updatedAt: 2
  },
  {
    id: 'preview-favorite-3',
    type: StartPageItemType.FAVORITE,
    title: '搜索',
    url: 'https://www.bing.com',
    order: 2,
    updatedAt: 3
  }
];

/** Primary visual check: the page surface flows into one native bottom chrome. */
@Preview
@Component
struct SafariImmersiveChromePreview {
  build() {
    Column() {
      Blank()
        .layoutWeight(1)
        .width('100%')
        .backgroundColor(Color.White);

      Column() {
        AddressSearchBar({
          address: '',
          selectedFontSize: PageFontSize.STANDARD,
          readerMode: false,
          webReady: false,
          onNavigate: (_value: string) => undefined,
          onFontSize: (_size: PageFontSize) => undefined,
          onPageAction: (_action: PageAction) => undefined
        })
        BottomBrowserBar({
          address: '',
          tabCount: 1,
          isPrivate: false,
          onBack: () => undefined,
          onForward: () => undefined,
          onShowLibrary: () => undefined,
          onShowOverview: () => undefined
        })
      }
        .width('100%')
        .height(128)
        .padding({ bottom: 28 })
        .backgroundColor('#D9F2F2F7')
        .borderRadius({ topLeft: HARMONY_RADIUS_SHEET, topRight: HARMONY_RADIUS_SHEET })
        .clip(true)
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
          interactive: false
        }))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
    }
      .width('100%')
      .height('100%');
  }
}

/** Static canvases for DevEco Studio Inspector two-way preview. */
@Preview
@Component
struct SafariAddressSearchBarPreview {
  build() {
    AddressSearchBar({
      address: '',
      selectedFontSize: PageFontSize.STANDARD,
      readerMode: false,
      webReady: false,
      onNavigate: (_value: string) => undefined,
      onFontSize: (_size: PageFontSize) => undefined,
      onPageAction: (_action: PageAction) => undefined
    })
  }
}

@Component
struct SafariStartPagePreview {
  build() {
    StartPage({
      items: [],
      settings: PREVIEW_SETTINGS,
      onOpen: (_url: string) => undefined,
      onAddFavorite: () => undefined,
      onCustomize: () => undefined
    })
  }
}

@Preview
@Component
struct SafariStartPageContentPreview {
  build() {
    StartPage({
      items: PREVIEW_START_PAGE_ITEMS,
      settings: {
        searchEngine: PREVIEW_SETTINGS.searchEngine,
        autoCloseTabs: PREVIEW_SETTINGS.autoCloseTabs,
        contentBlockingEnabled: PREVIEW_SETTINGS.contentBlockingEnabled,
        showFavorites: true,
        showFrequentSites: false,
        startPageSectionsConfigured: true,
        startPageBackgroundId: 'custom-pink',
        startPageAppearance: PREVIEW_SETTINGS.startPageAppearance,
        defaultFontSize: PREVIEW_SETTINGS.defaultFontSize
      },
      onOpen: (_url: string) => undefined,
      onAddFavorite: () => undefined,
      onCustomize: () => undefined
    })
  }
}

/** Full-height canvas used to verify the production vertical order. */
@Preview
@Component
struct SafariStartPageChromePreview {
  build() {
    Column() {
      Stack() {
        StartPage({
          items: [],
          settings: PREVIEW_SETTINGS,
          onOpen: (_url: string) => undefined,
          onAddFavorite: () => undefined,
          onCustomize: () => undefined
        })
      }
      .layoutWeight(1)
      .width('100%')

      Column() {
        AddressSearchBar({
          address: '',
          selectedFontSize: PageFontSize.STANDARD,
          readerMode: false,
          webReady: false,
          onNavigate: (_value: string) => undefined,
          onFontSize: (_size: PageFontSize) => undefined,
          onPageAction: (_action: PageAction) => undefined
        })

        BottomBrowserBar({
          address: '',
          tabCount: 1,
          isPrivate: false,
          onBack: () => undefined,
          onForward: () => undefined,
          onShowLibrary: () => undefined,
          onShowOverview: () => undefined
        })
      }
      .width('100%')
      .height(128)
      .padding({ bottom: 28 })
      .backgroundColor('#D9F2F2F7')
      .borderRadius({ topLeft: HARMONY_RADIUS_SHEET, topRight: HARMONY_RADIUS_SHEET })
      .clip(true)
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        interactive: false
      }))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
  }
}

@Preview
@Component
struct SafariToolbarPreview {
  build() {
    Column() {
      BottomBrowserBar({
        address: 'https://developer.huawei.com',
        tabCount: 2,
        isPrivate: false,
        selectedFontSize: PageFontSize.STANDARD,
        readerMode: false,
        webReady: true,
        onNavigate: (_value: string) => undefined,
        onBack: () => undefined,
        onForward: () => undefined,
        onReload: () => undefined,
        onNewTab: () => undefined,
        onNewPrivateTab: () => undefined,
        onShowLibrary: () => undefined,
        onCloseAllTabs: () => undefined,
        onReopenClosedTab: () => undefined,
        onShowOverview: () => undefined
      })
    }
    .width('100%')
    .height(76)
    .padding({ bottom: 28 })
    .backgroundColor('#D9F2F2F7')
    .borderRadius({ topLeft: HARMONY_RADIUS_SHEET, topRight: HARMONY_RADIUS_SHEET })
    .clip(true)
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      interactive: false
    }))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}

@Preview
@Component
struct SafariTabOverviewPreview {
  build() {
    TabOverview({
      tabs: PREVIEW_TABS,
      activeTabId: 'preview-tab-1',
      overviewProgress: 1,
      bottomInset: 28,
      onOpen: (_tabId: string) => undefined,
      onNewTab: () => undefined,
      onDismiss: () => undefined,
      onCloseStart: (_tabId: string) => undefined,
      onCloseUpdate: (_tabId: string, _sample: GestureSample) => undefined,
      onCloseEnd: (_tabId: string, _sample: GestureSample) => undefined,
      onCloseCancel: (_tabId: string) => undefined,
      onCloseTap: (_tabId: string) => undefined,
      onReorderStart: (_tabId: string) => undefined,
      onReorder: (_tabId: string, _targetIndex: number) => undefined
    })
  }
}

/** Video state after the overview search field is revealed. */
@Preview
@Component
struct SafariTabOverviewSearchPreview {
  build() {
    TabOverview({
      tabs: PREVIEW_TABS,
      activeTabId: 'preview-tab-1',
      overviewProgress: 1,
      showSearch: true,
      bottomInset: 28,
      onOpen: (_tabId: string) => undefined,
      onNewTab: () => undefined,
      onDismiss: () => undefined,
      onCloseStart: (_tabId: string) => undefined,
      onCloseUpdate: (_tabId: string, _sample: GestureSample) => undefined,
      onCloseEnd: (_tabId: string, _sample: GestureSample) => undefined,
      onCloseCancel: (_tabId: string) => undefined,
      onCloseTap: (_tabId: string) => undefined,
      onReorderStart: (_tabId: string) => undefined,
      onReorder: (_tabId: string, _targetIndex: number) => undefined
    })
  }
}

@Preview
@Component
struct SafariLibrarySheetPreview {
  build() {
    LibrarySheet({
      history: PREVIEW_HISTORY,
      bookmarks: PREVIEW_BOOKMARKS,
      onRemoveBookmark: (_url: string) => undefined,
      onRemoveHistory: (_url: string) => undefined,
      onOpen: (_url: string) => undefined,
      onClose: () => undefined
    })
  }
}

@Preview
@Component
struct SafariLibrarySheetSafeAreaPreview {
  build() {
    LibrarySheet({
      history: PREVIEW_HISTORY,
      bookmarks: PREVIEW_BOOKMARKS,
      topInset: 24,
      bottomInset: 28,
      onRemoveBookmark: (_url: string) => undefined,
      onRemoveHistory: (_url: string) => undefined,
      onOpen: (_url: string) => undefined,
      onClose: () => undefined
    })
  }
}

@Preview
@Component
struct SafariStartPageCustomizePreview {
  build() {
    StartPageCustomizeSheet({
      settings: PREVIEW_SETTINGS,
      items: PREVIEW_START_PAGE_ITEMS,
      topInset: 24,
      bottomInset: 28,
      onSettingsChange: (_settings: BrowserSettings) => undefined,
      onItemsChange: (_items: StartPageItem[]) => undefined,
      onClose: () => undefined
    })
  }
}

@Component
struct SafariPageDisplayMenuPreview {
  build() {
    PageDisplayMenu({
      selectedFontSize: PageFontSize.STANDARD,
      readerMode: false,
      webReady: true,
      onFontSize: (_size: PageFontSize) => undefined,
      onAction: (_action: PageAction) => undefined
    })
  }
}
