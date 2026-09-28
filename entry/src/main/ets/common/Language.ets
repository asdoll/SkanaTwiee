import { common, Want } from '@kit.AbilityKit';
import { i18n } from '@kit.LocalizationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PrefKeys } from './Const';
import { Prefs } from './Prefs';

const DOMAIN: number = 0x0000;
const TAG: string = 'Language';

/** Follow whatever the system is set to. The default, and what a fresh install has. */
export const LANGUAGE_SYSTEM: string = 'system';
/** Simplified Chinese, spelled the way i18n spells it. */
export const LANGUAGE_ZH: string = 'zh-Hans';
/** English, spelled the way i18n spells it. */
export const LANGUAGE_EN: string = 'en';

/** One language the setting offers. */
export class LanguageChoice {
  /** What is stored in the preferences. */
  value: string = '';
  /** What the menu shows. */
  label: string = '';

  constructor(value: string, label: string) {
    this.value = value;
    this.label = label;
  }
}

/**
 * The language the interface is drawn in.
 *
 * HarmonyOS resolves `$r('app.string.…')` against the *application's* preferred
 * language, which `i18n.System.setAppPreferredLanguage` sets - `'default'`
 * meaning "whatever the system is set to". Two consequences shape this class:
 *
 *  - the system only keeps that setting for the life of the process, so the
 *    choice is stored here and published again on every launch (EntryAbility);
 *  - resources are read once, when the application starts, so a change takes
 *    effect from the next cold start. That is why picking a language restarts
 *    the app rather than trying to re-render every screen in place.
 */
export class Language {
  /** The stored choice; the system language when nothing was ever chosen. */
  static current(): string {
    return Prefs.getString(PrefKeys.APP_LANGUAGE, LANGUAGE_SYSTEM);
  }

  static set(value: string): void {
    Prefs.setString(PrefKeys.APP_LANGUAGE, value);
  }

  /** What i18n understands by a stored choice. */
  static i18nValue(value: string): string {
    if (value === LANGUAGE_ZH || value === LANGUAGE_EN) {
      return value;
    }
    return 'default';
  }

  /** Publishes the stored choice; the resources follow on the next cold start. */
  static apply(): void {
    const chosen: string = Language.current();
    try {
      i18n.System.setAppPreferredLanguage(Language.i18nValue(chosen));
      hilog.info(DOMAIN, TAG, 'interface language: %{public}s', chosen);
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'could not set the language (%{public}s)', JSON.stringify(err.code));
    }
  }

  /**
   * What the settings row shows.
   *
   * A language names itself in its own language - 简体中文 stays 简体中文 in an
   * English interface - so only the "follow the system" row is translated, and
   * that one is read from the resources rather than kept here.
   */
  static label(value: string): string {
    if (value === LANGUAGE_ZH) {
      return '简体中文';
    }
    if (value === LANGUAGE_EN) {
      return 'English';
    }
    return '';
  }

  /**
   * The languages the setting offers, system first.
   *
   * The context is needed for the one label that is translated; the rest are
   * literal, so a failure to read it costs nothing.
   */
  static choices(context: common.UIAbilityContext): LanguageChoice[] {
    const choices: LanguageChoice[] = [];
    choices.push(new LanguageChoice(LANGUAGE_SYSTEM, Language.systemLabel(context)));
    choices.push(new LanguageChoice(LANGUAGE_ZH, '简体中文'));
    choices.push(new LanguageChoice(LANGUAGE_EN, 'English'));
    return choices;
  }

  /** "跟随系统" / "System default", named in whichever language is in force. */
  static systemLabel(context: common.UIAbilityContext): string {
    try {
      const label: string =
        context.resourceManager.getStringSync($r('app.string.language_system').id);
      if (label.length > 0) {
        return label;
      }
    } catch (e) {
      hilog.debug(DOMAIN, TAG, 'could not read the system-language label');
    }
    return 'System default';
  }

  /**
   * Restarts the app so a new language is picked up at once.
   *
   * Returns false when the platform refused, which is not fatal: the choice is
   * stored either way and the next launch reads it. The refusals that happen in
   * practice are 16000064 (restarted less than 3 s ago) and 16000053 (the ability
   * is not on top of the stack).
   */
  static restart(context: common.UIAbilityContext): boolean {
    const want: Want = {
      bundleName: context.abilityInfo.bundleName,
      abilityName: context.abilityInfo.name
    };
    try {
      context.getApplicationContext().restartApp(want);
      hilog.info(DOMAIN, TAG, 'restarting for the language change');
      return true;
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'could not restart for the language change (%{public}s)',
        JSON.stringify(err.code));
      return false;
    }
  }
}
