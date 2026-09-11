import { describe, expect, it } from '@ohos/hypium';
import {
  BrowserDownloadRequest,
  DownloadCoordinator,
  DownloadStartPort,
  SavePickerPort,
  sanitizeDownloadFileName
} from '../../../main/ets/browser/web/DownloadCoordinator';
import {
  PermissionDecision,
  PermissionPromptPort,
  WebPermissionCoordinator,
  WebResourceKind
} from '../../../main/ets/browser/web/WebPermissionCoordinator';

class PromptFixture implements PermissionPromptPort {
  calls: number = 0;
  async confirm(_origin: string, _resource: WebResourceKind, _isPrivate: boolean): Promise<PermissionDecision> {
    this.calls += 1;
    return PermissionDecision.ALLOW;
  }
}

class FailingPromptFixture implements PermissionPromptPort {
  async confirm(_origin: string, _resource: WebResourceKind, _isPrivate: boolean): Promise<PermissionDecision> {
    throw new Error('closed');
  }
}

class PickerFixture implements SavePickerPort {
  destination: string | undefined;
  receivedName: string = '';

  async chooseDestination(fileName: string): Promise<string | undefined> {
    this.receivedName = fileName;
    return this.destination;
  }
}

class StarterFixture implements DownloadStartPort {
  calls: number = 0;
  async start(_request: BrowserDownloadRequest, _destination: string): Promise<boolean> {
    this.calls += 1;
    return true;
  }
}

function downloadRequest(): BrowserDownloadRequest {
  return {
    url: 'https://example.com/file',
    suggestedFileName: '../secret.txt',
    mimeType: 'text/plain',
    isPrivate: false
  };
}

export default function webCoordinatorTest() {
  describe('WebPermissionCoordinator', () => {
    it('remembers normal decisions but keeps private decisions separate', 0, async () => {
      const prompt: PromptFixture = new PromptFixture();
      const coordinator: WebPermissionCoordinator = new WebPermissionCoordinator(prompt);
      expect(await coordinator.decide('https://example.com', WebResourceKind.CAMERA, false))
        .assertEqual(PermissionDecision.ALLOW);
      expect(await coordinator.decide('https://example.com', WebResourceKind.CAMERA, false))
        .assertEqual(PermissionDecision.ALLOW);
      expect(await coordinator.decide('https://example.com', WebResourceKind.CAMERA, true))
        .assertEqual(PermissionDecision.ALLOW);
      expect(prompt.calls).assertEqual(2);
    });

    it('denies unsupported resources and prompt failures', 0, async () => {
      const prompt: PermissionPromptPort = new FailingPromptFixture();
      const coordinator: WebPermissionCoordinator = new WebPermissionCoordinator(prompt);
      expect(await coordinator.decide('https://example.com', WebResourceKind.UNSUPPORTED, false))
        .assertEqual(PermissionDecision.DENY);
      expect(await coordinator.decide('https://example.com', WebResourceKind.GEOLOCATION, false))
        .assertEqual(PermissionDecision.DENY);
    });
  });

  describe('DownloadCoordinator', () => {
    it('sanitizes path separators and control characters', 0, () => {
      expect(sanitizeDownloadFileName('../secret.txt')).assertEqual('.._secret.txt');
      expect(sanitizeDownloadFileName(String.fromCharCode(0, 31))).assertEqual('download');
    });

    it('does not start ArkWeb before the picker resolves', 0, async () => {
      const picker: PickerFixture = new PickerFixture();
      const starter: StarterFixture = new StarterFixture();
      const coordinator: DownloadCoordinator = new DownloadCoordinator(picker, starter);
      picker.destination = undefined;
      expect(await coordinator.handle(downloadRequest())).assertFalse();
      expect(starter.calls).assertEqual(0);
      picker.destination = '/sandbox/secret.txt';
      expect(await coordinator.handle(downloadRequest())).assertTrue();
      expect(starter.calls).assertEqual(1);
      expect(picker.receivedName).assertEqual('.._secret.txt');
    });
  });
}
