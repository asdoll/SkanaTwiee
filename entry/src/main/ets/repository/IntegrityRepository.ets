import { Const, PrefKeys } from '../common/Const';
import { Prefs } from '../common/Prefs';
import { GqlClient } from '../network/GqlClient';
import { Http, HttpResult } from '../network/Http';
import { IntegrityResponse } from '../network/GqlTypes';

/** What a mutation needs to pass Twitch's integrity check. */
export class IntegrityCredentials {
  token: string = '';
  /** The device id the token was issued for; '' means "use the app's own". */
  deviceId: string = '';
  /** True when Twitch's own page minted it — the only kind mutations accept. */
  captured: boolean = false;

  constructor(token: string, deviceId: string, captured: boolean) {
    this.token = token;
    this.deviceId = deviceId;
    this.captured = captured;
  }
}

/**
 * Client-Integrity tokens.
 *
 * Twitch requires a `Client-Integrity` header on some mutations, follow and
 * unfollow among them, and answers `failed integrity check` without one.
 *
 * POST https://gql.twitch.tv/integrity does hand out a token with no browser
 * involved, but a mutation sent with one is still refused: Twitch honours only a
 * signature produced by its own page, for the signed-in session. Xtra therefore
 * loads twitch.tv in a WebView and keeps the headers that page sends
 * (IntegrityDialog.kt); pages/Login.ets does the same here and hands the pair
 * over through saveCaptured().
 *
 * The endpoint token remains as a fallback: harmless, and enough for anything
 * Twitch does not gate.
 */
export class IntegrityRepository {
  /** Bumped when a capture lands, so a pending action can retry itself. */
  static readonly KEY_INTEGRITY_VERSION: string = 'integrityVersion';

  /** True when a page-minted token is available and still fresh. */
  static hasCaptured(): boolean {
    const expiration: number = Prefs.getNumber(PrefKeys.INTEGRITY_EXPIRATION, 0);
    if (expiration > 0 && new Date().getTime() >= expiration) {
      return false;
    }
    return Prefs.getString(PrefKeys.INTEGRITY_TOKEN, '').length > 0;
  }

  /** Records the header pair Twitch's own page sent, and wakes pending callers. */
  static saveCaptured(token: string, deviceId: string): void {
    Prefs.setString(PrefKeys.INTEGRITY_TOKEN, token);
    Prefs.setString(PrefKeys.INTEGRITY_DEVICE_ID, deviceId);
    Prefs.setNumber(PrefKeys.INTEGRITY_EXPIRATION, new Date().getTime() + Const.INTEGRITY_TTL_MS);
    IntegrityRepository.bumpVersion();
  }

  /** Drops a token Twitch refused; the retry waits for the next capture instead. */
  static clearCaptured(): void {
    Prefs.setString(PrefKeys.INTEGRITY_TOKEN, '');
    Prefs.setString(PrefKeys.INTEGRITY_DEVICE_ID, '');
    Prefs.setNumber(PrefKeys.INTEGRITY_EXPIRATION, 0);
  }

  /** True when the message is Twitch's integrity refusal. */
  static isIntegrityError(message: string): boolean {
    return message !== undefined && message.toLowerCase().indexOf('integrity') >= 0;
  }

  /** Credentials for a mutation: the captured pair when there is one. */
  static async credentials(): Promise<IntegrityCredentials> {
    if (IntegrityRepository.hasCaptured()) {
      return new IntegrityCredentials(Prefs.getString(PrefKeys.INTEGRITY_TOKEN, ''),
        Prefs.getString(PrefKeys.INTEGRITY_DEVICE_ID, ''), true);
    }
    return new IntegrityCredentials(await IntegrityRepository.requestToken(), '', false);
  }

  /** A token from the device-id endpoint; not accepted on authenticated mutations. */
  private static async requestToken(): Promise<string> {
    const result: HttpResult = await Http.postJson(Const.INTEGRITY_URL,
      GqlClient.integrityHeaders());
    if (!result.ok) {
      throw new Error(`Integrity request failed with HTTP ${result.code}`);
    }
    const response: IntegrityResponse = JSON.parse(result.body) as IntegrityResponse;
    const token: string | undefined = response.token;
    if (token === undefined || token === null || token.length === 0) {
      throw new Error('Twitch returned no integrity token');
    }
    return token;
  }

  private static bumpVersion(): void {
    const version: number | undefined = AppStorage.get<number>(IntegrityRepository.KEY_INTEGRITY_VERSION);
    AppStorage.setOrCreate(IntegrityRepository.KEY_INTEGRITY_VERSION,
      version !== undefined ? version + 1 : 1);
  }
}
