import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ChatMessage, CommentPage, EmoteRange } from '../model/ChatMessage';
import { ChatRepository } from './ChatRepository';

const DOMAIN: number = 0x0000;
const TAG: string = 'Comments';
/** Upper bound on a stored replay, so a marathon broadcast cannot fill the disk. */
const MAX_PAGES: number = 60;

/**
 * The chat replay of a VOD, stored beside the downloaded video.
 *
 * A download without its comments is half a VOD: the panel is where the broadcast
 * actually happened. The replay is one JSON file named after the video file, so
 * a download is always the pair "<id>.mp4|ts" + "<id>.comments.json" and moving
 * or deleting one means moving or deleting both.
 *
 * The whole replay is fetched in one go - Twitch pages it, and an offline file
 * cannot page.
 */
export class CommentRepository {
  /** "<video>.mp4" -> "<video>.comments.json" (any extension works). */
  static pathFor(videoPath: string): string {
    const dot: number = videoPath.lastIndexOf('.');
    const slash: number = videoPath.lastIndexOf('/');
    if (dot > slash) {
      return `${videoPath.substring(0, dot)}.comments.json`;
    }
    return `${videoPath}.comments.json`;
  }

  /** Fetches every page of the replay, reporting the page count as it goes. */
  static async fetchAll(videoId: string, onPage: (pages: number) => void): Promise<ChatMessage[]> {
    const messages: ChatMessage[] = [];
    let cursor: string = '';
    let pages: number = 0;
    while (pages < MAX_PAGES) {
      const page: CommentPage = await ChatRepository.videoComments(videoId, 0, cursor);
      pages++;
      onPage(pages);
      for (let i = 0; i < page.messages.length; i++) {
        messages.push(page.messages[i]);
      }
      if (!page.hasNextPage || page.cursor.length === 0 || page.cursor === cursor) {
        break;
      }
      cursor = page.cursor;
    }
    hilog.info(DOMAIN, TAG, 'fetched %{public}d comments in %{public}d pages', messages.length, pages);
    return messages;
  }

  /** Writes the replay next to the video file it belongs to. */
  static save(videoPath: string, messages: ChatMessage[]): string {
    const path: string = CommentRepository.pathFor(videoPath);
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, JSON.stringify(messages));
    } finally {
      fs.closeSync(file);
    }
    return path;
  }

  /** Reads the stored replay of a downloaded video; empty when there is none. */
  static load(videoPath: string): ChatMessage[] {
    if (videoPath.length === 0) {
      return [];
    }
    const path: string = CommentRepository.pathFor(videoPath);
    try {
      if (!fs.accessSync(path)) {
        return [];
      }
      const parsed: ChatMessage[] = JSON.parse(fs.readTextSync(path)) as ChatMessage[];
      const messages: ChatMessage[] = [];
      for (let i = 0; i < parsed.length; i++) {
        messages.push(CommentRepository.normalize(parsed[i]));
      }
      return messages;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'the stored replay could not be read');
      return [];
    }
  }

  /**
   * JSON.parse gives plain objects, so the emote ranges are rebuilt as instances:
   * the panel walks their fields, not their methods, but a missing `emotes` array
   * would still break it.
   */
  private static normalize(raw: ChatMessage): ChatMessage {
    const message: ChatMessage = new ChatMessage();
    message.id = raw.id !== undefined ? raw.id : '';
    message.userLogin = raw.userLogin !== undefined ? raw.userLogin : '';
    message.userName = raw.userName !== undefined ? raw.userName : '';
    message.color = raw.color !== undefined ? raw.color : '';
    message.text = raw.text !== undefined ? raw.text : '';
    message.offsetSeconds = raw.offsetSeconds !== undefined ? raw.offsetSeconds : 0;
    message.own = false;
    const ranges: EmoteRange[] = raw.emotes !== undefined ? raw.emotes : [];
    for (let i = 0; i < ranges.length; i++) {
      const range: EmoteRange = ranges[i];
      message.emotes.push(new EmoteRange(range.id, range.begin, range.end));
    }
    return message;
  }
}
