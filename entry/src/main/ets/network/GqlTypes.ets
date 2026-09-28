/**
 * Strongly typed shapes for the GraphQL payloads we consume.
 * Every field is optional because a partial/failed response must not crash the UI.
 */

export interface GqlError {
  message?: string;
}

export interface GqlOwner {
  displayName?: string;
  id?: string;
  login?: string;
  profileImageURL?: string;
}

export interface GqlGame {
  displayName?: string;
  id?: string;
  slug?: string;
}

export interface GqlVideoNode {
  animatedPreviewURL?: string;
  broadcastType?: string;
  createdAt?: string;
  game?: GqlGame | null;
  id?: string;
  lengthSeconds?: number;
  owner?: GqlOwner | null;
  previewThumbnailURL?: string;
  title?: string;
  viewCount?: number;
}

export interface GqlPageInfo {
  hasNextPage?: boolean;
}

export interface GqlVideoEdge {
  cursor?: string;
  node?: GqlVideoNode;
}

export interface GqlVideosConnection {
  edges?: GqlVideoEdge[];
  pageInfo?: GqlPageInfo;
}

/* ---------- search videos: items[] + cursor on the connection ---------- */

export interface GqlSearchVideosConnection {
  cursor?: string;
  items?: GqlVideoNode[];
  pageInfo?: GqlPageInfo;
}

export interface GqlSearchFor {
  videos?: GqlSearchVideosConnection;
}

export interface SearchVideosData {
  searchFor?: GqlSearchFor;
}

export interface SearchVideosResponse {
  data?: SearchVideosData;
  errors?: GqlError[];
}

/* ---------- channel videos ---------- */

export interface GqlUserInfo {
  displayName?: string;
  login?: string;
  profileImageURL?: string;
  videos?: GqlVideosConnection;
}

export interface UserVideosData {
  user?: GqlUserInfo;
}

export interface UserVideosResponse {
  data?: UserVideosData;
  errors?: GqlError[];
}

/* ---------- followed videos ---------- */

export interface GqlFollowedVideos {
  followedVideos?: GqlVideosConnection;
}

export interface UserFollowedVideosData {
  user?: GqlFollowedVideos;
}

export interface UserFollowedVideosResponse {
  data?: UserFollowedVideosData;
  errors?: GqlError[];
}

/* ---------- current user ---------- */

export interface GqlCurrentUserInfo {
  id?: string;
  login?: string;
  displayName?: string;
  profileImageURL?: string;
}

export interface CurrentUserData {
  currentUser?: GqlCurrentUserInfo;
}

export interface CurrentUserResponse {
  data?: CurrentUserData;
  errors?: GqlError[];
}

/* ---------- video details ---------- */

export interface VideoDetailsData {
  video?: GqlVideoNode;
}

export interface VideoDetailsResponse {
  data?: VideoDetailsData;
  errors?: GqlError[];
}

/* ---------- playback access token ---------- */

export interface GqlPlaybackToken {
  signature?: string;
  value?: string;
}

export interface PlaybackAccessTokenData {
  videoPlaybackAccessToken?: GqlPlaybackToken;
}

export interface PlaybackAccessTokenResponse {
  data?: PlaybackAccessTokenData;
  errors?: GqlError[];
}

/* ---------- token validation (id.twitch.tv/oauth2/validate) ---------- */

export interface TokenValidationResponse {
  client_id?: string;
  login?: string;
  user_id?: string;
  scopes?: string[];
  expires_in?: number;
}

/* ---------- live streams ---------- */

export interface GqlBroadcastSettings {
  title?: string;
}

/** `broadcaster` on a stream node: the channel that owns the broadcast. */
export interface GqlBroadcaster {
  broadcastSettings?: GqlBroadcastSettings | null;
  displayName?: string;
  id?: string;
  login?: string;
  profileImageURL?: string;
}

export interface GqlFreeformTag {
  name?: string;
}

export interface GqlStreamNode {
  broadcaster?: GqlBroadcaster | null;
  createdAt?: string;
  freeformTags?: GqlFreeformTag[] | null;
  game?: GqlGame | null;
  id?: string;
  previewImageURL?: string;
  /** `UserChannelPage` selects the title on the stream itself. */
  title?: string;
  viewersCount?: number;
}

export interface GqlStreamEdge {
  cursor?: string;
  node?: GqlStreamNode;
}

export interface GqlStreamsConnection {
  edges?: GqlStreamEdge[];
  pageInfo?: GqlPageInfo;
}

export interface SearchStreamsData {
  searchStreams?: GqlStreamsConnection;
}

export interface SearchStreamsResponse {
  data?: SearchStreamsData;
  errors?: GqlError[];
}

/* ---------- followed live channels: a user node wrapping a stream ---------- */

export interface GqlLiveUserNode {
  displayName?: string;
  id?: string;
  login?: string;
  profileImageURL?: string;
  stream?: GqlStreamNode | null;
}

export interface GqlLiveUserEdge {
  cursor?: string;
  node?: GqlLiveUserNode;
}

export interface GqlFollowedLiveUsersConnection {
  edges?: GqlLiveUserEdge[];
  pageInfo?: GqlPageInfo;
}

export interface UserFollowedStreamsUser {
  followedLiveUsers?: GqlFollowedLiveUsersConnection;
}

export interface UserFollowedStreamsData {
  user?: UserFollowedStreamsUser;
}

export interface UserFollowedStreamsResponse {
  data?: UserFollowedStreamsData;
  errors?: GqlError[];
}

/* ---------- user (channel) search ---------- */

export interface GqlFollowerCount {
  totalCount?: number;
}

/** The `stream` sub-object on a searchUsers node; absent when offline. */
export interface GqlUserStreamInfo {
  viewersCount?: number;
}

export interface GqlSearchUserNode {
  displayName?: string;
  followers?: GqlFollowerCount | null;
  id?: string;
  login?: string;
  profileImageURL?: string;
  stream?: GqlUserStreamInfo | null;
}

export interface GqlSearchUserEdge {
  cursor?: string;
  node?: GqlSearchUserNode;
}

export interface GqlSearchUsersConnection {
  edges?: GqlSearchUserEdge[];
  pageInfo?: GqlPageInfo;
}

export interface SearchChannelsData {
  searchUsers?: GqlSearchUsersConnection;
}

export interface SearchChannelsResponse {
  data?: SearchChannelsData;
  errors?: GqlError[];
}

/* ---------- followed channels: identity + live state + latest video ---------- */

/** A `follows` edge node: a channel, its live stream (null when offline) and
 * its single most recent VOD (empty when the channel has never published). */
export interface GqlFollowedUserNode {
  displayName?: string;
  id?: string;
  login?: string;
  profileImageURL?: string;
  stream?: GqlStreamNode | null;
  videos?: GqlVideosConnection | null;
}

export interface GqlFollowedUserEdge {
  cursor?: string;
  node?: GqlFollowedUserNode;
}

export interface GqlFollowsConnection {
  edges?: GqlFollowedUserEdge[];
  pageInfo?: GqlPageInfo;
}

export interface GqlFollowsUser {
  follows?: GqlFollowsConnection;
}

export interface UserFollowedUsersData {
  user?: GqlFollowsUser;
}

export interface UserFollowedUsersResponse {
  data?: UserFollowedUsersData;
  errors?: GqlError[];
}

/* ---------- channel page ---------- */

export interface GqlRoles {
  isAffiliate?: boolean;
  isPartner?: boolean;
  isStaff?: boolean;
}

export interface GqlLastBroadcast {
  startedAt?: string;
}

export interface GqlChannelUser {
  bannerImageURL?: string;
  createdAt?: string;
  displayName?: string;
  followers?: GqlFollowerCount | null;
  lastBroadcast?: GqlLastBroadcast | null;
  id?: string;
  login?: string;
  profileImageURL?: string;
  roles?: GqlRoles | null;
  stream?: GqlStreamNode | null;
}

export interface UserChannelPageData {
  user?: GqlChannelUser;
}

export interface UserChannelPageResponse {
  data?: UserChannelPageData;
  errors?: GqlError[];
}

/* ---------- follow state ---------- */

export interface GqlNotificationSettings {
  isEnabled?: boolean;
}
export interface GqlSelfFollower {
  followedAt?: string;
  notificationSettings?: GqlNotificationSettings | null;
}

/* ---------- VOD comments (Xtra's VideoComments.graphql) ---------- */

export interface GqlCommentEmote {
  emoteID?: string | null;
}

/**
 * One piece of a comment. Twitch splits the message itself: a fragment either
 * carries plain `text`, or an `emote` alongside the text it stands for.
 */
export interface GqlCommentFragment {
  text?: string | null;
  emote?: GqlCommentEmote | null;
}

export interface GqlCommentBadge {
  setID?: string | null;
  version?: string | null;
}

export interface GqlCommentMessage {
  fragments?: (GqlCommentFragment | null)[] | null;
  userBadges?: (GqlCommentBadge | null)[] | null;
  userColor?: string | null;
}

export interface GqlCommentCommenter {
  id?: string | null;
  login?: string | null;
  displayName?: string | null;
}

export interface GqlCommentNode {
  id?: string | null;
  /** Seconds into the video at which the comment was sent. */
  contentOffsetSeconds?: number | null;
  createdAt?: string | null;
  commenter?: GqlCommentCommenter | null;
  message?: GqlCommentMessage | null;
}

export interface GqlCommentEdge {
  cursor?: string | null;
  node?: GqlCommentNode | null;
}

export interface GqlCommentsPageInfo {
  hasNextPage?: boolean | null;
}

export interface GqlCommentsConnection {
  edges?: (GqlCommentEdge | null)[] | null;
  pageInfo?: GqlCommentsPageInfo | null;
}

export interface GqlVideoCommentsNode {
  comments?: GqlCommentsConnection | null;
}

export interface VideoCommentsData {
  video?: GqlVideoCommentsNode | null;
}

export interface VideoCommentsResponse {
  data?: VideoCommentsData;
  errors?: GqlError[];
}

export interface GqlUserSelf {
  follower?: GqlSelfFollower | null;
}

export interface GqlSelfUser {
  self?: GqlUserSelf | null;
}

export interface SelfFollowingUserData {
  user?: GqlSelfUser;
}

export interface SelfFollowingUserResponse {
  data?: SelfFollowingUserData;
  errors?: GqlError[];
}

/** The follow/unfollow mutations only ever answer with errors. */
export interface GqlMutationResponse {
  errors?: GqlError[];
}

/* ---------- POST /integrity ---------- */

export interface IntegrityResponse {
  token?: string;
  /** Epoch milliseconds at which the token stops being accepted. */
  expiration?: number;
}

/* ---------- stream playback access token ---------- */
export interface StreamPlaybackAccessTokenData {
  streamPlaybackAccessToken?: GqlPlaybackToken;
}

export interface StreamPlaybackAccessTokenResponse {
  data?: StreamPlaybackAccessTokenData;
  errors?: GqlError[];
}
