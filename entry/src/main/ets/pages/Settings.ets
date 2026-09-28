import { common } from '@kit.AbilityKit';
import { PrefKeys } from '../common/Const';
import { Immersive, Insets } from '../common/Immersive';
import { Language, LanguageChoice } from '../common/Language';
import { Prefs } from '../common/Prefs';
import { RateChoice, QualityChoice, SettingsRepository } from '../repository/SettingsRepository';
import { SettingsFile, TransferStatus } from '../repository/SettingsFile';
import { ImmersiveHeader } from '../view/ImmersiveHeader';
import { MENU_WIDTH, MenuChoice, menuListHeight, PopupStateParam } from '../view/MenuChoice';
import { SettingRow } from '../view/SettingRow';

/**
 * The app's own settings.
 *
 * A page of its own rather than the bottom of the Me tab: the Me tab is where the
 * account and the collections are, and what the app does with a video - the
 * quality and rate it opens at, and whether the settings travel to another
 * device - is a different question with a different answer.
 */
@Component
export struct SettingsPage {
  /** Status-bar inset, so the header clears the clock. */
  @State topInset: number = 0;
  @State savePositions: boolean = true;
  /** Playback defaults, and the pickers that change them. */
  @State defaultQuality: string = '';
  @State showDefaultQuality: boolean = false;
  @State defaultRate: number = 1;
  @State showDefaultRate: boolean = false;
  /** Interface language, and the menu that changes it. */
  @State language: string = Language.current();
  @State showLanguage: boolean = false;

  aboutToAppear(): void {
    this.setupInsets();
    this.reload();
  }

  private async setupInsets(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const insets: Insets = await Immersive.enable(context);
    this.topInset = this.getUIContext().px2vp(insets.top);
  }

  /**
   * Reads every setting back out of the repository.
   *
   * Called again after an import, so what the rows show is what the app is
   * actually going to use.
   */
  private reload(): void {
    this.savePositions = Prefs.getBoolean(PrefKeys.SAVE_POSITIONS, true);
    this.defaultQuality = SettingsRepository.quality();
    this.defaultRate = SettingsRepository.rate();
    this.language = Language.current();
  }

  build() {
    NavDestination() {
      Column() {
        this.header()

        // A list rather than a scroll view: a scroll view places a child shorter
        // than itself in the middle of the screen, and a list of settings starts at
        // the top and scrolls once it outgrows the screen.
        List() {
          ListItem() {
            this.positionRow()
          }

          // What a video opens at. Both are only a starting point: the player's
          // own controls still change the quality and the rate for that video
          // alone.
          ListItem() {
            this.defaultQualityRow()
          }
          ListItem() {
            this.defaultRateRow()
          }

          // Which language the interface is drawn in.
          ListItem() {
            this.languageRow()
          }

          // These settings live in this install, so moving devices means carrying
          // them over by hand. Credentials stay behind: they belong to the account
          // they were minted for.
          ListItem() {
            SettingRow({
              icon: $r('sys.symbol.square_and_arrow_down'),
              label: $r('app.string.export_settings'),
              onTap: (): void => {
                this.exportSettings();
              }
            })
          }
          ListItem() {
            SettingRow({
              icon: $r('sys.symbol.arrow_clockwise'),
              label: $r('app.string.import_settings'),
              onTap: (): void => {
                this.importSettings();
              }
            })
          }

          ListItem() {
            Text($r('app.string.about_tagline'))
              .fontSize(12)
              .fontColor($r('app.color.text_muted'))
              .margin({ top: 20 })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .padding({ left: 16, right: 16, top: 12, bottom: 24 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'))
    }
    .hideTitleBar(true)
  }

  @Builder
  header() {
    ImmersiveHeader({ topInset: this.topInset, showBack: true }) {
      Text($r('app.string.settings'))
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: 4 })
    }
  }

  /** Whether a video remembers where it was left. */
  @Builder
  positionRow() {
    Row() {
      Text($r('app.string.save_player_positions'))
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.savePositions })
        .selectedColor($r('app.color.accent'))
        .onChange((isOn: boolean) => {
          this.savePositions = isOn;
          Prefs.setBoolean(PrefKeys.SAVE_POSITIONS, isOn);
        })
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(12)
    .margin({ top: 12 })
  }

  /**
   * Default playback quality.
   *
   * The choice is a resolution, and Auto is stored as no name at all: a broadcast
   * that does not carry the chosen resolution plays on Auto rather than refusing
   * to start.
   */
  @Builder
  defaultQualityRow() {
    Row() {
      SymbolGlyph($r('sys.symbol.gearshape_fill'))
        .fontSize(18)
        .fontColor([$r('app.color.accent')])
      Text($r('app.string.default_quality'))
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: 10 })
        .layoutWeight(1)
      Text(SettingsRepository.qualityLabel(this.defaultQuality))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
      Text('\u203a')
        .fontSize(18)
        .fontColor($r('app.color.text_muted'))
        .margin({ left: 6 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(12)
    .margin({ top: 12 })
    .onClick(() => {
      this.showDefaultQuality = true;
    })
    .bindPopup(this.showDefaultQuality, {
      builder: (): void => {
        this.defaultQualityPopup()
      },
      placement: Placement.Bottom,
      autoCancel: true,
      onStateChange: (event: PopupStateParam): void => {
        if (!event.isVisible) {
          this.showDefaultQuality = false;
        }
      }
    })
  }

  /** Default playback speed: only the video watched next uses it. */
  @Builder
  defaultRateRow() {
    Row() {
      SymbolGlyph($r('sys.symbol.play_fill'))
        .fontSize(18)
        .fontColor([$r('app.color.accent')])
      Text($r('app.string.default_speed'))
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: 10 })
        .layoutWeight(1)
      Text(SettingsRepository.rateLabel(this.defaultRate))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
      Text('\u203a')
        .fontSize(18)
        .fontColor($r('app.color.text_muted'))
        .margin({ left: 6 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(12)
    .margin({ top: 12 })
    .onClick(() => {
      this.showDefaultRate = true;
    })
    .bindPopup(this.showDefaultRate, {
      builder: (): void => {
        this.defaultRatePopup()
      },
      placement: Placement.Bottom,
      autoCancel: true,
      onStateChange: (event: PopupStateParam): void => {
        if (!event.isVisible) {
          this.showDefaultRate = false;
        }
      }
    })
  }

  /** The qualities the default-quality row offers, ticked where it stands. */
  @Builder
  defaultQualityPopup() {
    Column() {
      List() {
        ForEach(SettingsRepository.qualities(), (choice: QualityChoice) => {
          ListItem() {
            MenuChoice({
              label: choice.label,
              selected: this.defaultQuality === choice.name,
              onTap: (): void => {
                this.defaultQuality = choice.name;
                SettingsRepository.setQuality(choice.name);
                this.showDefaultQuality = false;
              }
            })
          }
        }, (choice: QualityChoice) => choice.name)
      }
      .width('100%')
      .scrollBar(BarState.Off)
      .height(menuListHeight(SettingsRepository.qualities().length))
    }
    .width(MENU_WIDTH)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(12)
    .clip(true)
  }

  /** The rates the default-speed row offers, ticked where it stands. */
  @Builder
  defaultRatePopup() {
    Column() {
      List() {
        ForEach(SettingsRepository.rates(), (choice: RateChoice) => {
          ListItem() {
            MenuChoice({
              label: choice.label,
              selected: this.defaultRate === choice.rate,
              onTap: (): void => {
                this.defaultRate = choice.rate;
                SettingsRepository.setRate(choice.rate);
                this.showDefaultRate = false;
              }
            })
          }
        }, (choice: RateChoice) => choice.label)
      }
      .width('100%')
      .scrollBar(BarState.Off)
      .height(menuListHeight(SettingsRepository.rates().length))
    }
    .width(MENU_WIDTH)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(12)
    .clip(true)
  }

  /**
   * Interface language.
   *
   * The row shows what is in force; the menu offers the system language and the
   * two this app carries resources for. The Chinese table lives in
   * `resources/zh_Hans`, spelt by script rather than by region: a qualifier has
   * to match the device state, and a phone set to Singapore is `zh-Hans-SG`,
   * which a `zh_CN` directory would not answer.
   */
  @Builder
  languageRow() {
    Row() {
      Text($r('app.string.language'))
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Text(this.languageLabel())
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
      Text('\u203a')
        .fontSize(18)
        .fontColor($r('app.color.text_muted'))
        .margin({ left: 6 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(12)
    .margin({ top: 12 })
    .onClick(() => {
      this.showLanguage = true;
    })
    .bindPopup(this.showLanguage, {
      builder: (): void => {
        this.languagePopup()
      },
      placement: Placement.Bottom,
      autoCancel: true,
      onStateChange: (event: PopupStateParam): void => {
        if (!event.isVisible) {
          this.showLanguage = false;
        }
      }
    })
  }

  /** What the language row reads: the chosen language, or "follow the system". */
  private languageLabel(): string {
    const named: string = Language.label(this.language);
    if (named.length > 0) {
      return named;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    return Language.systemLabel(context);
  }

  /** The languages the row offers, ticked where the setting stands. */
  @Builder
  languagePopup() {
    Column() {
      List() {
        ForEach(this.languageChoices(), (choice: LanguageChoice) => {
          ListItem() {
            MenuChoice({
              label: choice.label,
              selected: this.language === choice.value,
              onTap: (): void => {
                this.pickLanguage(choice.value);
              }
            })
          }
        }, (choice: LanguageChoice) => choice.value)
      }
      .width('100%')
      .scrollBar(BarState.Off)
      .height(menuListHeight(this.languageChoices().length))
    }
    .width(MENU_WIDTH)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(12)
    .clip(true)
  }

  private languageChoices(): LanguageChoice[] {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    return Language.choices(context);
  }

  /**
   * Stores the chosen language, then restarts the app.
   *
   * There is nothing to re-render in place: every screen is built from resources
   * that are read once per launch, so the app comes back up in the new language.
   * A restart the platform refuses leaves the setting stored - the next launch
   * picks it up - and says so rather than looking like nothing happened.
   */
  private pickLanguage(value: string): void {
    this.showLanguage = false;
    if (value === this.language) {
      return;
    }
    this.language = value;
    Language.set(value);
    Language.apply();
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!Language.restart(context)) {
      this.toast($r('app.string.language_needs_restart'));
    }
  }

  /**
   * Writes the settings to a file the user picks.
   *
   * Nothing happens until the picker has been answered: a dismissed dialog is not
   * an outcome worth reporting, and the file itself is written once the user has
   * said where it goes.
   */
  private exportSettings(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    SettingsFile.export(context).then((status: string) => {
      if (status !== TransferStatus.CANCELLED) {
        this.toast(status === TransferStatus.OK
          ? $r('app.string.settings_exported') : $r('app.string.settings_export_failed'));
      }
    }, (error: Error) => {
      this.toast($r('app.string.settings_export_failed'));
    });
  }

  /**
   * Applies the settings in a file the user picks.
   *
   * The rows read the settings back afterwards, so an import shows up at once
   * rather than only the next time the app starts.
   */
  private importSettings(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    SettingsFile.import(context).then((status: string) => {
      if (status === TransferStatus.CANCELLED) {
        return;
      }
      if (status === TransferStatus.OK) {
        this.reload();
        this.toast($r('app.string.settings_imported'));
        return;
      }
      this.toast(status === TransferStatus.NOT_SETTINGS
        ? $r('app.string.settings_not_ours') : $r('app.string.settings_import_failed'));
    }, (error: Error) => {
      this.toast($r('app.string.settings_import_failed'));
    });
  }

  /** Says what happened, in one line at the bottom of the screen. */
  private toast(message: Resource): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1600 });
    } catch (e) {
      // A toast is a courtesy: whatever was done to the settings has been done.
    }
  }
}
