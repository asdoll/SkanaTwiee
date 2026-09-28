/**
 * An emote inside a message, as a character range over its text.
 *
 * Twitch reports ranges rather than tokens - both in the IRC `emotes` tag and in
 * the fragment list of a VOD comment - so a message is stored as text plus where
 * the images go.
 */
export class EmoteRange {
  id: string = '';
  /** Inclusive character offsets into `text`. */
  begin: number = 0;
  end: number = 0;

  constructor(id: string, begin: number, end: number) {
    this.id = id;
    this.begin = begin;
    this.end = end;
  }
}

/** One chat line, from IRC (live) or from a VOD's comment replay. */
export class ChatMessage {
  id: string = '';
  userLogin: string = '';
  userName: string = '';
  /** Twitch's per-user colour, '' when the user has none. */
  color: string = '';
  text: string = '';
  emotes: EmoteRange[] = [];
  /** Replay only: seconds into the video at which the message was sent. */
  offsetSeconds: number = 0;
  /** True for messages this device sent, so they can be marked as such. */
  own: boolean = false;

  /** Stable key for LazyForEach / ForEach. */
  key(): string {
    return this.id.length > 0 ? this.id : `${this.userLogin}:${this.offsetSeconds}:${this.text}`;
  }
}

/** One call's worth of VOD comments. */
export class CommentPage {
  messages: ChatMessage[] = [];
  cursor: string = '';
  hasNextPage: boolean = false;

  static empty(): CommentPage {
    return new CommentPage();
  }
}
