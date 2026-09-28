import { ChatMessage, EmoteRange } from '../model/ChatMessage';

/** A run of message text, or one emote standing in for its own name. */
export class ChatToken {
  text: string = '';
  /** Emote id, or '' for a plain text run. */
  emoteId: string = '';

  constructor(text: string, emoteId: string) {
    this.text = text;
    this.emoteId = emoteId;
  }

  isEmote(): boolean {
    return this.emoteId.length > 0;
  }
}

/**
 * Turns a message plus its emote ranges into something renderable.
 *
 * Android wraps a Spannable in one TextView; ArkUI has no text spans built from
 * data, so the message is cut into runs and laid out by the view instead.
 */
export class ChatText {
  static tokenize(message: ChatMessage): ChatToken[] {
    const tokens: ChatToken[] = [];
    const text: string = message.text;
    if (text.length === 0) {
      return tokens;
    }
    const ranges: EmoteRange[] = ChatText.sortedRanges(message.emotes, text.length);
    let index: number = 0;
    for (let i = 0; i < ranges.length; i++) {
      const range: EmoteRange = ranges[i];
      if (range.begin > index) {
        tokens.push(new ChatToken(text.substring(index, range.begin), ''));
      }
      tokens.push(new ChatToken(text.substring(range.begin, range.end + 1), range.id));
      index = range.end + 1;
    }
    if (index < text.length) {
      tokens.push(new ChatToken(text.substring(index), ''));
    }
    return tokens;
  }

  /** Drops ranges that fall outside the text and sorts them by position. */
  private static sortedRanges(ranges: EmoteRange[], length: number): EmoteRange[] {
    const kept: EmoteRange[] = [];
    for (let i = 0; i < ranges.length; i++) {
      const range: EmoteRange = ranges[i];
      if (range.id.length > 0 && range.begin >= 0 && range.end >= range.begin && range.end < length) {
        kept.push(range);
      }
    }
    kept.sort((a: EmoteRange, b: EmoteRange): number => a.begin - b.begin);
    return kept;
  }

  /**
   * Twitch's IRC `emotes` tag indexes **code points**, while string offsets are
   * UTF-16 code units, so a message containing an emoji before an emote would
   * slice in the wrong place. Convert the index before using it.
   */
  static codePointToCodeUnit(text: string, codePointIndex: number): number {
    let index: number = 0;
    let count: number = 0;
    while (index < text.length && count < codePointIndex) {
      const code: number = text.charCodeAt(index);
      // A surrogate pair is one code point but two code units.
      index += code >= 0xd800 && code <= 0xdbff ? 2 : 1;
      count++;
    }
    return index;
  }
}
