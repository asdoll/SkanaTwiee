import { media } from '@kit.MediaKit';
import { PrefKeys } from '../common/Const';
import { Prefs } from '../common/Prefs';
import { isSourceRendition, renditionHeight } from '../model/Quality';

/** One playback rate the app offers. */
export class RateChoice {
  /** What the pickers show, e.g. "1.5x". */
  label: string = '';
  rate: number = 1;
  /**
   * AVPlayer takes a fixed enum rather than a number, so the rate carries the
   * one it maps to and nothing else has to know the mapping.
   */
  speed: media.PlaybackSpeed = media.PlaybackSpeed.SPEED_FORWARD_1_00_X;

  constructor(label: string, rate: number, speed: media.PlaybackSpeed) {
    this.label = label;
    this.rate = rate;
    this.speed = speed;
  }
}

/** One quality the default-quality setting offers. */
export class QualityChoice {
  /** What the pickers show, e.g. "720p60" or "audio only". */
  label: string = '';
  /** Playlist name of the rendition, e.g. "720p60"; empty for Auto. */
  name: string = '';

  constructor(label: string, name: string) {
    this.label = label;
    this.name = name;
  }
}

/**
 * What a video opens with: the quality and the rate set in the Me tab.
 *
 * Both are preferences rather than promises. A quality is asked for by
 * resolution and a video that does not carry it plays on Auto instead - so the
 * setting made once suits every video afterwards, instead of failing on the
 * first one that cannot honour it. A rate is a starting point too: only that
 * playback uses it, and changing it in the player lasts for that video alone.
 */
export class SettingsRepository {
  /**
   * The broadcaster's own rendition, stored under one name whatever the playlist
   * calls it: Twitch labels the same thing "source" in one request and
   * "chunked" in the next.
   */
  static readonly SOURCE: string = 'source';

  /**
   * Normal speed, which is also what a stored rate falls back to.
   */
  static rate(): number {
    const stored: number = Prefs.getNumber(PrefKeys.DEFAULT_SPEED, 1);
    const choices: RateChoice[] = SettingsRepository.rates();
    for (let i = 0; i < choices.length; i++) {
      if (choices[i].rate === stored) {
        return stored;
      }
    }
    return 1;
  }

  static setRate(rate: number): void {
    Prefs.setNumber(PrefKeys.DEFAULT_SPEED, rate);
  }

  /** "1x", "1.5x" - the same wording the player's own speed button uses. */
  static rateLabel(rate: number): string {
    return rate === 1 ? '1x' : `${rate}x`;
  }

  /**
   * Every rate the app offers.
   *
   * AVPlayer's enum stops at 3x, so this is the whole list there is: there is no
   * 4x to add without the platform supporting it.
   */
  static rates(): RateChoice[] {
    const rates: RateChoice[] = [];
    rates.push(new RateChoice('0.5x', 0.5, media.PlaybackSpeed.SPEED_FORWARD_0_50_X));
    rates.push(new RateChoice('1x', 1, media.PlaybackSpeed.SPEED_FORWARD_1_00_X));
    rates.push(new RateChoice('1.5x', 1.5, media.PlaybackSpeed.SPEED_FORWARD_1_50_X));
    rates.push(new RateChoice('1.75x', 1.75, media.PlaybackSpeed.SPEED_FORWARD_1_75_X));
    rates.push(new RateChoice('2x', 2, media.PlaybackSpeed.SPEED_FORWARD_2_00_X));
    rates.push(new RateChoice('3x', 3, media.PlaybackSpeed.SPEED_FORWARD_3_00_X));
    return rates;
  }

  /** The rendition to open at; empty means Auto. */
  static quality(): string {
    const stored: string = Prefs.getString(PrefKeys.DEFAULT_QUALITY, '');
    if (stored.length === 0) {
      return '';
    }
    if (isSourceRendition(stored)) {
      return SettingsRepository.SOURCE;
    }
    // The resolution, whatever the name says around it: a setting written when
    // the frame rate was still part of the name - "720p60" - means the same 720p
    // as the one written today.
    const height: number = renditionHeight(stored);
    const choices: QualityChoice[] = SettingsRepository.qualities();
    for (let i = 0; i < choices.length; i++) {
      const name: string = choices[i].name;
      if (name.length > 0 && renditionHeight(name) === height) {
        return name;
      }
    }
    // Anything else is Auto, which every video can honour.
    return '';
  }

  static setQuality(name: string): void {
    Prefs.setString(PrefKeys.DEFAULT_QUALITY, name);
  }

  /** "Auto" for the empty name, which is what the pickers tick. */
  static qualityLabel(name: string): string {
    const choices: QualityChoice[] = SettingsRepository.qualities();
    for (let i = 0; i < choices.length; i++) {
      if (choices[i].name === name) {
        return choices[i].label;
      }
    }
    return 'Auto';
  }

  /**
   * The qualities the setting offers.
   *
   * Resolutions only: a frame rate is not a quality anyone chose, and the two
   * renditions a broadcast may offer for one resolution - 60fps and 30fps - are
   * the same choice to make. A fixed list rather than whatever the video being
   * played happens to carry, because this is set in the Me tab with nothing
   * playing and has to mean the same thing for every video afterwards; a name a
   * broadcast does not offer leaves the player on Auto.
   */
  static qualities(): QualityChoice[] {
    const qualities: QualityChoice[] = [];
    qualities.push(new QualityChoice('Auto', ''));
    qualities.push(new QualityChoice('source', SettingsRepository.SOURCE));
    qualities.push(new QualityChoice('1080p', '1080p'));
    qualities.push(new QualityChoice('720p', '720p'));
    qualities.push(new QualityChoice('480p', '480p'));
    qualities.push(new QualityChoice('360p', '360p'));
    qualities.push(new QualityChoice('160p', '160p'));
    return qualities;
  }
}
