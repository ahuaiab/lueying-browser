export interface BrowserLifecyclePort {
  /** Reattach the active web surface after the ability returns to foreground. */
  onForeground(): void;
  onBackground(): Promise<void>;
  onMemoryPressure(level: number): void;
  onExternalUrl(url: string): void;
  /**
   * Handle the system back key/gesture at the browser shell boundary.
   * Returning true keeps the current UIAbility page alive.
   */
  onBackPress(): boolean;
}

/** Process-wide bridge used by UIAbility callbacks without retaining a UI
 * component after its page has been destroyed. */
export class BrowserLifecycleRegistry {
  private static active: BrowserLifecyclePort | undefined;

  static register(port: BrowserLifecyclePort): void {
    BrowserLifecycleRegistry.active = port;
  }

  static clear(port: BrowserLifecyclePort): void {
    if (BrowserLifecycleRegistry.active === port) {
      BrowserLifecycleRegistry.active = undefined;
    }
  }

  static async onBackground(): Promise<void> {
    await BrowserLifecycleRegistry.active?.onBackground();
  }

  static onForeground(): void {
    BrowserLifecycleRegistry.active?.onForeground();
  }

  static onMemoryPressure(level: number): void {
    BrowserLifecycleRegistry.active?.onMemoryPressure(level);
  }

  /** Forward an external http(s) launch to the mounted browser shell. */
  static onExternalUrl(url: string): boolean {
    const active: BrowserLifecyclePort | undefined = BrowserLifecycleRegistry.active;
    if (active === undefined) {
      return false;
    }
    active.onExternalUrl(url);
    return true;
  }

  /**
   * Forward the @Entry page's system back callback to the active browser shell.
   * A missing shell must not consume the event, so the ability keeps its
   * default back behavior during startup and teardown.
   */
  static onBackPress(): boolean {
    return BrowserLifecycleRegistry.active?.onBackPress() ?? false;
  }
}
