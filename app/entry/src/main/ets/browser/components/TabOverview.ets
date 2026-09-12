import { image } from '@kit.ImageKit';
import { uiMaterial } from '@kit.ArkUI';
import { BrowserTabRecord, GestureSample, TabId } from '../model/BrowserTypes';
import {
  filterTabsByQuery,
  TAB_OVERVIEW_LAYOUT,
  TAB_SEARCH_BAR_STYLE,
  TAB_OVERVIEW_BACKGROUND_COLOR,
  TAB_SEARCH_BAR_BACKGROUND_COLOR,
  TAB_SEARCH_BAR_CONTENT_INSET,
  TAB_SEARCH_REVEAL_ANIMATION_DURATION_MS,
  TAB_SEARCH_PULL_THRESHOLD,
  tabSearchPullProgress,
  tabSearchVisualProgress,
  tabOverviewSearchSlotHeightForProgress,
  tabOverviewTopPaddingForProgress,
  tabOverviewGridOpacityAtProgress,
  shouldUseTabOverviewCloseThumbnail,
  tabOverviewBorderOwner
} from '../model/TabOverviewActions';
import { placeholderForFocus } from '../model/BrowserInteraction';
import { TabCard } from './TabCard';
import { HARMONY_RADIUS_FLOATING } from '../model/BrowserVisualMetrics';

/**
 * Safari-like tab overview reconstructed from the 1:20–2:04 video segment.
 * The overview is intentionally edge-to-edge: cards in a two-column grid and
 * the compact plus/checkmark toolbar at the bottom. Search is revealed only after a
 * native downward pull from the grid, matching Safari's hidden search affordance.
 */
@ComponentV2
export struct TabOverview {
  @Param tabs: BrowserTabRecord[] = [];
  @Param activeTabId: TabId = '';
  @Param overviewProgress: number = 0;
  /** True only when this instance was mounted during an upward bar reveal. */
  @Param interactiveReveal: boolean = true;
  /** Keeps border ownership single during reverse card expansion. */
  @Param overviewClosing: boolean = false;
  /** The mounted BrowserTransitionScene is the active card's visual source. */
  @Param livePageTransform: boolean = false;
  @Param revision: number = 0;
  /** Top system avoid area in vp; the background remains edge-to-edge. */
  @Param topInset: number = 0;
  @Param bottomInset: number = 0;
  @Param thumbnailFor: (tabId: TabId) => image.PixelMap | undefined =
    (_tabId: TabId) => undefined;
  @Param cardProgressFor: (tabId: TabId) => number = (_tabId: TabId) => 0;
  @Param cardOffsetFor: (tabId: TabId) => number = (_tabId: TabId) => 0;
  @Param cardHorizontalOffsetFor: (tabId: TabId) => number = (_tabId: TabId) => 0;
  @Param onOpen: (tabId: TabId) => void = (_tabId: TabId) => undefined;
  @Param onNewTab: () => void = () => undefined;
  @Param onCloseAllTabs: () => void = () => undefined;
  @Param onDismiss: () => void = () => undefined;
  @Param onCloseStart: (tabId: TabId) => void = (_tabId: TabId) => undefined;
  @Param onCloseUpdate: (tabId: TabId, sample: GestureSample) => void =
    (_tabId: TabId, _sample: GestureSample) => undefined;
  @Param onCloseEnd: (tabId: TabId, sample: GestureSample) => void =
    (_tabId: TabId, _sample: GestureSample) => undefined;
  @Param onCloseCancel: (tabId: TabId) => void = (_tabId: TabId) => undefined;
  @Param onCloseTap: (tabId: TabId) => void = (_tabId: TabId) => undefined;
  @Param onReorderStart: (tabId: TabId) => void = (_tabId: TabId) => undefined;
  @Param onReorder: (tabId: TabId, targetIndex: number) => void =
    (_tabId: TabId, _targetIndex: number) => undefined;
  /** Enables the pull-to-reveal field; it is hidden until the user pulls down. */
  @Param showSearch: boolean = false;
  /** Publishes the same search geometry progress used by the card grid. */
  @Param onSearchProgress: (progress: number) => void = (_progress: number) => undefined;

  @Local searchQuery: string = '';
  @Local searchRevealed: boolean = false;
  @Local searchInputFocused: boolean = false;
  // These values drive the pull-to-reveal layout on every gesture frame. They
  // must be observable in ComponentV2; a plain private field would update the
  // value without rebuilding the search slot, which makes the keyboard appear
  // while the field itself remains at zero height.
  @Local searchPullOffset: number = 0;
  @Local searchPullFinished: boolean = false;
  private searchFocusScheduled: boolean = false;
  private searchAnimationToken: number = 0;

  aboutToAppear(): void {
    this.searchFocusScheduled = false;
    this.searchRevealed = false;
    this.searchPullOffset = 0;
    this.searchPullFinished = false;
    this.searchAnimationToken = 0;
    this.searchInputFocused = false;
    this.publishSearchProgress();
  }

  private requestSearchFocus(): void {
    if (!this.showSearch || !this.searchRevealed || this.searchFocusScheduled) {
      return;
    }
    this.searchFocusScheduled = true;
    // The overview is conditionally mounted after the address-bar swipe.
    // Request focus on the next UI turn so the TextInput is on the tree and
    // ArkUI can raise the system keyboard for direct tag searching.
    setTimeout(() => {
      this.searchFocusScheduled = false;
      if (!this.showSearch || !this.searchRevealed) {
        return;
      }
      try {
        this.getUIContext().getFocusController().requestFocus('tab-overview-search-input');
      } catch (_error) {
        // The field may be between conditional mount/unmount frames; a later
        // appearance will retry without affecting the overview transition.
      }
    }, 0);
  }

  private beginSearchPull(): void {
    this.searchAnimationToken += 1;
    this.searchPullOffset = this.searchRevealed ? TAB_SEARCH_PULL_THRESHOLD : 0;
    this.searchPullFinished = false;
    this.publishSearchProgress();
  }

  private updateSearchPull(event?: GestureEvent): void {
    if (!this.showSearch || this.searchPullFinished) {
      return;
    }
    const offsetY: number = event?.offsetY ?? 0;
    const baseOffset: number = this.searchRevealed ? TAB_SEARCH_PULL_THRESHOLD : 0;
    this.searchPullOffset = Math.max(0, baseOffset + offsetY);
    this.publishSearchProgress();
  }

  private finishSearchPull(): void {
    if (!this.showSearch || this.searchPullFinished) {
      return;
    }
    this.searchPullFinished = true;
    if (tabSearchPullProgress(this.searchPullOffset) >= 0.5) {
      this.animateSearchTo(TAB_SEARCH_PULL_THRESHOLD, true);
      return;
    }
    this.animateSearchTo(0, false);
  }

  private cancelSearchPull(): void {
    this.searchPullFinished = true;
    if (this.searchPullOffset <= 0 && !this.searchRevealed) {
      return;
    }
    this.animateSearchTo(0, false);
  }

  /** Animate the native search slot to/from its pull distance. */
  private animateSearchTo(targetOffset: number, reveal: boolean): void {
    const token: number = this.searchAnimationToken + 1;
    this.searchAnimationToken = token;
    this.getUIContext().animateTo({
      duration: TAB_SEARCH_REVEAL_ANIMATION_DURATION_MS,
      curve: Curve.Friction
    }, () => {
      this.searchPullOffset = targetOffset;
      // This callback runs inside the same native animation transaction as the
      // search slot and grid spacer, so the mounted live page follows them
      // instead of waiting for a second, independent animation.
      this.publishSearchProgress();
    });
    setTimeout(() => {
      if (token !== this.searchAnimationToken) {
        return;
      }
      this.searchRevealed = reveal;
      this.publishSearchProgress();
      if (reveal) {
        this.requestSearchFocus();
      }
    }, TAB_SEARCH_REVEAL_ANIMATION_DURATION_MS);
  }

  private visibleTabs(): BrowserTabRecord[] {
    return filterTabsByQuery(this.tabs, this.searchQuery);
  }

  private gridTopPadding(): number {
    return tabOverviewTopPaddingForProgress(this.topInset, this.searchProgress());
  }

  private searchProgress(): number {
    return tabSearchVisualProgress(this.searchPullOffset);
  }

  private panelOpacity(): number {
    // During a horizontal card close the thumbnail becomes the visual owner
    // of the active card. Keep the grid opaque for that interval; otherwise
    // the normal live-page handoff fades the card out while its snapshot is
    // still travelling with the shell.
    if (this.activeCloseThumbnailVisible()) {
      return 1;
    }
    if (this.livePageTransform) {
      return tabOverviewGridOpacityAtProgress(this.overviewProgress, true);
    }
    return this.interactiveReveal ? this.overviewProgress : 1;
  }

  private panelScale(): number {
    // The page-to-card scale belongs to the mounted live page below. Scaling
    // the whole grid here would make the two visual tracks drift apart.
    return 1;
  }

  private searchSlotHeight(): number {
    return tabOverviewSearchSlotHeightForProgress(this.topInset, this.searchProgress());
  }

  private publishSearchProgress(): void {
    this.onSearchProgress(this.searchProgress());
  }

  private indexFor(tabId: TabId): number {
    return this.tabs.findIndex((tab: BrowserTabRecord) => tab.id === tabId);
  }

  private activeCloseThumbnailVisible(): boolean {
    if (!this.livePageTransform || this.activeTabId.length === 0) {
      return false;
    }
    return shouldUseTabOverviewCloseThumbnail(
      this.cardProgressFor(this.activeTabId),
      this.thumbnailFor(this.activeTabId) !== undefined
    );
  }

  private cardUsesCloseThumbnail(tab: BrowserTabRecord): boolean {
    return tab.id === this.activeTabId && this.activeCloseThumbnailVisible();
  }

  @Builder
  private searchBar() {
    Stack() {
      Row() {
        TextInput({
          text: this.searchQuery,
          placeholder: placeholderForFocus('搜索标签页', this.searchInputFocused)
        })
          .id('tab-overview-search-input')
          .width('100%')
          .height(TAB_SEARCH_BAR_STYLE.height)
          // The inset is owned by the gray pill itself. With no leading icon
          // or nested frame, the native caret remains unobstructed.
          .padding({ left: TAB_SEARCH_BAR_CONTENT_INSET, right: TAB_SEARCH_BAR_CONTENT_INSET })
          .fontSize(15)
          .fontColor('#1D1D1F')
          .placeholderColor('#7E858B')
          .backgroundColor(Color.Transparent)
          .onFocus(() => this.searchInputFocused = true)
          .onBlur(() => this.searchInputFocused = false)
          // The field is focused only after the pull-to-reveal threshold, so
          // opening the multi-page view itself never raises the keyboard.
          .defaultFocus(this.showSearch && this.searchRevealed)
          .onVisibleAreaChange([0.0, 1.0], (isVisible: boolean, _ratio: number) => {
            if (isVisible) {
              this.requestSearchFocus();
            }
          })
          .onChange((value: string) => this.searchQuery = value);
      }
        .id('tab-overview-search-bar')
        .width(`calc(100% - ${TAB_SEARCH_BAR_STYLE.horizontalInset * 2}vp)`)
        .height(TAB_SEARCH_BAR_STYLE.height)
        .margin({ left: 12, right: 12, top: 10 + this.topInset, bottom: 4 })
        .opacity(this.searchProgress())
        .translate({ y: -20 * (1 - this.searchProgress()) })
        // A single gray pill is the pull-to-reveal search control.
        .backgroundColor(TAB_SEARCH_BAR_BACKGROUND_COLOR)
        .borderRadius(TAB_SEARCH_BAR_STYLE.cornerRadius);
    }
      .width('100%')
      .height(this.searchSlotHeight())
      .clip(true);
  }

  @Builder
  private buildCard(tab: BrowserTabRecord) {
    GridItem() {
      TabCard({
        tab: tab,
        index: this.indexFor(tab.id),
        tabCount: this.tabs.length,
        cardHeight: TAB_OVERVIEW_LAYOUT.cardHeight,
        isActive: tab.id === this.activeTabId,
        livePreview: this.livePageTransform && tab.id === this.activeTabId &&
          !this.cardUsesCloseThumbnail(tab),
        livePreviewBorder: this.livePageTransform && tab.id === this.activeTabId &&
          !this.cardUsesCloseThumbnail(tab) &&
          tabOverviewBorderOwner(this.overviewProgress, this.overviewClosing) === 'card',
        thumbnail: this.thumbnailFor(tab.id),
        closeProgress: this.cardProgressFor(tab.id),
        verticalOffset: this.cardOffsetFor(tab.id),
        horizontalOffset: this.cardHorizontalOffsetFor(tab.id),
        // The grid's single top spacer owns safe-area breathing room. Keeping
        // the card translation at zero avoids double-counting it per row.
        topOffset: 0,
        onOpen: (tabId: TabId) => this.onOpen(tabId),
        onCloseStart: (tabId: TabId) => this.onCloseStart(tabId),
        onCloseUpdate: (tabId: TabId, sample: GestureSample) => this.onCloseUpdate(tabId, sample),
        onCloseEnd: (tabId: TabId, sample: GestureSample) => this.onCloseEnd(tabId, sample),
        onCloseCancel: (tabId: TabId) => this.onCloseCancel(tabId),
        onCloseTap: (tabId: TabId) => this.onCloseTap(tabId),
        onNewTab: () => this.onNewTab(),
        onCloseAllTabs: () => this.onCloseAllTabs(),
        onReorderStart: (tabId: TabId) => this.onReorderStart(tabId),
        onReorder: (tabId: TabId, targetIndex: number) => this.onReorder(tabId, targetIndex)
      });
    }
      .width('100%')
      .height(TAB_OVERVIEW_LAYOUT.cardHeight);
  }

  @Builder
  private emptyState() {
    // Keep the overview quiet when a query has no match. User-facing
    // explanatory prompts are intentionally omitted from this surface.
    Blank()
      .id('tab-overview-empty-state')
      .width('100%')
      .layoutWeight(1)
      .height('100%');
  }

  @Builder
  private cardGrid() {
    Column() {
      Blank()
        .height(this.gridTopPadding())
        .width('100%');
      Grid() {
        ForEach(this.visibleTabs(), (tab: BrowserTabRecord) => {
          this.buildCard(tab);
        }, (tab: BrowserTabRecord) => tab.id);
      }
        .id('tab-overview-grid')
        .columnsTemplate('1fr 1fr')
        .rowsGap(TAB_OVERVIEW_LAYOUT.gap)
        .columnsGap(TAB_OVERVIEW_LAYOUT.gap)
        .padding({
          left: TAB_OVERVIEW_LAYOUT.horizontalPadding,
          right: TAB_OVERVIEW_LAYOUT.horizontalPadding,
          top: 0,
          bottom: 10
        })
        .layoutWeight(1)
        .width('100%')
      .parallelGesture(
          PanGesture({ direction: PanDirection.Vertical })
            .onActionStart(() => this.beginSearchPull())
            .onActionUpdate((event: GestureEvent | undefined) => this.updateSearchPull(event))
            .onActionEnd(() => this.finishSearchPull())
            .onActionCancel(() => this.cancelSearchPull())
        );
    }
      .id('tab-overview-grid-container')
      .layoutWeight(1)
      .width('100%');
  }

  @Builder
  private bottomToolbar() {
    // Keep the safe-area reservation in a transparent wrapper, so the
    // material surface itself can float above the system navigation area.
    Stack({ alignContent: Alignment.Bottom }) {
      Row() {
        Button({ type: ButtonType.Normal, stateEffect: false }) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(23)
            .fontColor(['#007AFF']);
        }
          .id('tab-overview-new-button')
          .width(44)
          .height(44)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .stateEffect(false)
          .onClick(() => this.onNewTab());
        Button({ type: ButtonType.Normal, stateEffect: false }) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(23)
            .fontColor(['#007AFF']);
        }
          .id('tab-overview-done-button')
          .width(44)
          .height(44)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .stateEffect(false)
          .onClick(() => this.onDismiss());
      }
        .width(108)
        .height(52)
        .padding({ left: 8, right: 8 })
        .justifyContent(FlexAlign.SpaceBetween)
        .backgroundColor('#D9F2F2F7')
        .borderRadius(HARMONY_RADIUS_FLOATING)
        .clip(true)
        .shadow({ radius: 16, color: '#28000000', offsetX: 0, offsetY: 4 })
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
          interactive: false
        }));
    }
      .id('tab-overview-bottom-toolbar')
      .width('100%')
      .height(60 + Math.max(0, this.bottomInset))
      .padding({ bottom: 8 + Math.max(0, this.bottomInset) })
      .backgroundColor(Color.Transparent)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.livePageTransform ? Color.Transparent : TAB_OVERVIEW_BACKGROUND_COLOR);

      Column() {
        if (this.showSearch) {
          this.searchBar();
        }
        if (this.visibleTabs().length === 0) {
          this.emptyState();
        } else {
          this.cardGrid();
        }
        this.bottomToolbar();
      }
        .id('tab-overview-panel')
        .width('100%')
        .height('100%')
        .backgroundColor(this.livePageTransform ? Color.Transparent : TAB_OVERVIEW_BACKGROUND_COLOR)
        .opacity(this.panelOpacity())
        .scale({
          x: this.panelScale(),
          y: this.panelScale(),
          z: 1
        });

    }
      .id('tab-overview')
      .width('100%')
      .height('100%');
  }
}
