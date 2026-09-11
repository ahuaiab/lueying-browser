/**
 * The visual affordance shown when the last tab is pulled left.  It is a
 * render-only layer: the real blank tab is created after the spring completes
 * and never during PanGesture.onActionUpdate.
 */
@ComponentV2
export struct TabNewPagePullPreview {
  @Param viewportWidth: number = 400;
  @Param progress: number = 0;
  @Param backgroundProgress: number = 0;

  private clamp(value: number): number {
    return Math.max(0, Math.min(1, value));
  }

  private safeProgress(): number {
    return this.clamp(this.progress);
  }

  private safeBackgroundProgress(): number {
    return this.clamp(this.backgroundProgress);
  }

  private revealOffset(): number {
    return this.viewportWidth * (1 - this.safeBackgroundProgress());
  }

  build() {
    Column() {
    }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.White)
      .opacity(this.safeBackgroundProgress())
      .translate({ x: this.revealOffset(), y: 0, z: 0 })
      .id('new-tab-pull-preview')
      .hitTestBehavior(HitTestMode.None);
  }
}
