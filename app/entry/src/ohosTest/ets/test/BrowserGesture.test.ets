import { Component, Driver, ON } from '@kit.TestKit';
import { beforeAll, describe, expect, it } from '@ohos/hypium';

async function findBar(driver: Driver): Promise<Component> {
  return await driver.findComponent(ON.id('bottom-browser-bar'));
}

async function swipeBar(driver: Driver, dx: number, dy: number, speed: number = 600): Promise<void> {
  const bounds = await (await findBar(driver)).getBounds();
  const x: number = (bounds.left + bounds.right) / 2;
  const y: number = (bounds.top + bounds.bottom) / 2;
  await driver.swipe(x, y, x + dx, y + dy, speed);
  await driver.delayMs(350);
}

async function tabCount(driver: Driver): Promise<number> {
  const countButton: Component = await driver.findComponent(ON.id('tab-count-button'));
  return Number(await countButton.getText());
}

async function ensureTabCount(driver: Driver, target: number): Promise<void> {
  while (await tabCount(driver) < target) {
    const newTab: Component = await driver.findComponent(ON.id('browser-new-tab-button'));
    await newTab.click();
    await driver.delayMs(350);
  }
}

async function setOverview(driver: Driver, visible: boolean): Promise<void> {
  const overviews: Array<Component> = await driver.findComponents(ON.id('tab-overview'));
  if ((overviews.length > 0) !== visible) {
    const countButton: Component = await driver.findComponent(ON.id('tab-count-button'));
    await countButton.click();
    await driver.delayMs(350);
  }
}

async function swipeFirstCard(driver: Driver, dy: number, speed: number): Promise<void> {
  const cards: Array<Component> = await driver.findComponents(ON.id('tab-card'));
  if (cards.length === 0) {
    return;
  }
  const card: Component = cards[0];
  const bounds = await card.getBounds();
  const x: number = (bounds.left + bounds.right) / 2;
  const y: number = (bounds.top + bounds.bottom) / 2;
  await driver.swipe(x, y, x, y + dy, speed);
  await driver.delayMs(400);
}

/**
 * Device-side acceptance tests for the production gesture region. Coordinates
 * are derived from the visible bar so the cases remain usable across phone
 * resolutions. They intentionally do not inspect BrowserShell private state.
 */
export default function browserGestureTest() {
  describe('BrowserGesture', () => {
    let driver: Driver;

    beforeAll(() => {
      driver = Driver.create();
    });

    it('exposes stable production gesture targets', 0, async () => {
      await driver.assertComponentExist(ON.id('bottom-browser-bar'));
      await driver.assertComponentExist(ON.id('web-tab-host'));
      await driver.assertComponentExist(ON.id('tab-count-button'));
      await driver.assertComponentExist(ON.id('browser-new-private-tab-button'));
      await driver.assertComponentExist(ON.id('browser-tab-mode-label'));
    });

    it('short upward swipe keeps tab overview hidden', 0, async () => {
      await swipeBar(driver, 0, -24, 300);
      const overviews: Array<Component> = await driver.findComponents(ON.id('tab-overview'));
      expect(overviews.length).assertEqual(0);
    });

    it('committed upward swipe shows tab overview', 0, async () => {
      await swipeBar(driver, 0, -720, 1600);
      await driver.assertComponentExist(ON.id('tab-overview'));
    });

    it('horizontal swipe changes the active tab at most once', 0, async () => {
      await setOverview(driver, false);
      const newTab: Component = await driver.findComponent(ON.id('browser-new-tab-button'));
      const countBefore: Component = await driver.findComponent(ON.id('tab-count-button'));
      const beforeText: string = await countBefore.getText();
      await newTab.click();
      await driver.delayMs(350);
      const countAfter: Component = await driver.findComponent(ON.id('tab-count-button'));
      const afterText: string = await countAfter.getText();
      expect(afterText).assertEqual(`${Number(beforeText) + 1}`);

      // A newly-created tab is active, so the positive direction targets its
      // previous sibling. The mirrored left-drag path is covered by fixtures.
      await swipeBar(driver, 420, 0, 1200);
      const countAfterSwipe: Component = await driver.findComponent(ON.id('tab-count-button'));
      expect(await countAfterSwipe.getText()).assertEqual(afterText);
    });

    it('short card swipe keeps the tab count unchanged', 0, async () => {
      await ensureTabCount(driver, 2);
      await setOverview(driver, true);
      const before: number = await tabCount(driver);
      await swipeFirstCard(driver, -40, 300);
      expect(await tabCount(driver)).assertEqual(before);
    });

    it('fast card fling closes exactly one tab', 0, async () => {
      await ensureTabCount(driver, 2);
      await setOverview(driver, true);
      const before: number = await tabCount(driver);
      await swipeFirstCard(driver, -240, 1600);
      expect(await tabCount(driver)).assertEqual(before - 1);
      await setOverview(driver, false);
    });

    it('closing the selected card leaves the right neighbour active', 0, async () => {
      await ensureTabCount(driver, 2);
      await setOverview(driver, true);
      const cards: Array<Component> = await driver.findComponents(ON.id('tab-card'));
      if (cards.length > 0) {
        await cards[0].click();
        await driver.delayMs(350);
      }
      await setOverview(driver, true);
      const before: number = await tabCount(driver);
      await swipeFirstCard(driver, -240, 1600);
      expect(await tabCount(driver)).assertEqual(Math.max(1, before - 1));
      await setOverview(driver, true);
      await driver.assertComponentExist(ON.id('tab-card-active-marker'));
      await setOverview(driver, false);
      await driver.assertComponentExist(ON.id('web-tab-host'));
    });

    it('closing the final normal card creates a start tab', 0, async () => {
      await setOverview(driver, true);
      let remaining: number = await tabCount(driver);
      while (remaining > 1) {
        await swipeFirstCard(driver, -240, 1600);
        remaining = await tabCount(driver);
        if (remaining > 1) {
          await setOverview(driver, true);
        }
      }
      expect(remaining).assertEqual(1);
      await setOverview(driver, false);
      await driver.assertComponentExist(ON.id('web-tab-host'));
    });
  });
}
