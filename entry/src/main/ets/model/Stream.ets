/**
 * A live broadcast, ported from Xtra's com.github.andreyasadchy.xtra.model.ui.Stream.
 *
 * Both sources of live rows collapse into this shape: `searchStreams` returns a
 * stream whose `broadcaster` is the channel, while `followedLiveUsers` returns a
 * channel whose `stream` is the broadcast.
 */
export class Stream {
  /** Broadcast id; empty for followed rows, which are keyed by channel. */
  id: string = '';
  channelId: string = '';
  channelLogin: string = '';
  channelName: string = '';
  channelImageURL: string = '';
  gameId: string = '';
  gameSlug: string = '';
  gameName: string = '';
  title: string = '';
  thumbnailURL: string = '';
  createdAt: string = '';
  viewersCount: number = 0;
  tags: string[] = [];

  /** Stable key for LazyForEach. */
  key(): string {
    return this.id.length > 0 ? this.id : this.channelLogin;
  }
}

/** One page of live streams plus the cursor for the next one. */
export class StreamPage {
  items: Stream[] = [];
  cursor: string = '';
  hasNextPage: boolean = false;

  constructor(items: Stream[], cursor: string, hasNextPage: boolean) {
    this.items = items;
    this.cursor = cursor;
    this.hasNextPage = hasNextPage;
  }

  static empty(): StreamPage {
    return new StreamPage([], '', false);
  }
}
