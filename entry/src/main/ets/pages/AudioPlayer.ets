import { media } from '@kit.MediaKit';
import { avSession } from '@kit.AVSessionKit';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';
import { Nav } from '../common/Nav';
import { Immersive, Insets } from '../common/Immersive';
import { AudioParams } from '../model/Routes';
import { PlaybackSession, mediaSession } from '../player/PlaybackSession';
import { ImageLoader } from '../util/ImageLoader';
import { TwitchHelper } from '../util/TwitchHelper';

const DOMAIN: number = 0x0000;
const TAG: string = 'AudioPlayer';
const ARTWORK_SIZE: number = 240;
/** How often the media session is told where playback is; see publishProgress. */
const PROGRESS_INTERVAL_MS: number = 1000;

/**
 * A downloaded audio-only file, played like a music track.
 *
 * There is no video surface here at all: AVPlayer plays sound without one, which
 * frees the whole screen for the shape a music player has - artwork, title, a
 * scrubber and one large button.
 */
@Component
export struct AudioPlayerPage {
  @State title: string = '';
  @State channel: string = '';
  @State artwork: string = '';
  @State playing: boolean = false;
  @State positionMs: number = 0;
  @State durationMs: number = 0;
  @State topInset: number = 0;
  /** Set when the file cannot be opened or the player refuses it. */
  @State failed: boolean = false;

  path: string = '';
  player: media.AVPlayer | undefined = undefined;
  /** Descriptor of the file, held open for as long as it plays. */
  descriptor: number = -1;
  /** True while the scrubber is being dragged, so timeUpdate does not fight it. */
  scrubbing: boolean = false;
  session: PlaybackSession | undefined = undefined;
  /** Timestamp of the last progress publication; see publishProgress. */
  lastProgressAt: number = 0;

  aboutToAppear(): void {
    this.setupInsets();
  }

  aboutToDisappear(): void {
    this.release();
  }

  build() {
    NavDestination() {
      Column() {
        this.header()

        if (this.failed) {
          Column() {
            Text($r('app.string.load_failed'))
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          this.cover()
          this.details()
          this.scrubber()
          this.controls()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'))
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      const params: AudioParams | undefined = context.pathInfo.param as AudioParams | undefined;
      if (params !== undefined) {
        this.path = params.path;
        this.title = params.title;
        this.channel = params.channel;
        this.artwork = params.artwork;
        this.durationMs = params.durationSeconds * 1000;
      }
      this.start();
    })
  }

  private async setupInsets(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const insets: Insets = await Immersive.enable(context);
    this.topInset = this.getUIContext().px2vp(insets.top);
  }

  @Builder
  header() {
    Row() {
      Button({ type: ButtonType.Circle }) {
        Text('\u2039')
          .fontSize(26)
          .fontColor($r('app.color.text_primary'))
      }
      .width(40)
      .height(40)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        Nav.back();
      })

      Text($r('app.string.audio_only'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ left: 8 })
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: this.topInset + 8 })
  }

  @Builder
  cover() {
    Column() {
      if (this.artwork.length > 0) {
        Image(TwitchHelper.videoThumbnail(this.artwork))
          .width(ARTWORK_SIZE)
          .height(ARTWORK_SIZE)
          .borderRadius(20)
          .objectFit(ImageFit.Cover)
          .shadow({ radius: 24, color: '#000000' })
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.square_and_arrow_down'))
            .fontSize(48)
            .fontColor([$r('app.color.text_muted')])
        }
        .width(ARTWORK_SIZE)
        .height(ARTWORK_SIZE)
        .borderRadius(20)
        .backgroundColor($r('app.color.surface'))
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  details() {
    Column() {
      Text(this.title.length > 0 ? this.title : this.path)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%')

      if (this.channel.length > 0) {
        Text(this.channel)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 8 })
          .maxLines(1)
      }
    }
    .width('100%')
    .padding({ left: 32, right: 32 })
  }

  @Builder
  scrubber() {
    Row() {
      Text(TwitchHelper.formatPlaybackTime(this.positionMs))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width(52)

      Slider({
        value: this.positionMs,
        min: 0,
        max: this.durationMs > 0 ? this.durationMs : 1,
        step: 1000,
        style: SliderStyle.OutSet
      })
        .selectedColor($r('app.color.accent'))
        .trackColor($r('app.color.surface_alt'))
        .layoutWeight(1)
        .onChange((value: number, mode: SliderChangeMode) => {
          if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
            this.scrubbing = true;
            this.positionMs = value;
            return;
          }
          this.scrubbing = false;
          this.seekTo(value);
        })

      Text(TwitchHelper.formatPlaybackTime(this.durationMs))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width(52)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 20, right: 20, top: 24 })
  }

  @Builder
  controls() {
    Row() {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph(this.playing ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
          .fontSize(44)
          .fontColor([Color.White])
      }
      .width(76)
      .height(76)
      .backgroundColor($r('app.color.accent'))
      .onClick(() => {
        this.toggle();
      })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 28, bottom: 48 })
  }

  /* --------------------------- playback --------------------------- */

  private async start(): Promise<void> {
    if (this.path.length === 0) {
      this.failed = true;
      return;
    }
    try {
      const info: fs.Stat = fs.statSync(this.path);
      const file = fs.openSync(this.path, fs.OpenMode.READ_ONLY);
      this.descriptor = file.fd;
      const player: media.AVPlayer = await media.createAVPlayer();
      this.player = player;
      player.on('stateChange', (state: string) => {
        this.onStateChange(state);
      });
      player.on('timeUpdate', (time: number) => {
        if (!this.scrubbing) {
          this.positionMs = time;
        }
        this.publishProgress(time);
      });
      player.on('durationUpdate', (duration: number) => {
        if (duration > 0) {
          this.durationMs = duration;
        }
      });
      player.fdSrc = { fd: file.fd, offset: 0, length: info.size };
      this.startSession();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'could not open the downloaded audio file');
      this.failed = true;
    }
  }

  private onStateChange(state: string): void {
    const player: media.AVPlayer | undefined = this.player;
    if (player === undefined) {
      return;
    }
    if (state === 'initialized') {
      // Assigning fdSrc only reaches 'initialized': without this the player sits
      // there preparing nothing, and the screen looks like it is playing silence.
      player.prepare().then(() => {
      }, () => {
        this.failed = true;
      });
      return;
    }
    if (state === 'prepared') {
      player.play().then(() => {
      }, () => {
      });
      return;
    }
    if (state === 'playing') {
      this.playing = true;
    } else if (state === 'paused' || state === 'completed') {
      this.playing = false;
    } else if (state === 'error') {
      this.failed = true;
    }
    this.syncSession(state);
  }

  /**
   * Keeps the media card, the status-bar capsule and the lock screen in step
   * with this track.
   *
   * The session is the app-wide one, created with the `'audio'` type so the
   * system draws the music card (cover art and a scrubber). Announcing an
   * audio-only file through a video session is one of the reasons this page
   * never showed up on the control centre.
   */
  private async startSession(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const session: PlaybackSession | undefined = await mediaSession.acquire(context, 'audio',
        this.title.length > 0 ? this.title : this.path, this.channel, this.durationMs);
      if (session === undefined) {
        hilog.warn(DOMAIN, TAG, 'no media session; the system card will not appear');
        return;
      }
      this.session = session;
      session.bindControls(
        (): void => {
          this.toggle();
        },
        (): void => {
          this.toggle();
        },
        (): void => {
          this.toggle();
        },
        (positionMs: number): void => {
          this.seekTo(positionMs);
        });
      // The cover the page shows, decoded for the card. A remote URL would have
      // to be fetched by the system service on every lock-screen draw.
      if (this.artwork.length > 0) {
        const cover: image.PixelMap | undefined =
          await ImageLoader.load(TwitchHelper.videoThumbnail(this.artwork), ARTWORK_SIZE);
        if (cover !== undefined) {
          session.setArtwork(cover);
        }
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'media session unavailable');
      this.session = undefined;
    }
  }

  /** Sprinkles the play head into the media card, at most once a second. */
  private publishProgress(positionMs: number): void {
    const session: PlaybackSession | undefined = this.session;
    if (session === undefined) {
      return;
    }
    const now: number = Date.now();
    if (now - this.lastProgressAt < PROGRESS_INTERVAL_MS) {
      return;
    }
    this.lastProgressAt = now;
    session.updateProgress(positionMs, this.durationMs);
  }

  /** Mirrors the player state into the media card, as the video player does. */
  private syncSession(state: string): void {
    const session: PlaybackSession | undefined = this.session;
    if (session === undefined) {
      return;
    }
    let playbackState: avSession.PlaybackState;
    if (state === 'playing') {
      playbackState = avSession.PlaybackState.PLAYBACK_STATE_PLAY;
    } else if (state === 'paused') {
      playbackState = avSession.PlaybackState.PLAYBACK_STATE_PAUSE;
    } else if (state === 'completed') {
      playbackState = avSession.PlaybackState.PLAYBACK_STATE_COMPLETED;
    } else {
      return;
    }
    session.updateState(playbackState, this.positionMs, this.durationMs);
  }

  private toggle(): void {
    const player: media.AVPlayer | undefined = this.player;
    if (player === undefined) {
      return;
    }
    if (this.playing) {
      player.pause();
      return;
    }
    player.play().then(() => {
    }, () => {
    });
  }

  private seekTo(positionMs: number): void {
    const player: media.AVPlayer | undefined = this.player;
    if (player === undefined) {
      return;
    }
    try {
      player.seek(positionMs, media.SeekMode.SEEK_CLOSEST);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'seek failed');
    }
  }

  private release(): void {
    const player: media.AVPlayer | undefined = this.player;
    this.player = undefined;
    if (player !== undefined) {
      player.off('stateChange');
      player.off('timeUpdate');
      player.off('durationUpdate');
      player.release().then(() => {
      }, () => {
      });
    }
    if (this.descriptor >= 0) {
      try {
        fs.closeSync(this.descriptor);
      } catch (e) {
        hilog.debug(DOMAIN, TAG, 'could not close the audio file');
      }
      this.descriptor = -1;
    }
    const session: PlaybackSession | undefined = this.session;
    this.session = undefined;
    if (session !== undefined) {
      session.unbindControls();
    }
    mediaSession.release('audio');
  }
}
