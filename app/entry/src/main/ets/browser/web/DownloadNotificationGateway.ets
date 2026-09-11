import { common, Context } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';

export interface NotificationPermissionPort {
  requestOnce(): Promise<boolean>;
}

export interface NotificationRequestClient {
  requestEnableNotification(context: Context): Promise<void>;
}

class HarmonyNotificationRequestClient implements NotificationRequestClient {
  async requestEnableNotification(context: Context): Promise<void> {
    return await notificationManager.requestEnableNotification(context as common.UIAbilityContext);
  }
}

export class DownloadNotificationGateway implements NotificationPermissionPort {
  private readonly context: Context;
  private readonly client: NotificationRequestClient;
  private request: Promise<boolean> | undefined = undefined;

  constructor(context: Context, client: NotificationRequestClient | undefined = undefined) {
    this.context = context;
    this.client = client ?? new HarmonyNotificationRequestClient();
  }

  requestOnce(): Promise<boolean> {
    if (this.request === undefined) {
      this.request = this.client.requestEnableNotification(this.context)
        .then((): boolean => true)
        .catch((_error: Error): boolean => false);
    }
    return this.request;
  }
}
