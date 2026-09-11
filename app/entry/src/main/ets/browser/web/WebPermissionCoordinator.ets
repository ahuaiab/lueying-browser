export enum WebResourceKind {
  CAMERA = 'camera',
  MICROPHONE = 'microphone',
  GEOLOCATION = 'geolocation',
  UNSUPPORTED = 'unsupported'
}

export enum PermissionDecision {
  ALLOW = 'allow',
  DENY = 'deny'
}

export interface PermissionPromptPort {
  confirm(origin: string, resource: WebResourceKind, isPrivate: boolean): Promise<PermissionDecision>;
}

/** Per-process permission memory. Private and ordinary tabs never share a
 * remembered decision, and unsupported resources are denied by default. */
export class WebPermissionCoordinator {
  private readonly normalDecisions: Map<string, PermissionDecision> = new Map();
  private readonly privateDecisions: Map<string, PermissionDecision> = new Map();
  private readonly prompt: PermissionPromptPort;

  constructor(prompt: PermissionPromptPort) {
    this.prompt = prompt;
  }

  async decide(origin: string, resource: WebResourceKind, isPrivate: boolean): Promise<PermissionDecision> {
    if (resource === WebResourceKind.UNSUPPORTED) {
      return PermissionDecision.DENY;
    }
    const decisions: Map<string, PermissionDecision> = isPrivate
      ? this.privateDecisions
      : this.normalDecisions;
    const key: string = `${origin}|${resource}`;
    const known: PermissionDecision | undefined = decisions.get(key);
    if (known !== undefined) {
      return known;
    }
    let decision: PermissionDecision = PermissionDecision.DENY;
    try {
      decision = await this.prompt.confirm(origin, resource, isPrivate);
    } catch (_error) {
      decision = PermissionDecision.DENY;
    }
    decisions.set(key, decision);
    return decision;
  }
}
