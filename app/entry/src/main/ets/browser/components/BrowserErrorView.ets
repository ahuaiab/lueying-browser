import { BrowserErrorKind, BrowserErrorState } from '../model/BrowserTypes';

@ComponentV2
export struct BrowserErrorView {
  @Require @Param error: BrowserErrorState;
  @Param onRetry: () => void = () => undefined;
  @Param onBack: () => void = () => undefined;

  private headline(): string {
    if (this.error.kind === BrowserErrorKind.SSL) {
      return '连接不安全';
    }
    if (this.error.kind === BrowserErrorKind.RENDERER_EXITED) {
      return '页面进程已退出';
    }
    return '网页无法打开';
  }

  private detail(): string {
    if (this.error.kind === BrowserErrorKind.SSL) {
      return '证书校验失败。为保护你的数据，不能跳过证书检查。';
    }
    if (this.error.kind === BrowserErrorKind.RENDERER_EXITED) {
      return '网页渲染进程意外退出，可以重新加载此页面。';
    }
    return '请检查网络连接后重试。';
  }

  build() {
    Column({ space: 14 }) {
      Text(this.headline())
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#0F172A')
      Text(this.error.host)
        .fontSize(14)
        .fontColor('#475569')
        .maxLines(1)
      Text(`${this.detail()}\n错误码：${this.error.code}`)
        .fontSize(15)
        .fontColor('#334155')
        .textAlign(TextAlign.Center)
      Row({ space: 12 }) {
        Button('返回', { type: ButtonType.Capsule, stateEffect: false })
          .id('browser-error-back-button')
          .onClick(() => this.onBack())
        Button('重试', { type: ButtonType.Capsule, stateEffect: false })
          .id('browser-error-retry-button')
          .onClick(() => this.onRetry())
      }
    }
    .id('browser-error-view')
    .width('100%')
    .height('100%')
    .padding(28)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(Color.White)
  }
}
