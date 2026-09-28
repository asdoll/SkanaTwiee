import { avSession } from '@kit.AVSessionKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { common, Want, WantAgent, wantAgent } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'PlaybackSession';
const SESSION_TAG: string = 'skanatwiee';
/** How long to wait before re-trying a session the service refused. */
const SESSION_RETRY_MS: number = 300;

function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout(resolve, ms);
  });
}

/** What is playing. It decides the session type the system renders. */
export type PlaybackKind = 'audio' | 'video';

/**
 * The AVSession type for a kind of playback.
 *
 * The system picks the card from this: `'audio'` is the music card - cover art
 * and a scrubber, plus the audio capsule in the status bar - while `'video'` is
 * the video card. Audio-only playback used to be announced through a `'video'`
 * session, which is one of the reasons neither surface ever showed up.
 */
function sessionTypeFor(kind: PlaybackKind): avSession.AVSessionType {
  return kind === 'audio' ? 'audio' : 'video';
}

/**
 * One playback session: the AVSession the system shows (control-centre card,
 * status-bar capsule, lock screen) plus the continuous task that keeps the
 * process alive while it plays.
 *
 * Xtra does this with a foreground MediaSessionService (BasePlaybackService ->
 * ExoPlayerService / Media3PlayerFragment). HarmonyOS splits it into two pieces,
 * and both are needed:
 *
 *  1. an AVSession, which registers the app as a media app, hands it audio focus
 *     and publishes the transport controls. Without an AVSession-connected task
 *     the system may cancel an AUDIO_PLAYBACK continuous task
 *     (SYSTEM_CANCEL_AUDIO_PLAYBACK_NOT_USE_AVSESSION) and suppresses the media
 *     notification.
 *  2. a continuous task, backed by ohos.permission.KEEP_BACKGROUND_RUNNING and
 *     "backgroundModes": ["audioPlayback"], which stops the process from being
 *     frozen once it leaves the foreground.
 *
 * The pages no longer build this themselves: `mediaSession` owns the single
 * instance and hands it out, because an ability may only hold one AVSession and
 * a create that races the destroy of the previous one is refused outright.
 */
export class PlaybackSession {
  private context: common.UIAbilityContext;
  private kind: PlaybackKind;
  private session: avSession.AVSession | undefined = undefined;
  private taskRunning: boolean = false;
  /** Last state pushed, so progress-only updates need not repeat it. */
  private lastState: avSession.PlaybackState = avSession.PlaybackState.PLAYBACK_STATE_PREPARE;
  /**
   * The metadata currently published. Kept here because setAVMetadata replaces
   * the whole record: the title, the artist, the duration and the artwork arrive
   * from different places (the live card's info, the video query, the avatar
   * download) and each arrival must not wipe out the others.
   */
  private title: string = '';
  private subtitle: string = '';
  private durationMs: number = 0;
  private artwork: image.PixelMap | undefined = undefined;

  constructor(context: common.UIAbilityContext, kind: PlaybackKind) {
    this.context = context;
    this.kind = kind;
  }

  /**
   * Creates and activates the media session, then claims the continuous task.
   *
   * Called on every acquire: the title, artist, duration and artwork are
   * refreshed, but the session itself is built only once.
   */
  async start(title: string, subtitle: string, durationMs: number): Promise<void> {
    this.title = title;
    this.subtitle = subtitle;
    this.durationMs = durationMs;
    if (this.session === undefined) {
      await this.startSession();
    } else {
      await this.pushMetadata();
    }
    await this.startContinuousTask();
  }

  private async startSession(): Promise<void> {
    try {
      await this.createSession();
      return;
    } catch (e) {
      const err = e as BusinessError;
      // 6600101 is the session service refusing the call: an ability may only
      // hold one AVSession, so a create overlapping the destroy of the previous
      // session lands here. One short retry wins that race - and without it the
      // app is left with no control-centre card, no capsule and no lock screen,
      // which is exactly how this looked on a device before.
      hilog.warn(DOMAIN, TAG, 'AVSession refused (%{public}s), retrying once',
        JSON.stringify(err.code));
    }
    await delay(SESSION_RETRY_MS);
    try {
      await this.createSession();
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'no AVSession (%{public}s): %{public}s',
        JSON.stringify(err.code), JSON.stringify(err.message));
    }
  }

  /** One attempt at the session itself, metadata and all. */
  private async createSession(): Promise<void> {
    const session: avSession.AVSession =
      await avSession.createAVSession(this.context, SESSION_TAG, sessionTypeFor(this.kind));
    this.session = session;
    // A session with no command registered does not count as a media app, so
    // the three transport handlers exist from the start and the page replaces
    // them when it binds its own (see bindControls).
    session.on('play', (): void => {});
    session.on('pause', (): void => {});
    session.on('stop', (): void => {});
    // The system decides from this value whether to draw its own live view for a
    // playing app once it goes to the background, and the default for a session
    // created as 'video' is DISABLE_BACKGROUND_PLAY - which is why neither the
    // status-bar capsule nor the lock-screen card ever appeared, while music
    // (an 'audio' session, default ENABLE) would have. This app does keep
    // playing in the background, which is exactly what the continuous task below
    // is claimed for, so the mode and the behaviour agree.
    try {
      await session.setBackgroundPlayMode(
        avSession.BackgroundPlayMode.ENABLE_BACKGROUND_PLAY);
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'could not enable background play (%{public}s)',
        JSON.stringify(err.code));
    }
    // What the capsule and the control-centre card start when they are tapped;
    // without it the system has nothing to bring back to the foreground.
    try {
      await session.setLaunchAbility(await this.launchAgent());
    } catch (e) {
      hilog.debug(DOMAIN, TAG, 'could not set the launch ability');
    }
    await session.setAVMetadata(this.metadata());
    await session.activate();
    hilog.info(DOMAIN, TAG, 'AVSession %{public}s activated (%{public}s)',
      session.sessionId, this.kind);
    await this.updateState(avSession.PlaybackState.PLAYBACK_STATE_PREPARE, 0, this.durationMs);
  }

  /** Brings this app back to the foreground: the continuous task and the card share it. */
  private async launchAgent(): Promise<WantAgent> {
    const want: Want = {
      bundleName: this.context.abilityInfo.bundleName,
      abilityName: this.context.abilityInfo.name
    };
    const info: wantAgent.WantAgentInfo = {
      wants: [want],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    return wantAgent.getWantAgent(info);
  }

  private metadata(): avSession.AVMetadata {
    const metadata: avSession.AVMetadata = {
      assetId: SESSION_TAG,
      title: this.title.length > 0 ? this.title : SESSION_TAG,
      artist: this.subtitle
    };
    if (this.durationMs > 0) {
      metadata.duration = this.durationMs;
    }
    // The artwork is what the media card, the lock screen and the live window
    // show next to the title; on a phone it is the only picture available.
    if (this.artwork !== undefined) {
      metadata.mediaImage = this.artwork;
    }
    return metadata;
  }

  private async startContinuousTask(): Promise<void> {
    if (this.taskRunning) {
      return;
    }
    try {
      const agent: WantAgent = await this.launchAgent();
      await backgroundTaskManager.startBackgroundRunning(this.context,
        backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK, agent);
      this.taskRunning = true;
      hilog.info(DOMAIN, TAG, 'continuous task (audioPlayback) started');
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'could not start continuous task (%{public}s)', JSON.stringify(err.code));
    }
  }

  /** Called after the video metadata arrives, so the notification gets a title. */
  async updateMetadata(title: string, subtitle: string, durationMs: number): Promise<void> {
    this.title = title;
    this.subtitle = subtitle;
    this.durationMs = durationMs;
    await this.pushMetadata();
  }

  /** Publishes the channel avatar, once it has been fetched and decoded. */
  async setArtwork(artwork: image.PixelMap | undefined): Promise<void> {
    this.artwork = artwork;
    await this.pushMetadata();
  }

  private async pushMetadata(): Promise<void> {
    const session: avSession.AVSession | undefined = this.session;
    if (session === undefined) {
      return;
    }
    try {
      await session.setAVMetadata(this.metadata());
    } catch (e) {
      hilog.debug(DOMAIN, TAG, 'metadata update failed');
    }
  }

  /** Mirrors AVPlayer state into the media session / control centre. */
  async updateState(state: avSession.PlaybackState, positionMs: number,
    durationMs: number): Promise<void> {
    this.lastState = state;
    await this.pushState(state, positionMs, durationMs);
  }

  /**
   * Publishes progress only, keeping the last reported state.
   *
   * The lock screen and the control-centre card draw their scrubber from the
   * position in the last update, so it has to be refreshed while playing - a
   * state change on its own leaves the card frozen at 0:00.
   */
  async updateProgress(positionMs: number, durationMs: number): Promise<void> {
    await this.pushState(this.lastState, positionMs, durationMs);
  }

  private async pushState(state: avSession.PlaybackState, positionMs: number,
    durationMs: number): Promise<void> {
    const session: avSession.AVSession | undefined = this.session;
    if (session === undefined) {
      return;
    }
    try {
      const position: avSession.PlaybackPosition = {
        elapsedTime: Math.max(0, Math.floor(positionMs)),
        updateTime: Date.now()
      };
      // speed is deliberately omitted unless playing: 0 is out of range and the
      // session rejects the whole state update if it is invalid.
      const playbackState: avSession.AVPlaybackState = {
        state: state,
        position: position
      };
      if (state === avSession.PlaybackState.PLAYBACK_STATE_PLAY) {
        playbackState.speed = 1;
      }
      if (durationMs > 0) {
        playbackState.duration = Math.floor(durationMs);
      }
      await session.setAVPlaybackState(playbackState);
    } catch (e) {
      const err = e as BusinessError;
      hilog.debug(DOMAIN, TAG, 'state update failed (%{public}s)', JSON.stringify(err.code));
    }
  }

  /**
   * Routes headset / notification / lock-screen transport buttons to the player.
   *
   * The session outlives the page now, so whatever the previous page bound is
   * dropped first: a stale handler would keep driving a released player.
   */
  bindControls(onPlay: () => void, onPause: () => void, onStop: () => void,
    onSeek: (positionMs: number) => void): void {
    const session: avSession.AVSession | undefined = this.session;
    if (session === undefined) {
      return;
    }
    this.unbindControls();
    try {
      session.on('play', onPlay);
      session.on('pause', onPause);
      session.on('stop', onStop);
      session.on('seek', onSeek);
    } catch (e) {
      hilog.debug(DOMAIN, TAG, 'could not bind remote controls');
    }
  }

  /** Leaves the transport buttons to nobody when the player page goes away. */
  unbindControls(): void {
    const session: avSession.AVSession | undefined = this.session;
    if (session === undefined) {
      return;
    }
    try {
      session.off('play');
      session.off('pause');
      session.off('stop');
      session.off('seek');
    } catch (e) {
      hilog.debug(DOMAIN, TAG, 'could not unbind remote controls');
    }
  }

  /** Releases the media session and the continuous task. Safe to call twice. */
  async stop(): Promise<void> {
    const session: avSession.AVSession | undefined = this.session;
    this.session = undefined;
    if (session !== undefined) {
      hilog.info(DOMAIN, TAG, 'releasing AVSession %{public}s', session.sessionId);
      try {
        session.off('play');
        session.off('pause');
        session.off('stop');
        session.off('seek');
      } catch (e) {
        hilog.debug(DOMAIN, TAG, 'unbind failed');
      }
      try {
        await session.deactivate();
      } catch (e) {
        hilog.debug(DOMAIN, TAG, 'deactivate failed');
      }
      try {
        await session.destroy();
      } catch (e) {
        hilog.debug(DOMAIN, TAG, 'destroy failed');
      }
    }
    if (this.taskRunning) {
      this.taskRunning = false;
      try {
        await backgroundTaskManager.stopBackgroundRunning(this.context);
        hilog.info(DOMAIN, TAG, 'continuous task stopped');
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'could not stop continuous task');
      }
    }
  }
}

/**
 * The app's media session - one per process.
 *
 * Ported from Petrelgram's `services/MediaPlaybackKeepAlive`, which is the shape
 * that is known to work on a device: a single long-lived session that appears
 * when playback starts and goes when the last player does, refcounted by kind so
 * two players cannot tear each other's session down, and every call serialized -
 * an ability may only hold one AVSession, and the old code created and destroyed
 * one per page, swallowing the failures, so a race left the app with no card, no
 * capsule and no lock screen at all.
 */
class MediaSessionService {
  private session: PlaybackSession | undefined = undefined;
  private kinds: Set<PlaybackKind> = new Set();
  private queue: Promise<void> = Promise.resolve();

  /**
   * Called by a player as it starts. The first caller builds the session; later
   * ones refresh the metadata and get the same object back.
   */
  async acquire(context: common.UIAbilityContext, kind: PlaybackKind, title: string,
    subtitle: string, durationMs: number): Promise<PlaybackSession | undefined> {
    this.kinds.add(kind);
    await this.enqueue(async (): Promise<void> => {
      if (this.session === undefined) {
        this.session = new PlaybackSession(context, kind);
      }
      const session: PlaybackSession | undefined = this.session;
      if (session !== undefined) {
        await session.start(title, subtitle, durationMs);
      }
    });
    return this.session;
  }

  /** Called when a player stops. The session goes with the last one. */
  release(kind: PlaybackKind): void {
    this.kinds.delete(kind);
    this.enqueue(async (): Promise<void> => {
      if (this.kinds.size > 0) {
        return;
      }
      const session: PlaybackSession | undefined = this.session;
      this.session = undefined;
      if (session !== undefined) {
        await session.stop();
      }
    });
  }

  /** The session in use, for updates that should not wait on acquire. */
  active(): PlaybackSession | undefined {
    return this.session;
  }

  private enqueue(action: () => Promise<void>): Promise<void> {
    const next: Promise<void> = this.queue.then(action).catch((error: Error): void => {
      hilog.warn(DOMAIN, TAG, 'media session operation failed: %{public}s', error.message);
    });
    this.queue = next;
    return next;
  }
}

/** The one media session of this app. */
export const mediaSession: MediaSessionService = new MediaSessionService();
