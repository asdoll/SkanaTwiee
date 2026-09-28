import { AudioParams, ChannelParams, LibraryParams, LoginParams, PlayerParams, SECTION_DOWNLOADS, SECTION_FAVOURITES } from '../model/Routes';

/**
 * Route names for the Navigation destinations in pages/Index.ets.
 */
export class RouteName {
  static readonly PLAYER: string = 'player';
  static readonly CHANNEL: string = 'channel';
  static readonly LOGIN: string = 'login';
  static readonly LIBRARY: string = 'library';
  static readonly SETTINGS: string = 'settings';
  static readonly AUDIO: string = 'audioPlayer';
}

/**
 * App-wide navigation stack.
 *
 * Replaces the deprecated `router` module; a single stack instance is shared by
 * the Navigation host in Index.ets and by every component that needs to push.
 */
export class Nav {
  static readonly stack: NavPathStack = new NavPathStack();

  static openPlayer(videoId: string, title: string, channelLogin: string): void {
    Nav.stack.pushPathByName(RouteName.PLAYER, new PlayerParams(videoId, title, channelLogin, false));
  }

  /** Live playback: the channel login is the stream identity, not a video id. */
  static openLiveStream(channelLogin: string, title: string): void {
    Nav.stack.pushPathByName(RouteName.PLAYER, new PlayerParams('', title, channelLogin, true));
  }

  static openChannel(login: string, displayName: string): void {
    Nav.stack.pushPathByName(RouteName.CHANNEL, new ChannelParams(login, displayName));
  }

  /**
   * The favourite videos. They are a collection of their own, with nothing on
   * disk behind them; the downloads have their own entry point below.
   */
  static openFavourites(): void {
    Nav.stack.pushPathByName(RouteName.LIBRARY, new LibraryParams(SECTION_FAVOURITES));
  }

  /** The videos kept on this device, which are not favourites unless marked so. */
  static openDownloads(): void {
    Nav.stack.pushPathByName(RouteName.LIBRARY, new LibraryParams(SECTION_DOWNLOADS));
  }

  /** The app's own settings: the account, the playback defaults, and the file. */
  static openSettings(): void {
    Nav.stack.pushPathByName(RouteName.SETTINGS, '');
  }

  /** Replays a downloaded file straight from the sandbox, with no network. */
  static openDownloadedVideo(videoId: string, path: string, title: string,
    channelLogin: string): void {
    Nav.stack.pushPathByName(RouteName.PLAYER,
      new PlayerParams(videoId, title, channelLogin, false, path));
  }

  /** A downloaded audio-only file, which opens in the music-player screen. */
  static openAudioPlayer(params: AudioParams): void {
    Nav.stack.pushPathByName(RouteName.AUDIO, params);
  }

  static openLogin(): void {
    Nav.stack.pushPathByName(RouteName.LOGIN, new LoginParams());
  }

  /**
   * Opens the Twitch page purely to capture an integrity token.
   *
   * Follow/unfollow is refused unless the request carries a Client-Integrity
   * signature, and only Twitch's own page can mint one for the signed-in user, so
   * the page is loaded with the stored session cookie and the header it sends is
   * recorded.
   */
  static openLoginVerify(): void {
    Nav.stack.pushPathByName(RouteName.LOGIN, new LoginParams(true));
  }

  static back(): void {
    Nav.stack.pop();
  }
}
