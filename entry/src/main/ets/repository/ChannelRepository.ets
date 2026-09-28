import { Const } from '../common/Const';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  FollowUserVars,
  GqlClient,
  UnfollowUserVars,
  UserLookupVars
} from '../network/GqlClient';
import { Queries } from '../network/Queries';
import {
  GqlChannelUser,
  GqlMutationResponse,
  GqlSelfFollower,
  GqlStreamNode,
  SelfFollowingUserResponse,
  UserChannelPageResponse
} from '../network/GqlTypes';
import { ChannelInfo } from '../model/ChannelInfo';
import { Stream } from '../model/Stream';
import { IntegrityCredentials, IntegrityRepository } from './IntegrityRepository';
import { StreamRepository } from './StreamRepository';

const DOMAIN: number = 0x0000;
const TAG: string = 'ChannelRepo';

function str(value?: string | null): string {
  return value !== undefined && value !== null ? value : '';
}

function num(value?: number | null): number {
  return value !== undefined && value !== null ? value : 0;
}

/**
 * The channel (user detail) page, ported from Xtra's ChannelPagerViewModel.
 *
 * Follow and unfollow go through Twitch's own persisted mutations
 * (FollowButton_FollowUser / FollowButton_UnfollowUser); they take the numeric
 * user id, which is why the page loads UserChannelPage first.
 */
export class ChannelRepository {
  /** Bumped after a follow change so the Following lists reload. */
  static readonly KEY_FOLLOW_VERSION: string = 'followVersion';

  /** Identity, follower count and live state for one channel. */
  static async channelInfo(login: string): Promise<ChannelInfo | undefined> {
    if (login.length === 0) {
      return undefined;
    }
    const text: string = await GqlClient.send('UserChannelPage', Queries.USER_CHANNEL_PAGE,
      new UserLookupVars('', login));
    const response: UserChannelPageResponse = JSON.parse(text) as UserChannelPageResponse;
    GqlClient.throwIfErrors(response.errors);

    const user: GqlChannelUser | undefined = response.data?.user;
    if (user === undefined || user === null) {
      return undefined;
    }

    const info = new ChannelInfo();
    info.id = str(user.id);
    info.login = str(user.login).length > 0 ? str(user.login) : login;
    info.displayName = str(user.displayName);
    info.profileImageURL = str(user.profileImageURL);
    info.followerCount = num(user.followers?.totalCount);
    info.lastBroadcastAt = str(user.lastBroadcast?.startedAt);

    // `stream` is null while the channel is offline.
    const stream: GqlStreamNode | null | undefined = user.stream;
    if (stream !== undefined && stream !== null) {
      const live: Stream = StreamRepository.toStream(stream);
      if (live.channelLogin.length === 0) {
        live.channelLogin = info.login;
      }
      if (live.channelName.length === 0) {
        live.channelName = info.displayName;
      }
      if (live.channelImageURL.length === 0) {
        live.channelImageURL = info.profileImageURL;
      }
      info.live = live;
      info.isLive = true;
    }
    return info;
  }

  /**
   * Whether the signed-in viewer follows this channel.
   *
   * Anonymous callers get `false`: the query needs a viewer, and a failure here
   * must not look like "not following" in a way that lets the UI offer a follow
   * that would then fail.
   */
  static async isFollowing(login: string): Promise<boolean> {
    if (login.length === 0) {
      return false;
    }
    try {
      const text: string = await GqlClient.send('SelfFollowingUser', Queries.SELF_FOLLOWING_USER,
        new UserLookupVars('', login));
      const response: SelfFollowingUserResponse = JSON.parse(text) as SelfFollowingUserResponse;
      GqlClient.throwIfErrors(response.errors);
      const follower: GqlSelfFollower | null | undefined = response.data?.user?.self?.follower;
      if (follower === undefined || follower === null) {
        return false;
      }
      const followedAt: string | undefined = follower.followedAt;
      return followedAt !== undefined && followedAt !== null && followedAt.length > 0;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'isFollowing(%{public}s) failed: %{public}s', login,
        JSON.stringify(e));
      return false;
    }
  }

  /** Follows a channel. Throws with the server's message when rejected. */
  static async follow(userId: string, disableNotifications: boolean): Promise<void> {
    await ChannelRepository.sendFollowMutation('FollowButton_FollowUser',
      Const.FOLLOW_USER_HASH, new FollowUserVars(userId, disableNotifications));
    ChannelRepository.notifyFollowChanged();
  }

  /** Unfollows a channel. Throws with the server's message when rejected. */
  static async unfollow(userId: string): Promise<void> {
    await ChannelRepository.sendFollowMutation('FollowButton_UnfollowUser',
      Const.UNFOLLOW_USER_HASH, new UnfollowUserVars(userId));
    ChannelRepository.notifyFollowChanged();
  }

  /**
   * Runs a follow mutation with a Client-Integrity signature.
   *
   * Twitch rejects these without one ("failed integrity check"). Only a token
   * minted by Twitch's own page is accepted, so a refusal is reported to the UI,
   * which can capture one and call back.
   */
  private static async sendFollowMutation(operationName: string, hash: string,
    variables: Object): Promise<void> {
    const credentials: IntegrityCredentials = await IntegrityRepository.credentials();
    const text: string = await GqlClient.sendPersistedWithIntegrity(
      operationName, hash, variables, credentials.token, credentials.deviceId);
    ChannelRepository.throwIfMutationFailed(text);
  }

  private static throwIfMutationFailed(text: string): void {
    const response: GqlMutationResponse = JSON.parse(text) as GqlMutationResponse;
    GqlClient.throwIfErrors(response.errors);
  }

  private static notifyFollowChanged(): void {
    const current: number = AppStorage.get<number>(ChannelRepository.KEY_FOLLOW_VERSION) ?? 0;
    AppStorage.setOrCreate(ChannelRepository.KEY_FOLLOW_VERSION, current + 1);
  }
}
