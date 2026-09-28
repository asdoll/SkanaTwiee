/**
 * Height of a rendition as its playlist name spells it: "720p60" -> 720.
 *
 * Zero for the names that carry no resolution - "source", "chunked",
 * "audio_only" - and the reason a frame rate is never part of a quality choice:
 * a broadcast that calls a rendition "720p60" and one that calls it "720p" are
 * both 720p, and both play at whatever rate they were encoded at.
 */
export function renditionHeight(name: string): number {
  let digits: string = '';
  for (let i = 0; i < name.length; i++) {
    const ch: string = name.charAt(i);
    if (ch < '0' || ch > '9') {
      break;
    }
    digits += ch;
  }
  return digits.length > 0 ? Number.parseInt(digits) : 0;
}

/** True for the broadcaster's own rendition, which the playlist names either way. */
export function isSourceRendition(name: string): boolean {
  return name === 'source' || name === 'chunked';
}

/**
 * A selectable HLS rendition. Matches the entries Twitch's usher master
 * playlist exposes (source/chunked, 1080p60, 720p60, audio_only, ...).
 */
export class Quality {
  /** Human readable name from the playlist, e.g. "1080p60". */
  name: string = '';
  /** Bandwidth in bits per second; used to match AVPlayer's availableBitrates. */
  bandwidth: number = 0;
  /** e.g. "1920x1080", empty for audio-only renditions. */
  resolution: string = '';
  frameRate: number = 0;
  isAudioOnly: boolean = false;
  isSource: boolean = false;
  /**
   * The rendition's own playlist URI, resolved against the master it came from.
   * Handing this to the player pins playback to exactly this rendition, which is
   * what makes a manual pick - and the automatic step down after one fails -
   * deterministic instead of a hint to the automatic bitrate selector.
   */
  url: string = '';

  constructor(name: string, bandwidth: number, resolution: string, frameRate: number,
    isAudioOnly: boolean, isSource: boolean, url: string) {
    this.name = name;
    this.bandwidth = bandwidth;
    this.resolution = resolution;
    this.frameRate = frameRate;
    this.isAudioOnly = isAudioOnly;
    this.isSource = isSource;
    this.url = url;
  }
}
