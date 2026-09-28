/**
 * Video model, ported from Xtra's com.github.andreyasadchy.xtra.model.ui.Video.
 */
export class Video {
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
  viewCount: number = 0;
  durationSeconds: number = 0;
  /** ARCHIVE | HIGHLIGHT | UPLOAD */
  type: string = '';
  animatedPreviewURL: string = '';
}

/** One page of videos plus the cursor needed to ask for the next one. */
export class VideoPage {
  items: Video[] = [];
  cursor: string = '';
  hasNextPage: boolean = false;

  constructor(items: Video[], cursor: string, hasNextPage: boolean) {
    this.items = items;
    this.cursor = cursor;
    this.hasNextPage = hasNextPage;
  }

  static empty(): VideoPage {
    return new VideoPage([], '', false);
  }
}
