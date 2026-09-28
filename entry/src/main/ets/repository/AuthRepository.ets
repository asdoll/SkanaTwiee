import { Const, PrefKeys } from '../common/Const';
import { Prefs } from '../common/Prefs';
import { Http, HttpResult } from '../network/Http';
import { GqlClient, EmptyVars } from '../network/GqlClient';
import { Queries } from '../network/Queries';
import { CurrentUserResponse, TokenValidationResponse } from '../network/GqlTypes';
import { TwitchUser } from '../model/TwitchUser';

/**
 * Owns the Twitch credentials captured by pages/Login.ets and handed to every
 * GraphQL call through GqlClient.
 */
export class AuthRepository {
  /** Incremented whenever the session changes so bound UI can react. */
  static readonly KEY_SESSION_VERSION: string = 'sessionVersion';

  static token(): string {
    return Prefs.getString(PrefKeys.GQL_TOKEN, '');
  }

  static clientId(): string {
    return Prefs.getString(PrefKeys.GQL_CLIENT_ID, Const.GQL_WEB_CLIENT_ID);
  }

  static isLoggedIn(): boolean {
    return AuthRepository.token().length > 0;
  }

  /** The account as last persisted; empty fields when logged out. */
  static currentUser(): TwitchUser {
    const user = new TwitchUser();
    user.id = Prefs.getString(PrefKeys.USER_ID, '');
    user.login = Prefs.getString(PrefKeys.USER_LOGIN, '');
    user.displayName = Prefs.getString(PrefKeys.USER_NAME, '');
    user.profileImageURL = Prefs.getString(PrefKeys.USER_IMAGE, '');
    return user;
  }

  /** https://id.twitch.tv/oauth2/validate */
  static async validate(token: string): Promise<TokenValidationResponse | undefined> {
    const headers: Record<string, string> = {};
    headers[Const.HEADER_AUTH] = `OAuth ${token}`;
    const result: HttpResult = await Http.get(Const.VALIDATE_URL, headers);
    if (!result.ok) {
      return undefined;
    }
    return JSON.parse(result.body) as TokenValidationResponse;
  }

  /**
   * Validates the captured token and persists it together with the identity it
   * belongs to. The validated client id is authoritative: a token is only valid
   * for the client that issued it.
   */
  static async save(token: string, fallbackClientId: string): Promise<TwitchUser | undefined> {
    const validation: TokenValidationResponse | undefined = await AuthRepository.validate(token);
    if (validation === undefined) {
      return undefined;
    }
    const validatedClientId: string | undefined = validation.client_id;
    if (validatedClientId === undefined || validatedClientId.length === 0) {
      return undefined;
    }

    const user = new TwitchUser();
    user.id = validation.user_id !== undefined ? validation.user_id : '';
    user.login = validation.login !== undefined ? validation.login : '';
    user.displayName = user.login;
    user.profileImageURL = '';

    Prefs.setString(PrefKeys.GQL_CLIENT_ID,
      validatedClientId.length > 0 ? validatedClientId : fallbackClientId);
    Prefs.setString(PrefKeys.GQL_TOKEN, token);
    Prefs.setString(PrefKeys.USER_ID, user.id);
    Prefs.setString(PrefKeys.USER_LOGIN, user.login);
    Prefs.setString(PrefKeys.USER_NAME, user.displayName);

    // Enrich with the display name / avatar; safe to fail, the login already succeeded.
    const enriched: TwitchUser | undefined = await AuthRepository.fetchCurrentUser();
    if (enriched !== undefined) {
      if (enriched.displayName.length > 0) {
        user.displayName = enriched.displayName;
      }
      user.profileImageURL = enriched.profileImageURL;
      Prefs.setString(PrefKeys.USER_NAME, user.displayName);
      Prefs.setString(PrefKeys.USER_IMAGE, user.profileImageURL);
    }
    AuthRepository.notifySessionChanged();
    return user;
  }

  /** `query CurrentUser` — requires a valid token. */
  static async fetchCurrentUser(): Promise<TwitchUser | undefined> {
    try {
      const text: string = await GqlClient.send('CurrentUser', Queries.CURRENT_USER, new EmptyVars());
      const response: CurrentUserResponse = JSON.parse(text) as CurrentUserResponse;
      GqlClient.throwIfErrors(response.errors);
      const info = response.data?.currentUser;
      if (info === undefined) {
        return undefined;
      }
      const user = new TwitchUser();
      user.id = info.id !== undefined ? info.id : '';
      user.login = info.login !== undefined ? info.login : '';
      user.displayName = info.displayName !== undefined ? info.displayName : user.login;
      user.profileImageURL = info.profileImageURL !== undefined ? info.profileImageURL : '';
      return user;
    } catch (e) {
      return undefined;
    }
  }

  static logout(): void {
    Prefs.remove(PrefKeys.GQL_TOKEN);
    Prefs.remove(PrefKeys.USER_ID);
    Prefs.remove(PrefKeys.USER_LOGIN);
    Prefs.remove(PrefKeys.USER_NAME);
    Prefs.remove(PrefKeys.USER_IMAGE);
    AuthRepository.notifySessionChanged();
  }

  private static notifySessionChanged(): void {
    const current: number = AppStorage.get<number>(AuthRepository.KEY_SESSION_VERSION) ?? 0;
    AppStorage.setOrCreate(AuthRepository.KEY_SESSION_VERSION, current + 1);
  }
}
