import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PrefKeys } from '../common/Const';
import { Prefs } from '../common/Prefs';
import { Favourite } from '../model/Favourite';
import { FavouriteRepository } from './FavouriteRepository';

const DOMAIN: number = 0x0000;
const TAG: string = 'SettingsFile';
/** Marks the file as ours, so importing something else fails with a reason. */
const APP_TAG: string = 'skanatwiee';
const KIND_TAG: string = 'settings';
/** Bumped when a stored setting changes meaning; other versions are refused. */
const FORMAT_VERSION: number = 1;
/** What the save dialog offers as a name, and the filter both dialogs use. */
const FILE_NAME: string = 'skanatwiee-settings.json';
const FILE_SUFFIX: string = '.json';

/**
 * What came of a transfer.
 *
 * A status rather than a message: the page owns the wording, the way every other
 * string in the app is a resource.
 */
export class TransferStatus {
  static readonly OK: string = 'ok';
  /** The picker was dismissed, which is not a failure to report. */
  static readonly CANCELLED: string = 'cancelled';
  /** Readable, but not one of our settings files. */
  static readonly NOT_SETTINGS: string = 'not_settings';
  /** The file could not be read, or written, at all. */
  static readonly FAILED: string = 'failed';
}

/**
 * What a settings file holds.
 *
 * One typed field per setting rather than a bag of raw keys: a file written by an
 * older build simply lacks the fields that build did not have, and anything a
 * file carries that this build does not know is ignored instead of being written
 * into the preferences unseen.
 *
 * Credentials are deliberately absent - the Twitch token and the integrity
 * cookies are tied to the account they were minted for - and so are the
 * downloads, which name files sitting on one device. What travels is what the Me
 * tab lets the user choose, plus the favourites: a list of videos is worth having
 * on the second device, and it is only names and ids.
 */
class SettingsPayload {
  app: string = APP_TAG;
  kind: string = KIND_TAG;
  version: number = FORMAT_VERSION;
  exportedAt: number = 0;
  defaultQuality: string = '';
  defaultSpeed: number = 1;
  savePositions: boolean = true;
  favourites: Favourite[] = [];
}

/**
 * Carries the playback settings to and from a file, so a second device can be
 * given them without setting each one again by hand.
 *
 * The file is written where the user keeps it, through the system picker rather
 * than into the app's own sandbox: a sandbox file is exactly the file the other
 * device cannot reach.
 */
export class SettingsFile {
  /** Writes the settings to a file the user picks. */
  static async export(context: common.Context): Promise<string> {
    let uris: string[] = [];
    try {
      uris = await SettingsFile.pickToSave(context);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'the save dialog failed: %{public}s', JSON.stringify(e));
      return TransferStatus.FAILED;
    }
    if (uris.length === 0) {
      return TransferStatus.CANCELLED;
    }
    try {
      // The picker has already created the file it returned; CREATE and TRUNC
      // between them mean the write starts from an empty one either way, so a
      // file being overwritten never keeps a tail of the old contents.
      const file = fs.openSync(uris[0],
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, JSON.stringify(SettingsFile.snapshot()));
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'the settings could not be written: %{public}s', JSON.stringify(e));
      return TransferStatus.FAILED;
    }
    hilog.info(DOMAIN, TAG, 'settings exported');
    return TransferStatus.OK;
  }

  /**
   * Applies the settings in a file the user picks.
   *
   * Only the fields the file actually carries, so a file written by a build that
   * knew fewer settings leaves the rest of them as they are rather than resetting
   * them. The values themselves are re-read through SettingsRepository, which
   * treats anything it does not recognise as "not set" - so even a hand-edited
   * file cannot leave the player unable to start.
   *
   * Favourites are merged rather than replaced: the device being imported to may
   * have favourites of its own.
   */
  static async import(context: common.Context): Promise<string> {
    let uris: string[] = [];
    try {
      uris = await SettingsFile.pickToLoad(context);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'the open dialog failed: %{public}s', JSON.stringify(e));
      return TransferStatus.FAILED;
    }
    if (uris.length === 0) {
      return TransferStatus.CANCELLED;
    }

    let payload: SettingsPayload;
    try {
      payload = JSON.parse(fs.readTextSync(uris[0])) as SettingsPayload;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'the chosen file could not be read: %{public}s', JSON.stringify(e));
      return TransferStatus.FAILED;
    }
    if (payload === undefined || payload.app !== APP_TAG || payload.kind !== KIND_TAG) {
      hilog.warn(DOMAIN, TAG, 'the chosen file is not ours');
      return TransferStatus.NOT_SETTINGS;
    }
    if (payload.version !== FORMAT_VERSION) {
      hilog.warn(DOMAIN, TAG, 'settings format %{public}s is not supported', `${payload.version}`);
      return TransferStatus.NOT_SETTINGS;
    }

    if (payload.defaultQuality !== undefined) {
      Prefs.setString(PrefKeys.DEFAULT_QUALITY, payload.defaultQuality);
    }
    if (payload.defaultSpeed !== undefined) {
      Prefs.setNumber(PrefKeys.DEFAULT_SPEED, payload.defaultSpeed);
    }
    if (payload.savePositions !== undefined) {
      Prefs.setBoolean(PrefKeys.SAVE_POSITIONS, payload.savePositions);
    }
    if (payload.favourites !== undefined) {
      const added: number = FavouriteRepository.merge(SettingsFile.entriesOf(payload.favourites));
      hilog.info(DOMAIN, TAG, 'added %{public}d favourites from the file', added);
    }
    hilog.info(DOMAIN, TAG, 'settings imported');
    return TransferStatus.OK;
  }

  /**
   * The favourites a file carries, rebuilt as entries.
   *
   * JSON.parse yields plain objects, so each one goes through the model's own
   * normalization - a file with a field missing would otherwise hand `undefined`
   * to the list that draws it.
   */
  private static entriesOf(raw: Favourite[]): Favourite[] {
    const entries: Favourite[] = [];
    for (let i = 0; i < raw.length; i++) {
      const entry: Favourite = Favourite.normalize(raw[i]);
      if (entry.id.length > 0 && entry.title.length > 0) {
        entries.push(entry);
      }
    }
    return entries;
  }

  /** The settings as the file holds them, read from where the app keeps them. */
  private static snapshot(): SettingsPayload {
    const payload: SettingsPayload = new SettingsPayload();
    payload.exportedAt = Date.now();
    payload.defaultQuality = Prefs.getString(PrefKeys.DEFAULT_QUALITY, '');
    payload.defaultSpeed = Prefs.getNumber(PrefKeys.DEFAULT_SPEED, 1);
    payload.savePositions = Prefs.getBoolean(PrefKeys.SAVE_POSITIONS, true);
    payload.favourites = FavouriteRepository.all();
    return payload;
  }

  /** The save dialog; an empty list means the user backed out of it. */
  private static async pickToSave(context: common.Context): Promise<string[]> {
    const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
    options.newFileNames = [FILE_NAME];
    options.fileSuffixChoices = [FILE_SUFFIX];
    const viewPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    return viewPicker.save(options);
  }

  /** The open dialog, filtered to JSON; an empty list means it was dismissed. */
  private static async pickToLoad(context: common.Context): Promise<string[]> {
    const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = [FILE_SUFFIX];
    const viewPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    return viewPicker.select(options);
  }
}
