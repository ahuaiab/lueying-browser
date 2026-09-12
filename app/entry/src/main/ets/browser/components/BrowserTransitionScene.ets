import { image } from '@kit.ImageKit';
import { RectShape } from '@kit.ArkUI';
import { BrowserErrorView } from './BrowserErrorView';
import { StartPage } from './StartPage';
import { BrowserSettings } from '../model/BrowserSettings';
import { PageAction } from '../model/PageActions';
import { PageFontSize } from '../model/PageDisplayState';
import { BrowserErrorState } from '../model/BrowserTypes';
import { StartPageItem } from '../model/StartPageModels';
import { TabPreviewKind as MotionPreviewKind } from '../model/TabGestureMotion';
import {
  TabTransitionSceneVisualState,
  tabTransitionSceneVisualState
} from '../model/SafariTabTransition';
import {
  TAB_OVERVIEW_CAPTION_FONT_SIZE,
  TabOverviewPageFrame,
  tabOverviewCaptionLocalRadius,
  TabOverviewLivePageCloseFrame,
  tabOverviewLivePageCloseFrame
} from '../model/TabOverviewActions';
import { WebNodeHostController } from '../web/WebTabNode';
import { availableContentHeight } from '../model/WindowAvoidance';

/**
 * Native ArkUI page scene for Safari-style tab transitions.
 *
 * The current and adjacent pages stay mounted as two translated layers while
 * the fixed address TabBar drives the gesture. This keeps ArkWeb native and
 * lets the page follow the same pointer progress as the address capsules.
 */
@ComponentV2
export struct BrowserTransitionScene {
  @Require @Param settings: BrowserSettings;
  @Param viewportWidth: number = 400;
  @Param viewportHeight: number = 800;
  @Param topContentInset: number = 0;
  @Param currentX: number = 0;
  @Param previewX: number = 0;
  @Param currentHost: WebNodeHostController | undefined = undefined;
  @Param previewHost: WebNodeHostController | undefined = undefined;
  @Param currentThumbnail: image.PixelMap | undefined = undefined;
  @Param previewThumbnail: image.PixelMap | undefined = undefined;
  @Param currentIsStartPage: boolean = false;
  @Param previewIsStartPage: boolean = false;
  @Param previewKind: MotionPreviewKind = MotionPreviewKind.NONE;
  @Param showPreview: boolean = false;
  /** The live page itself is transformed into the active overview card. */
  @Param overviewFrame: TabOverviewPageFrame | undefined = undefined;
  /** Horizontal close progress shared with the active transparent card shell. */
  @Param overviewCloseProgress: number = 0;
  @Param overviewCloseHorizontalOffset: number = 0;
  /** Title rendered inside the same transformed layer as the live page. */
  @Param overviewCaptionTitle: string = '';
  /** The shared address capsule owns the caption while the card expands back. */
  @Param overviewCaptionVisible: boolean = true;
  /** Final handoff opacity between the address capsule and card caption. */
  @Param overviewCaptionHandoffOpacity: number = 1;
  /** True while the live page owns the single overview selection ring. */
  @Param showOverviewPageBorder: boolean = false;
  @Param interactionLocked: boolean = false;
  @Param currentItems: StartPageItem[] = [];
  @Param errorState: BrowserErrorState | undefined = undefined;
  @Param onOpen: (url: string) => void = (_url: string) => undefined;
  @Param onAddFavorite: () => void = () => undefined;
  @Param onCustomize: () => void = () => undefined;
  @Param onNavigate: (value: string) => void = (_value: string) => undefined;
  @Param onFontSize: (size: PageFontSize) => void = (_size: PageFontSize) => undefined;
  @Param onPageAction: (action: PageAction) => void = (_action: PageAction) => undefined;
  @Param onRetry: () => void = () => undefined;
  @Param onBack: () => void = () => undefined;
  @Param onViewportChange: (width: number, height: number) => void =
    (_width: number, _height: number) => undefined;

  private visualState(): TabTransitionSceneVisualState {
    return tabTransitionSceneVisualState(
      this.currentX,
      this.previewX,
      this.previewKind,
      this.showPreview
    );
  }

  private pageContentHeight(): number {
    return availableContentHeight(this.viewportHeight, this.topContentInset);
  }

  private pageContentTop(): number {
    return Number.isFinite(this.topContentInset) ? Math.max(0, this.topContentInset) : 0;
  }

  private sceneWidth(): number {
    return Number.isFinite(this.viewportWidth) && this.viewportWidth > 0
      ? this.viewportWidth
      : 1;
  }

  private sceneHeight(): number {
    return Number.isFinite(this.viewportHeight) && this.viewportHeight > 0
      ? this.viewportHeight
      : 1;
  }

  private overviewScaleX(): number {
    return this.overviewFrame?.scaleX ?? 1;
  }

  private overviewScaleY(): number {
    return this.overviewFrame?.scaleY ?? 1;
  }

  private overviewClipLeft(): number {
    return this.overviewFrame?.clipLeft ?? 0;
  }

  private overviewClipTop(): number {
    return this.overviewFrame?.clipTop ?? 0;
  }

  private overviewClipWidth(): number {
    return this.overviewFrame?.clipWidth ?? this.sceneWidth();
  }

  private overviewClipHeight(): number {
    return this.overviewFrame?.clipHeight ?? this.sceneHeight();
  }

  private overviewCaptionTitleText(): string {
    return this.overviewCaptionTitle.length > 0 ? this.overviewCaptionTitle : '起始页';
  }

  private overviewCaptionMetric(value: number): number {
    return value * (this.overviewFrame?.captionContentScale ?? 1);
  }

  private overviewCaptionRadius(): number {
    return tabOverviewCaptionLocalRadius(this.overviewFrame);
  }

  private livePageCloseFrame(): TabOverviewLivePageCloseFrame {
    return tabOverviewLivePageCloseFrame(
      this.overviewCloseProgress,
      this.overviewCloseHorizontalOffset
    );
  }

  private livePageCloseTranslateX(): number {
    const frame: TabOverviewLivePageCloseFrame = this.livePageCloseFrame();
    const clipLeft: number = this.overviewFrame?.clipLeft ?? 0;
    const clipWidth: number = this.overviewFrame?.clipWidth ?? this.sceneWidth();
    const liveCenterX: number = clipLeft + clipWidth / 2;
    return frame.horizontalOffset + (1 - frame.scale) *
      (liveCenterX - this.sceneWidth() / 2);
  }

  private livePageCloseTranslateY(): number {
    const frame: TabOverviewLivePageCloseFrame = this.livePageCloseFrame();
    const clipTop: number = this.overviewFrame?.clipTop ?? 0;
    const clipHeight: number = this.overviewFrame?.clipHeight ?? this.sceneHeight();
    const liveCenterY: number = clipTop + clipHeight / 2;
    return (1 - frame.scale) * (liveCenterY - this.sceneHeight() / 2);
  }

  private hasCurrentContent(): boolean {
    return this.currentHost !== undefined || this.currentThumbnail !== undefined ||
      this.currentIsStartPage || this.errorState !== undefined;
  }

  private hasPreviewContent(): boolean {
    return this.previewHost !== undefined || this.previewThumbnail !== undefined ||
      this.previewIsStartPage || this.previewKind === MotionPreviewKind.NEW_TAB;
  }

  private shouldShowPreview(): boolean {
    const visual: TabTransitionSceneVisualState = this.visualState();
    return visual.showPreview && this.hasPreviewContent();
  }

  @Builder
  private buildCurrentPageScene() {
    Stack() {
      if (this.currentHost !== undefined) {
        NodeContainer(this.currentHost)
          .id(`transition-current-web-${this.currentHost.tabId}`)
          .width('100%')
          .height('100%')
          .clip(true)
          .hitTestBehavior(this.interactionLocked ? HitTestMode.None : HitTestMode.Default);
      } else if (this.currentIsStartPage) {
        StartPage({
          items: this.currentItems,
          settings: this.settings,
          pageTranslateX: 0,
          onOpen: this.onOpen,
          onAddFavorite: this.onAddFavorite,
          onCustomize: this.onCustomize
        })
          .width('100%')
          .height('100%')
          .hitTestBehavior(this.interactionLocked ? HitTestMode.None : HitTestMode.Default);
      } else if (this.currentThumbnail !== undefined) {
        Image(this.currentThumbnail)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .hitTestBehavior(HitTestMode.None);
      }
      if (this.errorState !== undefined) {
        BrowserErrorView({
          error: this.errorState,
          onRetry: this.onRetry,
          onBack: this.onBack
        });
      }
    }
      .id('transition-current-page-scene')
      // Keep the live page's layout viewport fixed while its native layer is
      // scaled. Resizing this NodeContainer would reflow the WebView and
      // produce the distorted card shown by the old implementation.
      .width(this.sceneWidth())
      .height(this.pageContentHeight())
      .position({ x: 0, y: this.pageContentTop() })
      .clip(true)
      .translate({ x: this.currentX, y: 0, z: 0 });
  }

  @Builder
  private buildPreviewPageScene() {
    Stack() {
      if (this.previewHost !== undefined) {
        NodeContainer(this.previewHost)
          .id(`transition-preview-web-${this.previewHost.tabId}`)
          .width('100%')
          .height('100%')
          .clip(true)
          .hitTestBehavior(HitTestMode.None);
      } else if (this.previewThumbnail !== undefined) {
        Image(this.previewThumbnail)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .hitTestBehavior(HitTestMode.None);
      } else if (this.previewIsStartPage || this.previewKind === MotionPreviewKind.NEW_TAB) {
        StartPage({
          items: this.currentItems,
          settings: this.settings,
          pageTranslateX: 0,
          onOpen: (_url: string) => undefined,
          onAddFavorite: () => undefined,
          onCustomize: () => undefined
        })
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.None);
      }
    }
      .id('transition-preview-page-scene')
      .width(this.sceneWidth())
      .height(this.pageContentHeight())
      .position({ x: 0, y: this.pageContentTop() })
      .clip(true)
      .translate({ x: this.previewX, y: 0, z: 0 });
  }

  @Builder
  private buildOverviewCaption() {
    Row() {
      Text(this.overviewCaptionTitleText())
        .fontSize(this.overviewCaptionMetric(TAB_OVERVIEW_CAPTION_FONT_SIZE))
        .fontWeight(FontWeight.Medium)
        .fontColor('#1D1D1F')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1);
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(this.overviewCaptionMetric(14))
          .fontColor(['#69727C']);
      }
        .width(this.overviewCaptionMetric(28))
        .height(this.overviewCaptionMetric(28))
        .padding(0)
        .backgroundColor(Color.Transparent)
        .stateEffect(false);
    }
      .id('browser-live-page-caption')
      .width('100%')
      .height(this.overviewFrame?.captionLocalHeight ?? 32)
      .position({
        x: 0,
        y: this.overviewFrame?.captionLocalTop ?? this.sceneHeight()
      })
      .padding({
        left: this.overviewCaptionMetric(12),
        right: this.overviewCaptionMetric(2)
      })
      .backgroundColor('#FFFFFF')
      .borderRadius({
        bottomLeft: this.overviewCaptionRadius(),
        bottomRight: this.overviewCaptionRadius()
      })
      .clip(true)
      .opacity(this.overviewCaptionVisible
        ? (this.overviewFrame?.captionOpacity ?? 0) *
          Math.max(0, Math.min(1, this.overviewCaptionHandoffOpacity))
        : 0)
      .hitTestBehavior(HitTestMode.None);
  }

  @Builder
  private buildPageLayers() {
    Stack() {
      if (this.hasCurrentContent()) {
        this.buildCurrentPageScene();
      }
      if (this.shouldShowPreview()) {
        this.buildPreviewPageScene();
      }
      this.buildOverviewCaption();
    }
      .id('browser-page-layers')
      .width(this.sceneWidth())
      .height(this.sceneHeight())
      // Keep the full native page viewport as the layout surface. The
      // surrounding clip shape crops it to the card without constraining or
      // remeasuring the ArkWeb NodeContainer.
      .scale({
        x: this.overviewScaleX(),
        y: this.overviewScaleY(),
        z: 1
      })
      .translate({
        x: this.overviewFrame?.translateX ?? 0,
        y: this.overviewFrame?.translateY ?? 0,
        z: 0
      });
  }

  private overviewClipShape(): RectShape {
    return new RectShape({
      width: this.overviewClipWidth(),
      height: this.overviewClipHeight(),
      radius: this.overviewFrame?.cornerRadius ?? 0
    }).position({
      x: this.overviewClipLeft(),
      y: this.overviewClipTop()
    });
  }

  @Builder
  private buildPageOutline() {
    Column()
      .id('browser-live-page-outline')
      .width(this.overviewClipWidth())
      .height(this.overviewClipHeight())
      .position({ x: this.overviewClipLeft(), y: this.overviewClipTop() })
      .borderRadius(this.overviewFrame?.cornerRadius ?? 0)
      .border({
        width: this.showOverviewPageBorder ? (this.overviewFrame?.borderWidth ?? 0) : 0,
        color: '#007AFF'
      })
      .backgroundColor(Color.Transparent)
      .hitTestBehavior(HitTestMode.None);
  }

  @Builder
  private buildPageWindow() {
    Stack() {
      this.buildPageLayers();
      this.buildPageOutline();
    }
      .id('browser-root-transition-scene')
      .width('100%')
      .height('100%')
      // ArkUI's native shape clip keeps the WebView's original layout
      // viewport unconstrained while cropping only the visible card window.
      .clipShape(this.overviewClipShape())
      .backgroundColor(Color.White)
      // The transparent active card shell and the live page must leave the
      // overview together. Compensate for the full-window transform origin so
      // the live page scales around the active card's center, just like the
      // card shell does.
      .opacity(this.livePageCloseFrame().opacity)
      .scale({
        x: this.livePageCloseFrame().scale,
        y: this.livePageCloseFrame().scale,
        z: 1
      })
      .translate({
        x: this.livePageCloseTranslateX(),
        y: this.livePageCloseTranslateY(),
        z: 0
      });
  }

  build() {
    Stack() {
      this.buildPageWindow();
    }
      .id('browser-transition-viewport')
      .width('100%')
      .height('100%')
      .onAreaChange((_oldValue, newValue) =>
        this.onViewportChange(newValue.width as number, newValue.height as number));
  }
}
