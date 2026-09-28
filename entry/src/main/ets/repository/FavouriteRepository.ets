import { hilog } from '@kit.PerformanceAnalysisKit';
import { PrefKeys } from '../common/Const';
import { Prefs } from '../common/Prefs';
import { Favourite } from '../model/Favourite';
import { Video } from '../model/Video';
import { LibraryMigration } from './LibraryMigration';

const DOMAIN: number = 0x0000;
const TAG: string = 'Favourite';

/**
 * The videos the user favourited.
 *
 * One JSON array in preferences. That is deliberately simple - a favourite is a
 * few hundred bytes and preferences are synchronous, so any screen can read the
 * list while it builds instead of turning a list into an async pipeline.
 *
 * Downloads are not recorded here at all. They have their own store, keyed
 * separately, so nothing a download does can change this list and nothing here
 * can delete a file.
 */
export class FavouriteRepository {
  /** Bumped on every change, so pages and cards showing favourites reload. */
  static readonly KEY_FAVOURITE_VERSION: string = 'favouriteVersion';

  /** Newest first. */
  static all(): Favourite[] {
    LibraryMigration.run();
    const text: string = Prefs.getString(PrefKeys.FAVOURITES, '');
    if (text.length === 0) {
      return [];
    }
    const entries: Favourite[] = [];
    try {
      const parsed: Favourite[] = JSON.parse(text) as Favourite[];
      for (let i = 0; i < parsed.length; i++) {
        const entry: Favourite = Favourite.normalize(parsed[i]);
        if (entry.id.length > 0) {
          entries.push(entry);
        }
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'favourites are unreadable, starting over');
      return [];
    }
    entries.sort((a: Favourite, b: Favourite) => b.favouritedAt - a.favouritedAt);
    return entries;
  }

  static find(id: string): Favourite | undefined {
    const all: Favourite[] = FavouriteRepository.all();
    for (let i = 0; i < all.length; i++) {
      if (all[i].id === id) {
        return all[i];
      }
    }
    return undefined;
  }

  static isFavourite(id: string): boolean {
    return FavouriteRepository.find(id) !== undefined;
  }

  /**
   * Adds the video, or removes it when it is already favourited.
   * Returns true when it is favourited afterwards.
   */
  static toggle(video: Video): boolean {
    if (FavouriteRepository.isFavourite(video.id)) {
      FavouriteRepository.remove(video.id);
      return false;
    }
    FavouriteRepository.addEntry(Favourite.fromVideo(video));
    return true;
  }

  /**
   * Stores the entry, keeping the time it was first favourited.
   *
   * Nothing about a download lives in here, so the only field that survives a
   * rewrite is the timestamp.
   */
  static addEntry(entry: Favourite): void {
    if (entry.id.length === 0) {
      return;
    }
    const all: Favourite[] = FavouriteRepository.all();
    let replaced: boolean = false;
    for (let i = 0; i < all.length; i++) {
      if (all[i].id === entry.id) {
        const favouritedAt: number = all[i].favouritedAt;
        entry.favouritedAt = favouritedAt > 0 ? favouritedAt : Date.now();
        all[i] = entry;
        replaced = true;
        break;
      }
    }
    if (!replaced) {
      if (entry.favouritedAt === 0) {
        entry.favouritedAt = Date.now();
      }
      all.push(entry);
    }
    FavouriteRepository.persist(all);
  }

  static remove(id: string): void {
    const all: Favourite[] = FavouriteRepository.all();
    const remaining: Favourite[] = [];
    for (let i = 0; i < all.length; i++) {
      if (all[i].id !== id) {
        remaining.push(all[i]);
      }
    }
    FavouriteRepository.persist(remaining);
  }

  /**
   * Adds every entry that is not already here, keeping the ones that are.
   *
   * Merging rather than replacing: an imported list can arrive on a device that
   * has favourites of its own, and neither list is worth losing. Returns how many
   * entries were added.
   */
  static merge(entries: Favourite[]): number {
    const all: Favourite[] = FavouriteRepository.all();
    const known: string[] = [];
    for (let i = 0; i < all.length; i++) {
      known.push(all[i].id);
    }
    let added: number = 0;
    for (let i = 0; i < entries.length; i++) {
      const entry: Favourite = entries[i];
      if (entry.id.length === 0 || known.indexOf(entry.id) >= 0) {
        continue;
      }
      known.push(entry.id);
      all.push(entry);
      added++;
    }
    if (added > 0) {
      FavouriteRepository.persist(all);
    }
    return added;
  }

  private static persist(entries: Favourite[]): void {
    try {
      Prefs.setString(PrefKeys.FAVOURITES, JSON.stringify(entries));
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'could not store the favourites');
    }
    const current: number = AppStorage.get<number>(FavouriteRepository.KEY_FAVOURITE_VERSION) ?? 0;
    AppStorage.setOrCreate(FavouriteRepository.KEY_FAVOURITE_VERSION, current + 1);
  }
}
