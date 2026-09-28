import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'Prefs';

/**
 * Thin synchronous wrapper around @ohos.data.preferences.
 * Initialised once from EntryAbility.onCreate().
 */
export class Prefs {
  private static store: preferences.Preferences | undefined = undefined;

  static init(context: common.Context): void {
    try {
      const options: preferences.Options = { name: 'skanatwiee' };
      Prefs.store = preferences.getPreferencesSync(context, options);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Failed to open preferences: %{public}s', JSON.stringify(e));
      Prefs.store = undefined;
    }
  }

  static getString(key: string, def: string): string {
    const store = Prefs.store;
    if (store === undefined) {
      return def;
    }
    try {
      const value: preferences.ValueType = store.getSync(key, def);
      return typeof value === 'string' ? value : def;
    } catch (e) {
      return def;
    }
  }

  static setString(key: string, value: string): void {
    Prefs.put(key, value);
  }

  static getBoolean(key: string, def: boolean): boolean {
    const store = Prefs.store;
    if (store === undefined) {
      return def;
    }
    try {
      const value: preferences.ValueType = store.getSync(key, def);
      return typeof value === 'boolean' ? value : def;
    } catch (e) {
      return def;
    }
  }

  static setBoolean(key: string, value: boolean): void {
    Prefs.put(key, value);
  }

  static getNumber(key: string, def: number): number {
    const store = Prefs.store;
    if (store === undefined) {
      return def;
    }
    try {
      const value: preferences.ValueType = store.getSync(key, def);
      return typeof value === 'number' ? value : def;
    } catch (e) {
      return def;
    }
  }

  static setNumber(key: string, value: number): void {
    Prefs.put(key, value);
  }

  static remove(key: string): void {
    const store = Prefs.store;
    if (store === undefined) {
      return;
    }
    try {
      store.deleteSync(key);
      store.flush();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'remove failed for %{public}s', key);
    }
  }

  private static put(key: string, value: preferences.ValueType): void {
    const store = Prefs.store;
    if (store === undefined) {
      return;
    }
    try {
      store.putSync(key, value);
      store.flush();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'put failed for %{public}s', key);
    }
  }
}
