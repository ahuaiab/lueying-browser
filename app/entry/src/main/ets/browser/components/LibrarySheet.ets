import {
  LibraryEntry,
  LibrarySection,
  HistoryDeleteRange,
  HistoryTimelineGroup,
  filterLibraryEntries,
  historyTimelineGroups,
  librarySectionAfterSwipe,
  libraryEntries,
  librarySectionChrome,
  librarySectionBackground,
  libraryDismissProgress,
  libraryDismissShouldClose,
  LIBRARY_DISMISS_THRESHOLD,
  LIBRARY_SEARCH_PULL_THRESHOLD,
  LIBRARY_SEARCH_REVEAL_ANIMATION_DURATION_MS,
  LIBRARY_SHEET_HEIGHT_PERCENT,
  librarySearchPullProgress
} from '../model/LibraryModels';
import { BookmarkRecord, HistoryRecord } from '../model/BrowserTypes';
import { curves, uiMaterial } from '@kit.ArkUI';
import {
  TAB_SEARCH_BAR_BACKGROUND_COLOR,
  TAB_SEARCH_BAR_CONTENT_INSET,
  TAB_SEARCH_BAR_STYLE
} from '../model/TabOverviewActions';
import { placeholderForFocus } from '../model/BrowserInteraction';
import {
  HARMONY_RADIUS_CONTROL,
  HARMONY_RADIUS_FLOATING,
  HARMONY_RADIUS_SHEET,
  LIBRARY_CONTENT_WIDTH_PERCENT
} from '../model/BrowserVisualMetrics';

/**
 * Safari-like library sheet. This pass is deliberately visual: it aligns the
 * sheet chrome and list geometry while keeping the existing data callbacks.
 */
@ComponentV2
export struct LibrarySheet {
  @Param history: HistoryRecord[] = [];
  @Param bookmarks: BookmarkRecord[] = [];
  /** System top avoid area in vp; the sheet keeps a visual breathing gap below it. */
  @Param topInset: number = 0;
  /** Bottom navigation-indicator avoid area in vp. */
  @Param bottomInset: number = 0;
  @Param onOpen: (url: string) => void = (_url: string) => undefined;
  @Param onRemoveBookmark: (url: string) => void = (_url: string) => undefined;
  @Param onRemoveHistory: (url: string) => void = (_url: string) => undefined;
  @Param onDeleteHistoryRange: (range: HistoryDeleteRange) => void =
    (_range: HistoryDeleteRange) => undefined;
  @Param onClose: () => void = () => undefined;

  @Local section: LibrarySection = LibrarySection.BOOKMARKS;
  @Local editing: boolean = false;
  @Local sectionSwipeOffset: number = 0;
  @Local sectionTransitionProgress: number = 1;
  @Local sectionGestureActive: boolean = false;
  @Local longPressEntryId: string = '';
  @Local menuEntryId: string = '';
  @Local suppressEntryClickId: string = '';
  @Local sheetSwipeOffset: number = 0;
  @Local sheetGestureActive: boolean = false;
  @Local searchQuery: string = '';
  @Local searchPullOffset: number = 0;
  @Local searchRevealed: boolean = false;
  @Local searchInputFocused: boolean = false;
  @Local searchPullFinished: boolean = false;
  @Local editMenuShown: boolean = false;
  @Local editLongPressActive: boolean = false;
  @Local suppressEditClick: boolean = false;
  private sectionSwitchDirection: number = 1;
  private sectionAnimationToken: number = 0;
  private sheetAnimationToken: number = 0;
  private searchAnimationToken: number = 0;

  private sectionTitle(section: LibrarySection): string {
    return librarySectionChrome(section).title;
  }

  private selectSection(next: LibrarySection): void {
    if (next === this.section) {
      return;
    }
    this.sectionSwitchDirection = next === LibrarySection.HISTORY ? -1 : 1;
    this.sectionTransitionProgress = 0;
    this.sectionSwipeOffset = 0;
    this.section = next;
    const token: number = this.sectionAnimationToken + 1;
    this.sectionAnimationToken = token;
    this.getUIContext().animateTo({
      curve: curves.springMotion(),
      onFinish: () => {
        if (token === this.sectionAnimationToken) {
          this.sectionTransitionProgress = 1;
          this.sectionSwipeOffset = 0;
        }
      }
    }, () => {
      this.sectionTransitionProgress = 1;
    });
  }

  private beginSectionSwipe(): void {
    this.sectionGestureActive = true;
    this.sectionSwipeOffset = 0;
  }

  private updateSectionSwipe(event?: GestureEvent): void {
    if (!this.sectionGestureActive) {
      return;
    }
    const offset: number = event?.offsetX ?? 0;
    this.sectionSwipeOffset = Math.max(-96, Math.min(96, offset));
  }

  private finishSectionSwipe(event?: GestureEvent): void {
    if (!this.sectionGestureActive) {
      return;
    }
    const offset: number = Math.abs(this.sectionSwipeOffset) > 0
      ? this.sectionSwipeOffset
      : (event?.offsetX ?? 0);
    this.sectionGestureActive = false;
    const next: LibrarySection = librarySectionAfterSwipe(this.section, offset);
    if (next !== this.section) {
      this.selectSection(next);
      return;
    }
    this.getUIContext().animateTo({ curve: curves.springMotion() }, () => {
      this.sectionSwipeOffset = 0;
      this.sectionTransitionProgress = 1;
    });
  }

  private cancelSectionSwipe(): void {
    if (!this.sectionGestureActive && this.sectionSwipeOffset === 0) {
      return;
    }
    this.sectionGestureActive = false;
    this.getUIContext().animateTo({ curve: curves.springMotion() }, () => {
      this.sectionSwipeOffset = 0;
      this.sectionTransitionProgress = 1;
    });
  }

  private beginSheetSwipe(): void {
    this.sheetGestureActive = true;
    this.sheetAnimationToken += 1;
  }

  private updateSheetSwipe(event?: GestureEvent): void {
    if (!this.sheetGestureActive) {
      return;
    }
    const offset: number = event?.offsetY ?? 0;
    this.sheetSwipeOffset = Math.min(240, Math.max(0, offset));
  }

  private finishSheetSwipe(event?: GestureEvent): void {
    if (!this.sheetGestureActive) {
      return;
    }
    const offset: number = Math.max(0, this.sheetSwipeOffset > 0
      ? this.sheetSwipeOffset
      : (event?.offsetY ?? 0));
    this.sheetGestureActive = false;
    const token: number = this.sheetAnimationToken + 1;
    this.sheetAnimationToken = token;
    if (libraryDismissShouldClose(offset, LIBRARY_DISMISS_THRESHOLD)) {
      this.getUIContext().animateTo({
        curve: curves.springMotion(),
        onFinish: () => {
          if (token === this.sheetAnimationToken) {
            this.sheetSwipeOffset = 0;
            this.onClose();
          }
        }
      }, () => {
        this.sheetSwipeOffset = 240;
      });
      return;
    }
    this.getUIContext().animateTo({ curve: curves.springMotion() }, () => {
      this.sheetSwipeOffset = 0;
    });
  }

  private cancelSheetSwipe(): void {
    if (!this.sheetGestureActive && this.sheetSwipeOffset === 0) {
      return;
    }
    this.sheetGestureActive = false;
    this.sheetAnimationToken += 1;
    this.getUIContext().animateTo({ curve: curves.springMotion() }, () => {
      this.sheetSwipeOffset = 0;
    });
  }

  private beginSearchPull(): void {
    this.searchAnimationToken += 1;
    this.searchPullOffset = this.searchRevealed ? LIBRARY_SEARCH_PULL_THRESHOLD : 0;
    this.searchPullFinished = false;
  }

  private updateSearchPull(event?: GestureEvent): void {
    if (this.searchPullFinished) {
      return;
    }
    const baseOffset: number = this.searchRevealed ? LIBRARY_SEARCH_PULL_THRESHOLD : 0;
    this.searchPullOffset = Math.max(0, baseOffset + (event?.offsetY ?? 0));
  }

  private finishSearchPull(): void {
    if (this.searchPullFinished) {
      return;
    }
    this.searchPullFinished = true;
    const reveal: boolean = librarySearchPullProgress(this.searchPullOffset) >= 0.5;
    this.animateSearchTo(reveal ? LIBRARY_SEARCH_PULL_THRESHOLD : 0, reveal);
  }

  private cancelSearchPull(): void {
    this.searchPullFinished = true;
    if (this.searchPullOffset <= 0 && !this.searchRevealed) {
      return;
    }
    this.animateSearchTo(0, false);
  }

  private animateSearchTo(targetOffset: number, reveal: boolean): void {
    const token: number = this.searchAnimationToken + 1;
    this.searchAnimationToken = token;
    this.getUIContext().animateTo({
      duration: LIBRARY_SEARCH_REVEAL_ANIMATION_DURATION_MS,
      curve: curves.springMotion(),
      onFinish: () => {
        if (token === this.searchAnimationToken) {
          this.searchRevealed = reveal;
          this.searchPullFinished = false;
          if (reveal) {
            this.requestSearchFocus();
          }
        }
      }
    }, () => {
      this.searchPullOffset = targetOffset;
    });
  }

  private requestSearchFocus(): void {
    if (!this.searchRevealed) {
      return;
    }
    setTimeout(() => {
      if (!this.searchRevealed) {
        return;
      }
      try {
        this.getUIContext().getFocusController().requestFocus('library-search-input');
      } catch (_error) {
        // The field may be between conditional mount frames.
      }
    }, 0);
  }

  @Builder
  private sectionIcon(section: LibrarySection, size: number, color: string) {
    if (section === LibrarySection.BOOKMARKS) {
      SymbolGlyph($r('sys.symbol.bookmark'))
        .fontSize(size)
        .fontColor([color]);
    } else {
      SymbolGlyph($r('sys.symbol.clock'))
        .fontSize(size)
        .fontColor([color]);
    }
  }

  @Builder
  private sectionButton(section: LibrarySection) {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      this.sectionIcon(section, 18, this.section === section ? '#1D1D1F' : '#6B7280');
    }
      .id(`library-section-${section}`)
      .layoutWeight(1)
      .height(24)
      .padding(0)
      .backgroundColor(this.section === section
        ? librarySectionBackground(true)
        : Color.Transparent)
      .stateEffect(false)
      // The selected segment is inset by 2vp. A 12vp radius keeps its corner
      // arc center aligned with the outer 20vp floating surface (the native
      // layout clamps both radii to the control height when necessary).
      .borderRadius(HARMONY_RADIUS_CONTROL)
      .onClick(() => this.selectSection(section));
  }

  @Builder
  private bookmarkFolderRow() {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.star'))
        .fontSize(20)
        .fontColor(['#007AFF']);
      Text('书签')
        .fontSize(14)
        .fontColor('#1D1D1F');
      Blank().layoutWeight(1);
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor(['#C7C7CC']);
    }
      .id('library-bookmarks-folder')
      .width('100%')
      .height(36)
      .padding({ left: 8, right: 8 });
  }

  private entries(): LibraryEntry[] {
    return libraryEntries(this.section, this.history, this.bookmarks);
  }

  private filteredEntries(): LibraryEntry[] {
    return filterLibraryEntries(this.entries(), this.searchQuery);
  }

  private historyGroups(): HistoryTimelineGroup[] {
    const groups: HistoryTimelineGroup[] = historyTimelineGroups(this.history, Date.now());
    return groups
      .map((group: HistoryTimelineGroup): HistoryTimelineGroup => ({
        section: group.section,
        title: group.title,
        entries: filterLibraryEntries(group.entries, this.searchQuery)
      }))
      .filter((group: HistoryTimelineGroup) => group.entries.length > 0);
  }

  private removeEntry(entry: LibraryEntry): void {
    if (entry.section === LibrarySection.BOOKMARKS) {
      this.onRemoveBookmark(entry.url);
    } else {
      this.onRemoveHistory(entry.url);
    }
  }

  private beginEntryLongPress(entry: LibraryEntry): void {
    if (entry.section !== LibrarySection.HISTORY) {
      return;
    }
    this.longPressEntryId = entry.id;
    this.menuEntryId = entry.id;
    this.suppressEntryClickId = entry.id;
  }

  private endEntryLongPress(entryId: string): void {
    if (this.longPressEntryId === entryId) {
      this.longPressEntryId = '';
    }
    // Keep menuEntryId until the native menu reports onDisappear. Clearing it
    // at release time would unmount the menu before ArkUI opens its window.
  }

  private dismissEntryMenu(entryId: string): void {
    if (this.menuEntryId === entryId) {
      this.menuEntryId = '';
    }
    if (this.longPressEntryId === entryId) {
      this.longPressEntryId = '';
    }
    if (this.suppressEntryClickId === entryId) {
      this.suppressEntryClickId = '';
    }
  }

  private handleEntryClick(entry: LibraryEntry): void {
    if (this.suppressEntryClickId === entry.id) {
      this.suppressEntryClickId = '';
      return;
    }
    if (!this.editing) {
      this.onOpen(entry.url);
    }
  }

  private beginEditLongPress(): void {
    this.editLongPressActive = true;
    this.editMenuShown = true;
    this.suppressEditClick = true;
  }

  private endEditLongPress(): void {
    this.editLongPressActive = false;
  }

  private dismissEditMenu(): void {
    this.editLongPressActive = false;
    this.editMenuShown = false;
    this.suppressEditClick = false;
  }

  private handleEditClick(): void {
    if (this.suppressEditClick) {
      this.suppressEditClick = false;
      return;
    }
    this.editing = !this.editing;
  }

  @Builder
  private editMenu() {
    Menu() {
      MenuItem({ content: '删除今天历史记录' })
        .contentFontColor('#FF3B30')
        .onChange((selected: boolean) => {
          if (selected) {
            this.onDeleteHistoryRange(HistoryDeleteRange.TODAY);
            this.dismissEditMenu();
          }
        })
      MenuItem({ content: '删除本周历史记录' })
        .contentFontColor('#FF3B30')
        .onChange((selected: boolean) => {
          if (selected) {
            this.onDeleteHistoryRange(HistoryDeleteRange.THIS_WEEK);
            this.dismissEditMenu();
          }
        })
      MenuItem({ content: '删除全部历史记录' })
        .contentFontColor('#FF3B30')
        .onChange((selected: boolean) => {
          if (selected) {
            this.onDeleteHistoryRange(HistoryDeleteRange.ALL);
            this.dismissEditMenu();
          }
        })
    }
  }

  @Builder
  private historyMenu(entry: LibraryEntry) {
    Menu() {
      MenuItem({ content: '打开' })
        .onChange((selected: boolean) => {
          if (selected) {
            this.onOpen(entry.url);
            this.dismissEntryMenu(entry.id);
          }
        })
      MenuItem({ content: '删除' })
        .onChange((selected: boolean) => {
          if (selected) {
            this.onRemoveHistory(entry.url);
            this.dismissEntryMenu(entry.id);
          }
        })
    }
  }

  @Builder
  private entryIcon(entry: LibraryEntry) {
    if (entry.section === LibrarySection.BOOKMARKS) {
      SymbolGlyph($r('sys.symbol.bookmark_fill'))
        .fontSize(18)
        .fontColor(['#007AFF']);
    } else {
      SymbolGlyph($r('sys.symbol.clock'))
        .fontSize(18)
        .fontColor(['#8A8A90']);
    }
  }

  @Builder
  private entryRow(entry: LibraryEntry) {
    Column() {
      Row({ space: 12 }) {
        if (this.editing) {
          Button({ type: ButtonType.Normal, stateEffect: false }) {
            SymbolGlyph($r('sys.symbol.minus_circle_fill'))
              .fontSize(18)
              .fontColor(['#FF3B30']);
          }
            .id(`library-delete-${entry.id}`)
            .width(26)
            .height(26)
            .padding(0)
            .backgroundColor(Color.Transparent)
            .stateEffect(false)
            .onClick(() => this.removeEntry(entry));
        }
        Stack() {
          this.entryIcon(entry);
        }
          .width(26)
          .height(26)
          .alignContent(Alignment.Center);
        Column({ space: 2 }) {
          Text(entry.title)
            .fontSize(14)
            .fontColor('#1D1D1F')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%');
          if (entry.section !== LibrarySection.BOOKMARKS) {
            Text(entry.url)
              .fontSize(11)
              .fontColor('#8A8A90')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%');
          }
        }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start);
      }
        .width('100%')
        .height(entry.section === LibrarySection.BOOKMARKS ? 36 : 56);
      Row()
        .width('100%')
        .height(1)
        .margin({ left: 36 })
        .backgroundColor('#E5E5EA');
    }
      .id(`library-entry-${entry.id}`)
      .width('100%')
      .padding({ left: 8, right: 0 })
      .backgroundColor(Color.White)
      // ArkUI owns insertion/removal transitions so a delete from either
      // bookmark or history editing feels native and remains interruptible.
      .transition(
        TransitionEffect.asymmetric(
          TransitionEffect.OPACITY.combine(TransitionEffect.move(TransitionEdge.END)),
          TransitionEffect.OPACITY.combine(TransitionEffect.move(TransitionEdge.END))
        ).animation({ duration: 180, curve: Curve.EaseOut })
      )
      .onClick(() => this.handleEntryClick(entry))
      .bindContextMenu(this.menuEntryId === entry.id, this.historyMenu(entry), {
        placement: Placement.TopRight,
        systemMaterial: new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THIN,
          interactive: true
        }),
        onDisappear: () => this.dismissEntryMenu(entry.id)
      })
      .gesture(
        LongPressGesture({ duration: 300 })
          .onAction(() => this.beginEntryLongPress(entry))
          .onActionEnd(() => this.endEntryLongPress(entry.id))
          .onActionCancel(() => this.endEntryLongPress(entry.id))
      );
  }

  @Builder
  private sectionHeading(section: LibrarySection) {
    Text(this.sectionTitle(section))
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor('#6B6B72')
      .width('100%')
      .padding({ left: 14, top: 8, bottom: 6 });
  }

  @Builder
  private timelineHeading(title: string) {
    Text(title)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor('#6B6B72')
      .width('100%')
      .padding({ left: 14, top: 8, bottom: 6 });
  }

  @Builder
  private emptyState() {
    // Keep an empty history surface quiet. The sheet is a navigation surface,
    // not a toast area; no explanatory placeholder text is rendered here.
    Blank()
      .width('100%')
      .layoutWeight(1)
      .height('100%');
  }

  private searchProgress(): number {
    return librarySearchPullProgress(this.searchPullOffset);
  }

  private searchSlotHeight(): number {
    return (TAB_SEARCH_BAR_STYLE.height + 16) * this.searchProgress();
  }

  @Builder
  private searchBar() {
    Stack() {
      if (this.searchPullOffset > 0 || this.searchRevealed) {
        Row() {
          TextInput({
            text: this.searchQuery,
            placeholder: placeholderForFocus('搜索书签或历史记录', this.searchInputFocused)
          })
            .id('library-search-input')
            .width('100%')
            .height(TAB_SEARCH_BAR_STYLE.height)
            .padding({ left: TAB_SEARCH_BAR_CONTENT_INSET, right: TAB_SEARCH_BAR_CONTENT_INSET })
            .fontSize(15)
            .fontColor('#1D1D1F')
            .placeholderColor('#7E858B')
            .backgroundColor(Color.Transparent)
            .defaultFocus(this.searchRevealed)
            .onFocus(() => this.searchInputFocused = true)
            .onBlur(() => this.searchInputFocused = false)
            .onChange((value: string) => this.searchQuery = value);
        }
          .id('library-search-bar')
          .width(`calc(100% - ${TAB_SEARCH_BAR_STYLE.horizontalInset * 2}vp)`)
          .height(TAB_SEARCH_BAR_STYLE.height)
          .margin({ left: 12, right: 12, top: 10, bottom: 6 })
          .opacity(this.searchProgress())
          .translate({ y: -20 * (1 - this.searchProgress()) })
          .backgroundColor(TAB_SEARCH_BAR_BACKGROUND_COLOR)
          .borderRadius(TAB_SEARCH_BAR_STYLE.cornerRadius);
      }
    }
      .id('library-search-slot')
      .width('100%')
      .height(this.searchSlotHeight())
      .clip(true);
  }

  @Builder
  private bookmarkContent() {
    Scroll() {
      Column() {
        if (this.searchQuery.trim().length === 0) {
          this.bookmarkFolderRow();
        }
        ForEach(this.filteredEntries(), (entry: LibraryEntry) => {
          this.entryRow(entry);
        }, (entry: LibraryEntry) => entry.id);
      }
        .width('100%')
        // Scroll stretches its child to the viewport on the preview/device
        // renderer. Pin the content column to the top so the first folder
        // row stays directly below the segmented tabs instead of appearing
        // in the vertical middle of the sheet.
        .height('100%')
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Start);
    }
      .id(`library-entry-scroll-${this.section}`)
      .width(`${LIBRARY_CONTENT_WIDTH_PERCENT}%`)
      .alignSelf(ItemAlign.Center)
      .layoutWeight(1)
      .scrollBar(BarState.Off);
  }

  @Builder
  private listContent() {
    Scroll() {
      Column() {
        ForEach(this.historyGroups(), (group: HistoryTimelineGroup) => {
          Column() {
            this.timelineHeading(group.title);
            ForEach(group.entries, (entry: LibraryEntry) => {
              this.entryRow(entry);
            }, (entry: LibraryEntry) => entry.id);
          }
            .width('100%');
        }, (group: HistoryTimelineGroup) => group.section);
      }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Start);
    }
      .id(`library-entry-scroll-${this.section}`)
      .width(`${LIBRARY_CONTENT_WIDTH_PERCENT}%`)
      .alignSelf(ItemAlign.Center)
      .layoutWeight(1)
      .scrollBar(BarState.Off);
  }

  @Builder
  private content() {
    if (this.section === LibrarySection.BOOKMARKS) {
      this.bookmarkContent();
    } else if (this.historyGroups().length === 0) {
      this.emptyState();
    } else {
      this.listContent();
    }
  }

  @Builder
  private footerSpacer() {
    // The navigation indicator is a system-owned region. Keep the white
    // sheet's content clear of it; the edit control is rendered independently
    // as a floating action below, matching the tab overview chrome.
    Blank()
      .id('library-footer-spacer')
      .width('100%')
      .height(this.safeBottomInset());
  }

  @Builder
  private floatingEditButton() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      if (this.editing) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(22)
          .fontColor(['#007AFF']);
      } else {
        SymbolGlyph($r('sys.symbol.pencil_line'))
          .fontSize(22)
          .fontColor(['#007AFF']);
      }
    }
      .id('library-edit-button')
      .width(52)
      .height(52)
      .padding(0)
      .backgroundColor('#D9F2F2F7')
      .borderRadius(HARMONY_RADIUS_FLOATING)
      .shadow({ radius: 16, color: '#28000000', offsetX: 0, offsetY: 4 })
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        interactive: false
      }))
      .stateEffect(false)
      .onClick(() => this.handleEditClick())
      .bindContextMenu(this.editMenuShown, this.editMenu, {
        placement: Placement.TopRight,
        onDisappear: () => this.dismissEditMenu()
      })
      .parallelGesture(
        LongPressGesture({ duration: 300 })
          .onAction(() => this.beginEditLongPress())
          .onActionEnd(() => this.endEditLongPress())
          .onActionCancel(() => this.endEditLongPress())
      );
  }

  private safeBottomInset(): number {
    // Keep the edit action above the gesture indicator even when the window
    // reports its avoid area one frame late (or reports zero in Previewer).
    return Math.max(16, this.bottomInset);
  }

  private topContentInset(): number {
    // A small non-zero fallback covers the first frame on devices that report
    // TYPE_SYSTEM after the overlay has already been mounted. The page root
    // remains immersive, while the header text always starts below its
    // rounded sheet edge.
    // The rounded sheet edge already sits below the status region. A compact
    // 8–12vp breathing gap keeps the title visually attached to that edge.
    return Math.max(8, Math.min(this.topInset, 12));
  }

  build() {
    Stack() {
      Column() {
      // Keep the overlay itself transparent. Only the bottom sheet paints a
      // white surface, so the status-bar region is never covered by the
      // sheet's rounded top edge. This is important on full-screen devices
      // where the app content is laid out under the system status bar.
      Blank()
        .width('100%')
        .layoutWeight(1)
        // The backdrop is intentionally a real hit target: tapping outside
        // the sheet dismisses the library without adding a visible close
        // button or toast.
        .onClick(() => this.onClose());

      Column() {
        Blank()
          .width('100%')
          .height(this.topContentInset());
        Row() {
          this.sectionButton(LibrarySection.BOOKMARKS);
          this.sectionButton(LibrarySection.HISTORY);
        }
          .id('library-section-tabs')
          .width(`${LIBRARY_CONTENT_WIDTH_PERCENT}%`)
          .alignSelf(ItemAlign.Center)
          .height(30)
          .padding({ left: 2, right: 2, top: 2, bottom: 2 })
          // No persistent track: an unselected segment is the sheet surface
          // itself, while only the selected segment paints the gray pill.
          .backgroundColor(Color.Transparent);

        this.searchBar();

        Column() {
          this.content();
        }
          .id('library-content-transition')
          .width('100%')
          .layoutWeight(1)
          .opacity(0.72 + 0.28 * this.sectionTransitionProgress)
          .translate({
            x: this.sectionSwipeOffset + (1 - this.sectionTransitionProgress) * this.sectionSwitchDirection * 24,
            y: 0
          })
          .parallelGesture(
            PanGesture({ direction: PanDirection.Horizontal, distance: 8 })
              .onActionStart(() => this.beginSectionSwipe())
              .onActionUpdate((event: GestureEvent | undefined) => this.updateSectionSwipe(event))
              .onActionEnd((event: GestureEvent | undefined) => this.finishSectionSwipe(event))
              .onActionCancel(() => this.cancelSectionSwipe())
          )
          .parallelGesture(
            PanGesture({ direction: PanDirection.Vertical, distance: 8 })
              .onActionStart(() => this.beginSearchPull())
              .onActionUpdate((event: GestureEvent | undefined) => this.updateSearchPull(event))
              .onActionEnd(() => this.finishSearchPull())
              .onActionCancel(() => this.cancelSearchPull())
          );
        this.footerSpacer();
      }
        .id('library-sheet')
        .width('100%')
        // Leave a transparent breathing area above the sheet. The child
        // remains bottom-anchored and paints only its own rounded surface.
        .height(`${LIBRARY_SHEET_HEIGHT_PERCENT}%`)
        .padding({ left: 0, right: 0, top: 0, bottom: 0 })
        .backgroundColor(Color.White)
        .borderRadius({ topLeft: HARMONY_RADIUS_SHEET, topRight: HARMONY_RADIUS_SHEET })
        .shadow({ radius: 12, color: '#55000000', offsetX: 0, offsetY: -3 })
        .clip(true)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        .translate({ x: 0, y: this.sheetSwipeOffset })
        .opacity(1 - 0.22 * libraryDismissProgress(this.sheetSwipeOffset))
        .parallelGesture(
          PanGesture({ direction: PanDirection.Vertical, distance: 8 })
            .onActionStart(() => this.beginSheetSwipe())
            .onActionUpdate((event: GestureEvent | undefined) => this.updateSheetSwipe(event))
            .onActionEnd((event: GestureEvent | undefined) => this.finishSheetSwipe(event))
            .onActionCancel(() => this.cancelSheetSwipe())
        );
      }
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent);

      // Keep the edit/check control outside the sheet hierarchy. This gives
      // the library page the same independent floating action treatment as
      // the tab overview's plus and done controls.
      Stack({ alignContent: Alignment.BottomEnd }) {
        this.floatingEditButton();
      }
        .id('library-floating-edit-host')
        .width('100%')
        .height('100%')
        .padding({ right: 16, bottom: this.safeBottomInset() + 12 })
        // The host only positions the floating pencil. It must not become a
        // full-screen hit target and steal taps from the library tabs/list.
        .hitTestBehavior(HitTestMode.Transparent);
    }
      .width('100%')
      .height('100%');
  }
}
