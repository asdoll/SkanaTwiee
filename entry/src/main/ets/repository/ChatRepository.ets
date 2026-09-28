import { webSocket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Const } from '../common/Const';
import { AuthRepository } from './AuthRepository';
import { GqlClient, VideoCommentsVars } from '../network/GqlClient';
import { Queries } from '../network/Queries';
import {
  GqlCommentEdge,
  GqlCommentFragment,
  GqlCommentNode,
  GqlCommentsConnection,
  VideoCommentsResponse
} from '../network/GqlTypes';
import { ChatMessage, CommentPage, EmoteRange } from '../model/ChatMessage';
import { ChatText } from '../util/ChatText';

const DOMAIN: number = 0x0000;
const TAG: string = 'Chat';
/** Anonymous viewers identify themselves as justinfan<number>. */
const ANON_NICK_MIN: number = 1000;
const ANON_NICK_MAX: number = 99999;
/** Comments pulled per replay request, as Xtra does. */
const REPLAY_PAGE_SIZE: number = 100;

/** Live chat state, so the UI can show what is going on. */
export class ChatStatus {
  static readonly IDLE: string = 'idle';
  static readonly CONNECTING: string = 'connecting';
  static readonly CONNECTED: string = 'connected';
  static readonly FAILED: string = 'failed';
}

/**
 * Chat, both kinds.
 *
 * Live chat is Twitch's IRC gateway; Xtra talks to it over a raw socket or a
 * WebSocket and so does this, using ArkTS's WebSocket. A VOD has no gateway to
 * join - its comments already exist - so they are paged out of GQL and released
 * by playback position instead.
 */
export class ChatRepository {
  private static socket: webSocket.WebSocket | undefined = undefined;
  private static channel: string = '';
  private static listener: ((message: ChatMessage) => void) | undefined = undefined;
  private static stateListener: ((status: string) => void) | undefined = undefined;
  /** Emotes seen in chat, which is what the picker falls back to offline. */
  private static observedEmotes: Map<string, string> = new Map();

  static status: string = ChatStatus.IDLE;

  /* ------------------------------ live ------------------------------ */

  static connect(channelLogin: string, onMessage: (message: ChatMessage) => void,
    onStatus: (status: string) => void): void {
    ChatRepository.disconnect();
    ChatRepository.channel = channelLogin;
    ChatRepository.listener = onMessage;
    ChatRepository.stateListener = onStatus;
    if (channelLogin.length === 0) {
      return;
    }
    ChatRepository.setStatus(ChatStatus.CONNECTING);
    const socket: webSocket.WebSocket = webSocket.createWebSocket();
    ChatRepository.socket = socket;
    socket.on('open', () => {
      ChatRepository.send(`CAP REQ :twitch.tv/tags twitch.tv/commands`);
      const token: string = AuthRepository.token();
      const login: string = AuthRepository.currentUser().login;
      if (token.length > 0 && login.length > 0) {
        // Signing in is what makes PRIVMSG allowed; reads work anonymously.
        ChatRepository.send(`PASS oauth:${token}`);
        ChatRepository.send(`NICK ${login}`);
      } else {
        ChatRepository.send(`NICK justinfan${ChatRepository.randomNick()}`);
      }
      ChatRepository.send(`JOIN #${channelLogin}`);
      ChatRepository.setStatus(ChatStatus.CONNECTED);
    });
    socket.on('message', (err: BusinessError, value: string | ArrayBuffer) => {
      if (typeof value !== 'string') {
        return;
      }
      ChatRepository.handlePayload(value);
    });
    socket.on('close', () => {
      ChatRepository.setStatus(ChatStatus.IDLE);
    });
    socket.on('error', (err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'chat socket error %{public}s', JSON.stringify(err));
      ChatRepository.setStatus(ChatStatus.FAILED);
    });
    socket.connect(Const.CHAT_SOCKET_URL, (err: BusinessError) => {
      if (err !== undefined && err !== null) {
        hilog.warn(DOMAIN, TAG, 'chat connect failed %{public}s', JSON.stringify(err));
        ChatRepository.setStatus(ChatStatus.FAILED);
      }
    });
  }

  static disconnect(): void {
    const socket: webSocket.WebSocket | undefined = ChatRepository.socket;
    ChatRepository.socket = undefined;
    ChatRepository.listener = undefined;
    ChatRepository.stateListener = undefined;
    ChatRepository.channel = '';
    ChatRepository.status = ChatStatus.IDLE;
    if (socket !== undefined) {
      socket.close((err: BusinessError) => {
      });
    }
  }

  /** Sends a line to the channel's chat. Requires a signed-in session. */
  static sendMessage(text: string): boolean {
    if (ChatRepository.socket === undefined || ChatRepository.channel.length === 0) {
      return false;
    }
    if (AuthRepository.token().length === 0) {
      return false;
    }
    const clean: string = text.replace('\r', ' ').replace('\n', ' ');
    if (clean.trim().length === 0) {
      return false;
    }
    ChatRepository.send(`PRIVMSG #${ChatRepository.channel} :${clean}`);
    return true;
  }

  private static send(line: string): void {
    const socket: webSocket.WebSocket | undefined = ChatRepository.socket;
    if (socket === undefined) {
      return;
    }
    socket.send(line, (err: BusinessError) => {
      if (err !== undefined && err !== null) {
        hilog.debug(DOMAIN, TAG, 'chat send failed');
      }
    });
  }

  private static setStatus(status: string): void {
    ChatRepository.status = status;
    const listener: ((status: string) => void) | undefined = ChatRepository.stateListener;
    if (listener !== undefined) {
      listener(status);
    }
  }

  /**
   * One WebSocket frame can hold several IRC lines, and Twitch sends PING as a
   * keepalive that must be answered or the connection is dropped.
   */
  private static handlePayload(payload: string): void {
    const lines: string[] = payload.split('\r\n');
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i];
      if (line.length === 0) {
        continue;
      }
      if (line.startsWith('PING')) {
        ChatRepository.send('PONG :tmi.twitch.tv');
        continue;
      }
      const parsed: IrcLine | undefined = IrcLine.parse(line);
      if (parsed === undefined) {
        continue;
      }
      if (parsed.command === 'PRIVMSG' || parsed.command === 'USERNOTICE') {
        const message: ChatMessage | undefined = parsed.toChatMessage();
        if (message !== undefined) {
          const listener: ((message: ChatMessage) => void) | undefined = ChatRepository.listener;
          if (listener !== undefined) {
            listener(message);
          }
        }
      } else if (parsed.command === 'RECONNECT') {
        ChatRepository.disconnect();
      }
    }
  }

  private static randomNick(): number {    return Math.floor(Math.random() * (ANON_NICK_MAX - ANON_NICK_MIN)) + ANON_NICK_MIN;
  }

  /* ------------------------------ replay ------------------------------ */

  /**
   * A page of a VOD's comments.
   *
   * `offsetSeconds` starts the replay at a playback position; `cursor` continues
   * from the previous page. Xtra does the same in ChatReplayManager.
   */
  static async videoComments(videoId: string, offsetSeconds: number,
    cursor: string): Promise<CommentPage> {
    const page: CommentPage = CommentPage.empty();
    if (videoId.length === 0) {
      return page;
    }
    const vars: VideoCommentsVars = new VideoCommentsVars(videoId, REPLAY_PAGE_SIZE);
    if (cursor.length > 0) {
      vars.after = cursor;
    } else {
      vars.offset = offsetSeconds;
    }
    const text: string = await GqlClient.send('VideoComments', Queries.VIDEO_COMMENTS, vars);
    const response: VideoCommentsResponse = JSON.parse(text) as VideoCommentsResponse;
    GqlClient.throwIfErrors(response.errors);
    const connection: GqlCommentsConnection | null | undefined = response.data?.video?.comments;
    const edges: (GqlCommentEdge | null)[] | null | undefined = connection?.edges;
    if (edges !== null && edges !== undefined) {
      for (let i = 0; i < edges.length; i++) {
        const edge: GqlCommentEdge | null | undefined = edges[i];
        const node: GqlCommentNode | null | undefined = edge?.node;
        if (node === null || node === undefined) {
          continue;
        }
        const message: ChatMessage | undefined = ChatRepository.toMessage(node, videoId);
        if (message !== undefined) {
          page.messages.push(message);
        }
        const edgeCursor: string | null | undefined = edge?.cursor;
        if (edgeCursor !== null && edgeCursor !== undefined && edgeCursor.length > 0) {
          page.cursor = edgeCursor;
        }
      }
    }
    page.hasNextPage = connection?.pageInfo?.hasNextPage === true && page.cursor.length > 0;
    return page;
  }

  /** Turns a comment node into a message, rebuilding the text from its fragments. */
  private static toMessage(node: GqlCommentNode, videoId: string): ChatMessage | undefined {
    const id: string | null | undefined = node.id;
    if (id === null || id === undefined || id.length === 0) {
      return undefined;
    }
    const message: ChatMessage = new ChatMessage();
    message.id = id;
    message.userName = ChatRepository.str(node.commenter?.displayName);
    message.userLogin = ChatRepository.str(node.commenter?.login);
    message.color = ChatRepository.str(node.message?.userColor);
    const offset: number | null | undefined = node.contentOffsetSeconds;
    message.offsetSeconds = offset !== null && offset !== undefined ? offset : 0;

    const fragments: (GqlCommentFragment | null)[] | null | undefined = node.message?.fragments;
    if (fragments !== null && fragments !== undefined) {
      let built: string = '';
      for (let i = 0; i < fragments.length; i++) {
        const fragment: GqlCommentFragment | null | undefined = fragments[i];
        const text: string | null | undefined = fragment?.text;
        if (text === null || text === undefined || text.length === 0) {
          continue;
        }
        const emoteId: string | null | undefined = fragment?.emote?.emoteID;
        if (emoteId !== null && emoteId !== undefined && emoteId.length > 0) {
          message.emotes.push(new EmoteRange(emoteId, built.length, built.length + text.length - 1));
          // Also feeds the emote picker, which otherwise has nothing to show in
          // a VOD when the API turns the request down.
          ChatRepository.rememberEmote(emoteId, text);
        }
        built += text;
      }
      message.text = built;
    }
    return message;
  }

  private static str(value?: string | null): string {
    return value !== undefined && value !== null ? value : '';
  }

  /* ------------------------------ emotes ------------------------------ */

  /** Emotes seen in live chat, as id -> name, for the picker's fallback. */
  static observed(): Map<string, string> {
    return ChatRepository.observedEmotes;
  }

  static rememberEmote(id: string, name: string): void {
    if (id.length > 0 && name.length > 0) {
      ChatRepository.observedEmotes.set(id, name);
    }
  }
}

/**
 * One parsed IRC line: `@tags :prefix COMMAND params`.
 *
 * Port of Xtra's ChatUtils.parseIRCMessage, including the tag escapes.
 */
class IrcLine {
  tags: Map<string, string> = new Map();
  command: string = '';
  params: string[] = [];

  static parse(line: string): IrcLine | undefined {
    const message: IrcLine = new IrcLine();
    let index: number = 0;
    if (line.startsWith('@')) {
      index = 1;
      const next: number = line.indexOf(' ', index);
      if (next === -1) {
        return undefined;
      }
      const tagBlock: string = line.substring(index, next);
      const pairs: string[] = tagBlock.split(';');
      for (let i = 0; i < pairs.length; i++) {
        const pair: string = pairs[i];
        const split: number = pair.indexOf('=');
        if (split <= 0) {
          continue;
        }
        const key: string = pair.substring(0, split);
        // IRC escapes: \\s is a space and \\: a semicolon.
        const value: string = pair.substring(split + 1).replace('\\s', ' ').replace('\\:', ';');
        message.tags.set(key, value);
      }
      index = next;
    }
    while (index < line.length && line.charAt(index) === ' ') {
      index++;
    }
    if (index < line.length && line.charAt(index) === ':') {
      index++;
      const next: number = line.indexOf(' ', index);
      if (next === -1) {
        return undefined;
      }
      index = next;
    }
    while (index < line.length && line.charAt(index) === ' ') {
      index++;
    }
    const next: number = line.indexOf(' ', index);
    if (next === -1) {
      message.command = line.substring(index);
      return message;
    }
    message.command = line.substring(index, next);
    index = next;
    while (index < line.length) {
      while (index < line.length && line.charAt(index) === ' ') {
        index++;
      }
      if (index >= line.length) {
        break;
      }
      if (line.charAt(index) === ':') {
        message.params.push(line.substring(index + 1));
        break;
      }
      const end: number = line.indexOf(' ', index);
      if (end === -1) {
        message.params.push(line.substring(index));
        break;
      }
      message.params.push(line.substring(index, end));
      index = end;
    }
    return message;
  }

  /** Builds a message from a PRIVMSG/USERNOTICE line, or undefined when unusable. */
  toChatMessage(): ChatMessage | undefined {
    if (this.params.length === 0) {
      return undefined;
    }
    const text: string = this.params.length > 1 ? this.params[1] : '';
    const message: ChatMessage = new ChatMessage();
    const id: string = this.tag('id');
    const offset: number = Number.parseFloat(this.tag('tmi-sent-ts'));
    message.id = id.length > 0 ? id : `${this.tag('tmi-sent-ts')}-${text}`;
    message.userName = this.tag('display-name');
    message.userLogin = this.login();
    message.color = this.tag('color');
    message.text = text;
    message.emotes = this.parseEmotes(text);
    if (!Number.isNaN(offset)) {
      message.offsetSeconds = Math.floor(offset / 1000);
    }
    return message;
  }

  private login(): string {
    const prefix: string = this.tag('login');
    if (prefix.length > 0) {
      return prefix;
    }
    return '';
  }

  private tag(name: string): string {
    const value: string | undefined = this.tags.get(name);
    return value !== undefined ? value : '';
  }

  /**
   * The `emotes` tag looks like `25:0-4/1902:6-10`, with indices in code points.
   */
  private parseEmotes(text: string): EmoteRange[] {
    const ranges: EmoteRange[] = [];
    const raw: string = this.tag('emotes');
    if (raw.length === 0) {
      return ranges;
    }
    const groups: string[] = raw.split('/');
    for (let i = 0; i < groups.length; i++) {
      const group: string = groups[i];
      const colon: number = group.indexOf(':');
      if (colon <= 0) {
        continue;
      }
      const id: string = group.substring(0, colon);
      const spans: string[] = group.substring(colon + 1).split(',');
      for (let j = 0; j < spans.length; j++) {
        const dash: number = spans[j].indexOf('-');
        if (dash <= 0) {
          continue;
        }
        const from: number = Number.parseInt(spans[j].substring(0, dash), 10);
        const to: number = Number.parseInt(spans[j].substring(dash + 1), 10);
        if (Number.isNaN(from) || Number.isNaN(to)) {
          continue;
        }
        const begin: number = ChatText.codePointToCodeUnit(text, from);
        const end: number = ChatText.codePointToCodeUnit(text, to + 1) - 1;
        ranges.push(new EmoteRange(id, begin, end));
        ChatRepository.rememberEmote(id, text.substring(begin, end + 1));
      }
    }
    return ranges;
  }
}
