/**
 * Static constants shared across the app.
 * Ported from Xtra (com.github.andreyasadchy.xtra.util.C).
 */
export class Const {
  static readonly GQL_URL: string = 'https://gql.twitch.tv/gql';
  /** Twitch's IRC gateway, the same endpoint Xtra's chat sockets use. */
  static readonly CHAT_SOCKET_URL: string = 'wss://irc-ws.chat.twitch.tv:443';
  /**
   * Codecs AVPlayer can decode, sent to usher as `supported_codecs`.
   *
   * Twitch lists an AV1 rendition first for broadcasters using enhanced
   * broadcasting, and AVPlayer rejects it with 5400106 (unsupported format) -
   * whichever channel happens to be streaming AV1 then fails to play. Xtra
   * passes the device's codec list for the same reason.
   */
  static readonly SUPPORTED_CODECS: string =
    'avc1.42E01E,avc1.42E01F,avc1.4D401E,avc1.4D401F,avc1.4D4028,'
      + 'avc1.64001E,avc1.64001F,avc1.640028,avc1.64002A,avc1.640032,'
      + 'hvc1.1.6.L93.B0,hvc1.1.6.L120.B0,hvc1.2.4.L120.B0';
  /** Helix, used for the emote picker's global and channel emote sets. */
  static readonly HELIX_GLOBAL_EMOTES: string = 'https://api.twitch.tv/helix/chat/emotes/global';
  static readonly HELIX_CHANNEL_EMOTES: string = 'https://api.twitch.tv/helix/chat/emotes?broadcaster_id=';
  /** Issues the Client-Integrity token that follow/unfollow mutations require. */
  static readonly INTEGRITY_URL: string = 'https://gql.twitch.tv/integrity';
  static readonly VALIDATE_URL: string = 'https://id.twitch.tv/oauth2/validate';
  static readonly USHER_VOD_URL: string = 'https://usher.ttvnw.net/vod/v2/';
  static readonly USHER_LIVE_URL: string = 'https://usher.ttvnw.net/api/v2/channel/hls/';
  static readonly TWITCH_HOME_URL: string = 'https://www.twitch.tv/';
  static readonly TWITCH_LOGIN_URL: string = 'https://www.twitch.tv/login';
  /** Host whose requests carry the Client-Integrity signature. */
  static readonly GQL_HOST: string = 'gql.twitch.tv';
  /** Twitch's own session cookie; writing it signs the page in without a password. */
  static readonly AUTH_TOKEN_COOKIE: string = 'auth-token';
  /** Xtra's INTEGRITY_EXPIRATION offset: a captured token is good for ~16 hours. */
  static readonly INTEGRITY_TTL_MS: number = 57600000;

  /** Public Twitch web client id, used for anonymous and signed-in GQL calls. */
  static readonly GQL_WEB_CLIENT_ID: string = 'kimne78kx3ncx6brgo4mv6wki5h1ko';

  static readonly HEADER_CLIENT_ID: string = 'Client-Id';
  static readonly HEADER_AUTH: string = 'Authorization';
  static readonly HEADER_DEVICE_ID: string = 'X-Device-Id';
  static readonly HEADER_INTEGRITY: string = 'Client-Integrity';

  /** Player type Twitch expects for VOD playback tokens. */
  static readonly DEFAULT_PLAYER_TYPE: string = 'channel_home_live';

  /** Persisted query hash for the VOD playback access token. */
  static readonly PLAYBACK_TOKEN_HASH: string =
    'ed230aa1e33e07eebb8928504583da78a5173989fadfb1ac94be06a04f3cdbe9';

  /* Persisted mutations for the follow button, as used by Xtra. */
  static readonly FOLLOW_USER_HASH: string =
    '800e7346bdf7e5278a3c1d3f21b2b56e2639928f86815677a7126b093b2fdd08';
  static readonly UNFOLLOW_USER_HASH: string =
    'f7dae976ebf41c755ae2d758546bfd176b4eeb856656098bb40e0a672ca0d880';

  static readonly PAGE_SIZE: number = 30;
  /**
   * Followed channels are a shorter page: each row also resolves the channel's
   * live state and its latest VOD, so the query is heavier per item.
   */
  static readonly FOLLOWED_USERS_PAGE_SIZE: number = 20;
  static readonly MAX_RECENT_SEARCHES: number = 15;
}

/** Preference keys. */
export class PrefKeys {
  static readonly GQL_CLIENT_ID: string = 'gql_client_id';
  static readonly GQL_TOKEN: string = 'gql_token';
  /** Header set captured from Twitch's own page (see IntegrityRepository). */
  static readonly INTEGRITY_TOKEN: string = 'integrity_token';
  static readonly INTEGRITY_DEVICE_ID: string = 'integrity_device_id';
  static readonly INTEGRITY_EXPIRATION: string = 'integrity_expiration';
  static readonly USER_ID: string = 'user_id';
  static readonly USER_LOGIN: string = 'user_login';
  static readonly USER_NAME: string = 'user_name';
  static readonly USER_IMAGE: string = 'user_image';
  static readonly PLAYER_TYPE: string = 'player_type';
  /** Stable per-install device id, shared by playback and integrity requests. */
  static readonly DEVICE_ID: string = 'device_id';
  static readonly SAVE_POSITIONS: string = 'save_positions';
  static readonly POSITION_PREFIX: string = 'pos_';
  static readonly LAST_QUALITY: string = 'last_quality';
  static readonly RECENT_SEARCHES: string = 'recent_searches';
  /** Default rendition a video opens at, by playlist name; '' means Auto. */
  static readonly DEFAULT_QUALITY: string = 'default_quality';
  /** Default playback rate, 1 being normal speed. */
  static readonly DEFAULT_SPEED: string = 'default_speed';

  /**
   * Interface language: 'system' (the default), 'zh-Hans' or 'en'.
   *
   * The system only remembers the application's preferred language while the
   * process lives, so the choice is kept here and published again on each cold
   * start - see common/Language.ets and EntryAbility.
   */
  static readonly APP_LANGUAGE: string = 'app_language';
  /** Favourited videos, a JSON array; see FavouriteRepository. */
  static readonly FAVOURITES: string = 'favourite_videos';
  /** Videos kept on the device, a JSON array; see DownloadRepository. */
  static readonly DOWNLOADS: string = 'download_videos';
  /** The single favourites-and-downloads array earlier builds used. */
  static readonly LEGACY_LIBRARY: string = 'library_videos';
}
