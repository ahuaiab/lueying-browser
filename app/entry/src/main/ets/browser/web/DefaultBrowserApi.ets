import { defaultAppManager, Want } from '@kit.AbilityKit';

const BROWSABLE_ACTION: string = 'ohos.want.action.viewData';
const BROWSABLE_ENTITY: string = 'entity.system.browsable';

export enum DefaultBrowserRequestStatus {
  ALREADY_DEFAULT = 'already-default',
  PICKER_LAUNCHED = 'picker-launched',
  INVALID_URL = 'invalid-url',
  FAILED = 'failed'
}

export interface DefaultBrowserRequestResult {
  status: DefaultBrowserRequestStatus;
  errorCode?: number;
}

export interface DefaultBrowserApplicationManager {
  isDefaultApplication(type: string): Promise<boolean>;
}

export interface DefaultBrowserLaunchContext {
  startAbility(want: Want): Promise<void>;
}

interface DefaultBrowserErrorLike {
  code?: number;
}

class HarmonyDefaultBrowserApplicationManager implements DefaultBrowserApplicationManager {
  async isDefaultApplication(type: string): Promise<boolean> {
    return await defaultAppManager.isDefaultApplication(type);
  }
}

function normalizedWebUrl(url: string): string | undefined {
  const candidate: string = url.trim();
  const lowerCaseCandidate: string = candidate.toLowerCase();
  if (lowerCaseCandidate.startsWith('http://') || lowerCaseCandidate.startsWith('https://')) {
    return candidate;
  }
  return undefined;
}

function errorCodeFor(error: Error): number {
  const candidate: DefaultBrowserErrorLike = error as DefaultBrowserErrorLike;
  return candidate.code ?? -1;
}

export function createDefaultBrowserWant(url: string): Want {
  return {
    action: BROWSABLE_ACTION,
    entities: [BROWSABLE_ENTITY],
    uri: url,
    parameters: {
      'ohos.ability.params.showDefaultPicker': true
    }
  };
}

export class DefaultBrowserApi {
  private readonly context: DefaultBrowserLaunchContext;
  private readonly applicationManager: DefaultBrowserApplicationManager;

  constructor(
    context: DefaultBrowserLaunchContext,
    applicationManager: DefaultBrowserApplicationManager | undefined = undefined
  ) {
    this.context = context;
    this.applicationManager = applicationManager ?? new HarmonyDefaultBrowserApplicationManager();
  }

  async isDefaultBrowser(): Promise<boolean> {
    return await this.applicationManager.isDefaultApplication(defaultAppManager.ApplicationType.BROWSER);
  }

  async requestSetAsDefaultBrowser(url: string): Promise<DefaultBrowserRequestResult> {
    const browsableUrl: string | undefined = normalizedWebUrl(url);
    if (browsableUrl === undefined) {
      return { status: DefaultBrowserRequestStatus.INVALID_URL };
    }

    try {
      if (await this.isDefaultBrowser()) {
        return { status: DefaultBrowserRequestStatus.ALREADY_DEFAULT };
      }
      await this.context.startAbility(createDefaultBrowserWant(browsableUrl));
      return { status: DefaultBrowserRequestStatus.PICKER_LAUNCHED };
    } catch (error) {
      return {
        status: DefaultBrowserRequestStatus.FAILED,
        errorCode: errorCodeFor(error)
      };
    }
  }
}
