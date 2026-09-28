import { Video } from './Video';

/**
 * A video kept on the device.
 *
 * The file is the point of this record, so it carries where the media lives and
 * how big it is. It is stored separately from Favourite and shares nothing with
 * it: un-favouriting a video leaves the file alone, and deleting the file leaves
 * any bookmark alone.
 */
export class DownloadEntry {
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
  /** Unix ms the transfer was queued, so the list can show the newest first. */
  startedAt: number = 0;
  /** Sandbox path of the file; empty while the transfer is still running. */
  filePath: string = '';
  /** Size of the file in bytes, 0 until it has finished. */
  fileSize: number = 0;
  /**
   * True when the file holds sound only, so it opens in the audio player rather
   * than the video one.
   */
  audioOnly: boolean = false;

  /** True once the media has actually been written, not merely queued. */
  get downloaded(): boolean {
    return this.filePath.length > 0;
  }

  /** Copies everything about a video that the downloads list needs to draw it. */
  static fromVideo(video: Video): DownloadEntry {
    const entry: DownloadEntry = new DownloadEntry();
    entry.id = video.id;
    entry.title = video.title;
    entry.channelLogin = video.channelLogin;
    entry.channelName = video.channelName;
    entry.channelImageURL = video.channelImageURL;
    entry.thumbnailURL = video.thumbnailURL;
    entry.durationSeconds = video.durationSeconds;
    entry.createdAt = video.createdAt;
    entry.type = video.type;
    entry.startedAt = Date.now();
    return entry;
  }

  /**
   * Rebuilds an entry read back from preferences, with a fallback per field so a
   * record written by an older build cannot hand `undefined` to code that expects
   * a string.
   */
  static normalize(raw: DownloadEntry): DownloadEntry {
    const entry: DownloadEntry = new DownloadEntry();
    entry.id = raw.id !== undefined ? raw.id : '';
    entry.title = raw.title !== undefined ? raw.title : '';
    entry.channelLogin = raw.channelLogin !== undefined ? raw.channelLogin : '';
    entry.channelName = raw.channelName !== undefined ? raw.channelName : '';
    entry.channelImageURL = raw.channelImageURL !== undefined ? raw.channelImageURL : '';
    entry.thumbnailURL = raw.thumbnailURL !== undefined ? raw.thumbnailURL : '';
    entry.durationSeconds = raw.durationSeconds !== undefined ? raw.durationSeconds : 0;
    entry.createdAt = raw.createdAt !== undefined ? raw.createdAt : '';
    entry.type = raw.type !== undefined ? raw.type : '';
    entry.startedAt = raw.startedAt !== undefined ? raw.startedAt : 0;
    entry.filePath = raw.filePath !== undefined ? raw.filePath : '';
    entry.fileSize = raw.fileSize !== undefined ? raw.fileSize : 0;
    entry.audioOnly = raw.audioOnly !== undefined ? raw.audioOnly : false;
    return entry;
  }
}
