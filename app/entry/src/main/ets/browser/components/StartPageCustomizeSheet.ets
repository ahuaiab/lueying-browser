import { uiMaterial } from '@kit.ArkUI';
import { curves } from '@kit.ArkUI';
import {
  BrowserSearchEngine,
  BrowserSettings,
  copyBrowserSettings,
  DEFAULT_BROWSER_SETTINGS
} from '../model/BrowserSettings';
import { searchEngineLabel } from '../model/BrowserTypes';
import {
  StartPageItem,
  StartPageItemType,
  copyStartPageItem,
  sortStartPageItems
} from '../model/StartPageModels';
import {
  HARMONY_RADIUS_CARD,
  HARMONY_RADIUS_SHEET,
  START_PAGE_CUSTOMIZE_DISMISS_SPRING_RESPONSE,
  START_PAGE_CUSTOMIZE_DISMISS_SPRING_DAMPING,
  START_PAGE_CUSTOMIZE_DISMISS_SPRING_OVERLAP
} from '../model/BrowserVisualMetrics';

/**
 * Native start-page editor.  The video exposes switches and reorder handles;
 * this sheet keeps those actions local to the app and deliberately omits the
 * excluded Reading List and Tab Groups entries.
 */
@ComponentV2
export struct StartPageCustomizeSheet {
  @Param settings: BrowserSettings = DEFAULT_BROWSER_SETTINGS;
  @Param items: StartPageItem[] = [];
  @Param topInset: number = 0;
  @Param bottomInset: number = 0;
  @Param onSettingsChange: (settings: BrowserSettings) => void =
    (_settings: BrowserSettings) => undefined;
  @Param onItemsChange: (items: StartPageItem[]) => void =
    (_items: StartPageItem[]) => undefined;
  @Param onSelectBackground: () => void = () => undefined;
  @Param onClose: () => void = () => undefined;
  @Param onDismissStart: () => void = () => undefined;

  @Local engineExpanded: boolean = false;
  @Local swipeItemId: string = '';
  @Local swipeOffsetY: number = 0;
  private swipeFinished: boolean = false;
  @Local sheetOffsetY: number = 0;
  private sheetSwipeFinished: boolean = false;
  @Local reorderItemId: string = '';
  @Local reorderOffsetY: number = 0;
  private reorderTracking: boolean = false;
  private reorderLongPressTriggered: boolean = false;

  private safeTopInset(): number {
    // The sheet itself is aligned to the bottom of an immersive window. Keep
    // a bounded breathing gap so the title never touches the status capsule,
    // even during the first frame before avoidAreaChange is delivered.
    // This sheet already starts well below the status region. Keep the title
    // close to its rounded top edge instead of reserving a second full safe
    // area inside the sheet.
    return Math.max(0, Math.min(this.topInset, 4));
  }

  private settingWith(
    showFavorites: boolean,
    showFrequentSites: boolean,
    searchEngine: BrowserSearchEngine = this.settings.searchEngine
  ): BrowserSettings {
    const next: BrowserSettings = copyBrowserSettings(this.settings);
    next.showFavorites = showFavorites;
    next.showFrequentSites = showFrequentSites;
    next.searchEngine = searchEngine;
    // A change made from the editor is an explicit opt-in. This marker also
    // prevents legacy persisted defaults from silently reappearing.
    next.startPageSectionsConfigured = true;
    return next;
  }

  private updateSettings(next: BrowserSettings): void {
    this.onSettingsChange(copyBrowserSettings(next));
  }

  private startPageBackgroundLabel(): string {
    return this.settings.startPageBackgroundId.trim() === 'system-gradient'
      ? '系统默认'
      : '选择图片';
  }

  private engineOptions(): BrowserSearchEngine[] {
    return [
      BrowserSearchEngine.YAHOO,
      BrowserSearchEngine.BING,
      BrowserSearchEngine.BAIDU,
      BrowserSearchEngine.GOOGLE,
      BrowserSearchEngine.DUCKDUCKGO,
      BrowserSearchEngine.SOGOU
    ];
  }

  private editableItems(): StartPageItem[] {
    // History/frequently-visited records are intentionally not managed from
    // the custom start page. Only explicit favorites are user-owned tiles.
    return sortStartPageItems(this.items.filter((item: StartPageItem) =>
      item.type === StartPageItemType.FAVORITE));
  }

  private itemPosition(item: StartPageItem): number {
    return this.editableItems().findIndex((candidate: StartPageItem) => candidate.id === item.id);
  }

  private moveItem(item: StartPageItem, direction: number): void {
    const all: StartPageItem[] = this.items.map((candidate: StartPageItem) => copyStartPageItem(candidate));
    const sameType: StartPageItem[] = sortStartPageItems(all.filter((candidate: StartPageItem) =>
      candidate.type === item.type));
    const index: number = sameType.findIndex((candidate: StartPageItem) => candidate.id === item.id);
    const target: number = index + direction;
    if (index < 0 || target < 0 || target >= sameType.length) {
      return;
    }
    const firstOrder: number = sameType[index].order;
    sameType[index].order = sameType[target].order;
    sameType[target].order = firstOrder;
    const orderById: Map<string, number> = new Map();
    sameType.forEach((candidate: StartPageItem) => orderById.set(candidate.id, candidate.order));
    const reordered: StartPageItem[] = all.map((candidate: StartPageItem) => {
      const next: StartPageItem = copyStartPageItem(candidate);
      next.order = orderById.get(candidate.id) ?? candidate.order;
      return next;
    });
    this.onItemsChange(sortStartPageItems(reordered));
  }

  private beginReorder(item: StartPageItem): void {
    this.reorderItemId = item.id;
    this.reorderOffsetY = 0;
    this.reorderTracking = true;
    this.reorderLongPressTriggered = false;
  }

  private markReorderLongPress(item: StartPageItem): void {
    if (!this.reorderTracking || this.reorderItemId !== item.id) {
      return;
    }
    this.reorderLongPressTriggered = true;
  }

  private updateReorder(item: StartPageItem, event?: GestureEvent): void {
    if (!this.reorderTracking || !this.reorderLongPressTriggered || this.reorderItemId !== item.id) {
      return;
    }
    this.reorderOffsetY = event?.offsetY ?? 0;
  }

  private finishReorder(item: StartPageItem): void {
    if (!this.reorderTracking || this.reorderItemId !== item.id) {
      return;
    }
    const offset: number = this.reorderOffsetY;
    this.reorderTracking = false;
    this.reorderLongPressTriggered = false;
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.reorderOffsetY = 0;
    });
    const step: number = Math.round(offset / 64);
    if (step !== 0) {
      this.moveItem(item, step);
    }
    setTimeout(() => {
      if (!this.reorderTracking) {
        this.reorderItemId = '';
      }
    }, 180);
  }

  private cancelReorder(item: StartPageItem): void {
    if (this.reorderItemId !== item.id) {
      return;
    }
    this.reorderTracking = false;
    this.reorderLongPressTriggered = false;
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.reorderOffsetY = 0;
    });
    this.reorderItemId = '';
  }

  private removeItem(item: StartPageItem): void {
    this.onItemsChange(this.items
      .filter((candidate: StartPageItem) => candidate.id !== item.id)
      .map((candidate: StartPageItem) => copyStartPageItem(candidate)));
  }

  private beginItemSwipe(item: StartPageItem): void {
    this.swipeItemId = item.id;
    this.swipeOffsetY = 0;
    this.swipeFinished = false;
  }

  private updateItemSwipe(item: StartPageItem, event?: GestureEvent): void {
    if (this.swipeFinished || this.swipeItemId !== item.id) {
      return;
    }
    this.swipeOffsetY = Math.max(0, event?.offsetY ?? 0);
  }

  private finishItemSwipe(item: StartPageItem): void {
    if (this.swipeFinished || this.swipeItemId !== item.id) {
      return;
    }
    this.swipeFinished = true;
    if (this.swipeOffsetY < 48) {
      this.swipeOffsetY = 0;
      this.swipeItemId = '';
      return;
    }
    const target: StartPageItem = copyStartPageItem(item);
    this.getUIContext().animateTo({ duration: 180, curve: Curve.Friction }, () => {
      this.swipeOffsetY = 72;
    });
    setTimeout(() => {
      this.removeItem(target);
      this.swipeOffsetY = 0;
      this.swipeItemId = '';
    }, 180);
  }

  private cancelItemSwipe(item: StartPageItem): void {
    if (this.swipeItemId !== item.id) {
      return;
    }
    this.swipeFinished = true;
    this.swipeOffsetY = 0;
    this.swipeItemId = '';
  }

  private beginSheetSwipe(): void {
    this.sheetOffsetY = 0;
    this.sheetSwipeFinished = false;
  }

  private updateSheetSwipe(event?: GestureEvent): void {
    if (this.sheetSwipeFinished) {
      return;
    }
    this.sheetOffsetY = Math.max(0, event?.offsetY ?? 0);
  }

  private finishSheetSwipe(): void {
    if (this.sheetSwipeFinished) {
      return;
    }
    this.sheetSwipeFinished = true;
    if (this.sheetOffsetY < 80) {
      this.getUIContext().animateTo({
        curve: curves.springMotion(
          START_PAGE_CUSTOMIZE_DISMISS_SPRING_RESPONSE,
          START_PAGE_CUSTOMIZE_DISMISS_SPRING_DAMPING,
          START_PAGE_CUSTOMIZE_DISMISS_SPRING_OVERLAP
        )
      }, () => {
        this.sheetOffsetY = 0;
      });
      return;
    }
    this.onDismissStart();
    // The parent owns the single dismissal spring. Starting another spring to
    // a fixed 260vp offset here creates a visible pause before the removal
    // transition begins. Keep the current drag offset and hand off directly
    // so the sheet continues downward without a two-stage stop.
    this.onClose();
  }

  private cancelSheetSwipe(): void {
    this.sheetSwipeFinished = true;
    this.getUIContext().animateTo({
      curve: curves.springMotion(
        START_PAGE_CUSTOMIZE_DISMISS_SPRING_RESPONSE,
        START_PAGE_CUSTOMIZE_DISMISS_SPRING_DAMPING,
        START_PAGE_CUSTOMIZE_DISMISS_SPRING_OVERLAP
      )
    }, () => {
      this.sheetOffsetY = 0;
    });
  }

  @Builder
  private toggleRow(id: string, icon: Resource, title: string, value: boolean,
    onChange: (enabled: boolean) => void) {
    Row({ space: 12 }) {
      SymbolGlyph(icon)
        .id(`${id}-icon`)
        .fontSize(22)
        .fontColor(['#1D1D1F']);
      Text(title)
        .fontSize(16)
        .fontColor('#1D1D1F')
        .layoutWeight(1);
      Toggle({ type: ToggleType.Switch, isOn: value })
        .id(`${id}-toggle`)
        .selectedColor('#007AFF')
        .switchPointColor(Color.White)
        .onChange(onChange);
    }
      .id(id)
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 12 })
      .border({ width: { bottom: 1 }, color: '#E5E5EA' });
  }

  @Builder
  private engineRow() {
    Column() {
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(22)
          .fontColor(['#1D1D1F']);
        Text('搜索引擎')
          .fontSize(16)
          .fontColor('#1D1D1F')
          .layoutWeight(1);
        Button(searchEngineLabel(this.settings.searchEngine), { type: ButtonType.Normal, stateEffect: false })
          .id('start-page-search-engine-value')
          .fontSize(14)
          .fontColor('#007AFF')
          .backgroundColor(Color.Transparent)
          .padding({ left: 8, right: 0 })
          .stateEffect(false)
          .onClick(() => this.engineExpanded = !this.engineExpanded);
        SymbolGlyph(this.engineExpanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
          .fontSize(15)
          .fontColor(['#8E8E93']);
      }
        .id('start-page-search-engine-row')
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 });

      if (this.engineExpanded) {
        Column() {
          ForEach(this.engineOptions(), (engine: BrowserSearchEngine) => {
            Button({ type: ButtonType.Normal, stateEffect: false }) {
              Row() {
                Text(searchEngineLabel(engine))
                  .fontSize(15)
                  .fontColor('#1D1D1F')
                  .layoutWeight(1);
                if (this.settings.searchEngine === engine) {
                  SymbolGlyph($r('sys.symbol.checkmark'))
                    .fontSize(18)
                    .fontColor(['#007AFF']);
                }
              }
                .width('100%')
                .height(44);
            }
              .id(`start-page-search-engine-${engine}`)
              .width('100%')
              .height(44)
              .padding({ left: 52, right: 16 })
              .backgroundColor(Color.Transparent)
              .stateEffect(false)
              .onClick(() => {
                this.updateSettings(this.settingWith(
                  this.settings.showFavorites,
                  this.settings.showFrequentSites,
                  engine
                ));
                this.engineExpanded = false;
              });
          }, (engine: BrowserSearchEngine) => engine);
        }
          .width('100%')
          .backgroundColor('#F8F8FA');
      }
    }
      .id('start-page-search-engine-section')
      .width('100%')
      // Every settings group uses the same quiet gray surface; only the
      // expanded options get a slightly lighter inset to preserve hierarchy.
      .backgroundColor('#F2F2F7')
      .border({ width: { bottom: 1 }, color: '#E5E5EA' });
  }

  @Builder
  private backgroundRow() {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.circle_lefthalf_inset_filled'))
        .fontSize(22)
        .fontColor(['#1D1D1F']);
      Text('初始页背景')
        .fontSize(16)
        .fontColor('#1D1D1F')
        .layoutWeight(1);
      Text(this.startPageBackgroundLabel())
        .fontSize(14)
        .fontColor('#007AFF');
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(15)
        .fontColor(['#8E8E93']);
    }
      .id('start-page-background-row')
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .onClick(() => this.onSelectBackground());
  }

  @Builder
  private reorderRow(item: StartPageItem) {
    Row({ space: 10 }) {
      SymbolGlyph(item.type === StartPageItemType.FAVORITE
        ? $r('sys.symbol.star') : $r('sys.symbol.clock'))
        .fontSize(19)
        .fontColor(['#007AFF']);
      Column({ space: 2 }) {
        Text(item.title.length > 0 ? item.title : item.url)
          .fontSize(14)
          .fontColor('#1D1D1F')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%');
        Text(item.type === StartPageItemType.FAVORITE ? '书签' : '经常访问的网站')
          .fontSize(11)
          .fontColor('#8E8E93');
      }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);
      // Each user-managed start-page entry is enabled by default. Turning the
      // switch off removes that entry from the start page; the adjacent native
      // handle remains dedicated to long-press vertical ordering.
      Toggle({ type: ToggleType.Switch, isOn: true })
        .id(`start-page-item-toggle-${item.id}`)
        .selectedColor('#007AFF')
        .switchPointColor(Color.White)
        .onChange((enabled: boolean) => {
          if (!enabled) {
            this.removeItem(item);
          }
        });
      // Native three-line handle. The parallel long-press/pan recognizers
      // require a deliberate 300ms hold before vertical movement can reorder
      // the item; a short tap does nothing and never changes the switch.
      SymbolGlyph($r('sys.symbol.line_3_horizontal'))
        .id(`start-page-item-reorder-${item.id}`)
        .fontSize(20)
        .fontColor(['#8E8E93'])
        .width(40)
        .height(40)
        .hitTestBehavior(HitTestMode.Block)
        .gesture(
          GestureGroup(
            GestureMode.Parallel,
            LongPressGesture({ duration: 300 })
              .onAction(() => this.markReorderLongPress(item)),
            PanGesture({ direction: PanDirection.Vertical })
              .onActionStart(() => this.beginReorder(item))
              .onActionUpdate((event: GestureEvent | undefined) => this.updateReorder(item, event))
              .onActionEnd(() => this.finishReorder(item))
              .onActionCancel(() => this.cancelReorder(item))
          )
        );
    }
      .id(`start-page-item-editor-${item.id}`)
      .width('100%')
      .height(58)
      .padding({ left: 16, right: 10 })
      // User-managed start-page entries are lightweight gray labels on the
      // white sheet, matching the Safari card hierarchy.
      .backgroundColor('#F2F2F7')
      .border({ width: { bottom: 1 }, color: '#E5E5EA' })
      .borderRadius(HARMONY_RADIUS_CARD)
      .clip(true)
      .opacity(this.swipeItemId === item.id ? Math.max(0.25, 1 - this.swipeOffsetY / 90) : 1)
      .translate({
        y: this.reorderItemId === item.id
          ? this.reorderOffsetY
          : (this.swipeItemId === item.id ? this.swipeOffsetY : 0),
        x: 0,
        z: 0
      })
      .scale({
        x: this.reorderItemId === item.id ? 1.02 : 1,
        y: this.reorderItemId === item.id ? 1.02 : 1,
        z: 1
      })
      // A downward swipe removes an explicit favorite; there is no red
      // close button competing with the row's reorder controls.
      .gesture(
        PanGesture({ direction: PanDirection.Down })
          .onActionStart(() => this.beginItemSwipe(item))
          .onActionUpdate((event: GestureEvent | undefined) => this.updateItemSwipe(item, event))
          .onActionEnd(() => this.finishItemSwipe(item))
          .onActionCancel(() => this.cancelItemSwipe(item))
      );
  }

  build() {
    Column() {
      // Measure the sheet against the full window and anchor it at the
      // bottom. A direct height on the component itself can otherwise be
      // aligned to the remaining content area above the browser chrome.
      Blank()
        .width('100%')
        .layoutWeight(1);

      Column() {
      Blank()
        .width('100%')
        .height(this.safeTopInset());
        Row() {
          Text('自定义起始页')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1D1D1F')
            .layoutWeight(1)
            .textAlign(TextAlign.Center);
        }
        .id('start-page-customize-header')
        .width('100%')
        .height(40)
        .padding({ left: 8, right: 8 });

      Scroll() {
        Column({ space: 16 }) {
          Column() {
            this.toggleRow('start-page-favorites-toggle', $r('sys.symbol.star'), '书签',
              this.settings.showFavorites, (enabled: boolean) => {
                this.updateSettings(this.settingWith(enabled, this.settings.showFrequentSites));
              });
            this.engineRow();
          }
            .width('100%')
            .backgroundColor('#F2F2F7')
            .clip(true)
            .borderRadius(HARMONY_RADIUS_CARD);

          Column() {
            this.backgroundRow();
          }
            .id('start-page-background-card')
            .width('100%')
            .backgroundColor('#F2F2F7')
            .clip(true)
            .borderRadius(HARMONY_RADIUS_CARD);

          Column() {
            ForEach(this.editableItems(), (item: StartPageItem) => {
              this.reorderRow(item);
            }, (item: StartPageItem) => item.id);
          }
            .width('100%')
            .backgroundColor('#F2F2F7')
            .clip(true)
            .borderRadius(HARMONY_RADIUS_CARD);

        }
          .width('100%')
          .height('100%')
          .padding({ left: 12, right: 12, bottom: 24 });
      }
        .id('start-page-customize-scroll')
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off);

      Blank()
        .width('100%')
        .height(Math.max(0, this.bottomInset));
      }
        .id('start-page-customize-sheet')
        .width('100%')
        // Keep the editor just high enough to cover the start-page edit affordance;
        // the rest of the options remain reachable through the native Scroll.
      .height('56%')
        .backgroundColor(Color.White)
        .borderRadius({ topLeft: HARMONY_RADIUS_SHEET, topRight: HARMONY_RADIUS_SHEET })
        .shadow({ radius: 18, color: '#55000000', offsetX: 0, offsetY: -4 })
        .clip(true)
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THIN,
          interactive: true
        }))
        .translate({ x: 0, y: this.sheetOffsetY, z: 0 })
        .parallelGesture(
          PanGesture({ direction: PanDirection.Down })
            .onActionStart(() => this.beginSheetSwipe())
            .onActionUpdate((event: GestureEvent | undefined) => this.updateSheetSwipe(event))
            .onActionEnd(() => this.finishSheetSwipe())
            .onActionCancel(() => this.cancelSheetSwipe())
        )
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
    }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent);
  }
}
