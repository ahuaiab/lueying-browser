import { BrowserShell } from '../browser/components/BrowserShell';
import { BrowserLifecycleRegistry } from '../browser/lifecycle/BrowserLifecyclePort';

@Entry
@ComponentV2
struct Index {
  /**
   * @Entry is the page-level owner of system back dispatch. Delegate to the
   * active browser shell so an open multi-page overview closes before the
   * ability falls through to its default exit behavior.
   */
  onBackPress(): boolean {
    return BrowserLifecycleRegistry.onBackPress();
  }

  build() {
    Stack() {
      // The background is the only layer allowed to reach the system cutout.
      // BrowserShell's page scenes remain explicitly inset by the live avoid
      // area value, while its floating TabBar keeps its own bottom geometry.
      Stack()
        .backgroundColor(Color.White)
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.None)

      BrowserShell()
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
