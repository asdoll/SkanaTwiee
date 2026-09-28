import { Const } from '../common/Const';
import { CursorPageVars, GqlClient, SearchStreamsVars } from '../network/GqlClient';
import { Queries } from '../network/Queries';
import {
  GqlFreeformTag,
  GqlLiveUserEdge,
  GqlLiveUserNode,
  GqlStreamEdge,
  GqlStreamNode,
  SearchStreamsResponse,
  UserFollowedStreamsResponse
} from '../network/GqlTypes';
import { Stream, StreamPage } from '../model/Stream';

function str(value?: string | null): string {
  return value !== undefined && value !== null ? value : '';
}

function num(value?: number | null): number {
  return value !== undefined && value !== null ? value : 0;
}

/**
 * Live streams, ported from Xtra's GraphQLRepository + StreamsDataSource.
 *
 * The two queries return different node shapes for the same concept, so both
 * are normalised into Stream here rather than in the UI.
 *
 * Twitch answers with `null` rather than omitting a relation it has nothing to
 * say about, so every nested object is reached through optional chaining.
 */
export class StreamRepository {
  /**
   * Normalises a stream node.
   *
   * `searchStreams` carries the broadcast title on `broadcaster.broadcastSettings`
   * while `UserChannelPage` puts it straight on the stream, so both are read.
   */
  static toStream(node: GqlStreamNode): Stream {
    const stream = new Stream();
    stream.id = str(node.id);
    stream.thumbnailURL = str(node.previewImageURL);
    stream.createdAt = str(node.createdAt);
    stream.viewersCount = num(node.viewersCount);

    stream.channelId = str(node.broadcaster?.id);
    stream.channelLogin = str(node.broadcaster?.login);
    stream.channelName = str(node.broadcaster?.displayName);
    stream.channelImageURL = str(node.broadcaster?.profileImageURL);

    const ownTitle: string = str(node.title);
    stream.title = ownTitle.length > 0 ? ownTitle : str(node.broadcaster?.broadcastSettings?.title);

    stream.gameId = str(node.game?.id);
    stream.gameSlug = str(node.game?.slug);
    stream.gameName = str(node.game?.displayName);

    const tags: GqlFreeformTag[] | null | undefined = node.freeformTags;
    if (tags !== undefined && tags !== null) {
      for (let i = 0; i < tags.length; i++) {
        const tag: string = str(tags[i].name);
        if (tag.length > 0) {
          stream.tags.push(tag);
        }
      }
    }
    return stream;
  }

  /** `followedLiveUsers` node: the channel owns the stream. */
  private static fromLiveUserNode(node: GqlStreamNode, channelLogin: string, channelName: string,
    channelImageURL: string, channelId: string): Stream {
    const stream: Stream = StreamRepository.toStream(node);
    if (stream.channelLogin.length === 0) {
      stream.channelLogin = channelLogin;
    }
    if (stream.channelName.length === 0) {
      stream.channelName = channelName;
    }
    if (stream.channelImageURL.length === 0) {
      stream.channelImageURL = channelImageURL;
    }
    if (stream.channelId.length === 0) {
      stream.channelId = channelId;
    }
    // The broadcast title lives on the stream's own broadcaster, which the
    // followedLiveUsers query also selects.
    return stream;
  }

  /** Search live channels. Works anonymously. */
  static async searchStreams(query: string, after: string): Promise<StreamPage> {
    if (query.length === 0) {
      return StreamPage.empty();
    }
    const text: string = await GqlClient.send('SearchStreams', Queries.SEARCH_STREAMS,
      new SearchStreamsVars(query, Const.PAGE_SIZE, after));
    const response: SearchStreamsResponse = JSON.parse(text) as SearchStreamsResponse;
    GqlClient.throwIfErrors(response.errors);

    const connection = response.data?.searchStreams;
    if (connection === undefined) {
      return StreamPage.empty();
    }
    const items: Stream[] = [];
    const edges: GqlStreamEdge[] | undefined = connection.edges;
    if (edges !== undefined) {
      for (let i = 0; i < edges.length; i++) {
        const node: GqlStreamNode | null | undefined = edges[i].node;
        if (node !== undefined && node !== null) {
          const stream: Stream = StreamRepository.toStream(node);
          if (stream.channelLogin.length > 0) {
            items.push(stream);
          }
        }
      }
    }
    const cursor: string = edges !== undefined && edges.length > 0 ? str(edges[edges.length - 1].cursor) : '';
    return new StreamPage(items, cursor, connection.pageInfo?.hasNextPage === true);
  }

  /** Live channels the signed-in user follows. Requires login. */
  static async followedLiveStreams(after: string): Promise<StreamPage> {
    const text: string = await GqlClient.send('UserFollowedStreams', Queries.USER_FOLLOWED_STREAMS,
      new CursorPageVars(Const.PAGE_SIZE, after));
    const response: UserFollowedStreamsResponse = JSON.parse(text) as UserFollowedStreamsResponse;
    GqlClient.throwIfErrors(response.errors);

    const connection = response.data?.user?.followedLiveUsers;
    if (connection === undefined) {
      return StreamPage.empty();
    }
    const items: Stream[] = [];
    const edges: GqlLiveUserEdge[] | undefined = connection.edges;
    if (edges !== undefined) {
      for (let i = 0; i < edges.length; i++) {
        const node: GqlLiveUserNode | null | undefined = edges[i].node;
        if (node === undefined || node === null) {
          continue;
        }
        const login: string = str(node.login);
        const streamNode: GqlStreamNode | null | undefined = node.stream;
        if (streamNode === undefined || streamNode === null || login.length === 0) {
          continue;
        }
        items.push(StreamRepository.fromLiveUserNode(streamNode, login, str(node.displayName),
          str(node.profileImageURL), str(node.id)));
      }
    }
    const cursor: string = edges !== undefined && edges.length > 0 ? str(edges[edges.length - 1].cursor) : '';
    return new StreamPage(items, cursor, connection.pageInfo?.hasNextPage === true);
  }
}
