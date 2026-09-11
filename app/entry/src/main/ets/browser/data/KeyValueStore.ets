import preferences from '@ohos.data.preferences';
import { Context } from '@kit.AbilityKit';

export interface KeyValueStore {
  getString(key: string, fallback: string): Promise<string>;
  putString(key: string, value: string): Promise<void>;
  flush(): Promise<void>;
}

export interface ApplicationContextProvider {
  getApplicationContext(): Context;
}

export class MemoryKeyValueStore implements KeyValueStore {
  private readonly values: Map<string, string> = new Map();

  async getString(key: string, fallback: string): Promise<string> {
    return this.values.get(key) ?? fallback;
  }

  async putString(key: string, value: string): Promise<void> {
    this.values.set(key, value);
  }

  async flush(): Promise<void> {}
}

/**
 * Preferences are application-scoped. UI host contexts can be backed by a
 * page/window context and are rejected by the Preferences API on device, so
 * always normalize the context before opening the store.
 */
export function applicationContextForPreferences(context: Context | ApplicationContextProvider): Context {
  return context.getApplicationContext();
}

/** Preferences adapter. The repository depends on the small interface above
 * so corruption and persistence behavior can be tested without a device. */
export class PreferencesKeyValueStore implements KeyValueStore {
  private readonly preferences: Promise<preferences.Preferences>;

  constructor(context: Context) {
    this.preferences = preferences.getPreferences(applicationContextForPreferences(context), 'glide_browser');
  }

  async getString(key: string, fallback: string): Promise<string> {
    try {
      const store: preferences.Preferences = await this.preferences;
      const value: preferences.ValueType = await store.get(key, fallback);
      return typeof value === 'string' ? value : fallback;
    } catch (_error) {
      return fallback;
    }
  }

  async putString(key: string, value: string): Promise<void> {
    try {
      const store: preferences.Preferences = await this.preferences;
      await store.put(key, value);
    } catch (_error) {
      // Best-effort persistence; the repository remains usable in memory.
    }
  }

  async flush(): Promise<void> {
    try {
      const store: preferences.Preferences = await this.preferences;
      await store.flush();
    } catch (_error) {
      // Best-effort persistence; a later lifecycle save can retry.
    }
  }
}
