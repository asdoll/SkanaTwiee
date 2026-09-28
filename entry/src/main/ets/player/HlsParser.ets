/**
 * Parses an HLS master playlist (Twitch's usher VOD output) into a list of
 * selectable renditions.
 *
 * Example (abridged):
 *
 *   #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio_only",NAME="audio_only",URI=".../audio_only/index-dvr.m3u8"
 *   #EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=1920x1080,FRAME-RATE=60.000,VIDEO="1080p60",NAME="1080p60"
 *   https://vod-secure.twitch.tv/.../1080p60/index-dvr.m3u8
 */
import { isSourceRendition, Quality } from '../model/Quality';

export class HlsParser {
  /**
   * `baseUrl` is the master playlist's own URL; rendition URIs the master gives
   * relatively are resolved against it, because the returned `Quality.url` is
   * handed straight to the player.
   */
  static parseMaster(playlist: string, baseUrl: string = ''): Quality[] {
    const lines: string[] = playlist.split('\n');
    const qualities: Quality[] = [];
    const seen: string[] = [];

    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i].trim();

      if (line.startsWith('#EXT-X-MEDIA:')) {
        const attrs: Record<string, string> = HlsParser.parseAttributes(line.substring(13));
        const type: string = attrs['TYPE'];
        if (type === 'AUDIO') {
          const uri: string = attrs['URI'] !== undefined ? attrs['URI'] : '';
          if (uri.length > 0) {
            const name: string = attrs['NAME'] !== undefined ? attrs['NAME'] : 'audio_only';
            const bandwidth: number = HlsParser.toNumber(attrs['BANDWIDTH']);
            const quality = new Quality(name, bandwidth, '', 0, true, false,
              HlsParser.resolveUrl(uri, baseUrl));
            if (seen.indexOf(quality.name) === -1) {
              seen.push(quality.name);
              qualities.push(quality);
            }
          }
        }
        continue;
      }

      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        const attrs: Record<string, string> = HlsParser.parseAttributes(line.substring(18));
        const uri: string = HlsParser.nextNonCommentLine(lines, i + 1);
        if (uri.length === 0) {
          continue;
        }
        const bandwidth: number = HlsParser.firstNumber(attrs, 'BANDWIDTH', 'AVERAGE-BANDWIDTH');
        const resolution: string = attrs['RESOLUTION'] !== undefined ? attrs['RESOLUTION'] : '';
        const frameRate: number = HlsParser.toNumber(attrs['FRAME-RATE']);
        const rawName: string = attrs['NAME'] !== undefined ? attrs['NAME']
          : (attrs['VIDEO'] !== undefined ? attrs['VIDEO'] : '');
        const name: string = rawName.length > 0 ? rawName : HlsParser.deriveName(resolution, frameRate, bandwidth);
        const isSource: boolean = isSourceRendition(name);

        if (seen.indexOf(name) === -1) {
          seen.push(name);
          qualities.push(new Quality(name, bandwidth, resolution, frameRate, false, isSource,
            HlsParser.resolveUrl(uri, baseUrl)));
        }
      }
    }

    qualities.sort((a: Quality, b: Quality) => b.bandwidth - a.bandwidth);
    return qualities;
  }

  /** "1920x1080" + 60 -> "1080p60" */
  private static deriveName(resolution: string, frameRate: number, bandwidth: number): string {
    const xIndex: number = resolution.indexOf('x');
    if (xIndex > 0) {
      const height: string = resolution.substring(xIndex + 1);
      const fps: number = frameRate >= 59 ? 60 : 30;
      return `${height}p${fps}`;
    }
    if (bandwidth > 0) {
      return `${Math.round(bandwidth / 1000)}kbps`;
    }
    return 'unknown';
  }

  /**
   * Turns a playlist-relative URI into one the player (or a download) can open.
   *
   * Rendition URIs are usually absolute, but the segments inside a media
   * playlist are plain file names, so a relative URI has to resolve against the
   * playlist's own directory rather than the host root.
   */
  static resolveUrl(uri: string, baseUrl: string): string {
    if (uri.length === 0 || baseUrl.length === 0) {
      return uri;
    }
    if (uri.indexOf('://') > 0) {
      return uri;
    }
    const scheme: number = baseUrl.indexOf('://');
    if (scheme < 0) {
      return uri;
    }
    const origin: string = baseUrl.substring(0, scheme + 1);
    if (uri.startsWith('//')) {
      return origin + uri;
    }
    const authorityEnd: number = baseUrl.indexOf('/', scheme + 3);
    const root: string = authorityEnd > 0 ? baseUrl.substring(0, authorityEnd) : baseUrl;
    if (uri.startsWith('/')) {
      return root + uri;
    }
    const query: number = baseUrl.indexOf('?');
    const clean: string = query > 0 ? baseUrl.substring(0, query) : baseUrl;
    const slash: number = clean.lastIndexOf('/');
    const directory: string = slash > scheme + 2 ? clean.substring(0, slash + 1) : `${root}/`;
    return `${directory}${uri}`;
  }

  private static nextNonCommentLine(lines: string[], from: number): string {
    for (let i = from; i < lines.length; i++) {
      const candidate: string = lines[i].trim();
      if (candidate.length > 0 && !candidate.startsWith('#')) {
        return candidate;
      }
    }
    return '';
  }

  /** Splits `A=1,B="x,y",C=3` respecting quoted commas. */
  private static parseAttributes(input: string): Record<string, string> {
    const result: Record<string, string> = {};
    let key: string = '';
    let value: string = '';
    let inQuotes: boolean = false;
    let readingKey: boolean = true;

    for (let i = 0; i < input.length; i++) {
      const ch: string = input.charAt(i);
      if (readingKey) {
        if (ch === '=') {
          readingKey = false;
        } else {
          key += ch;
        }
        continue;
      }
      if (ch === '"') {
        inQuotes = !inQuotes;
        continue;
      }
      if (ch === ',' && !inQuotes) {
        result[key.trim()] = value;
        key = '';
        value = '';
        readingKey = true;
        continue;
      }
      value += ch;
    }
    if (key.length > 0) {
      result[key.trim()] = value;
    }
    return result;
  }

  private static firstNumber(attrs: Record<string, string>, first: string, second: string): number {
    let value: number = HlsParser.toNumber(attrs[first]);
    if (value === 0) {
      value = HlsParser.toNumber(attrs[second]);
    }
    return value;
  }

  private static toNumber(value?: string): number {
    if (value === undefined) {
      return 0;
    }
    const parsed: number = Number.parseFloat(value);
    return Number.isNaN(parsed) ? 0 : parsed;
  }
}
