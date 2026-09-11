import { image } from '@kit.ImageKit';
import { WebNodeHostController } from '../web/WebTabNode';

/**
 * Hosts the committed page and, only while a horizontal tab gesture is active,
 * one adjacent native page (or its captured thumbnail).  The transient
 * adjacent slot makes the page follow the finger without changing TabStore.
 */
@ComponentV2
export struct WebTabHost {
  @Param previous: WebNodeHostController | undefined = undefined;
  @Param active: WebNodeHostController | undefined = undefined;
  @Param next: WebNodeHostController | undefined = undefined;
  @Param previousThumbnail: image.PixelMap | undefined = undefined;
  @Param nextThumbnail: image.PixelMap | undefined = undefined;
  @Param previewHost: WebNodeHostController | undefined = undefined;
  @Param previewThumbnail: image.PixelMap | undefined = undefined;
  @Param viewportWidth: number = 400;
  @Param horizontalOffset: number = 0;
  @Param pageTranslateX: number = 0;
  @Param adjacentTranslateX: number = 0;
  @Param isDragging: boolean = false;
  @Param gestureActive: boolean = false;
  @Param onViewportChange: (width: number, height: number) => void = (_width: number, _height: number) => undefined;

  @Builder
  private buildHost(host: WebNodeHostController, offset: number, interactive: boolean) {
    NodeContainer(host)
      // Keep each tab's native host keyed to its tab id.  Without a stable
      // identity ArkUI can recycle the three conditional slots when overview
      // closes, leaving the new active tab with the previous tab's frame.
      .id(`web-tab-host-${host.tabId}`)
      .width('100%')
      .height('100%')
      .translate({ x: offset, y: 0, z: 0 })
      // Let the active ArkWeb surface receive native scrolling and link
      // gestures. Block on the NodeContainer captures the touch stream at
      // the host boundary and prevents the Web component from scrolling.
      .hitTestBehavior(interactive ? HitTestMode.Default : HitTestMode.None)
  }

  build() {
    Stack() {
      if (this.isDragging && this.previewHost !== undefined) {
        this.buildHost(this.previewHost, this.adjacentTranslateX, false);
      } else if (this.isDragging && this.previewThumbnail !== undefined) {
        Image(this.previewThumbnail)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .translate({ x: this.adjacentTranslateX, y: 0, z: 0 });
      } else if (!this.isDragging) {
        if (this.previousThumbnail !== undefined) {
          Image(this.previousThumbnail)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .translate({ x: this.horizontalOffset - this.viewportWidth, y: 0, z: 0 });
        }
        if (this.nextThumbnail !== undefined) {
          Image(this.nextThumbnail)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .translate({ x: this.horizontalOffset + this.viewportWidth, y: 0, z: 0 });
        }
      }
      if (this.active !== undefined) {
        this.buildHost(this.active, this.pageTranslateX, !this.gestureActive)
      }
    }
    .id('web-tab-host')
    .width('100%')
    .height('100%')
    .clip(true)
    .backgroundColor(Color.White)
    .onAreaChange((_oldValue, newValue) => this.onViewportChange(newValue.width as number, newValue.height as number))
  }
}
