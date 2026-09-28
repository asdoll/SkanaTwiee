/**
 * Formatting helpers, ported from Xtra's util/TwitchApiHelper.
 *
 * Xtra leans on android.text.format.DateUtils and ICU CompactDecimalFormat;
 * here everything is plain arithmetic so it also works on a bare ArkTS runtime.
 */
export class TwitchHelper {
  private static readonly IMAGE_SIZE_PATTERN: RegExp = new RegExp('-[0-9]+x[0-9]+\\.');
  private static readonly NOT_FOUND_VIDEO: string = 'https://vod-secure.twitch.tv/_404/404_processing_320x180.png';
  private static readonly MONTHS: string[] = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /** 1280x720 maxresdefault-equivalent VOD thumbnail. */
  static videoThumbnail(url: string): string {
    if (url.length === 0 || url.startsWith('https://vod-secure.twitch.tv/_404/404_processing')) {
      return TwitchHelper.NOT_FOUND_VIDEO;
    }
    if (url.indexOf('{width}x{height}') >= 0) {
      return url.replace('{width}', '1280').replace('{height}', '720');
    }
    if (url.indexOf('%{width}x%{height}') >= 0) {
      return url.replace('%{width}', '1280').replace('%{height}', '720');
    }
    return url.replace(TwitchHelper.IMAGE_SIZE_PATTERN, '-1280x720.');
  }

  static profileImage(url: string): string {
    if (url.length === 0) {
      return '';
    }
    return url.replace(TwitchHelper.IMAGE_SIZE_PATTERN, '-300x300.');
  }

  /**
   * Live preview thumbnail. Unlike VOD thumbnails these have no 404 sentinel;
   * an empty URL simply has no image.
   */
  static streamThumbnail(url: string): string {
    if (url.length === 0) {
      return '';
    }
    if (url.indexOf('{width}x{height}') >= 0) {
      return url.replace('{width}', '1280').replace('{height}', '720');
    }
    return url.replace(TwitchHelper.IMAGE_SIZE_PATTERN, '-1280x720.');
  }

  /** Seconds a broadcast has been live -> "8:21:33"; '' when unknown. */
  static formatUptime(createdAt: string): string {
    if (createdAt.length === 0) {
      return '';
    }
    const started: number = Date.parse(createdAt);
    if (Number.isNaN(started)) {
      return '';
    }
    const elapsed: number = Math.floor((new Date().getTime() - started) / 1000);
    if (elapsed <= 0) {
      return '';
    }
    return TwitchHelper.formatDuration(elapsed);
  }

  /** 133769 -> "133.7K" when compact. */
  static formatCount(count: number, compact: boolean): string {
    if (!compact) {
      return TwitchHelper.groupDigits(count);
    }
    if (count < 1000) {
      return count.toString();
    }
    let suffix: string = 'K';
    let divisor: number = 1000;
    if (count >= 1000000000) {
      suffix = 'B';
      divisor = 1000000000;
    } else if (count >= 1000000) {
      suffix = 'M';
      divisor = 1000000;
    }
    const truncated: number = Math.floor(count / (divisor / 10));
    const value: number = truncated / 10;
    const hasDecimal: boolean = truncated % 10 !== 0;
    return `${hasDecimal ? value.toFixed(1) : truncated / 10}${suffix}`;
  }

  private static groupDigits(count: number): string {
    const raw: string = count.toString();
    let out: string = '';
    let seen: number = 0;
    for (let i = raw.length - 1; i >= 0; i--) {
      out = raw.charAt(i) + out;
      seen++;
      if (seen % 3 === 0 && i > 0) {
        out = ',' + out;
      }
    }
    return out;
  }

  /** Seconds -> "1:02:03" or "13:37". */
  static formatDuration(seconds: number): string {
    const total: number = Math.max(0, Math.floor(seconds));
    const h: number = Math.floor(total / 3600);
    const m: number = Math.floor((total % 3600) / 60);
    const s: number = total % 60;
    if (h > 0) {
      return `${h}:${TwitchHelper.pad2(m)}:${TwitchHelper.pad2(s)}`;
    }
    return `${m}:${TwitchHelper.pad2(s)}`;
  }

  /** Milliseconds -> "1:02:03"; used by the player scrubber. */
  static formatPlaybackTime(ms: number): string {
    return TwitchHelper.formatDuration(Math.floor(ms / 1000));
  }

  /** Bytes -> "1.4 GB"; used to estimate what a download will cost. */
  static formatSize(bytes: number): string {
    if (bytes <= 0) {
      return '';
    }
    const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];
    let value: number = bytes;
    let unit: number = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value = value / 1024;
      unit++;
    }
    const rounded: string = unit === 0 || value >= 100
      ? `${Math.round(value)}` : value.toFixed(1);
    return `${rounded} ${units[unit]}`;
  }

  /** ISO timestamp -> "3h ago" / "Apr 20, 2017". */
  static formatDate(iso: string): string {
    if (iso.length === 0) {
      return '';
    }
    const time: number = Date.parse(iso);
    if (Number.isNaN(time)) {
      return '';
    }
    const now: number = new Date().getTime();
    const diff: number = now - time;
    if (diff < 0) {
      return TwitchHelper.absoluteDate(new Date(time));
    }
    const minutes: number = Math.floor(diff / 60000);
    if (minutes < 1) {
      return 'Just now';
    }
    if (minutes < 60) {
      return `${minutes}m ago`;
    }
    const hours: number = Math.floor(minutes / 60);
    if (hours < 24) {
      return `${hours}h ago`;
    }
    const days: number = Math.floor(hours / 24);
    if (days < 7) {
      return `${days}d ago`;
    }
    return TwitchHelper.absoluteDate(new Date(time));
  }

  private static absoluteDate(date: Date): string {
    const month: string = TwitchHelper.MONTHS[date.getMonth()];
    return `${month} ${date.getDate()}, ${date.getFullYear()}`;
  }

  private static pad2(value: number): string {
    return value < 10 ? `0${value}` : value.toString();
  }
}
