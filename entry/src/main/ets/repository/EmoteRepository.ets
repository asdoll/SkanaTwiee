import { hilog } from '@kit.PerformanceAnalysisKit';
import { Const } from '../common/Const';
import { AuthRepository } from './AuthRepository';
import { ChatRepository } from './ChatRepository';
import { Http, HttpResult } from '../network/Http';

const DOMAIN: number = 0x0000;
const TAG: string = 'Emote';

/** One pickable emote. */
export class Emote {
  id: string = '';
  name: string = '';

  constructor(id: string, name: string) {
    this.id = id;
    this.name = name;
  }
}

interface HelixEmote {
  id?: string | null;
  name?: string | null;
}

interface HelixEmoteResponse {
  data?: (HelixEmote | null)[] | null;
}

/**
 * Emotes for the picker.
 *
 * Xtra merges Twitch's own sets with BTTV/FFZ/7TV; only the Twitch sets are
 * fetched here, from the same Helix endpoints Xtra uses, plus anything already
 * seen in the channel's chat - which keeps the picker useful even when Helix
 * turns the request down.
 */
export class EmoteRepository {
  /** The emote CDN, spelled exactly as Xtra's TwitchEmote builds it. */
  static imageUrl(id: string): string {
    return `https://static-cdn.jtvnw.net/emoticons/v2/${id}/default/dark/2.0`;
  }

  static async load(channelId: string): Promise<Emote[]> {
    const emotes: Emote[] = [];
    const seen: Map<string, boolean> = new Map();
    await EmoteRepository.appendHelix(emotes, seen, Const.HELIX_GLOBAL_EMOTES);
    if (channelId.length > 0) {
      await EmoteRepository.appendHelix(emotes, seen, `${Const.HELIX_CHANNEL_EMOTES}${channelId}`);
    }
    // Emotes that came past in chat but are missing from the API response.
    const observed: Map<string, string> = ChatRepository.observed();
    observed.forEach((name: string, id: string) => {
      if (!seen.has(id)) {
        seen.set(id, true);
        emotes.push(new Emote(id, name));
      }
    });
    return emotes;
  }

  private static async appendHelix(emotes: Emote[], seen: Map<string, boolean>,
    url: string): Promise<void> {
    const token: string = AuthRepository.token();
    if (token.length === 0) {
      return;
    }
    const headers: Record<string, string> = {};
    headers[Const.HEADER_CLIENT_ID] = AuthRepository.clientId();
    headers[Const.HEADER_AUTH] = `Bearer ${token}`;
    try {
      const result: HttpResult = await Http.get(url, headers);
      if (!result.ok) {
        hilog.debug(DOMAIN, TAG, 'emote request failed with HTTP %{public}d for %{public}s',
          result.code, url);
        return;
      }
      const response: HelixEmoteResponse = JSON.parse(result.body) as HelixEmoteResponse;
      const data: (HelixEmote | null)[] | null | undefined = response.data;
      if (data === null || data === undefined) {
        return;
      }
      for (let i = 0; i < data.length; i++) {
        const item: HelixEmote | null | undefined = data[i];
        const id: string | null | undefined = item?.id;
        const name: string | null | undefined = item?.name;
        if (id === null || id === undefined || id.length === 0) {
          continue;
        }
        if (name === null || name === undefined || name.length === 0) {
          continue;
        }
        if (seen.has(id)) {
          continue;
        }
        seen.set(id, true);
        emotes.push(new Emote(id, name));
      }
    } catch (e) {
      hilog.debug(DOMAIN, TAG, 'emote request failed');
    }
  }
}
