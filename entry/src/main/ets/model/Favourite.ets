import { Video } from './Video';

/**
 * A video the user favourited.
 *
 * A favourite is a bookmark and nothing else: a note about a video, with no file
 * behind it. Downloads are a separate collection of their own (see
 * DownloadEntry) and the two never share a record, so removing a favourite can
 * never touch anything on disk and removing a download can never drop a
 * bookmark. A video can be favourited, downloaded, both, or neither.
 */
export class Favourite {
  /** Twitch video id; the identity of the entry. */
  id: string = '';
  title: string = '';
  channelLogin: string = '';
  channelName: string = '';
  channelImageURL: string = '';
  thumbnailURL: string = '';
  durationSeconds: number = 0;
  createdAt: string = '';
  /** ARCHIVE | HIGHLIGHT | UPLOAD */
  type: string = '';
  /** Unix ms the entry was favourited, so the list can show the newest first. */
  favouritedAt: number = 0;

  /** Copies everything about a video that the list needs to draw it offline. */
  static fromVideo(video: Video): Favourite {
    const entry: Favourite = new Favourite();
    entry.id = video.id;
    entry.title = video.title;
    entry.channelLogin = video.channelLogin;
    entry.channelName = video.channelName;
    entry.channelImageURL = video.channelImageURL;
    entry.thumbnailURL = video.thumbnailURL;
    entry.durationSeconds = video.durationSeconds;
    entry.createdAt = video.createdAt;
    entry.type = video.type;
    entry.favouritedAt = Date.now();
    return entry;
  }

  /**
   * Rebuilds an entry read back from preferences.
   *
   * JSON.parse yields plain objects, so every field is copied across with a
   * fallback: an entry written by an older build would otherwise hand `undefined`
   * to code that expects a string.
   */
  static normalize(raw: Favourite): Favourite {
    const entry: Favourite = new Favourite();
    entry.id = raw.id !== undefined ? raw.id : '';
    entry.title = raw.title !== undefined ? raw.title : '';
    entry.channelLogin = raw.channelLogin !== undefined ? raw.channelLogin : '';
    entry.channelName = raw.channelName !== undefined ? raw.channelName : '';
    entry.channelImageURL = raw.channelImageURL !== undefined ? raw.channelImageURL : '';
    entry.thumbnailURL = raw.thumbnailURL !== undefined ? raw.thumbnailURL : '';
    entry.durationSeconds = raw.durationSeconds !== undefined ? raw.durationSeconds : 0;
    entry.createdAt = raw.createdAt !== undefined ? raw.createdAt : '';
    entry.type = raw.type !== undefined ? raw.type : '';
    entry.favouritedAt = raw.favouritedAt !== undefined ? raw.favouritedAt : 0;
    return entry;
  }
}
