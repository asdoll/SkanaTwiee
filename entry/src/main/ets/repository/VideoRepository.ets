import { Const } from '../common/Const';
import { GqlClient, FollowedVideosVars, SearchVideosVars, UserVideosVars, VideoIdVars } from '../network/GqlClient';
import { Queries } from '../network/Queries';
import {
  GqlVideoNode,
  SearchVideosResponse,
  UserFollowedVideosResponse,
  UserVideosResponse,
  VideoDetailsResponse
} from '../network/GqlTypes';
import { Video, VideoPage } from '../model/Video';

function str(value?: string | null): string {
  return value !== undefined && value !== null ? value : '';
}

function num(value?: number | null): number {
  return value !== undefined && value !== null ? value : 0;
}

/**
 * Video queries, ported from Xtra's GraphQLRepository + *VideosDataSource.
 *
 * Xtra chains GQL -> persisted GQL -> Helix; every path returns the same model,
 * so the first one that succeeds wins here.
 */
export class VideoRepository {
  static readonly SORT_TIME: string = 'TIME';
  static readonly SORT_TIME_ASC: string = 'TIME_ASC';
  static readonly SORT_VIEWS: string = 'VIEWS';

  /** What Xtra passes as `types` for channel/followed video lists. */
  static readonly DEFAULT_TYPES: string[] = ['ARCHIVE', 'HIGHLIGHT', 'UPLOAD'];

  static toVideo(node: GqlVideoNode): Video {
    const video = new Video();
    video.id = str(node.id);
    video.title = str(node.title);
    video.thumbnailURL = str(node.previewThumbnailURL);
    video.createdAt = str(node.createdAt);
    video.viewCount = num(node.viewCount);
    video.durationSeconds = num(node.lengthSeconds);
    video.type = str(node.broadcastType).toUpperCase();
    video.animatedPreviewURL = str(node.animatedPreviewURL);

    // Twitch reports absent relations as null rather than omitting them.
    video.channelId = str(node.owner?.id);
    video.channelLogin = str(node.owner?.login);
    video.channelName = str(node.owner?.displayName);
    video.channelImageURL = str(node.owner?.profileImageURL);

    video.gameId = str(node.game?.id);
    video.gameSlug = str(node.game?.slug);
    video.gameName = str(node.game?.displayName);
    return video;
  }

  /** Search VODs. Works anonymously. */
  static async searchVideos(query: string, after: string): Promise<VideoPage> {
    if (query.length === 0) {
      return VideoPage.empty();
    }
    const text: string = await GqlClient.send('SearchVideos', Queries.SEARCH_VIDEOS,
      new SearchVideosVars(query, Const.PAGE_SIZE, after));
    const response: SearchVideosResponse = JSON.parse(text) as SearchVideosResponse;
    GqlClient.throwIfErrors(response.errors);

    const connection = response.data?.searchFor?.videos;
    if (connection === undefined) {
      return VideoPage.empty();
    }
    const items: Video[] = [];
    const nodes: GqlVideoNode[] | undefined = connection.items;
    if (nodes !== undefined) {
      for (let i = 0; i < nodes.length; i++) {
        const node: GqlVideoNode | null | undefined = nodes[i];
        if (node !== undefined && node !== null) {
          items.push(VideoRepository.toVideo(node));
        }
      }
    }
    return new VideoPage(items, str(connection.cursor), connection.pageInfo?.hasNextPage === true);
  }

  /** A channel's VODs. Works anonymously. */
  static async channelVideos(login: string, after: string, sort: string,
    types: string[]): Promise<VideoPage> {
    const text: string = await GqlClient.send('UserVideos', Queries.USER_VIDEOS,
      new UserVideosVars(login, sort, types, Const.PAGE_SIZE, after));
    const response: UserVideosResponse = JSON.parse(text) as UserVideosResponse;
    GqlClient.throwIfErrors(response.errors);

    const connection = response.data?.user?.videos;
    if (connection === undefined) {
      return VideoPage.empty();
    }
    const items: Video[] = [];
    const edges = connection.edges;
    if (edges !== undefined) {
      for (let i = 0; i < edges.length; i++) {
        const node: GqlVideoNode | null | undefined = edges[i].node;
        if (node !== undefined && node !== null) {
          const video: Video = VideoRepository.toVideo(node);
          video.channelLogin = video.channelLogin.length > 0 ? video.channelLogin : login;
          items.push(video);
        }
      }
    }
    const cursor: string = edges !== undefined && edges.length > 0 ? str(edges[edges.length - 1].cursor) : '';
    return new VideoPage(items, cursor, connection.pageInfo?.hasNextPage === true);
  }

  /** VODs from followed channels; requires login. */
  static async followedVideos(after: string): Promise<VideoPage> {
    const text: string = await GqlClient.send('UserFollowedVideos', Queries.USER_FOLLOWED_VIDEOS,
      new FollowedVideosVars(VideoRepository.SORT_TIME, VideoRepository.DEFAULT_TYPES, Const.PAGE_SIZE, after));
    const response: UserFollowedVideosResponse = JSON.parse(text) as UserFollowedVideosResponse;
    GqlClient.throwIfErrors(response.errors);

    const connection = response.data?.user?.followedVideos;
    if (connection === undefined) {
      return VideoPage.empty();
    }
    const items: Video[] = [];
    const edges = connection.edges;
    if (edges !== undefined) {
      for (let i = 0; i < edges.length; i++) {
        const node: GqlVideoNode | null | undefined = edges[i].node;
        if (node !== undefined && node !== null) {
          items.push(VideoRepository.toVideo(node));
        }
      }
    }
    const cursor: string = edges !== undefined && edges.length > 0 ? str(edges[edges.length - 1].cursor) : '';
    return new VideoPage(items, cursor, connection.pageInfo?.hasNextPage === true);
  }

  /** Full metadata for a single VOD, used by the player when opened by id. */
  static async videoDetails(id: string): Promise<Video | undefined> {
    const text: string = await GqlClient.send('Video', Queries.VIDEO_DETAILS, new VideoIdVars(id));
    const response: VideoDetailsResponse = JSON.parse(text) as VideoDetailsResponse;
    GqlClient.throwIfErrors(response.errors);
    const node: GqlVideoNode | undefined = response.data?.video;
    if (node === undefined) {
      return undefined;
    }
    const video: Video = VideoRepository.toVideo(node);
    if (video.id.length === 0) {
      video.id = id;
    }
    return video;
  }
}
