/** Navigation payloads; router params survive as plain field bags. */
export class PlayerParams {
  videoId: string = '';
  title: string = '';
  channelLogin: string = '';
  /** Live playback keys off the channel login instead of a VOD id. */
  isLive: boolean = false;
  /**
   * Sandbox path of a downloaded file. When it is set the player opens the file
   * directly and never asks Twitch for a token or a playlist.
   */
  localPath: string = '';
  /** Channel avatar URL, so the live window has a picture to publish. */
  channelImageURL: string = '';

  constructor(videoId: string, title: string, channelLogin: string, isLive: boolean,
    localPath: string = '', channelImageURL: string = '') {
    this.videoId = videoId;
    this.title = title;
    this.channelLogin = channelLogin;
    this.isLive = isLive;
    this.localPath = localPath;
    this.channelImageURL = channelImageURL;
  }
}

/** The favourited videos. */
export const SECTION_FAVOURITES: number = 0;
/** Only what is on this device. */
export const SECTION_DOWNLOADS: number = 1;

/** The library page; `section` picks which of the two collections it lists. */
export class LibraryParams {
  section: number = SECTION_FAVOURITES;

  constructor(section: number = SECTION_FAVOURITES) {
    this.section = section;
  }
}

/** A downloaded file opened in the audio player. */
export class AudioParams {
  path: string = '';
  title: string = '';
  channel: string = '';
  /** Thumbnail URL, used as the artwork. */
  artwork: string = '';
  durationSeconds: number = 0;

  constructor(path: string, title: string, channel: string, artwork: string, durationSeconds: number) {
    this.path = path;
    this.title = title;
    this.channel = channel;
    this.artwork = artwork;
    this.durationSeconds = durationSeconds;
  }
}

export class ChannelParams {
  login: string = '';
  displayName: string = '';

  constructor(login: string, displayName: string) {
    this.login = login;
    this.displayName = displayName;
  }
}

/** The login destination needs no payload, but NavPathStack wants a param. */
export class LoginParams {
  /** True when the page only exists to mint an integrity token, not to sign in. */
  verify: boolean = false;

  constructor(verify: boolean = false) {
    this.verify = verify;
  }
}
