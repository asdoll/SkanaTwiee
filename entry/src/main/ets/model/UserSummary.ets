/**
 * A channel row for the "Users" search tab.
 *
 * Ported from Xtra's com.github.andreyasadchy.xtra.model.ui.User, which is the
 * searchUsers result: identity plus a follower count and, when the channel is
 * broadcasting, the current viewer count.
 */
export class UserSummary {
  id: string = '';
  login: string = '';
  displayName: string = '';
  profileImageURL: string = '';
  followerCount: number = 0;
  /** Non-zero while the channel is live. */
  viewersCount: number = 0;

  isLive(): boolean {
    return this.viewersCount > 0;
  }

  key(): string {
    return this.id.length > 0 ? this.id : this.login;
  }
}

/** One page of channels plus the cursor for the next one. */
export class UserSummaryPage {
  items: UserSummary[] = [];
  cursor: string = '';
  hasNextPage: boolean = false;

  constructor(items: UserSummary[], cursor: string, hasNextPage: boolean) {
    this.items = items;
    this.cursor = cursor;
    this.hasNextPage = hasNextPage;
  }

  static empty(): UserSummaryPage {
    return new UserSummaryPage([], '', false);
  }
}
