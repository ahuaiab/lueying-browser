import {
  BrowserTabRecord,
  GestureAxis,
  GestureDecision,
  GestureOutcome,
  GestureSample,
  TabDirection,
  TabId
} from '../model/BrowserTypes';
import { GestureDecisionEngine } from '../gesture/GestureDecisionEngine';
import { DEFAULT_GESTURE_PROFILE } from '../gesture/GestureProfile';
import { TabStore } from '../store/TabStore';
import { HARMONY_RADIUS_FLOATING, HARMONY_RADIUS_SHEET } from '../model/BrowserVisualMetrics';

/**
 * 手势实验页验收清单：
 * 1. 底栏慢速上拖超过阈值后进入卡片总览。
 * 2. 底栏短距离上拖后松手回到单页。
 * 3. 底栏左拖切换下一个彩色标签。
 * 4. 最后一个标签继续左拖只产生阻尼并回弹。
 * 5. 总览卡片上甩关闭且只关闭一次。
 * 6. 总览卡片上拖不足阈值时回弹。
 */
@ComponentV2
export struct GestureLab {
  @Local overviewProgress: number = 0;
  @Local horizontalOffset: number = 0;
  @Local cardCloseProgress: number = 0;
  @Local debugText: string = 'IDLE';
  @Local activeCardId: TabId = '';

  private readonly store: TabStore = new TabStore();
  private readonly bottomEngine: GestureDecisionEngine = new GestureDecisionEngine();
  private readonly cardEngine: GestureDecisionEngine = new GestureDecisionEngine();
  private readonly panelColors: string[] = ['#F56C6C', '#67C23A', '#409EFF'];
  private readonly viewportWidth: number = 400;
  private readonly viewportHeight: number = 800;
  private readonly cardWidth: number = 160;

  aboutToAppear(): void {
    if (this.store.tabs.length === 0) {
      this.store.createTab('https://red.example', false);
      this.store.createTab('https://green.example', false);
      this.store.createTab('https://blue.example', false);
      const firstTab: BrowserTabRecord | undefined = this.store.tabs[0];
      if (firstTab !== undefined) {
        this.store.activateTab(firstTab.id);
      }
    }
  }

  private activeTab(): BrowserTabRecord | undefined {
    return this.store.tabs.find((tab: BrowserTabRecord) => tab.id === this.store.activeTabId);
  }

  private activeTitle(): string {
    return this.activeTab()?.title ?? '起始页';
  }

  private activeUrl(): string {
    return this.activeTab()?.url ?? 'about:blank';
  }

  private activeColor(): string {
    const index: number = this.store.tabs.findIndex(
      (tab: BrowserTabRecord) => tab.id === this.store.activeTabId
    );
    return this.panelColors[index < 0 ? 0 : index % this.panelColors.length];
  }

  private sampleFrom(event?: GestureEvent): GestureSample {
    return {
      dx: event?.offsetX ?? 0,
      dy: event?.offsetY ?? 0,
      velocityX: event?.velocityX ?? 0,
      velocityY: event?.velocityY ?? 0
    };
  }

  private hasPrevious(): boolean {
    return this.store.adjacentTabId(TabDirection.PREVIOUS) !== undefined;
  }

  private hasNext(): boolean {
    return this.store.adjacentTabId(TabDirection.NEXT) !== undefined;
  }

  private formatDecision(decision: GestureDecision): string {
    return `${decision.axis} 进度=${decision.progress.toFixed(2)} 偏移=${decision.visualOffset.toFixed(1)} 结果=${decision.outcome}`;
  }

  private applyBottomUpdate(decision: GestureDecision): void {
    if (decision.axis === GestureAxis.VERTICAL) {
      this.overviewProgress = decision.progress;
      this.horizontalOffset = 0;
    } else if (decision.axis === GestureAxis.HORIZONTAL) {
      this.horizontalOffset = decision.visualOffset;
      this.overviewProgress = 0;
    }
    this.debugText = this.formatDecision(decision);
  }

  private animateBottomTo(progress: number): void {
    this.getUIContext().animateTo({
      duration: DEFAULT_GESTURE_PROFILE.settleDurationMs,
      curve: Curve.Friction
    }, () => {
      this.overviewProgress = progress;
      this.horizontalOffset = 0;
    });
  }

  private finishBottomGesture(event?: GestureEvent): void {
    const decision: GestureDecision = this.bottomEngine.endBottomBar(
      this.sampleFrom(event),
      this.viewportWidth,
      this.viewportHeight,
      this.hasPrevious(),
      this.hasNext()
    );
    this.debugText = this.formatDecision(decision);
    if (decision.outcome === GestureOutcome.SHOW_OVERVIEW) {
      this.animateBottomTo(1);
      return;
    }
    if (decision.outcome === GestureOutcome.PREVIOUS_TAB) {
      const previous: TabId | undefined = this.store.adjacentTabId(TabDirection.PREVIOUS);
      if (previous !== undefined) {
        this.store.activateTab(previous);
      }
    } else if (decision.outcome === GestureOutcome.NEXT_TAB) {
      const next: TabId | undefined = this.store.adjacentTabId(TabDirection.NEXT);
      if (next !== undefined) {
        this.store.activateTab(next);
      }
    }
    this.animateBottomTo(0);
  }

  private cancelBottomGesture(): void {
    const decision: GestureDecision = this.bottomEngine.cancel();
    this.debugText = this.formatDecision(decision);
    this.animateBottomTo(0);
  }

  private openTab(tabId: TabId): void {
    this.store.activateTab(tabId);
    this.activeCardId = '';
    this.cardCloseProgress = 0;
    this.animateBottomTo(0);
    this.debugText = `打开标签 ${tabId}`;
  }

  private beginCardGesture(tabId: TabId): void {
    this.activeCardId = tabId;
    this.cardEngine.begin();
    this.cardCloseProgress = 0;
    this.debugText = `标签 ${tabId} 手势开始`;
  }

  private updateCardGesture(event?: GestureEvent): void {
    if (this.activeCardId.length === 0) {
      return;
    }
    const decision: GestureDecision = this.cardEngine.updateCardClose(
      this.sampleFrom(event),
      this.cardWidth
    );
    this.cardCloseProgress = decision.progress;
    this.debugText = this.formatDecision(decision);
  }

  private finishCardGesture(event?: GestureEvent): void {
    if (this.activeCardId.length === 0) {
      return;
    }
    const closingId: TabId = this.activeCardId;
    const decision: GestureDecision = this.cardEngine.endCardClose(
      this.sampleFrom(event),
      this.cardWidth
    );
    this.debugText = this.formatDecision(decision);
    if (decision.outcome === GestureOutcome.CLOSE_TAB) {
      this.store.closeTab(closingId);
      this.activeCardId = '';
      this.cardCloseProgress = 0;
      if (this.store.tabs.length <= 1) {
        this.animateBottomTo(0);
      }
      return;
    }
    this.getUIContext().animateTo({
      duration: DEFAULT_GESTURE_PROFILE.settleDurationMs,
      curve: Curve.Friction
    }, () => {
      this.cardCloseProgress = 0;
      this.activeCardId = '';
    });
  }

  private cancelCardGesture(): void {
    if (this.activeCardId.length === 0) {
      return;
    }
    const decision: GestureDecision = this.cardEngine.cancel();
    this.debugText = this.formatDecision(decision);
    this.getUIContext().animateTo({
      duration: DEFAULT_GESTURE_PROFILE.settleDurationMs,
      curve: Curve.Friction
    }, () => {
      this.cardCloseProgress = 0;
      this.activeCardId = '';
    });
  }

  @Builder
  private buildTabCard(tab: BrowserTabRecord) {
    Column() {
      Text(tab.title)
        .fontSize(18)
        .fontColor(Color.White)
        .maxLines(1)
      Text(tab.url)
        .fontSize(12)
        .fontColor('#EAF2FF')
        .maxLines(1)
        .margin({ top: 8 })
    }
    .width('100%')
    .height(this.cardWidth)
    .padding(16)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.panelColors[this.store.tabs.findIndex((item: BrowserTabRecord) => item.id === tab.id) % this.panelColors.length])
    .borderRadius(HARMONY_RADIUS_FLOATING)
    .opacity(tab.id === this.activeCardId ? 1 - 0.55 * this.cardCloseProgress : 1)
    .scale({
      x: tab.id === this.activeCardId ? 1 - 0.06 * this.cardCloseProgress : 1,
      y: tab.id === this.activeCardId ? 1 - 0.06 * this.cardCloseProgress : 1,
      z: 1
    })
    .translate({
      x: tab.id === this.activeCardId ? -this.cardWidth * this.cardCloseProgress : 0,
      z: 0
    })
    .onClick(() => this.openTab(tab.id))
    .gesture(
      PanGesture()
        .onActionStart(() => this.beginCardGesture(tab.id))
        .onActionUpdate((event: GestureEvent | undefined) => this.updateCardGesture(event))
        .onActionEnd((event: GestureEvent | undefined) => this.finishCardGesture(event))
        .onActionCancel(() => this.cancelCardGesture())
    )
  }

  build() {
    Column() {
      Text(this.debugText)
        .id('gesture-debug-strip')
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .fontSize(12)
        .fontColor('#334155')
        .backgroundColor('#E2E8F0')

      Stack() {
        Column() {
          Text(this.activeTitle())
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
          Text(this.activeUrl())
            .fontSize(14)
            .fontColor('#F8FAFC')
            .margin({ top: 12 })
          Text('ArkUI 原生手势实验页')
            .fontSize(13)
            .fontColor('#F8FAFC')
            .margin({ top: 28 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(this.activeColor())
        .borderRadius(HARMONY_RADIUS_SHEET * this.overviewProgress)
        .scale({
          x: 1 - 0.08 * this.overviewProgress,
          y: 1 - 0.08 * this.overviewProgress,
          z: 1
        })
        .translate({ x: this.horizontalOffset, y: 0, z: 0 })

        if (this.overviewProgress > 0) {
          Grid() {
            ForEach(this.store.tabs, (tab: BrowserTabRecord) => {
              GridItem() {
                this.buildTabCard(tab)
              }
            }, (tab: BrowserTabRecord) => tab.id)
          }
          .id('tab-overview-grid')
          .columnsTemplate('1fr 1fr')
          .rowsGap(12)
          .columnsGap(12)
          .padding(16)
          .width('100%')
          .height('100%')
          .opacity(this.overviewProgress)
          .backgroundColor('#E6000000')
        }
      }
      .layoutWeight(1)
      .width('100%')

      Row() {
        Text(`简阅 · ${this.store.tabs.length} 个标签`)
          .fontSize(14)
          .fontColor(Color.White)
          .layoutWeight(1)
        Button() {
          Text('总览')
            .fontSize(14)
        }
        .height(40)
        .onClick(() => this.animateBottomTo(1))
      }
      .id('gesture-bottom-bar')
      .height(72)
      .width('100%')
      .padding({ left: 16, right: 16 })
      .backgroundColor('#1E293B')
      .gesture(
        PanGesture()
          .onActionStart(() => {
            this.bottomEngine.begin();
            this.debugText = '手势开始';
          })
          .onActionUpdate((event: GestureEvent | undefined) => {
            const decision: GestureDecision = this.bottomEngine.updateBottomBar(
              this.sampleFrom(event),
              this.viewportWidth,
              this.viewportHeight,
              this.hasPrevious(),
              this.hasNext()
            );
            this.applyBottomUpdate(decision);
          })
          .onActionEnd((event: GestureEvent | undefined) => this.finishBottomGesture(event))
          .onActionCancel(() => this.cancelBottomGesture())
      )
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F8FAFC')
  }
}
