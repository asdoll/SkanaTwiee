import { Const, PrefKeys } from '../common/Const';
import { Prefs } from '../common/Prefs';
import { Http, HttpResult } from './Http';
import { GqlError } from './GqlTypes';
/* ------------------------------------------------------------------ */
/* Request bodies                                                      */
/* ------------------------------------------------------------------ */

class PersistedQueryRef {
  sha256Hash: string;
  version: number;

  constructor(hash: string) {
    this.sha256Hash = hash;
    this.version = 1;
  }
}

class GqlExtensions {
  persistedQuery: PersistedQueryRef;

  constructor(hash: string) {
    this.persistedQuery = new PersistedQueryRef(hash);
  }
}

class GqlQueryBody {
  operationName: string;
  query: string;
  variables: Object;

  constructor(operationName: string, query: string, variables: Object) {
    this.operationName = operationName;
    this.query = query;
    this.variables = variables;
  }
}

class GqlPersistedBody {
  operationName: string;
  extensions: GqlExtensions;
  variables: Object;

  constructor(operationName: string, hash: string, variables: Object) {
    this.operationName = operationName;
    this.extensions = new GqlExtensions(hash);
    this.variables = variables;
  }
}

/* ------------------------------------------------------------------ */
/* Typed variable objects. Unset optional fields are dropped by        */
/* JSON.stringify, which is how Twitch distinguishes "absent" from "". */
/* ------------------------------------------------------------------ */

export class EmptyVars {
}

export class SearchVideosVars {
  query: string;
  first?: number;
  after?: string;

  constructor(query: string, first: number, after: string) {
    this.query = query;
    if (first > 0) {
      this.first = first;
    }
    if (after.length > 0) {
      this.after = after;
    }
  }
}

export class UserVideosVars {
  login: string;
  sort?: string;
  types?: string[];
  first?: number;
  after?: string;

  constructor(login: string, sort: string, types: string[], first: number, after: string) {
    this.login = login;
    if (sort.length > 0) {
      this.sort = sort;
    }
    if (types.length > 0) {
      this.types = types;
    }
    if (first > 0) {
      this.first = first;
    }
    if (after.length > 0) {
      this.after = after;
    }
  }
}

export class FollowedVideosVars {
  sort?: string;
  type?: string[];
  first?: number;
  after?: string;

  constructor(sort: string, types: string[], first: number, after: string) {
    if (sort.length > 0) {
      this.sort = sort;
    }
    if (types.length > 0) {
      this.type = types;
    }
    if (first > 0) {
      this.first = first;
    }
    if (after.length > 0) {
      this.after = after;
    }
  }
}

export class VideoIdVars {
  id: string;

  constructor(id: string) {
    this.id = id;
  }
}

export class SearchStreamsVars {
  query: string;
  first?: number;
  after?: string;

  constructor(query: string, first: number, after: string) {
    this.query = query;
    if (first > 0) {
      this.first = first;
    }
    if (after.length > 0) {
      this.after = after;
    }
  }
}

/** searchUsers takes the same (query, first, after) triple as searchFor. */
export class SearchUsersVars {
  query: string;
  first?: number;
  after?: string;

  constructor(query: string, first: number, after: string) {
    this.query = query;
    if (first > 0) {
      this.first = first;
    }
    if (after.length > 0) {
      this.after = after;
    }
  }
}

/** The plain (first, after) pair most paged connections take. */
export class CursorPageVars {
  first?: number;
  after?: string;

  constructor(first: number, after: string) {
    if (first > 0) {
      this.first = first;
    }
    if (after.length > 0) {
      this.after = after;
    }
  }
}

export class StreamPlaybackTokenVars {
  login: string;
  platform: string;
  playerType: string;

  constructor(login: string, platform: string, playerType: string) {
    this.login = login;
    this.platform = platform;
    this.playerType = playerType;
  }
}

/** `user(id, login, lookupType)` takes either identifier. */
export class UserLookupVars {
  id?: string;
  login?: string;

  constructor(id: string, login: string) {
    if (id.length > 0) {
      this.id = id;
    }
    if (login.length > 0) {
      this.login = login;
    }
  }
}

class FollowUserInput {
  disableNotifications: boolean;
  targetID: string;

  constructor(targetID: string, disableNotifications: boolean) {
    this.targetID = targetID;
    this.disableNotifications = disableNotifications;
  }
}

class UnfollowUserInput {
  targetID: string;

  constructor(targetID: string) {
    this.targetID = targetID;
  }
}

/** FollowButton_FollowUser; `targetID` is the user id, not the login. */
export class FollowUserVars {
  input: FollowUserInput;

  constructor(targetID: string, disableNotifications: boolean) {
    this.input = new FollowUserInput(targetID, disableNotifications);
  }
}

/** FollowButton_UnfollowUser. */
export class UnfollowUserVars {
  input: UnfollowUserInput;

  constructor(targetID: string) {
    this.input = new UnfollowUserInput(targetID);
  }
}

/**
 * VideoComments.
 *
 * Twitch takes either a time offset (where to start a replay) or a cursor (where
 * to page on from), never both: leave the unused one unset so it is dropped from
 * the request body.
 */
export class VideoCommentsVars {
  id: string;
  first: number;
  after?: string;
  offset?: number;

  constructor(id: string, first: number) {
    this.id = id;
    this.first = first;
  }
}

export class VideoPlaybackTokenVars {
  id: string;
  platform: string;
  playerType: string;

  constructor(id: string, platform: string, playerType: string) {
    this.id = id;
    this.platform = platform;
    this.playerType = playerType;
  }
}

export class PlaybackTokenVars {
  isLive: boolean;
  login: string;
  isVod: boolean;
  vodID: string;
  platform: string;
  playerType: string;

  constructor(isLive: boolean, login: string, isVod: boolean, vodID: string, platform: string, playerType: string) {
    this.isLive = isLive;
    this.login = login;
    this.isVod = isVod;
    this.vodID = vodID;
    this.platform = platform;
    this.playerType = playerType;
  }
}

/* ------------------------------------------------------------------ */
/* Client                                                             */
/* ------------------------------------------------------------------ */

/**
 * Minimal Twitch GQL client.
 *
 * Xtra used Apollo plus Cronet/OkHttp/HttpEngine; on HarmonyOS there is a single
 * HTTP stack so all of that collapses into Http.
 */
export class GqlClient {
  /** Standard headers: anonymous calls simply omit Authorization. */
  static gqlHeaders(extra?: Record<string, string>): Record<string, string> {
    const headers: Record<string, string> = {};
    headers['Content-Type'] = 'application/json';
    const clientId: string = Prefs.getString(PrefKeys.GQL_CLIENT_ID, Const.GQL_WEB_CLIENT_ID);
    headers[Const.HEADER_CLIENT_ID] = clientId.length > 0 ? clientId : Const.GQL_WEB_CLIENT_ID;
    const token: string = Prefs.getString(PrefKeys.GQL_TOKEN, '');
    if (token.length > 0) {
      headers[Const.HEADER_AUTH] = `OAuth ${token}`;
    }
    if (extra !== undefined) {
      const keys: string[] = Object.keys(extra);
      for (let i = 0; i < keys.length; i++) {
        headers[keys[i]] = extra[keys[i]];
      }
    }
    return headers;
  }

  /**
   * Token request headers also carry X-Device-Id, like Xtra's getPlaybackAccessTokenHeaders().
   * The id is stable so the tokens Twitch issues stay valid for this install.
   */
  static playbackTokenHeaders(): Record<string, string> {
    const extra: Record<string, string> = {};
    extra[Const.HEADER_DEVICE_ID] = GqlClient.deviceId();
    return GqlClient.gqlHeaders(extra);
  }

  /** Headers for POST /integrity: client id plus the same device id the token is bound to. */
  static integrityHeaders(): Record<string, string> {
    const extra: Record<string, string> = {};
    extra[Const.HEADER_DEVICE_ID] = GqlClient.deviceId();
    return GqlClient.gqlHeaders(extra);
  }

  /** Persisted device id; generated once and kept across launches. */
  static deviceId(): string {
    const stored: string = Prefs.getString(PrefKeys.DEVICE_ID, '');
    if (stored.length > 0) {
      return stored;
    }
    const generated: string = GqlClient.randomDeviceId();
    Prefs.setString(PrefKeys.DEVICE_ID, generated);
    return generated;
  }

  static async send(operationName: string, query: string, variables: Object,
    withDeviceId: boolean = false): Promise<string> {
    const body: string = JSON.stringify(new GqlQueryBody(operationName, query, variables));
    return GqlClient.post(body, withDeviceId);
  }

  static async sendPersisted(operationName: string, hash: string, variables: Object,
    withDeviceId: boolean = false): Promise<string> {
    const body: string = JSON.stringify(new GqlPersistedBody(operationName, hash, variables));
    return GqlClient.post(body, withDeviceId);
  }

  /**
   * Persisted mutation carrying a Client-Integrity signature.
   *
   * Twitch refuses follow/unfollow without one and answers "failed integrity
   * check". The signature is only valid together with the device id it was
   * issued for, so a captured pair must keep both; an empty deviceId falls back
   * to this install's own id.
   */
  static async sendPersistedWithIntegrity(operationName: string, hash: string, variables: Object,
    integrityToken: string, deviceId: string): Promise<string> {
    const body: string = JSON.stringify(new GqlPersistedBody(operationName, hash, variables));
    const extra: Record<string, string> = {};
    extra[Const.HEADER_DEVICE_ID] = deviceId !== undefined && deviceId.length > 0
      ? deviceId
      : GqlClient.deviceId();
    extra[Const.HEADER_INTEGRITY] = integrityToken;
    return GqlClient.post(body, false, extra);
  }

  private static async post(body: string, withDeviceId: boolean,
    extra?: Record<string, string>): Promise<string> {
    const headers: Record<string, string> = extra !== undefined
      ? GqlClient.gqlHeaders(extra)
      : (withDeviceId ? GqlClient.playbackTokenHeaders() : GqlClient.gqlHeaders());
    const result: HttpResult = await Http.postJson(Const.GQL_URL, headers, body);
    if (!result.ok) {
      throw new Error(`GQL request failed with HTTP ${result.code}`);
    }
    return result.body;
  }

  /** Raises the first GraphQL error so the UI can show something useful. */
  static throwIfErrors(errors?: GqlError[]): void {
    if (errors !== undefined && errors.length > 0) {
      const message: string | undefined = errors[0].message;
      throw new Error(message !== undefined && message.length > 0 ? message : 'GraphQL error');
    }
  }

  /** 32 lowercase hex chars; Twitch accepts this as a device id. */
  static randomDeviceId(): string {
    let out: string = '';
    while (out.length < 32) {
      out += Math.floor(Math.random() * 0x100000000).toString(16).padStart(8, '0');
    }
    return out.substring(0, 32);
  }
}
