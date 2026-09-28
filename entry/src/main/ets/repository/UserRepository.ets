import { Const } from '../common/Const';
import { CursorPageVars, GqlClient, SearchUsersVars } from '../network/GqlClient';
import { Queries } from '../network/Queries';
import {
  GqlFollowedUserEdge,
  GqlFollowedUserNode,
  GqlSearchUserEdge,
  GqlSearchUserNode,
  GqlStreamNode,
  GqlVideoEdge,
  GqlVideoNode,
  SearchChannelsResponse,
  UserFollowedUsersResponse
} from '../network/GqlTypes';
import { FollowedUser, FollowedUserPage } from '../model/FollowedUser';
import { UserSummary, UserSummaryPage } from '../model/UserSummary';

function str(value?: string | null): string {
  return value !== undefined && value !== null ? value : '';
}

function num(value?: number | null): number {
  return value !== undefined && value !== null ? value : 0;
}

/**
 * Channel search, ported from Xtra's SearchUsersViewModel (SearchChannels.graphql).
 *
 * Only what the "Users" tab shows is mapped: identity, followers, and whether
 * the channel is currently live.
 */
export class UserRepository {
  static toUserSummary(node: GqlSearchUserNode): UserSummary {
    const user = new UserSummary();
    user.id = str(node.id);
    user.login = str(node.login);
    user.displayName = str(node.displayName);
    user.profileImageURL = str(node.profileImageURL);
    user.followerCount = num(node.followers?.totalCount);
    // `stream` is null in the response when the channel is offline.
    user.viewersCount = num(node.stream?.viewersCount);
    return user;
  }

  /** Search channels by login or display name. Works anonymously. */
  static async searchUsers(query: string, after: string): Promise<UserSummaryPage> {
    if (query.length === 0) {
      return UserSummaryPage.empty();
    }
    const text: string = await GqlClient.send('SearchChannels', Queries.SEARCH_CHANNELS,
      new SearchUsersVars(query, Const.PAGE_SIZE, after));
    const response: SearchChannelsResponse = JSON.parse(text) as SearchChannelsResponse;
    GqlClient.throwIfErrors(response.errors);

    const connection = response.data?.searchUsers;
    if (connection === undefined) {
      return UserSummaryPage.empty();
    }
    const items: UserSummary[] = [];
    const edges: GqlSearchUserEdge[] | undefined = connection.edges;
    if (edges !== undefined) {
      for (let i = 0; i < edges.length; i++) {
        const node: GqlSearchUserNode | null | undefined = edges[i].node;
        if (node !== undefined && node !== null) {
          const user: UserSummary = UserRepository.toUserSummary(node);
          if (user.login.length > 0) {
            items.push(user);
          }
        }
      }
    }
    const cursor: string = edges !== undefined && edges.length > 0 ? str(edges[edges.length - 1].cursor) : '';
    return new UserSummaryPage(items, cursor, connection.pageInfo?.hasNextPage === true);
  }

  /* ------------------------------------------------------------------ */
  /* Followed channels                                                    */
  /* ------------------------------------------------------------------ */

  /**
   * One followed channel: identity, live state and latest VOD in a single row.
   *
   * `stream` is null while the channel is offline and `videos` is empty when it
   * has never published, so both are treated as "nothing to show" rather than
   * as errors.
   */
  static toFollowedUser(node: GqlFollowedUserNode): FollowedUser {
    const user = new FollowedUser();
    user.id = str(node.id);
    user.login = str(node.login);
    user.displayName = str(node.displayName);
    user.profileImageURL = str(node.profileImageURL);

    const stream: GqlStreamNode | null | undefined = node.stream;
    if (stream !== undefined && stream !== null) {
      user.isLive = true;
      user.liveViewers = num(stream.viewersCount);
      user.liveThumbnailURL = str(stream.previewImageURL);
      user.liveStartedAt = str(stream.createdAt);
      user.liveGameName = str(stream.game?.displayName);
      user.liveTitle = str(stream.broadcaster?.broadcastSettings?.title);
    }

    const videoEdges: GqlVideoEdge[] | null | undefined = node.videos?.edges;
    if (videoEdges !== undefined && videoEdges !== null && videoEdges.length > 0) {
      const videoNode: GqlVideoNode | null | undefined = videoEdges[0].node;
      if (videoNode !== undefined && videoNode !== null) {
        user.hasVideo = true;
        user.videoId = str(videoNode.id);
        user.videoTitle = str(videoNode.title);
        user.videoThumbnailURL = str(videoNode.previewThumbnailURL);
        user.videoCreatedAt = str(videoNode.createdAt);
        user.videoDurationSeconds = num(videoNode.lengthSeconds);
        user.videoViewCount = num(videoNode.viewCount);
        user.videoGameName = str(videoNode.game?.displayName);
        user.videoType = str(videoNode.broadcastType).toUpperCase();
      }
    }
    return user;
  }

  /** Channels the signed-in user follows. Requires login. */
  static async followedUsers(after: string): Promise<FollowedUserPage> {
    const text: string = await GqlClient.send('UserFollowedUsers', Queries.USER_FOLLOWED_USERS,
      new CursorPageVars(Const.FOLLOWED_USERS_PAGE_SIZE, after));
    const response: UserFollowedUsersResponse = JSON.parse(text) as UserFollowedUsersResponse;
    GqlClient.throwIfErrors(response.errors);

    const connection = response.data?.user?.follows;
    if (connection === undefined) {
      return FollowedUserPage.empty();
    }
    const items: FollowedUser[] = [];
    const edges: GqlFollowedUserEdge[] | undefined = connection.edges;
    if (edges !== undefined) {
      for (let i = 0; i < edges.length; i++) {
        const node: GqlFollowedUserNode | null | undefined = edges[i].node;
        if (node === undefined || node === null) {
          continue;
        }
        const user: FollowedUser = UserRepository.toFollowedUser(node);
        if (user.login.length > 0) {
          items.push(user);
        }
      }
    }
    const cursor: string = edges !== undefined && edges.length > 0 ? str(edges[edges.length - 1].cursor) : '';
    return new FollowedUserPage(items, cursor, connection.pageInfo?.hasNextPage === true);
  }
}
