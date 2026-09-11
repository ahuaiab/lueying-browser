import { describe, expect, it } from '@ohos/hypium';
import { Want } from '@kit.AbilityKit';
import {
  DefaultBrowserApi,
  DefaultBrowserApplicationManager,
  DefaultBrowserLaunchContext,
  DefaultBrowserRequestStatus
} from '../../../main/ets/browser/web/DefaultBrowserApi';

class FakeDefaultBrowserManager implements DefaultBrowserApplicationManager {
  queriedType: string = '';
  defaultApplication: boolean = false;
  shouldReject: boolean = false;

  async isDefaultApplication(type: string): Promise<boolean> {
    this.queriedType = type;
    if (this.shouldReject) {
      throw new Error('default application query failed');
    }
    return this.defaultApplication;
  }
}

class PickerUnavailableError extends Error {
  readonly code: number;

  constructor(code: number) {
    super('picker unavailable');
    this.code = code;
  }
}

class FakeDefaultBrowserContext implements DefaultBrowserLaunchContext {
  startedWant: Want | undefined = undefined;
  startCalls: number = 0;
  shouldReject: boolean = false;
  rejectionCode: number = 801;

  async startAbility(want: Want): Promise<void> {
    this.startCalls += 1;
    this.startedWant = want;
    if (this.shouldReject) {
      throw new PickerUnavailableError(this.rejectionCode);
    }
  }
}

interface DefaultBrowserFixture {
  manager: FakeDefaultBrowserManager;
  context: FakeDefaultBrowserContext;
  api: DefaultBrowserApi;
}

function createFixture(): DefaultBrowserFixture {
  const manager: FakeDefaultBrowserManager = new FakeDefaultBrowserManager();
  const context: FakeDefaultBrowserContext = new FakeDefaultBrowserContext();
  const api: DefaultBrowserApi = new DefaultBrowserApi(context, manager);
  return { manager, context, api };
}

export default function defaultBrowserApiTest() {
  describe('DefaultBrowserApi', () => {
    it('queries the current application using the browser default type', 0, async () => {
      const fixture: DefaultBrowserFixture = createFixture();

      expect(await fixture.api.isDefaultBrowser()).assertFalse();
      expect(fixture.manager.queriedType).assertEqual('Web Browser');
    });

    it('returns already-default without opening the picker', 0, async () => {
      const fixture: DefaultBrowserFixture = createFixture();
      fixture.manager.defaultApplication = true;

      const result = await fixture.api.requestSetAsDefaultBrowser('https://example.com');

      expect(result.status).assertEqual(DefaultBrowserRequestStatus.ALREADY_DEFAULT);
      expect(fixture.context.startCalls).assertEqual(0);
    });

    it('opens the system picker with a browsable HTTPS want', 0, async () => {
      const fixture: DefaultBrowserFixture = createFixture();

      const result = await fixture.api.requestSetAsDefaultBrowser('https://example.com/path');
      const want: Want = fixture.context.startedWant!;

      expect(result.status).assertEqual(DefaultBrowserRequestStatus.PICKER_LAUNCHED);
      expect(want.action).assertEqual('ohos.want.action.viewData');
      expect(want.entities?.[0]).assertEqual('entity.system.browsable');
      expect(want.uri).assertEqual('https://example.com/path');
      expect(want.parameters?.['ohos.ability.params.showDefaultPicker']).assertTrue();
    });

    it('rejects non-web URLs without launching another ability', 0, async () => {
      const fixture: DefaultBrowserFixture = createFixture();

      const result = await fixture.api.requestSetAsDefaultBrowser('ftp://example.com/file');

      expect(result.status).assertEqual(DefaultBrowserRequestStatus.INVALID_URL);
      expect(fixture.context.startCalls).assertEqual(0);
    });

    it('reports a system picker failure without claiming success', 0, async () => {
      const fixture: DefaultBrowserFixture = createFixture();
      fixture.context.shouldReject = true;
      fixture.context.rejectionCode = 801;

      const result = await fixture.api.requestSetAsDefaultBrowser('https://example.com');

      expect(result.status).assertEqual(DefaultBrowserRequestStatus.FAILED);
      expect(result.errorCode).assertEqual(801);
    });
  });
}
