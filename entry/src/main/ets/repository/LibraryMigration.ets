import { hilog } from '@kit.PerformanceAnalysisKit';
import { PrefKeys } from '../common/Const';
import { Prefs } from '../common/Prefs';
import { DownloadEntry } from '../model/DownloadEntry';
import { Favourite } from '../model/Favourite';

const DOMAIN: number = 0x0000;
const TAG: string = 'LibraryMigration';

/**
 * The shape of one record in the old combined library.
 *
 * It carried the favourites and the downloads in the same object, which is
 * exactly what the split below takes apart. Every field of both new records is
 * present, so one of these can be read as either - which is the point, since the
 * old array did not say what a row was until you looked at its flags.
 */
class LegacyEntry {
  id: string = '';
  title: string = '';
  channelLogin: string = '';
  channelName: string = '';
  channelImageURL: string = '';
  thumbnailURL: string = '';
  durationSeconds: number = 0;
  createdAt: string = '';
  type: string = '';
  savedAt: number = 0;
  favorite: boolean = false;
  startedAt: number = 0;
  favouritedAt: number = 0;
  filePath: string = '';
  fileSize: number = 0;
  audioOnly: boolean = false;

  get downloaded(): boolean {
    return this.filePath.length > 0;
  }
}

/**
 * One-time split of the old combined library.
 *
 * Earlier builds kept favourites and downloads in a single `library_videos`
 * array, each entry either flagged `favorite`, carrying a file path, or both. The
 * two are now separate collections under separate keys, so the old array is read
 * once, split into the two stores, and cleared - after which nothing here runs
 * again, and neither collection can see the other.
 */
export class LibraryMigration {
  static run(): void {
    const text: string = Prefs.getString(PrefKeys.LEGACY_LIBRARY, '');
    if (text.length === 0) {
      return;
    }
    // Cleared first: a read that fails must not leave the old array behind to be
    // tried again on every load.
    Prefs.setString(PrefKeys.LEGACY_LIBRARY, '');

    let raw: LegacyEntry[] = [];
    try {
      raw = JSON.parse(text) as LegacyEntry[];
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'the old library was unreadable, nothing to move');
      return;
    }

    const favourites: Favourite[] = [];
    const downloads: DownloadEntry[] = [];
    for (let i = 0; i < raw.length; i++) {
      const entry: LegacyEntry = raw[i];
      if (entry === undefined || entry.id === undefined || entry.id.length === 0) {
        continue;
      }
      // Only the bookmarked ones were favourites; the time they carry is the one
      // the list sorts by.
      if (entry.favorite === true) {
        const favourite: Favourite = Favourite.normalize(entry as Favourite);
        favourite.favouritedAt = entry.savedAt !== undefined ? entry.savedAt : 0;
        favourites.push(favourite);
      }
      // An entry with no file behind it was never a download, whatever the old
      // record claimed.
      if (entry.filePath !== undefined && entry.filePath.length > 0) {
        const download: DownloadEntry = DownloadEntry.normalize(entry as DownloadEntry);
        download.startedAt = entry.savedAt !== undefined ? entry.savedAt : 0;
        downloads.push(download);
      }
    }

    Prefs.setString(PrefKeys.FAVOURITES, JSON.stringify(favourites));
    Prefs.setString(PrefKeys.DOWNLOADS, JSON.stringify(downloads));
    hilog.info(DOMAIN, TAG, 'split the old library: %{public}d favourites, %{public}d downloads',
      favourites.length, downloads.length);
  }
}
