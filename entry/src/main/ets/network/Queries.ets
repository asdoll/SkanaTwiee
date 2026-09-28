/**
 * GraphQL documents, copied verbatim from the .graphql files under
 * app/src/main/graphql in Xtra.
 *
 * Note: Xtra sends the generated Apollo document with the operation name
 * replaced by "null" and no operationName field. We send operationName
 * normally, which Twitch's GQL endpoint also accepts for these public queries.
 */
export class Queries {
  /**
   * VOD comments, from Xtra's VideoComments.graphql.
   *
   * `contentOffsetSeconds` is the video time a comment was sent at, which is what
   * the replay uses to release comments as playback reaches them; the same query
   * pages by `after` cursor, and Twitch expects only one of the two per call.
   */
  static readonly VIDEO_COMMENTS: string = `query VideoComments($id: ID, $first: Int, $after: Cursor, $offset: Int) {
  video(id: $id) {
    comments(first: $first, after: $after, contentOffsetSeconds: $offset) {
      edges {
        cursor
        node {
          commenter {
            displayName
            id
            login
          }
          contentOffsetSeconds
          createdAt
          id
          message {
            fragments {
              emote {
                emoteID
              }
              text
            }
            userBadges {
              setID
              version
            }
            userColor
          }
        }
      }
      pageInfo {
        hasNextPage
      }
    }
  }
}`;

  static readonly SEARCH_VIDEOS: string = `query SearchVideos($query: String!, $first: Int, $after: String) {
  searchFor(userQuery: $query, platform: "", target: {cursor: $after, index: VOD, limit: $first}) {
    videos {
      cursor
      items {
        animatedPreviewURL
        broadcastType
        createdAt
        game {
          displayName
          id
          slug
        }
        id
        lengthSeconds
        owner {
          displayName
          id
          login
          profileImageURL(width: 300)
        }
        previewThumbnailURL
        title
        viewCount
      }
      pageInfo {
        hasNextPage
      }
    }
  }
}`;

  static readonly USER_VIDEOS: string = `query UserVideos($id: ID, $login: String, $sort: VideoSort, $types: [BroadcastType!], $first: Int, $after: Cursor) {
  user(id: $id, login: $login, lookupType: ALL) {
    displayName
    login
    profileImageURL(width: 300)
    videos(first: $first, after: $after, types: $types, sort: $sort) {
      edges {
        cursor
        node {
          animatedPreviewURL
          broadcastType
          createdAt
          game {
            displayName
            id
            slug
          }
          id
          lengthSeconds
          previewThumbnailURL
          title
          viewCount
        }
      }
      pageInfo {
        hasNextPage
      }
    }
  }
}`;

  static readonly USER_FOLLOWED_VIDEOS: string = `query UserFollowedVideos($languages: [String!], $sort: VideoSort, $type: [BroadcastType!], $first: Int, $after: Cursor) {
  user {
    followedVideos(first: $first, after: $after, languages: $languages, types: $type, sort: $sort) {
      edges {
        cursor
        node {
          animatedPreviewURL
          broadcastType
          createdAt
          game {
            displayName
            id
            slug
          }
          id
          lengthSeconds
          owner {
            displayName
            id
            login
            profileImageURL(width: 300)
          }
          previewThumbnailURL
          title
          viewCount
        }
      }
      pageInfo {
        hasNextPage
      }
    }
  }
}`;

  static readonly CURRENT_USER: string = `query CurrentUser {
  currentUser {
    id
    login
    displayName
    profileImageURL(width: 300)
  }
}`;

  static readonly VIDEO_DETAILS: string = `query Video($id: ID) {  video(id: $id) {
    animatedPreviewURL
    broadcastType
    createdAt
    game {
      displayName
      id
      slug
    }
    id
    lengthSeconds
    owner {
      displayName
      id
      login
      profileImageURL(width: 300)
    }
    previewThumbnailURL
    title
    viewCount
  }
}`;

  /**
   * Everything the channel page shows: identity, follower count, and the live
   * stream when there is one (absent, not empty, while the channel is offline).
   */
  static readonly USER_CHANNEL_PAGE: string = `query UserChannelPage($id: ID, $login: String) {
  user(id: $id, login: $login, lookupType: ALL) {
    bannerImageURL
    createdAt
    displayName
    followers {
      totalCount
    }
    lastBroadcast {
      startedAt
    }
    id
    login
    profileImageURL(width: 300)
    roles {
      isAffiliate
      isPartner
      isStaff
    }
    stream {
      createdAt
      game {
        displayName
        id
        slug
      }
      id
      previewImageURL
      title
      viewersCount
    }
  }
}`;

  /**
   * Whether the signed-in viewer follows this channel.
   *
   * `self.follower` is null when not following, so `followedAt` being present is
   * the test. Requires a valid token, like the follow button it backs.
   */
  static readonly SELF_FOLLOWING_USER: string = `query SelfFollowingUser($id: ID, $login: String) {
  user(id: $id, login: $login, lookupType: ALL) {
    self {
      follower {
        followedAt
        notificationSettings {
          isEnabled
        }
      }
    }
  }
}`;

  /** Fallback used when the persisted playback-token query is rejected. */
  static readonly VIDEO_PLAYBACK_TOKEN: string =
    `query VideoPlaybackAccessToken($id: ID!, $platform: String!, $playerType: String!) {
  videoPlaybackAccessToken(id: $id, params: { platform: $platform, playerType: $playerType }) {
    signature
    value
  }
}`;

  static readonly STREAM_PLAYBACK_TOKEN: string =
    `query StreamPlaybackAccessToken($login: String!, $platform: String!, $playerType: String!) {
  streamPlaybackAccessToken(channelName: $login, params: { platform: $platform, playerType: $playerType }) {
    signature
    value
  }
}`;

  static readonly SEARCH_STREAMS: string = `query SearchStreams($query: String!, $first: Int, $after: Cursor) {
  searchStreams(userQuery: $query, first: $first, after: $after) {
    edges {
      cursor
      node {
        broadcaster {
          broadcastSettings {
            title
          }
          displayName
          id
          login
          profileImageURL(width: 300)
        }
        createdAt
        freeformTags {
          name
        }
        game {
          displayName
          id
          slug
        }
        id
        previewImageURL
        viewersCount
      }
    }
    pageInfo {
      hasNextPage
    }
  }
}`;

  static readonly USER_FOLLOWED_STREAMS: string = `query UserFollowedStreams($first: Int, $after: Cursor) {
  user {
    followedLiveUsers(first: $first, after: $after) {
      edges {
        cursor
        node {
          displayName
          id
          login
          profileImageURL(width: 300)
          stream {
            broadcaster {
              broadcastSettings {
                title
              }
            }
            createdAt
            freeformTags {
              name
            }
            game {
              displayName
              id
              slug
            }
            id
            previewImageURL
            viewersCount
          }
        }
      }
      pageInfo {
        hasNextPage
      }
    }
  }
}`;

  static readonly SEARCH_CHANNELS: string = `query SearchChannels($query: String!, $first: Int, $after: Cursor) {
  searchUsers(userQuery: $query, first: $first, after: $after) {
    edges {
      cursor
      node {
        displayName
        followers {
          totalCount
        }
        id
        login
        profileImageURL(width: 300)
        stream {
          viewersCount
        }
      }
    }
    pageInfo {
      hasNextPage
    }
  }
}`;

  /**
   * Channels the user follows, with what each one is doing right now.
   *
   * Xtra's UserFollowedUsers.graphql only selects identity + lastBroadcast and
   * fills the rest in with follow-up queries; the same fields are reachable on
   * the follow node itself, so one request answers "is this channel live, and
   * what did it last publish".
   */
  static readonly USER_FOLLOWED_USERS: string = `query UserFollowedUsers($first: Int, $after: Cursor) {
  user {
    follows(first: $first, after: $after, order: ASC) {
      edges {
        cursor
        node {
          id
          login
          displayName
          profileImageURL(width: 300)
          stream {
            id
            createdAt
            viewersCount
            previewImageURL
            game {
              displayName
              id
              slug
            }
            broadcaster {
              broadcastSettings {
                title
              }
            }
          }
          videos(first: 1, sort: TIME, types: [ARCHIVE, HIGHLIGHT, UPLOAD]) {
            edges {
              node {
                broadcastType
                createdAt
                game {
                  displayName
                  id
                  slug
                }
                id
                lengthSeconds
                previewThumbnailURL
                title
                viewCount
              }
            }
          }
        }
      }
      pageInfo {
        hasNextPage
      }
    }
  }
}`;
}
