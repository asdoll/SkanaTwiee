/**
 * A channel the signed-in user follows, together with what it is doing now:
 * whether it is live, and the most recent VOD it published.
 *
 * Xtra keeps these in two separate lists (FollowedChannelsFragment and the
 * following-live tab); folding them into one row is what makes a followed
 * channel card useful at a glance.
 */
export class FollowedUser {
  id: string = '';
  login: string = '';
  displayName: string = '';
  profileImageURL: string = '';

  /* ---- live state, only meaningful while isLive ---- */
  isLive: boolean = false;
  liveTitle: string = '';
  liveViewers: number = 0;
  liveThumbnailURL: string = '';
  liveGameName: string = '';
  liveStartedAt: string = '';

  /* ---- the channel's most recent VOD, when it has one ---- */
  hasVideo: boolean = false;
  videoId: string = '';
  videoTitle: string = '';
  videoThumbnailURL: string = '';
  videoCreatedAt: string = '';
  videoDurationSeconds: number = 0;
  videoViewCount: number = 0;
  videoGameName: string = '';
  /** ARCHIVE | HIGHLIGHT | UPLOAD */
  videoType: string = '';

  /** Stable key for LazyForEach. */
  key(): string {
    return this.id.length > 0 ? this.id : this.login;
  }
}

/** One page of followed channels plus the cursor for the next one. */
export class FollowedUserPage {
  items: FollowedUser[] = [];
  cursor: string = '';
  hasNextPage: boolean = false;

  constructor(items: FollowedUser[], cursor: string, hasNextPage: boolean) {
    this.items = items;
    this.cursor = cursor;
    this.hasNextPage = hasNextPage;
  }

  static empty(): FollowedUserPage {
    return new FollowedUserPage([], '', false);
  }
}
