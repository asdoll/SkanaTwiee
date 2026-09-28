import { hilog } from '@kit.PerformanceAnalysisKit';
import { Const, PrefKeys } from '../common/Const';
import { Prefs } from '../common/Prefs';
import { GqlClient, PlaybackTokenVars, StreamPlaybackTokenVars, VideoPlaybackTokenVars } from '../network/GqlClient';
import { Queries } from '../network/Queries';
import {
  GqlPlaybackToken,
  PlaybackAccessTokenResponse,
  StreamPlaybackAccessTokenResponse
} from '../network/GqlTypes';
import { Http, HttpResult } from '../network/Http';
import { HlsParser } from '../player/HlsParser';
import { Quality } from '../model/Quality';

const DOMAIN: number = 0x0000;
const TAG: string = 'PlaybackRepo';

/** signature + value pair returned by Twitch for VOD playback. */
export class PlaybackToken {
  signature: string = '';
  value: string = '';
  /**
   * `chansub.restricted_bitrates` from the token, when present. Xtra uses this
   * as the rendition list for the preview-derived fallback below.
   */
  restrictedBitrates: string[] = [];

  constructor(signature: string, value: string, restrictedBitrates: string[]) {
    this.signature = signature;
    this.value = value;
    this.restrictedBitrates = restrictedBitrates;
  }
}

/** One rendition that is playable straight from the VOD CDN. */
export class DirectQuality {
  /** Display name; the chunked rendition is shown as "source". */
  name: string = '';
  /** CDN path segment, e.g. "chunked" or "720p60". */
  segment: string = '';
  url: string = '';

  constructor(name: string, segment: string, url: string) {
    this.name = name;
    this.segment = segment;
    this.url = url;
  }
}

interface ChansubToken {
  restricted_bitrates?: string[];
}

interface PlaybackTokenValue {
  chansub?: ChansubToken;
}

/**
 * Builds the HLS URL for a VOD and resolves its available renditions.
 *
 * Ported from Xtra's PlayerRepository.loadVideoPlaylistUrl():
 *   https://usher.ttvnw.net/vod/v2/{id}.m3u8?allow_source=true&allow_audio_only=true
 *     &include_unavailable=true&p={random}&sig={signature}&token={value}
 */
export class PlaybackRepository {
  /**
   * Rendition names Xtra's getVideoUrlsFromPreview() walks, in Xtra's final
   * display order: source first, audio_only last.
   */
  static readonly QUALITY_LIST: string[] = ['chunked', '1080p60', '1080p30', '720p60', '720p30',
    '480p30', '360p30', '160p30', '144p30', 'high', 'medium', 'low', 'mobile', 'audio_only'];

  static playerType(): string {
    return Prefs.getString(PrefKeys.PLAYER_TYPE, Const.DEFAULT_PLAYER_TYPE);
  }

  /** Persisted PlaybackAccessToken query; the fast path Xtra tries first. */
  static async accessToken(videoId: string): Promise<PlaybackToken | undefined> {
    try {
      const variables = new PlaybackTokenVars(false, '', true, videoId, 'web', PlaybackRepository.playerType());
      const text: string = await GqlClient.sendPersisted('PlaybackAccessToken',
        Const.PLAYBACK_TOKEN_HASH, variables, true);
      const token: PlaybackToken | undefined = PlaybackRepository.readToken(text);
      if (token !== undefined) {
        return token;
      }
    } catch (e) {
      // fall through to the explicit query below
    }
    return PlaybackRepository.accessTokenQuery(videoId);
  }

  /** Explicit VideoPlaybackAccessToken query; the fallback. */
  static async accessTokenQuery(videoId: string): Promise<PlaybackToken | undefined> {
    try {
      const variables = new VideoPlaybackTokenVars(videoId, 'web', PlaybackRepository.playerType());
      const text: string = await GqlClient.send('VideoPlaybackAccessToken',
        Queries.VIDEO_PLAYBACK_TOKEN, variables, true);
      return PlaybackRepository.readToken(text);
    } catch (e) {
      return undefined;
    }
  }

  private static readToken(text: string): PlaybackToken | undefined {
    const response: PlaybackAccessTokenResponse = JSON.parse(text) as PlaybackAccessTokenResponse;
    GqlClient.throwIfErrors(response.errors);
    return PlaybackRepository.toToken(response.data?.videoPlaybackAccessToken);
  }

  private static readStreamToken(text: string): PlaybackToken | undefined {
    const response: StreamPlaybackAccessTokenResponse =
      JSON.parse(text) as StreamPlaybackAccessTokenResponse;
    GqlClient.throwIfErrors(response.errors);
    return PlaybackRepository.toToken(response.data?.streamPlaybackAccessToken);
  }

  private static toToken(token: GqlPlaybackToken | undefined): PlaybackToken | undefined {
    if (token === undefined) {
      return undefined;
    }
    const signature: string | undefined = token.signature;
    const value: string | undefined = token.value;
    if (signature === undefined || value === undefined) {
      return undefined;
    }
    return new PlaybackToken(signature, value, PlaybackRepository.readRestrictedBitrates(value));
  }

  /* ------------------------------ live ------------------------------ */

  /**
   * Playback token for a live channel.
   *
   * Twitch serves live and VOD tokens from the same persisted query, keyed by
   * `isLive`/`login` instead of `isVod`/`vodID`, but returns them under a
   * different response field (streamPlaybackAccessToken).
   */
  static async liveAccessToken(login: string): Promise<PlaybackToken | undefined> {
    try {
      const variables = new PlaybackTokenVars(true, login, false, '', 'web', PlaybackRepository.playerType());
      const text: string = await GqlClient.sendPersisted('PlaybackAccessToken',
        Const.PLAYBACK_TOKEN_HASH, variables, true);
      const token: PlaybackToken | undefined = PlaybackRepository.readStreamToken(text);
      if (token !== undefined) {
        return token;
      }
    } catch (e) {
      // fall through to the explicit query below
    }
    return PlaybackRepository.liveAccessTokenQuery(login);
  }

  /** Explicit StreamPlaybackAccessToken query; the fallback. */
  static async liveAccessTokenQuery(login: string): Promise<PlaybackToken | undefined> {
    try {
      const variables = new StreamPlaybackTokenVars(login, 'web', PlaybackRepository.playerType());
      const text: string = await GqlClient.send('StreamPlaybackAccessToken',
        Queries.STREAM_PLAYBACK_TOKEN, variables, true);
      return PlaybackRepository.readStreamToken(text);
    } catch (e) {
      return undefined;
    }
  }

  /**
   * Live master playlist, ported from Xtra's loadStreamPlaylistUrl().
   *
   * `fast_bread` opts into the low-latency ladder; without a token Twitch still
   * answers, which keeps anonymous viewing of public channels working.
   *
   * `allow_source` is deliberately **not** sent. Twitch lists the broadcaster's
   * source rendition first, and when that is a resolution or codec the platform
   * cannot decode - emiru streams 1440p60, which the web player greys out for the
   * same reason - AVPlayer answers 5400106 (unsupported format) and the whole
   * channel looks broken. Leaving it out offers only the transcoded renditions,
   * so playback lands on 1080p60 instead of failing outright.
   */
  static buildLiveUrl(login: string, token: PlaybackToken | undefined): string {
    let url: string = `${Const.USHER_LIVE_URL}${login}.m3u8`
      + `?allow_audio_only=true&fast_bread=true`
      + `&supported_codecs=${encodeURIComponent(Const.SUPPORTED_CODECS)}`
      + `&p=${Math.floor(Math.random() * 9999999)}`;
    if (token !== undefined) {
      url += `&sig=${encodeURIComponent(token.signature)}&token=${encodeURIComponent(token.value)}`;
    }
    return url;
  }

  /** Reads `chansub.restricted_bitrates` out of the token payload. */
  private static readRestrictedBitrates(token: string): string[] {
    const result: string[] = [];
    try {
      const parsed: PlaybackTokenValue = JSON.parse(token) as PlaybackTokenValue;
      const chansub: ChansubToken | undefined = parsed.chansub;
      if (chansub === undefined) {
        return result;
      }
      const bitrates: string[] | undefined = chansub.restricted_bitrates;
      if (bitrates === undefined) {
        return result;
      }
      for (let i = 0; i < bitrates.length; i++) {
        if (bitrates[i] !== undefined && bitrates[i].length > 0) {
          result.push(bitrates[i]);
        }
      }
    } catch (e) {
      // Malformed payload: no restricted renditions.
    }
    return result;
  }

  /**
   * Full master-playlist URL. Without a token Twitch still serves public VODs,
   * which keeps anonymous browsing working.
   */
  static buildVodUrl(videoId: string, token: PlaybackToken | undefined): string {
    let url: string = `${Const.USHER_VOD_URL}${videoId}.m3u8`
      + `?allow_source=true&allow_audio_only=true&include_unavailable=true`
      + `&p=${Math.floor(Math.random() * 9999999)}`;
    if (token !== undefined) {
      url += `&sig=${encodeURIComponent(token.signature)}&token=${encodeURIComponent(token.value)}`;
    }
    return url;
  }

  /**
   * Renditions derived from the VOD's storyboard URL.
   *
   * Ported from Xtra's TwitchApiHelper.getVideoUrlsFromPreview(). A VOD exposes
   * its storyboard on the same CDN path as the stream itself:
   *
   *   https://<cdn>/<hash>_<channel>_<streamId>_<ts>/storyboards/<vodId>-strip-0.jpg
   *
   * Replacing the "storyboards" segment with a rendition name and the file name
   * with index-dvr.m3u8 (highlight-<id>.m3u8 for highlights) produces a playlist
   * that plays without any playback access token - which is why Xtra falls back
   * to it when the usher request is rejected.
   *
   * `restricted` is the token's restricted_bitrates list: when the token names
   * specific renditions, those are the ones that are actually served.
   */
  static directQualities(previewUrl: string, type: string, restricted: string[]): DirectQuality[] {
    const result: DirectQuality[] = [];
    if (previewUrl.length === 0 || previewUrl.indexOf('storyboards') < 0) {
      return result;
    }
    const qualities: string[] = restricted.length > 0 ? restricted : PlaybackRepository.QUALITY_LIST;
    const slash: number = previewUrl.lastIndexOf('/');
    const directory: string = previewUrl.substring(0, slash);
    const fileName: string = previewUrl.substring(slash + 1);

    let suffix: string = 'index-dvr.m3u8';
    if (type.toLowerCase() === 'highlight') {
      const dash: number = fileName.indexOf('-');
      const id: string = dash > 0 ? fileName.substring(0, dash) : fileName;
      suffix = `highlight-${id}.m3u8`;
    }

    for (let i = 0; i < qualities.length; i++) {
      const segment: string = qualities[i];
      const name: string = segment === 'chunked' ? 'source' : segment;
      const url: string = `${directory.replace('storyboards', segment)}/${suffix}`;
      result.push(new DirectQuality(name, segment, url));
    }
    return result;
  }

  /**
   * Headers for the usher playlist request.
   *
   * Usher wants the same client id the web player sends. Without it Twitch
   * answers 403, the master comes back empty, and the quality list ends up with
   * nothing but "Auto" in it - which also leaves a download with no rendition to
   * offer.
   */
  static usherHeaders(): Record<string, string> {
    const headers: Record<string, string> = {};
    headers[Const.HEADER_CLIENT_ID] = Const.GQL_WEB_CLIENT_ID;
    headers['Origin'] = 'https://www.twitch.tv';
    headers['Referer'] = 'https://www.twitch.tv/';
    return headers;
  }

  /**
   * Downloads the master playlist and lists its renditions so the quality dialog
   * can show real names ("1080p60") instead of raw bitrates. Returns an empty
   * list when the playlist cannot be read; the player then offers Auto only.
   */
  static async loadQualities(masterUrl: string): Promise<Quality[]> {
    let body: string = '';
    try {
      const result: HttpResult = await Http.get(masterUrl, PlaybackRepository.usherHeaders());
      if (!result.ok) {
        hilog.warn(DOMAIN, TAG, 'usher answered %{public}d for the master playlist', result.code);
        return [];
      }
      body = result.body;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'could not fetch the master playlist');
      return [];
    }
    if (body.length === 0 || body.indexOf('#EXTM3U') !== 0) {
      return [];
    }
    // The master's URL is the base for rendition URIs that are not absolute.
    const qualities: Quality[] = HlsParser.parseMaster(body, masterUrl);
    // What the master offered decides which rendition plays and which one is
    // stepped down from, so the ladder is logged the moment it is read.
    hilog.info(DOMAIN, TAG, 'master offers %{public}d renditions', qualities.length);
    for (let i = 0; i < qualities.length; i++) {
      const quality: Quality = qualities[i];
      hilog.info(DOMAIN, TAG, 'rendition %{public}d: %{public}s %{public}s %{public}d', i,
        quality.name, quality.resolution, quality.bandwidth);
    }
    return qualities;
  }

  // ---- resume position -------------------------------------------------

  static savePosition(videoId: string, positionMs: number, durationMs: number): void {
    if (!Prefs.getBoolean(PrefKeys.SAVE_POSITIONS, true)) {
      return;
    }
    // Ignore the first few seconds and anything essentially finished.
    if (positionMs < 5000 || (durationMs > 0 && positionMs > durationMs - 15000)) {
      Prefs.remove(PrefKeys.POSITION_PREFIX + videoId);
      return;
    }
    Prefs.setNumber(PrefKeys.POSITION_PREFIX + videoId, positionMs);
  }

  static savedPosition(videoId: string): number {
    if (!Prefs.getBoolean(PrefKeys.SAVE_POSITIONS, true)) {
      return 0;
    }
    return Prefs.getNumber(PrefKeys.POSITION_PREFIX + videoId, 0);
  }
}
