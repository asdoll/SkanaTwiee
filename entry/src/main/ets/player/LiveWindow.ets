import { liveViewManager } from '@kit.LiveViewKit';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'LiveWindow';
/** Live view scenario used while a VOD is playing. */
const EVENT_PROGRESS: string = 'PROGRESS';
/** Live view scenario used while a live stream is playing. */
const EVENT_TIMER: string = 'TIMER';
/**
 * Size the avatar is decoded to for the capsule icon.
 *
 * Live View Kit caps that icon at 30 KB on releases before 26.0.0, and a decoded
 * bitmap costs four bytes a pixel: 96x96 is already 36 KB and is refused, while
 * 64x64 is 16 KB and fits.
 */
export const CAPSULE_ICON_SIZE: number = 64;

/**
 * The system live view (实况窗) for whatever is currently playing.
 *
 * This is the HarmonyOS counterpart of Xtra's MediaSession notification: a card
 * that lives in the notification panel and on the lock screen, with a capsule in
 * the status bar. It shows the channel's avatar and the stream title, which the
 * system scrolls when it does not fit.
 *
 * Two things can stop it from appearing, and both are handled by giving up
 * quietly rather than by breaking playback:
 *
 *  - the live view switch in Settings, which isLiveViewEnabled() reports;
 *  - Live View Kit's scenario rights, which an app has to be granted by the
 *    platform per scenario. A refusal is remembered for the rest of the process
 *    so the service is asked exactly once.
 *
 * Playback is never gated on any of this: the media session (PlaybackSession)
 * carries the same title and artwork and always works.
 */
export class LiveWindow {
  /** 0 while no live view of ours is running. */
  private static id: number = 0;
  /** Must increase with every update and with the final stop. */
  private static sequence: number = 0;
  private static active: boolean = false;
  /** Set after a refusal, so the service is not asked again this run. */
  private static unavailable: boolean = false;
  /** Kept because stopping a live view needs the object it was started with. */
  private static last: liveViewManager.LiveView | undefined = undefined;

  static isActive(): boolean {
    return LiveWindow.active;
  }

  /** Starts, or refreshes, the live view for what is playing. */
  static async show(title: string, channel: string, avatar: image.PixelMap | undefined,
    isLive: boolean): Promise<void> {
    if (LiveWindow.unavailable || title.length === 0) {
      return;
    }
    if (!LiveWindow.active && !await LiveWindow.available()) {
      return;
    }
    const updating: boolean = LiveWindow.active;
    try {
      const view: liveViewManager.LiveView =
        LiveWindow.build(title, channel, avatar, isLive, updating);
      LiveWindow.sequence = view.sequence !== undefined ? view.sequence : LiveWindow.sequence;
      const result: liveViewManager.LiveViewResult = updating
        ? await liveViewManager.updateLiveView(view)
        : await liveViewManager.startLiveView(view);
      // The live view exists either way. A non-zero code names the one area that
      // failed to refresh - the capsule, most often, when its icon does not fit
      // the budget - and the next update is free to put that right, so nothing is
      // written off for the rest of the run over it.
      LiveWindow.last = view;
      LiveWindow.active = true;
      if (result.resultCode === 0) {
        hilog.info(DOMAIN, TAG, 'live view %{public}d %{public}s',
          view.id, updating ? 'updated' : 'started');
      } else {
        hilog.warn(DOMAIN, TAG, 'live view %{public}d: %{public}s was not refreshed (%{public}d)',
          view.id, LiveWindow.area(result.resultCode), result.resultCode);
      }
    } catch (e) {
      const err = e as BusinessError;
      LiveWindow.active = false;
      if (err.code === 1003500004 || err.code === 1003500005) {
        // The switch or the scenario right. Neither changes while the app runs,
        // so the service is not asked again this time.
        hilog.warn(DOMAIN, TAG, 'live view refused (%{public}d): %{public}s',
          err.code, LiveWindow.right(err.code));
        LiveWindow.unavailable = true;
        return;
      }
      hilog.warn(DOMAIN, TAG, 'live view failed (%{public}s)', JSON.stringify(err.code));
    }
  }

  /** What a refusal code means, in the words of whoever has to act on it. */
  private static right(code: number): string {
    if (code === 1003500004) {
      return 'live views are switched off in the system settings';
    }
    return 'this app has no live view right for the scenario - apply for it in AppGallery Connect';
  }

  /** Which part of the live view a non-zero result code is about. */
  private static area(code: number): string {
    if (code === 1) {
      return 'the fixed area';
    }
    if (code === 2) {
      return 'the auxiliary area';
    }
    if (code === 3) {
      return 'the extension area';
    }
    if (code === 4) {
      return 'the capsule';
    }
    if (code === 5) {
      return 'the cover screen';
    }
    return 'an unknown area';
  }

  /** Ends the live view; harmless when none was ever started. */
  static async stop(): Promise<void> {
    const view: liveViewManager.LiveView | undefined = LiveWindow.last;
    LiveWindow.last = undefined;
    const wasActive: boolean = LiveWindow.active;
    LiveWindow.active = false;
    LiveWindow.id = 0;
    if (!wasActive || view === undefined) {
      return;
    }
    try {
      // The end message has to carry a higher version than the last update.
      LiveWindow.sequence++;
      const ended: liveViewManager.LiveView = LiveWindow.buildWith(view, LiveWindow.sequence);
      await liveViewManager.stopLiveView(ended);
    } catch (e) {
      hilog.debug(DOMAIN, TAG, 'could not end the live view');
    }
  }

  /** Asks the user's live view switch; only ever called once per process. */
  private static async available(): Promise<boolean> {
    try {
      const enabled: boolean = await liveViewManager.isLiveViewEnabled();
      if (!enabled) {
        hilog.info(DOMAIN, TAG, 'the live view switch is off in Settings');
        LiveWindow.unavailable = true;
      }
      return enabled;
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'live view service missing (%{public}s)', JSON.stringify(err.code));
      LiveWindow.unavailable = true;
      return false;
    }
  }

  private static build(title: string, channel: string, avatar: image.PixelMap | undefined,
    isLive: boolean, updating: boolean): liveViewManager.LiveView {
    // The playback title is the headline - it is the thing to read next to the
    // avatar - and the channel is the line under it. Whichever does not fit is
    // scrolled by the system.
    const secondary: string = channel.length > 0 ? channel : title;
    const content: liveViewManager.RichText[] = [{ text: secondary, textColor: '#99000000' }];
    const capsule: liveViewManager.TextCapsule = {
      type: liveViewManager.CapsuleType.CAPSULE_TYPE_TEXT,
      status: 1,
      title: title,
      content: secondary,
      isContentDisplayed: true
    };
    if (avatar !== undefined) {
      capsule.icon = avatar;
    }
    const primary: liveViewManager.PrimaryData = {
      title: title,
      content: content,
      // 0 keeps the card in the panel only while it is running.
      keepTime: 0
    };
    if (LiveWindow.id === 0) {
      LiveWindow.id = LiveWindow.identity(isLive ? `live:${channel}` : `vod:${title}`);
    }
    if (!updating) {
      LiveWindow.sequence = 1;
    } else {
      LiveWindow.sequence++;
    }
    const view: liveViewManager.LiveView = {
      id: LiveWindow.id,
      event: isLive ? EVENT_TIMER : EVENT_PROGRESS,
      sequence: LiveWindow.sequence,
      isMute: true,
      liveViewData: {
        primary: primary,
        capsule: capsule
      }
    };
    return view;
  }

  /** The same view again, with a version high enough to end it. */
  private static buildWith(view: liveViewManager.LiveView, sequence: number): liveViewManager.LiveView {
    const ended: liveViewManager.LiveView = {
      id: view.id,
      event: view.event,
      sequence: sequence,
      isMute: true,
      liveViewData: view.liveViewData
    };
    return ended;
  }

  /** Stable 32-bit identity for a live view, derived from the thing playing. */
  private static identity(key: string): number {
    let value: number = 0;
    for (let i = 0; i < key.length; i++) {
      value = (value * 31 + key.charCodeAt(i)) | 0;
    }
    return value === 0 ? 1 : value;
  }
}
