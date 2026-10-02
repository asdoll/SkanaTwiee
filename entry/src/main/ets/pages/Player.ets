import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { media } from '@kit.MediaKit';
import { avSession } from '@kit.AVSessionKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Nav } from '../common/Nav';
import { Immersive, Insets } from '../common/Immersive';
import { PlayerParams } from '../model/Routes';
import { isSourceRendition, Quality, renditionHeight } from '../model/Quality';
import { PlaybackSession, mediaSession } from '../player/PlaybackSession';
import { DirectQuality, PlaybackRepository, PlaybackToken } from '../repository/PlaybackRepository';
import { VideoRepository } from '../repository/VideoRepository';
import { ChannelRepository } from '../repository/ChannelRepository';
import { ChannelInfo } from '../model/ChannelInfo';
import { ChatRepository, ChatStatus } from '../repository/ChatRepository';
import { ChatMessage, CommentPage } from '../model/ChatMessage';
import { AuthRepository } from '../repository/AuthRepository';
import { TwitchHelper } from '../util/TwitchHelper';
import { ChatPanel } from '../view/ChatPanel';
import { Video } from '../model/Video';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { DownloadEntry } from '../model/DownloadEntry';
import { Favourite } from '../model/Favourite';
import { FavouriteRepository } from '../repository/FavouriteRepository';
import { CommentRepository } from '../repository/CommentRepository';
import { DownloadProgress, DownloadRepository } from '../repository/DownloadRepository';
import { RateChoice, SettingsRepository } from '../repository/SettingsRepository';
import { ImageLoader } from '../util/ImageLoader';
import { LiveWindow, CAPSULE_ICON_SIZE } from '../player/LiveWindow';
import { MENU_WIDTH, MenuChoice, menuListHeight, PopupStateParam } from '../view/MenuChoice';

const DOMAIN: number = 0x0000;
const TAG: string = 'Player';
const HIDE_CONTROLS_DELAY_MS: number = 4500;
/**
 * How long a source switch is allowed to take before errors are believed again.
 * AVPlayer reports failures for the superseded source for a moment after a new
 * URI is assigned, so those reports must not be read as failures of the new one.
 */
const SOURCE_GRACE_MS: number = 12000;
/**
 * Wash over the whole video while the controls are up. Xtra tints only the top
 * and bottom strips; covering the frame instead keeps every icon legible over
 * any shot without two hard edges across the picture.
 */
const SCRIM_BACKGROUND: string = '#80000000';
const STATUS_LOADING: string = 'loading';
const STATUS_READY: string = 'ready';
const STATUS_ERROR: string = 'error';
/** Refill the comment queue once fewer than this many are waiting. */
const REPLAY_BUFFER_MIN: number = 40;
/** Lines kept in the panel before the oldest are dropped. */
const MAX_CHAT_LINES: number = 300;
/**
 * How often the media session is told where playback has got to. The control
 * centre and the lock screen draw their scrubber from that value and the system
 * does not interpolate it, so without a refresh the card sits at 0:00 for the
 * whole video.
 */
const PROGRESS_INTERVAL_MS: number = 1000;
/**
 * Horizontal travel that arms the seek swipe, in vp. Small enough for the
 * gesture to be recognised promptly, large enough that it cannot be mistaken for
 * the tap that toggles the controls.
 */
const SEEK_SWIPE_DISTANCE: number = 24;
/** Floor for the drag's seek rate, in ms per vp. */
const SEEK_MS_PER_VP_MIN: number = 500;
/** Ceiling for the drag's seek rate, in ms per vp. */
const SEEK_MS_PER_VP_MAX: number = 4000;
/** Divisor that scales the drag's seek rate to the video's own length. */
const SEEK_RATE_DIVISOR: number = 600;

/**
 * Preferred order for an automatic download: a rendition small enough to be
 * sensible, with the broadcaster's own source last since it can be enormous.
 */
function downloadRank(name: string): number {
  const ranks: string[] = ['720p60', '720p30', '480p30', '360p30', '1080p30', '1080p60',
    '160p30', '144p30'];
  const index: number = ranks.indexOf(name);
  if (index >= 0) {
    return index;
  }
  return ranks.length + (name === 'source' ? 1 : 0);
}
/**
 * How many renditions the automatic step down may try after failures before it
 * hands the decision back to the user. Each attempt costs a source-grace window,
 * so this stays small.
 */
const MAX_LADDER_STEPS: number = 2;

/** One row of the quality picker. */
class QualityOption {
  label: string = '';
  bitrate: number = 0;
  isAuto: boolean = true;
  /** Set when the option plays from a URL of its own. */
  url: string = '';
  /** Playlist name of the rendition, e.g. "720p60"; empty for "Auto". */
  name: string = '';

  constructor(label: string, bitrate: number, isAuto: boolean, url: string, name: string = '') {
    this.label = label;
    this.bitrate = bitrate;
    this.isAuto = isAuto;
    this.url = url;
    this.name = name;
  }
}

/**
 * VOD player.
 *
 * Replaces Xtra's Media3PlayerFragment (ExoPlayer + Media3) with the HarmonyOS
 * AVPlayer. The Twitch playback-token + usher URL flow is identical, and
 * quality selection uses AVPlayer's availableBitrates/setBitrate pair, which is
 * the platform equivalent of ExoPlayer's track selector.
 */
@Component
export struct PlayerPage {
  @State title: string = '';
  @State status: string = STATUS_LOADING;
  @State errorText: string = '';
  @State playing: boolean = false;
  @State buffering: boolean = false;
  @State positionMs: number = 0;
  @State durationMs: number = 0;
  @State showControls: boolean = true;
  @State showQuality: boolean = false;
  /** The three-dot menu; it holds the channel-page shortcut for now. */
  @State showMenu: boolean = false;
  @State qualityOptions: QualityOption[] = [];
  @State selectedQuality: string = 'Auto';
  /** Viewers currently watching a live stream. */
  @State liveViewers: number = 0;
  /**
   * A live stream's elapsed time, counted from the broadcast's own start time
   * rather than from when this screen opened.
   */
  @State liveUptime: string = '';
  /** The player opens inline (portrait); the fullscreen button goes landscape. */
  @State fullscreen: boolean = false;
  /** Status bar inset, so the inline video clears the clock. */
  @State topInset: number = 0;
  /** Playback rate; AVPlayer takes its own enum, see speedOptions(). */
  @State speedRate: number = 1;
  @State showSpeed: boolean = false;
  /** Bumped whenever chatMessages changes, so the panel re-reads the array. */
  @State chatVersion: number = 0;
  @State chatStatus: string = ChatStatus.IDLE;
  /** True when this video is bookmarked. */
  @State favourite: boolean = false;
  /** The download-quality sheet, which is what the menu's download entry opens. */
  @State showDownload: boolean = false;
  /** True while a horizontal seek swipe is dragging the progress bar. */
  @State seeking: boolean = false;
  /** Where the seek swipe has dragged playback to; the bar and preview follow it. */
  @State seekTargetMs: number = 0;
  /** Signed change the seek swipe has made so far, shown by the preview. */
  @State seekDeltaMs: number = 0;

  videoId: string = '';
  channelLogin: string = '';
  /** Live playback keys off channelLogin and has no duration or resume point. */
  isLive: boolean = false;
  masterUrl: string = '';
  player: media.AVPlayer | undefined = undefined;
  surfaceId: string = '';
  surfaceReady: boolean = false;
  scrubbing: boolean = false;
  /** Position playback was at when a horizontal seek swipe began. */
  seekStartMs: number = 0;
  parsedQualities: Quality[] = [];
  availableBitrates: number[] = [];
  hideTimer: number = -1;
  resumeMs: number = 0;
  appliedResume: boolean = false;
  started: boolean = false;
  playbackSession: PlaybackSession | undefined = undefined;
  /** Timestamp of the last progress publication; see publishProgress. */
  lastProgressAt: number = 0;
  /** Storyboard URL from the GQL video node; the source of the fallback links. */
  previewUrl: string = '';
  videoType: string = '';
  restrictedBitrates: string[] = [];
  /** True once playback has moved to preview-derived, token-free CDN links. */
  usingDirect: boolean = false;
  /**
   * 0 = fallback not tried, 1 = in flight, 2 = fallback is now in use,
   * 3 = fallback finished without success.
   */
  fallbackState: number = 0;
  directQualities: DirectQuality[] = [];
  /** True while a newly assigned source is still coming up. */
  switchGrace: boolean = false;
  graceTimer: number = -1;
  lastErrorCode: number = 0;
  /** URL currently backing "Auto"; usher master, or the source direct link. */
  activeUrl: string = '';
  /**
   * Rendition playback is pinned to, matched by playlist name; empty while the
   * automatic selector is still in charge.
   */
  currentQualityName: string = '';
  /** True once the Me tab's default quality has had its say for this video. */
  private defaultQualityApplied: boolean = false;
  /** True once the quality has been picked by hand, which settles the matter. */
  private handPickedQuality: boolean = false;
  /**
   * Renditions the automatic step down has already tried and failed to play, so
   * the walk downwards never repeats one. Cleared by a manual pick or a retry.
   */
  failedQualityNames: string[] = [];
  /** Automatic step downs spent on this source; bounded by MAX_LADDER_STEPS. */
  ladderSteps: number = 0;
  /** URL to hand to the player once reset() has returned it to 'idle'. */
  pendingUrl: string = '';
  pendingResume: number = 0;
  /** GQL start time of the live broadcast; the live clock counts from here. */
  liveStartedAt: string = '';
  uptimeTimer: number = -1;
  /** Chat lines already shown, and the replay's queue of not-yet-due ones. */
  @State chatMessages: ChatMessage[] = [];
  replayBuffer: ChatMessage[] = [];
  replayCursor: string = '';
  replayHasMore: boolean = true;
  replayLoaded: boolean = false;
  replayTimer: number = -1;
  /**
   * The whole stored replay of a downloaded video, and how far through it
   * playback has got. Empty while streaming, where comments are paged instead.
   */
  offlineComments: ChatMessage[] = [];
  offlineCommentIndex: number = 0;
  /** Channel id for the picker's channel emote set. */
  chatChannelId: string = '';
  metadataPromise: Promise<void> | undefined = undefined;
  xController: XComponentController = new XComponentController();
  /** Sandbox path when this is a downloaded file played offline; '' otherwise. */
  localPath: string = '';
  /** Descriptor of the local file, held open for as long as it is playing. */
  localFd: number = -1;
  /** Channel avatar URL; the media session and the live window both publish it. */
  channelImageURL: string = '';
  /** Channel name as shown to the user; the live window's headline. */
  channelName: string = '';
  /** Full video record, so a download can store everything its list shows. */
  videoMeta: Video | undefined = undefined;

  aboutToDisappear(): void {
    this.clearHideTimer();
    this.clearGraceTimer();
    this.stopUptimeTimer();
    this.stopReplay();
    ChatRepository.disconnect();
    // The live view belongs to this playback session, not to the app.
    LiveWindow.stop();
    if (this.localFd >= 0) {
      try {
        fs.closeSync(this.localFd);
      } catch (e) {
        hilog.debug(DOMAIN, TAG, 'could not close the local file');
      }
      this.localFd = -1;
    }
    // A live stream has no resume point; a downloaded file does, and it has the
    // id to store it under.
    if (!this.isLive && this.videoId.length > 0) {
      PlaybackRepository.savePosition(this.videoId, this.positionMs, this.durationMs);
    }
    this.releasePlayer();
    this.stopPlaybackSession();
    this.applyWindow(false);
  }

  build() {
    NavDestination() {
      this.surface()
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.onParamsReady(context);
    })
  }

  private onParamsReady(context: NavDestinationContext): void {
    const params: PlayerParams | undefined = context.pathInfo.param as PlayerParams | undefined;
    if (params !== undefined) {
      this.videoId = params.videoId !== undefined ? params.videoId : '';
      this.title = params.title !== undefined ? params.title : '';
      this.channelLogin = params.channelLogin !== undefined ? params.channelLogin : '';
      this.isLive = params.isLive === true;
      this.localPath = params.localPath !== undefined ? params.localPath : '';
      this.channelImageURL = params.channelImageURL !== undefined ? params.channelImageURL : '';
    }
    this.favourite = FavouriteRepository.isFavourite(this.videoId);
    // The Me tab's default rate, unless this is a live stream: there is no rate
    // control on a live one, and playing a broadcast fast-forward helps nobody.
    this.speedRate = this.isLive ? 1 : SettingsRepository.rate();
    this.applyWindow(false);
    this.setupInsets();
    if (this.isLive) {
      this.startUptimeTimer();
      this.startLiveChat();
    } else if (this.localPath.length === 0) {
      // Comments only start once the metadata says which broadcast this is; a
      // downloaded file loads its stored replay first (see setupLocalFile).
      this.resetReplay(0);
    }
    this.setup();
  }

  private async setupInsets(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const insets: Insets = await Immersive.enable(context);
    this.topInset = this.getUIContext().px2vp(insets.top);
  }

  @Builder
  surface() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.fullscreen) {
        this.videoLayers()
      } else {
        Column() {
          Column() {
            this.videoLayers()
          }
          .width('100%')
          .aspectRatio(16 / 9)
          .backgroundColor(Color.Black)

          // Everything below the video is the comments: live chat can also be
          // written to, a VOD's replay is read-only.
          ChatPanel({
            lines: $chatMessages,
            version: this.chatVersion,
            canSend: this.isLive && AuthRepository.isLoggedIn(),
            channelId: this.chatChannelId,
            statusText: this.chatStatusText(),
            onSend: (text: string): void => {
              this.sendChat(text);
            }
          })
            .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.topInset })
        .backgroundColor($r('app.color.background'))
      }

      if (this.showDownload) {
        this.downloadSheet()
      }

      if (this.showMenu) {
        this.moreMenu()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  /**
   * The video surface and every overlay that belongs to it. Its root is a single
   * Stack so the absolutely positioned bars keep one positioning context, both
   * inline (16:9) and fullscreen.
   */
  @Builder
  videoLayers() {
    Stack({ alignContent: Alignment.Bottom }) {
      XComponent({ type: XComponentType.SURFACE, controller: this.xController })
        .onLoad(() => {
          this.surfaceId = this.xController.getXComponentSurfaceId();
          this.surfaceReady = true;
          this.attachSurface();
          this.startPlayback();
        })
        .onDestroy(() => {
          this.surfaceReady = false;
        })
        .width('100%')
        .height('100%')

      // Tap target for toggling the controls, and the seek surface while they
      // are up: a tap brings the bars in or out, a horizontal drag moves the bar.
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.toggleControls();
        })
        .gesture(
          PanGesture({ direction: PanDirection.Horizontal, distance: SEEK_SWIPE_DISTANCE })
            .onActionStart(() => {
              this.beginSeekSwipe();
            })
            .onActionUpdate((event: GestureEvent) => {
              this.updateSeekSwipe(event.offsetX);
            })
            .onActionEnd(() => {
              this.endSeekSwipe();
            })
            .onActionCancel(() => {
              this.cancelSeekSwipe();
            })
        )

      // The control wash. It goes under the loading and error layers so those
      // keep full contrast, and lets taps through to the target above.
      if (this.showControls && this.status === STATUS_READY) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(SCRIM_BACKGROUND)
          .hitTestBehavior(HitTestMode.Transparent)
      }

      if (this.status === STATUS_LOADING) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color($r('app.color.accent'))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }

      if (this.buffering && this.status === STATUS_READY) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color($r('app.color.accent'))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .hitTestBehavior(HitTestMode.Transparent)
      }

      if (this.status === STATUS_ERROR) {
        Column() {
          Text($r('app.string.load_failed'))
            .fontSize(16)
            .fontColor(Color.White)
          Text(this.errorText)
            .fontSize(13)
            .fontColor('#B3FFFFFF')
            .margin({ top: 8 })
            .maxLines(3)
            .textAlign(TextAlign.Center)
          Text($r('app.string.error_hint'))
            .fontSize(12)
            .fontColor('#99FFFFFF')
            .margin({ top: 8 })
            .maxLines(2)
            .textAlign(TextAlign.Center)
          Button($r('app.string.retry'))
            .fontSize(14)
            .backgroundColor($r('app.color.accent'))
            .fontColor(Color.White)
            .margin({ top: 18 })
            .onClick(() => {
              this.retry();
            })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .padding(32)
        // A failure must not take the page away: the wash is translucent and
        // lets taps through, so the video area and the bars stay usable.
        .backgroundColor('#CC000000')
        .hitTestBehavior(HitTestMode.Transparent)
      }

      // The error state keeps its bars too - the quality menu behind that
      // button is the manual way out of a source the automatic step down
      // could not rescue. Only the big play button is dropped there, since
      // there is nothing playing to pause.
      // A download belongs to the downloads page, which shows its progress; the
      // playback screen stays about playback.
      if (this.showControls && this.status !== STATUS_LOADING) {
        this.topBar()
        // The seek readout takes the big play button's place while the bar is
        // being dragged, so the two never sit on top of one another.
        if (this.status === STATUS_READY && !this.seeking) {
          this.centerControls()
        }
        this.bottomBar()
      }

      if (this.seeking) {
        this.seekPreview()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
  }

  /* ------------------------------ UI ------------------------------ */

  /** The rate itself is the label, which says more than any icon would. */
  @Builder
  speedButton() {
    Button({ type: ButtonType.Circle }) {
      Text(SettingsRepository.rateLabel(this.speedRate))
        .fontSize(13)
        .fontColor(Color.White)
    }
    .width(44)
    .height(40)
    .backgroundColor(Color.Transparent)
    .onClick(() => {
      this.openSpeed();
    })
    .bindPopup(this.showSpeed, {
      builder: (): void => {
        this.speedPopup()
      },
      placement: Placement.TopLeft,
      autoCancel: true,
      onStateChange: (event: PopupStateParam): void => {
        if (!event.isVisible) {
          this.closeSpeed();
        }
      }
    })
  }

  /**
   * The playback rates, as one row each, ticked where it stands.
   *
   * A popup's own card, so it carries no placement of its own: the popup is
   * anchored to the button that opens it (see speedButton).
   */
  @Builder
  speedPopup() {
    Column() {
      List() {
        ForEach(SettingsRepository.rates(), (choice: RateChoice) => {
          ListItem() {
            MenuChoice({
              label: choice.label,
              selected: this.speedRate === choice.rate,
              onTap: (): void => {
                this.applySpeed(choice);
              }
            })
          }
        }, (choice: RateChoice) => choice.label)
      }
      .width('100%')
      .scrollBar(BarState.Off)
      .height(menuListHeight(SettingsRepository.rates().length))
    }
    .width(MENU_WIDTH)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(12)
    .clip(true)
  }

  private openSpeed(): void {
    this.clearHideTimer();
    this.closeOthers(2);
    this.showSpeed = true;
  }

  private closeSpeed(): void {
    this.showSpeed = false;
    this.scheduleHideTimer();
  }

  private applySpeed(option: RateChoice): void {
    this.speedRate = option.rate;
    this.closeSpeed();
    this.setPlayerSpeed(option);
  }

  /**
   * Pushes the selected rate to the player.
   *
   * Called again once a new source is playing, because a source switch resets the
   * rate back to 1x.
   */
  private setPlayerSpeed(option: RateChoice): void {
    const player: media.AVPlayer | undefined = this.player;
    if (player === undefined || this.speedRate === 1) {
      return;
    }
    try {
      player.setSpeed(option.speed);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'setSpeed failed');
    }
  }

  private reapplySpeed(): void {
    if (this.speedRate === 1) {
      return;
    }
    const options: RateChoice[] = SettingsRepository.rates();
    for (let i = 0; i < options.length; i++) {
      if (options[i].rate === this.speedRate) {
        this.setPlayerSpeed(options[i]);
        return;
      }
    }
  }

  /** Chromeless icon button; both bars are built out of these. */
  @Builder
  iconButton(symbol: Resource, onTap: () => void) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(symbol)
        .fontSize(22)
        .fontColor([Color.White])
    }
    .width(40)
    .height(40)
    .backgroundColor(Color.Transparent)
    .onClick(() => {
      onTap();
    })
  }

  @Builder
  topBar() {
    Row() {
      Button({ type: ButtonType.Circle }) {
        Text('\u2039')
          .fontSize(26)
          .fontColor(Color.White)
      }
      .width(40)
      .height(40)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        Nav.back();
      })

      Column() {
        Text(this.title)
          .fontSize(15)
          .fontColor(Color.White)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (this.channelLogin.length > 0) {
          Text(this.channelLogin)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 10 })

      // No bare "ellipsis" symbol exists in the system set; the circled one is
      // the closest to a three-dot menu button.
      this.iconButton($r('sys.symbol.ellipsis_circle'), () => {
        this.openMenu();
      })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .position({ x: 0, y: 0 })
  }

  @Builder
  centerControls() {
    Row() {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph(this.playing ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
          .fontSize(46)
          .fontColor([Color.White])
      }
      .width(72)
      .height(72)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.togglePlay();
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .hitTestBehavior(HitTestMode.Transparent)
  }

  /**
   * The seek readout shown while a horizontal drag is moving the bar: where the
   * drag has got to, and how far it has moved from where playback was.
   *
   * Purely a readout, so every touch belongs to the surface underneath and the
   * gesture that opened it keeps receiving the drag.
   */
  @Builder
  seekPreview() {
    Column() {
      Column({ space: 2 }) {
        Text(TwitchHelper.formatPlaybackTime(this.seekTargetMs))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)

        Text(this.seekDeltaLabel())
          .fontSize(13)
          .fontColor($r('app.color.accent'))
      }
      .padding({ left: 18, right: 18, top: 10, bottom: 10 })
      .backgroundColor('#B3000000')
      .borderRadius(12)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .hitTestBehavior(HitTestMode.None)
  }

  /**
   * Bottom controls.
   *
   * A VOD keeps the progress bar, with quality on its left and fullscreen on its
   * right. A live stream has no progress to show, so its single row carries the
   * refresh, the quality, the broadcast's real elapsed time and the viewers.
   */
  @Builder
  bottomBar() {
    Column() {
      if (this.isLive) {
        Row() {
          this.iconButton($r('sys.symbol.arrow_clockwise'), () => {
            this.refreshLive();
          })

          this.qualityButton()

          Blank()

          Text(this.liveUptime)
            .fontSize(13)
            .fontColor(Color.White)

          if (this.liveViewers > 0) {
            Text(TwitchHelper.formatCount(this.liveViewers, true))
              .fontSize(13)
              .fontColor(Color.White)
              .margin({ left: 12 })
            Text($r('app.string.viewers'))
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .margin({ left: 4 })
          }

          this.iconButton($r('sys.symbol.arrow_up_left_and_arrow_down_right'), () => {
            this.toggleFullscreen();
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      } else {
        Row() {
          this.qualityButton()

          this.speedButton()

          Blank()

          this.iconButton(this.fullscreen
            ? $r('sys.symbol.arrow_down_right_and_arrow_up_left')
            : $r('sys.symbol.arrow_up_left_and_arrow_down_right'), () => {
            this.toggleFullscreen();
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Row() {
          Text(TwitchHelper.formatPlaybackTime(this.positionMs))
            .fontSize(12)
            .fontColor(Color.White)
            .width(56)

          Slider({
            value: this.positionMs,
            min: 0,
            max: this.durationMs > 0 ? this.durationMs : 1,
            step: 1000,
            style: SliderStyle.OutSet
          })
            .selectedColor($r('app.color.accent'))
            .trackColor('#55FFFFFF')
            .layoutWeight(1)
            .onChange((value: number, mode: SliderChangeMode) => {
              this.onScrub(value, mode);
            })

          Text(TwitchHelper.formatPlaybackTime(this.durationMs))
            .fontSize(12)
            .fontColor(Color.White)
            .width(56)
            .textAlign(TextAlign.End)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 6, bottom: 10 })
  }

  /**
   * The three-dot menu: the channel page, saving to the library, and downloading.
   * Tapping outside dismisses it.
   */
  @Builder
  menuRow(symbol: Resource, label: ResourceStr, onTap: () => void) {
    Row() {
      SymbolGlyph(symbol)
        .fontSize(18)
        .fontColor([$r('app.color.text_primary')])
      Text(label)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: 10 })
    }
    .width('100%')
    .padding({ left: 14, right: 20, top: 13, bottom: 13 })
    .onClick(() => {
      onTap();
    })
  }

  /** The layer that closes a menu when anything outside it is tapped. */
  @Builder
  menuDismiss(onTap: () => void) {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        onTap();
      })
  }

  /**
   * The gear button and the quality menu it opens.
   *
   * The menu is bound to the button rather than placed by hand: the framework
   * hangs it off the button's own corner and moves it when it would not fit,
   * which is what keeps it beside the button in the inline player and in
   * fullscreen alike - and it knows where the bar ended up, which the page does
   * not.
   */
  @Builder
  qualityButton() {
    Column() {
      this.iconButton($r('sys.symbol.gearshape_fill'), () => {
        this.openQuality();
      })
    }
    .bindPopup(this.showQuality, {
      builder: (): void => {
        this.qualityPopup()
      },
      placement: Placement.TopLeft,
      autoCancel: true,
      onStateChange: (event: PopupStateParam): void => {
        if (!event.isVisible) {
          this.closeQuality();
        }
      }
    })
  }

  /**
   * The three-dot menu: the channel page, the bookmark, and the download.
   * Tapping outside dismisses it.
   */
  @Builder
  moreMenu() {
    Stack({ alignContent: Alignment.TopEnd }) {
      this.menuDismiss(() => {
        this.closeMenu();
      })

      Column() {
        this.menuRow($r('sys.symbol.person_crop_circle_fill'), $r('app.string.channel_page'),
          (): void => {
            this.openChannelPage();
          })

        // Favouriting and downloading are VOD ideas: a live stream has no id to
        // keep and nothing to store, and a downloaded file is already local.
        if (this.videoId.length > 0 && this.localPath.length === 0) {
          this.menuRow(this.favourite ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'),
            this.favourite ? $r('app.string.in_favourites') : $r('app.string.add_favourite'),
            (): void => {
              this.toggleFavourite();
            })

          if (DownloadRepository.isActive(this.videoId)) {
            // Only a reminder that one is running - the progress belongs to the
            // downloads page - and tapping it stops the transfer.
            this.menuRow($r('sys.symbol.square_and_arrow_down'), $r('app.string.downloading'),
              (): void => {
                DownloadRepository.cancel(this.videoId);
              })
          } else if (!this.isLive) {
            this.menuRow($r('sys.symbol.square_and_arrow_down'), $r('app.string.download_video'),
              (): void => {
                this.openDownload();
              })
          }
        }
      }
      .width(210)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(12)
      // Just under the three-dot button, which sits in the top bar.
      .margin({ top: this.fullscreen ? 52 : this.topInset + 52, right: 12 })
      .shadow({ radius: 16, color: '#000000' })
    }
    .width('100%')
    .height('100%')
    // Fades the whole overlay, dismiss layer included.
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.FastOutSlowIn }))
  }

  @Builder
  qualityPopup() {
    Column() {
      List() {
        ForEach(this.qualityOptions, (option: QualityOption) => {
          ListItem() {
            MenuChoice({
              label: option.label,
              selected: this.selectedQuality === option.label,
              onTap: (): void => {
                // A rendition picked by hand outranks the setting from the Me tab.
                this.handPickedQuality = true;
                this.selectQuality(option);
              }
            })
          }
        }, (option: QualityOption) => option.label)
      }
      .width('100%')
      .scrollBar(BarState.Off)
      .height(menuListHeight(this.qualityOptions.length))
    }
    .width(MENU_WIDTH)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(12)
    .clip(true)
  }

  /* --------------------------- playback --------------------------- */

  private async setup(): Promise<void> {
    if (this.localPath.length > 0) {
      await this.setupLocalFile();
      return;
    }
    if (this.isLive) {
      await this.setupLive();
      return;
    }
    if (this.videoId.length === 0) {
      this.status = STATUS_ERROR;
      this.errorText = 'No video id was provided.';
      return;
    }
    try {
      const token: PlaybackToken | undefined = await PlaybackRepository.accessToken(this.videoId);
      this.restrictedBitrates = token !== undefined ? token.restrictedBitrates : [];
      this.masterUrl = PlaybackRepository.buildVodUrl(this.videoId, token);
      this.activeUrl = this.masterUrl;
      this.resumeMs = PlaybackRepository.savedPosition(this.videoId);
      this.loadQualities();
      // Needed as soon as the usher path fails: it carries the storyboard URL
      // that the direct CDN links are derived from.
      this.metadataPromise = this.loadMetadata();
      await this.startPlaybackSession();
      this.publishNowPlaying();
      await this.createPlayer();
    } catch (e) {
      const err = e as BusinessError;
      this.status = STATUS_ERROR;
      this.errorText = `Could not start playback (${err.code !== undefined ? err.code : 'unknown'}).`;
    }
  }

  /**
   * Offline playback of a downloaded file.
   *
   * There is nothing to resolve and nothing to choose: the file is already on
   * disk, so the player is handed the descriptor directly (see startPlayback)
   * and the title comes from the library entry that launched this page.
   */
  private async setupLocalFile(): Promise<void> {
    this.status = STATUS_LOADING;
    if (this.title.length === 0) {
      this.title = this.channelLogin.length > 0 ? this.channelLogin : 'Download';
    }
    // The replay was downloaded with the video, so an offline viewing still has
    // the comments - there is nothing to fetch and nothing to page.
    this.offlineComments = CommentRepository.load(this.localPath);
    if (this.offlineComments.length > 0) {
      hilog.info(DOMAIN, TAG, 'replaying %{public}d stored comments', this.offlineComments.length);
    }
    await this.startPlaybackSession();
    await this.createPlayer();
    this.publishNowPlaying();
    this.resetReplay(PlaybackRepository.savedPosition(this.videoId));
  }

  /**
   * Live playback: same AVPlayer pipeline, but the source is the channel's
   * playlist and there is no storyboard fallback to retreat to.
   */
  private async setupLive(): Promise<void> {
    if (this.channelLogin.length === 0) {
      this.status = STATUS_ERROR;
      this.errorText = 'No channel was provided.';
      return;
    }
    if (this.title.length === 0) {
      this.title = this.channelLogin;
    }
    // Viewers and the broadcast's real start time; playback does not wait on it.
    this.loadLiveInfo();
    try {
      const token: PlaybackToken | undefined =
        await PlaybackRepository.liveAccessToken(this.channelLogin);
      this.masterUrl = PlaybackRepository.buildLiveUrl(this.channelLogin, token);
      this.activeUrl = this.masterUrl;
      this.loadQualities();
      await this.startPlaybackSession();
      this.publishNowPlaying();
      await this.createPlayer();
    } catch (e) {
      const err = e as BusinessError;
      this.status = STATUS_ERROR;
      this.errorText = `Could not start playback (${err.code !== undefined ? err.code : 'unknown'}).`;
    }
  }

  /**
   * Live metadata.
   *
   * The elapsed clock has to show how long the broadcast has been running, so it
   * counts from the stream's own createdAt instead of from the moment playback
   * started here - opening a stream that began hours ago must not read 0:00.
   */
  private async loadLiveInfo(): Promise<void> {
    try {
      const info: ChannelInfo | undefined = await ChannelRepository.channelInfo(this.channelLogin);
      if (info !== undefined) {
        this.liveViewers = info.live.viewersCount;
        if (info.live.createdAt.length > 0) {
          this.liveStartedAt = info.live.createdAt;
        }
        if (this.chatChannelId.length === 0) {
          this.chatChannelId = info.live.channelId;
        }
        if (this.title.length === 0 && info.live.title.length > 0) {
          this.title = info.live.title;
        }
        this.channelImageURL = info.profileImageURL;
        this.channelName = info.displayName;
        // Live streams get their live view as soon as the channel is known, and
        // the avatar is available on the same response.
        this.publishNowPlaying();
      }
    } catch (e) {
      // Only the clock and the viewer count depend on this.
    }
    this.tickUptime();
  }

  private startUptimeTimer(): void {
    if (this.uptimeTimer !== -1) {
      return;
    }
    this.uptimeTimer = setInterval(() => {
      this.tickUptime();
    }, 1000);
  }

  private stopUptimeTimer(): void {
    if (this.uptimeTimer !== -1) {
      clearInterval(this.uptimeTimer);
      this.uptimeTimer = -1;
    }
  }

  private tickUptime(): void {
    const uptime: string = TwitchHelper.formatUptime(this.liveStartedAt);
    if (uptime.length > 0) {
      this.liveUptime = uptime;
    } else if (this.positionMs > 0) {
      // The start time is not known yet; counting from playback beats showing 0.
      this.liveUptime = TwitchHelper.formatPlaybackTime(this.positionMs);
    } else {
      this.liveUptime = '';
    }
  }

  /** Reloads the live metadata and reconnects, the way a player refresh does. */
  private refreshLive(): void {
    this.loadLiveInfo();
    this.retry();
  }

  private openChannelPage(): void {
    this.closeMenu();
    if (this.channelLogin.length === 0) {
      return;
    }
    Nav.openChannel(this.channelLogin, this.channelLogin);
  }

  /* ------------------------------ chat ------------------------------ */

  /** Joins the channel's IRC room; live chat can also be written to. */
  private startLiveChat(): void {
    if (this.channelLogin.length === 0) {
      return;
    }
    ChatRepository.connect(this.channelLogin, (message: ChatMessage) => {
      // The gateway's callback does not run on the UI thread, so the state change
      // is handed back to it - ArkUI only redraws for updates made there.
      this.getUIContext().runScopedTask(() => {
        this.chatMessages.push(message);
        this.chatVersion++;
      });
    }, (status: string) => {
      this.chatStatus = status;
    });
  }

  /**
   * Restarts a VOD's comment replay at a playback position.
   *
   * A comment belongs to a moment of the video, so the replay has to be reloaded
   * whenever playback jumps somewhere else - exactly what Xtra's
   * ChatReplayManager does when the player seeks.
   */
  private resetReplay(positionMs: number): void {
    // Cleared in place: the panel holds this array by reference, so replacing it
    // would leave the panel reading a list nothing is appended to.
    this.chatMessages.length = 0;
    this.replayBuffer = [];
    this.replayCursor = '';
    this.replayHasMore = true;
    this.replayLoaded = false;
    this.chatStatus = ChatStatus.IDLE;
    this.chatVersion++;
    const positionSeconds: number = Math.floor(positionMs / 1000);
    if (this.offlineComments.length > 0) {
      // A stored replay is complete, so a seek just moves the cursor in it.
      this.offlineCommentIndex = 0;
      while (this.offlineCommentIndex < this.offlineComments.length
        && this.offlineComments[this.offlineCommentIndex].offsetSeconds < positionSeconds) {
        this.offlineCommentIndex++;
      }
      this.replayLoaded = true;
      this.replayHasMore = false;
      this.startReplayTimer();
      this.tickReplay();
      return;
    }
    this.startReplayTimer();
    this.loadReplayPage(positionSeconds);
  }

  private startReplayTimer(): void {
    if (this.replayTimer !== -1) {
      return;
    }
    this.replayTimer = setInterval(() => {
      this.tickReplay();
    }, 1000);
  }

  private stopReplay(): void {
    if (this.replayTimer !== -1) {
      clearInterval(this.replayTimer);
      this.replayTimer = -1;
    }
  }

  /** First page after a seek: Twitch pages by offset, not by cursor. */
  private async loadReplayPage(offsetSeconds: number): Promise<void> {
    if (this.videoId.length === 0) {
      return;
    }
    try {
      const page: CommentPage = await ChatRepository.videoComments(this.videoId, offsetSeconds, '');
      this.replayCursor = page.cursor;
      this.replayHasMore = page.hasNextPage;
      this.replayBuffer = page.messages;
      this.replayLoaded = true;
      hilog.info(DOMAIN, TAG, 'replay from %{public}d: %{public}d comments, more=%{public}s',
        offsetSeconds, page.messages.length, `${page.hasNextPage}`);
      this.tickReplay();
    } catch (e) {
      this.replayLoaded = true;
      this.chatStatus = ChatStatus.FAILED;
      hilog.warn(DOMAIN, TAG, 'replay failed: %{public}s', JSON.stringify(e));
    }
  }

  private async loadReplayMore(): Promise<void> {
    if (this.videoId.length === 0 || !this.replayHasMore || this.offlineComments.length > 0) {
      return;
    }
    try {
      const page: CommentPage = await ChatRepository.videoComments(this.videoId, 0, this.replayCursor);
      this.replayCursor = page.cursor;
      this.replayHasMore = page.hasNextPage;
      for (let i = 0; i < page.messages.length; i++) {
        this.replayBuffer.push(page.messages[i]);
      }
      this.tickReplay();
    } catch (e) {
      this.replayHasMore = false;
    }
  }

  /** Releases the comments playback has reached, and keeps the queue fed. */
  private tickReplay(): void {
    const positionSeconds: number = this.positionMs / 1000;
    let added: boolean = false;
    if (this.offlineComments.length > 0) {
      // A downloaded replay is already whole, so it is simply walked through.
      while (this.offlineCommentIndex < this.offlineComments.length
        && this.offlineComments[this.offlineCommentIndex].offsetSeconds <= positionSeconds) {
        this.chatMessages.push(this.offlineComments[this.offlineCommentIndex]);
        this.offlineCommentIndex++;
        added = true;
      }
    } else {
      while (this.replayBuffer.length > 0 && this.replayBuffer[0].offsetSeconds <= positionSeconds) {
        const next: ChatMessage | undefined = this.replayBuffer.shift();
        if (next === undefined) {
          break;
        }
        this.chatMessages.push(next);
        added = true;
      }
    }
    if (added) {
      // Bounded: a long broadcast produces far more lines than a panel can hold.
      while (this.chatMessages.length > MAX_CHAT_LINES) {
        this.chatMessages.shift();
      }
      this.chatVersion++;
    }
    if (this.offlineComments.length === 0 && this.replayLoaded && this.replayHasMore
      && this.replayBuffer.length < REPLAY_BUFFER_MIN) {
      this.loadReplayMore();
    }
  }

  private async sendChat(text: string): Promise<void> {
    if (ChatRepository.sendMessage(text)) {
      return;
    }
    this.chatStatus = ChatStatus.FAILED;
  }

  /** What the comment panel says above the messages, if anything. */
  private chatStatusText(): string {
    if (!this.isLive) {
      return '';
    }
    if (this.chatStatus === ChatStatus.CONNECTING) {
      return 'Connecting to chat\u2026';
    }
    if (this.chatStatus === ChatStatus.FAILED) {
      return 'Chat is unavailable.';
    }
    if (!AuthRepository.isLoggedIn()) {
      return 'Log in with Twitch to send messages.';
    }
    return '';
  }

  private async loadMetadata(): Promise<void> {
    try {
      const video: Video | undefined = await VideoRepository.videoDetails(this.videoId);
      if (video !== undefined) {
        if (this.title.length === 0) {
          this.title = video.title;
        }
        if (this.durationMs === 0 && video.durationSeconds > 0) {
          this.durationMs = video.durationSeconds * 1000;
        }
        if (this.channelLogin.length === 0) {
          this.channelLogin = video.channelLogin;
        }
        this.previewUrl = video.animatedPreviewURL;
        this.videoType = video.type;
        this.videoMeta = video;
        if (this.channelImageURL.length === 0) {
          this.channelImageURL = video.channelImageURL;
        }
        if (this.channelName.length === 0) {
          this.channelName = video.channelName;
        }
        const session: PlaybackSession | undefined = this.playbackSession;
        if (session !== undefined) {
          session.updateMetadata(this.title, this.channelLogin, this.durationMs);
        }
        // The avatar only arrives with this query, so the live window gets its
        // picture here rather than at setup time.
        this.publishNowPlaying();
      }
    } catch (e) {
      // Metadata is not required for playback; only the fallback needs it.
    }
  }

  private async loadQualities(): Promise<void> {
    try {
      this.parsedQualities = await PlaybackRepository.loadQualities(this.masterUrl);
      this.buildQualityOptions();
    } catch (e) {
      hilog.debug(DOMAIN, TAG, 'quality list unavailable');
    }
  }

  /**
   * Opens on the quality chosen in the Me tab.
   *
   * The choice is matched against the very list the quality menu offers, so the
   * setting works everywhere picking by hand works: the usher ladder, the CDN
   * links playback falls back to, and the bitrates the player itself reports. It
   * is matched on resolution and not on the playlist's name for it - a broadcast
   * that calls a rendition "720p60" and one that calls it "720p" are the same
   * 720p, and the frame rate was never part of the choice.
   *
   * The choice is a preference, not a promise: a rendition this broadcast does
   * not carry leaves the player on Auto rather than failing, so one setting suits
   * every video afterwards. Nothing matching yet is not that case - the list is
   * rebuilt as more is learned about the source, and the next attempt may find
   * it - so the setting is only recorded as applied once it has been. A quality
   * picked by hand in the meantime wins outright.
   */
  private applyDefaultQuality(): void {
    if (this.defaultQualityApplied || this.handPickedQuality) {
      return;
    }
    const wanted: string = SettingsRepository.quality();
    if (wanted.length === 0) {
      return;
    }
    const option: QualityOption | undefined = this.defaultQualityOption(wanted);
    if (option === undefined) {
      return;
    }
    this.defaultQualityApplied = true;
    hilog.info(DOMAIN, TAG, 'opening at the default quality %{public}s', option.label);
    this.selectQuality(option);
  }

  /** The offered option that is the quality asked for, when it is on the list. */
  private defaultQualityOption(wanted: string): QualityOption | undefined {
    const source: boolean = wanted === SettingsRepository.SOURCE;
    const height: number = renditionHeight(wanted);
    let best: QualityOption | undefined = undefined;
    for (let i = 0; i < this.qualityOptions.length; i++) {
      const option: QualityOption = this.qualityOptions[i];
      // Auto is not a rendition, and an option with no rendition name is a bare
      // bitrate the player reported - neither can be pinned by hand either.
      if (option.isAuto || option.name.length === 0) {
        continue;
      }
      const matches: boolean = source
        ? isSourceRendition(option.name) : renditionHeight(option.name) === height;
      if (!matches) {
        continue;
      }
      // Both frame rates of one resolution can be on offer; the faster one is the
      // better picture.
      if (best === undefined || option.bitrate > best.bitrate) {
        best = option;
      }
    }
    return best;
  }

  private async createPlayer(): Promise<void> {
    const player: media.AVPlayer = await media.createAVPlayer();
    this.player = player;

    player.on('error', (err: BusinessError) => {
      this.onPlaybackError(err.code);
    });
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
      // A live playlist reports no meaningful duration, and the bar shows a
      // LIVE badge instead of a scrubber.
      if (duration > 0 && !this.isLive) {
        this.durationMs = duration;
      }
    });
    player.on('seekDone', (position: number) => {
      this.positionMs = position;
    });
    player.on('availableBitrates', (bitrates: number[]) => {
      this.availableBitrates = bitrates;
      this.buildQualityOptions();
    });
    player.on('bufferingUpdate', (infoType: media.BufferingInfoType, value: number) => {
      this.buffering = infoType === media.BufferingInfoType.BUFFERING_START;
      if (this.playing) {
        this.syncSessionState(this.buffering ? 'buffering' : 'playing');
      }
    });

    this.startPlayback();
  }

  /**
   * Hands the media source to the player only once both the player and the
   * XComponent surface exist; assigning the surface after playback has begun is
   * not guaranteed to render video.
   */
  private startPlayback(): void {
    const player: media.AVPlayer | undefined = this.player;
    if (player === undefined || this.started || !this.surfaceReady
      || this.surfaceId.length === 0) {
      return;
    }
    if (this.localPath.length > 0) {
      this.startLocalPlayback(player);
      return;
    }
    if (this.activeUrl.length === 0) {
      return;
    }
    this.started = true;
    player.url = this.activeUrl;
  }

  /**
   * Hands the player a downloaded file.
   *
   * A local file goes in by descriptor rather than by URL: a sandbox path is not
   * something AVPlayer can resolve on its own, and the descriptor keeps the file
   * open for the whole session.
   */
  private startLocalPlayback(player: media.AVPlayer): void {
    try {
      const info: fs.Stat = fs.statSync(this.localPath);
      const file = fs.openSync(this.localPath, fs.OpenMode.READ_ONLY);
      this.localFd = file.fd;
      this.started = true;
      player.fdSrc = { fd: file.fd, offset: 0, length: info.size };
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'could not open the downloaded file');
      this.failPlayback(-1);
      this.errorText = 'The downloaded file could not be opened.';
    }
  }

  private onStateChange(state: string): void {
    const player: media.AVPlayer | undefined = this.player;
    if (player === undefined) {
      return;
    }
    if (state === 'idle') {
      // A reset() has completed; only now is assigning a new source allowed.
      this.applyPendingUrl();
      return;
    }
    if (state === 'initialized') {
      this.attachSurface();
      player.prepare().then(() => {
      }, (err: BusinessError) => {
        this.onPlaybackError(err.code);
      });
    } else if (state === 'prepared') {
      this.attachSurface();
      this.status = STATUS_READY;
      player.play().then(() => {
      }, (err: BusinessError) => {
        this.onPlaybackError(err.code);
      });
    } else if (state === 'playing') {
      this.status = STATUS_READY;
      this.playing = true;
      this.buffering = false;
      this.endSourceGrace();
      // A fresh source starts at 1x, so the chosen rate is pushed again here.
      this.reapplySpeed();
      if (!this.appliedResume && this.resumeMs > 0) {
        this.appliedResume = true;
        this.seekTo(this.resumeMs);
      }
      this.scheduleHideTimer();
    } else if (state === 'paused') {
      this.playing = false;
      this.showControls = true;
      this.clearHideTimer();
    } else if (state === 'completed') {
      this.playing = false;
      this.showControls = true;
      this.clearHideTimer();
    } else if (state === 'error') {
      this.onPlaybackError(-1);
    }
    this.syncSessionState(state);
  }

  /* ----------------------- background playback ----------------------- */

  /**
   * Creates the AVSession and claims the continuous task, so AVPlayer keeps
   * playing when the app leaves the foreground or the screen turns off.
   *
   * The session itself belongs to `mediaSession`, not to this page: an ability
   * may only hold one, and building a fresh one per page is what used to race
   * its own teardown and leave the app with no card and no capsule.
   */
  private async startPlaybackSession(): Promise<void> {
    if (this.playbackSession !== undefined) {
      return;
    }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const session: PlaybackSession | undefined = await mediaSession.acquire(context, 'video',
        this.title.length > 0 ? this.title : this.channelLogin, this.channelLogin, this.durationMs);
      if (session === undefined) {
        hilog.warn(DOMAIN, TAG, 'no media session; the system card will not appear');
        return;
      }
      this.playbackSession = session;
      session.bindControls(
        (): void => {
          this.resumePlayback();
        },
        (): void => {
          this.pausePlayback();
        },
        (): void => {
          this.pausePlayback();
        },
        (positionMs: number): void => {
          this.seekTo(positionMs);
        });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'background playback unavailable');
      this.playbackSession = undefined;
    }
  }

  private stopPlaybackSession(): void {
    const session: PlaybackSession | undefined = this.playbackSession;
    this.playbackSession = undefined;
    if (session !== undefined) {
      session.unbindControls();
    }
    mediaSession.release('video');
  }

  /**
   * Sprinkles the play head into the media session, at most once a second.
   *
   * Throttled because timeUpdate fires far more often than the system needs and
   * every call is a cross-process write.
   */
  private publishProgress(positionMs: number): void {
    const session: PlaybackSession | undefined = this.playbackSession;
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

  private syncSessionState(playerState: string): void {
    const session: PlaybackSession | undefined = this.playbackSession;
    if (session === undefined) {
      return;
    }
    let state: avSession.PlaybackState;
    if (playerState === 'playing') {
      state = avSession.PlaybackState.PLAYBACK_STATE_PLAY;
    } else if (playerState === 'buffering') {
      state = avSession.PlaybackState.PLAYBACK_STATE_BUFFERING;
    } else if (playerState === 'paused') {
      state = avSession.PlaybackState.PLAYBACK_STATE_PAUSE;
    } else if (playerState === 'prepared') {
      state = avSession.PlaybackState.PLAYBACK_STATE_PREPARE;
    } else if (playerState === 'completed') {
      state = avSession.PlaybackState.PLAYBACK_STATE_COMPLETED;
    } else {
      return;
    }
    session.updateState(state, this.positionMs, this.durationMs);
  }

  private attachSurface(): void {
    const player: media.AVPlayer | undefined = this.player;
    if (player !== undefined && this.surfaceReady && this.surfaceId.length > 0) {
      try {
        player.surfaceId = this.surfaceId;
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'failed to attach surface');
      }
    }
  }

  private releasePlayer(): void {
    const player: media.AVPlayer | undefined = this.player;
    this.player = undefined;
    if (player !== undefined) {
      player.off('stateChange');
      player.off('timeUpdate');
      player.off('durationUpdate');
      player.off('availableBitrates');
      player.off('seekDone');
      player.release().then(() => {
      }, (err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'release failed %{public}s', JSON.stringify(err));
      });
    }
  }

  private retry(): void {
    this.status = STATUS_LOADING;
    this.errorText = '';
    this.positionMs = 0;
    this.started = false;
    this.usingDirect = false;
    this.fallbackState = 0;
    this.directQualities = [];
    // A fresh start: the master is rebuilt below, so the old renditions no longer
    // apply, and the ladder begins again from the automatic selector.
    this.parsedQualities = [];
    this.currentQualityName = '';
    this.failedQualityNames = [];
    this.ladderSteps = 0;
    this.selectedQuality = 'Auto';
    this.releasePlayer();
    this.stopPlaybackSession();
    this.setup();
  }

  private resumePlayback(): void {
    const player: media.AVPlayer | undefined = this.player;
    if (player === undefined) {
      return;
    }
    player.play().then(() => {
    }, (err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'play failed %{public}s', JSON.stringify(err));
    });
  }

  private pausePlayback(): void {
    const player: media.AVPlayer | undefined = this.player;
    if (player !== undefined) {
      player.pause();
    }
  }

  private togglePlay(): void {
    if (this.playing) {
      this.pausePlayback();
    } else {
      this.resumePlayback();
    }
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

  private onScrub(value: number, mode: SliderChangeMode): void {
    if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
      this.scrubbing = true;
      this.positionMs = value;
      this.clearHideTimer();
      return;
    }
    this.scrubbing = false;
    this.seekTo(value);
    if (!this.isLive) {
      // A comment belongs to a moment of the video, so the replay follows the seek.
      this.resetReplay(value);
    }
    this.scheduleHideTimer();
  }

  /* --------------------------- seek swipe --------------------------- */

  /**
   * How much of the video one vp of horizontal drag covers.
   *
   * Scaled to the video's own length, so the same gesture feels the same on a
   * three-minute clip and a three-hour broadcast, and bounded at both ends:
   * without the floor a long video would take far too many swipes to cross,
   * without the ceiling a short one would leap about at the lightest touch.
   */
  private seekMsPerVp(): number {
    const scaled: number = this.durationMs / SEEK_RATE_DIVISOR;
    return Math.max(SEEK_MS_PER_VP_MIN, Math.min(SEEK_MS_PER_VP_MAX, scaled));
  }

  /**
   * Starts a seek swipe.
   *
   * Only meaningful with the controls up - that is the state the progress bar is
   * in, and the state the gesture is for - and only with a duration to move
   * along: a live stream has no progress to adjust.
   */
  private beginSeekSwipe(): void {
    if (!this.showControls || this.status !== STATUS_READY || this.durationMs <= 0
      || this.seeking) {
      return;
    }
    this.seeking = true;
    // Reused by the scrubber: while it is set, the player's own time updates are
    // not allowed to pull the bar back to the position still being played.
    this.scrubbing = true;
    this.seekStartMs = this.positionMs;
    this.seekTargetMs = this.positionMs;
    this.seekDeltaMs = 0;
    this.clearHideTimer();
  }

  /** Drags the bar: the preview and the slider both follow the finger. */
  private updateSeekSwipe(offsetX: number): void {
    if (!this.seeking) {
      return;
    }
    const moved: number = this.seekStartMs + offsetX * this.seekMsPerVp();
    this.seekTargetMs = Math.max(0, Math.min(this.durationMs, moved));
    this.seekDeltaMs = this.seekTargetMs - this.seekStartMs;
    this.positionMs = this.seekTargetMs;
  }

  /** Lands the swipe on the position it reached. */
  private endSeekSwipe(): void {
    if (!this.seeking) {
      return;
    }
    const target: number = this.seekTargetMs;
    this.clearSeekSwipe();
    this.seekTo(target);
    if (!this.isLive) {
      // A comment belongs to a moment of the video, so the replay follows the seek.
      this.resetReplay(target);
    }
    this.scheduleHideTimer();
  }

  /**
   * A cancelled drag just puts the bar back: playback never left where it was, so
   * there is nothing to seek to.
   */
  private cancelSeekSwipe(): void {
    if (!this.seeking) {
      return;
    }
    this.clearSeekSwipe();
    this.scheduleHideTimer();
  }

  private clearSeekSwipe(): void {
    this.seeking = false;
    this.scrubbing = false;
    this.seekDeltaMs = 0;
    this.seekTargetMs = 0;
  }

  /** "+1:30" / "-0:45" for the seek in progress. */
  private seekDeltaLabel(): string {
    const sign: string = this.seekDeltaMs < 0 ? '-' : '+';
    return `${sign}${TwitchHelper.formatPlaybackTime(Math.abs(this.seekDeltaMs))}`;
  }

  /* --------------------------- qualities --------------------------- */

  /**
   * Rebuilds the list the quality menu offers, then gives the default its chance
   * against it.
   *
   * Every route that learns something about the source rebuilds the list - the
   * usher ladder, the CDN links playback falls back to, the bitrates the player
   * reports - and the setting is matched against whatever ends up on it, because
   * which renditions can be offered is only known as they arrive.
   */
  private buildQualityOptions(): void {
    this.rebuildQualityOptions();
    this.applyDefaultQuality();
  }

  private rebuildQualityOptions(): void {
    if (this.usingDirect) {
      // Direct mode: every rendition is its own URL, so no bitrate matching.
      const direct: QualityOption[] = [];
      for (let i = 0; i < this.directQualities.length; i++) {
        const quality: DirectQuality = this.directQualities[i];
        direct.push(new QualityOption(quality.name, 0, false, quality.url, quality.name));
      }
      this.qualityOptions = direct;
      return;
    }

    const options: QualityOption[] = [];
    options.push(new QualityOption('Auto', 0, true, ''));

    const ladder: Quality[] = this.qualityLadder();
    if (ladder.length > 0) {
      // The playlist knows both the rendition names and their own URIs, so the
      // list is built from it: picking a row pins that rendition outright, which
      // is what lets a failure step down to the next resolution.
      for (let i = 0; i < ladder.length; i++) {
        const quality: Quality = ladder[i];
        options.push(new QualityOption(this.qualityLabel(quality), quality.bandwidth, false,
          quality.url, quality.name));
      }
      this.qualityOptions = options;
      return;
    }

    // No readable playlist yet: fall back to the bitrates the player reports.
    const bitrates: number[] = this.availableBitrates.slice();
    bitrates.sort((a: number, b: number) => b - a);
    for (let i = 0; i < bitrates.length; i++) {
      const bitrate: number = bitrates[i];
      const matched: Quality | undefined = this.matchQuality(bitrate);
      const label: string = matched !== undefined
        ? this.qualityLabel(matched) : `${Math.round(bitrate / 1000)} kbps`;
      options.push(new QualityOption(label, bitrate, false, '',
        matched !== undefined ? matched.name : ''));
    }
    this.qualityOptions = options;
  }

  private qualityLabel(quality: Quality): string {
    const kbps: number = Math.round(quality.bandwidth / 1000);
    return kbps > 0 ? `${quality.name} \u00b7 ${kbps} kbps` : quality.name;
  }

  /**
   * The renditions available to step down through: those the playlist gave a URI
   * of their own, best first (the parser sorts them by bandwidth, descending).
   */
  private qualityLadder(): Quality[] {
    const ladder: Quality[] = [];
    for (let i = 0; i < this.parsedQualities.length; i++) {
      const quality: Quality = this.parsedQualities[i];
      if (quality.url.length > 0 && quality.bandwidth > 0) {
        ladder.push(quality);
      }
    }
    return ladder;
  }

  /** The playlist entry playback is currently pinned to, if any. */
  private pinnedQuality(): Quality | undefined {
    if (this.currentQualityName.length === 0) {
      return undefined;
    }
    const ladder: Quality[] = this.qualityLadder();
    for (let i = 0; i < ladder.length; i++) {
      if (ladder[i].name === this.currentQualityName) {
        return ladder[i];
      }
    }
    return undefined;
  }

  /**
   * The rendition to try after a failure: the best one below whatever just
   * failed, skipping the ones already known not to play.
   *
   * While nothing is pinned the failing rendition is unknown, so the top of the
   * ladder is taken as the suspect. That is the case this exists for - a source
   * rendition the platform cannot decode (5400106) taking the whole channel down
   * with it, while every transcoded rendition below it plays.
   */
  private nextLowerQuality(ladder: Quality[]): Quality | undefined {
    if (ladder.length === 0) {
      return undefined;
    }
    let ceiling: number = ladder[0].bandwidth + 1;
    const pinned: Quality | undefined = this.pinnedQuality();
    if (pinned !== undefined) {
      ceiling = pinned.bandwidth;
    }
    for (let i = 0; i < ladder.length; i++) {
      const candidate: Quality = ladder[i];
      if (candidate.bandwidth >= ceiling) {
        continue;
      }
      if (this.failedQualityNames.indexOf(candidate.name) >= 0) {
        continue;
      }
      return candidate;
    }
    return undefined;
  }

  /** Notes which rendition just failed, so the walk downwards skips it. */
  private rememberFailedQuality(): void {
    let failed: string = this.currentQualityName;
    if (failed.length === 0) {
      const ladder: Quality[] = this.qualityLadder();
      if (ladder.length > 0) {
        failed = ladder[0].name;
      }
    }
    if (failed.length > 0 && this.failedQualityNames.indexOf(failed) < 0) {
      this.failedQualityNames.push(failed);
    }
  }

  /** Pins playback to one rendition, which also turns automatic switching off. */
  private pinQuality(quality: Quality): void {
    this.currentQualityName = quality.name;
    this.selectedQuality = this.qualityLabel(quality);
    this.status = STATUS_LOADING;
    this.errorText = '';
    hilog.info(DOMAIN, TAG, 'playing rendition %{public}s', quality.name);
    this.restartWithUrl(quality.url, this.positionMs);
  }

  private matchQuality(bitrate: number): Quality | undefined {
    let best: Quality | undefined = undefined;
    let bestDelta: number = -1;
    for (let i = 0; i < this.parsedQualities.length; i++) {
      const quality: Quality = this.parsedQualities[i];
      if (quality.bandwidth <= 0) {
        continue;
      }
      const delta: number = Math.abs(quality.bandwidth - bitrate);
      if (bestDelta < 0 || delta < bestDelta) {
        bestDelta = delta;
        best = quality;
      }
    }
    // Only trust the name when the playlist entry is genuinely close.
    if (best !== undefined && bestDelta >= 0 && bestDelta <= bitrate * 0.25) {
      return best;
    }
    return undefined;
  }

  private selectQuality(option: QualityOption): void {
    this.closeQuality();
    this.selectedQuality = option.label;
    // A manual pick starts the ladder over: whatever failed before may well be
    // exactly what the user is deliberately asking for now.
    this.failedQualityNames = [];
    this.ladderSteps = 0;
    if (this.usingDirect) {
      if (option.url.length > 0) {
        this.restartWithUrl(option.url);
      }
      return;
    }
    if (option.isAuto) {
      this.restartAt(this.positionMs);
      return;
    }
    this.currentQualityName = option.name;
    if (option.url.length > 0) {
      // A rendition that carries its own playlist is played directly, so the
      // choice sticks instead of being a hint to the automatic selector.
      this.restartWithUrl(option.url, this.positionMs);
      return;
    }
    const player: media.AVPlayer | undefined = this.player;
    if (player !== undefined && option.bitrate > 0) {
      try {
        player.setBitrate(option.bitrate);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'setBitrate failed');
      }
    }
  }

  /** Re-creates the pipeline so the player resumes automatic bitrate selection. */
  private restartAt(positionMs: number): void {
    // activeUrl follows the last source handed over, which may be a single
    // rendition; "Auto" always means the whole master playlist again.
    const url: string = this.usingDirect ? this.activeUrl : this.masterUrl;
    if (url.length === 0) {
      return;
    }
    this.currentQualityName = '';
    this.restartWithUrl(url, positionMs);
  }

  /**
   * Reloads the player against another URL, keeping the playback position.
   *
   * reset() is not instantaneous: assigning `url` before the player reports
   * 'idle' is rejected by the engine (5400102, operation not permitted), so the
   * URL is parked until the idle state arrives.
   */
  private restartWithUrl(url: string, positionMs: number = -1): void {
    const player: media.AVPlayer | undefined = this.player;
    if (player === undefined || url.length === 0) {
      return;
    }
    const resumeAt: number = positionMs >= 0 ? positionMs : this.positionMs;
    this.pendingUrl = url;
    this.pendingResume = resumeAt > 0 ? resumeAt : this.resumeMs;
    this.buffering = true;
    this.status = STATUS_LOADING;
    this.beginSourceGrace();

    if (player.state === 'idle') {
      this.applyPendingUrl();
      return;
    }
    try {
      player.reset();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'reset failed');
    }
  }

  /** Hands the parked URL to the player now that it is idle again. */
  private applyPendingUrl(): void {
    const player: media.AVPlayer | undefined = this.player;
    const url: string = this.pendingUrl;
    if (player === undefined || url.length === 0) {
      return;
    }
    this.pendingUrl = '';
    this.activeUrl = url;
    this.resumeMs = this.pendingResume;
    this.appliedResume = false;
    this.started = true;
    this.status = STATUS_LOADING;
    try {
      player.url = url;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'could not set media url');
    }
  }

  /* ------------------------ playback failure ------------------------ */

  /**
   * Both the AVPlayer 'error' event and the failed prepare()/play() promises land
   * here. Xtra reacts to a rejected VOD request by re-deriving the rendition list
   * from the storyboard URL and playing straight off the CDN, so the same retry
   * is attempted once before surfacing the failure - after the rendition ladder
   * has been walked down, which is what saves a stream whose source rendition the
   * platform cannot decode.
   *
   * An AVPlayer failure usually arrives twice (the 'error' event and the 'error'
   * state), and the rescue takes a moment, so the terminal decision waits until
   * the attempt settles - otherwise the second event would tear down the media
   * session that the retry needs to keep alive.
   */
  private onPlaybackError(code: number): void {
    this.lastErrorCode = code;
    if (this.switchGrace) {
      // Teardown noise from the source we just replaced.
      hilog.info(DOMAIN, TAG, 'ignoring error %{public}d during source switch', code);
      return;
    }
    if (this.fallbackState === 1) {
      return;
    }
    if (this.fallbackState === 2 || this.fallbackState === 3) {
      this.failPlayback(code);
      return;
    }
    this.fallbackState = 1;
    this.handlePlaybackError(code);
  }

  /**
   * Tries to rescue playback, cheapest move first:
   *
   *   1. step down the rendition ladder - a source rendition the platform cannot
   *      decode (5400106) takes the whole channel down with it while the
   *      transcoded renditions below it play;
   *   2. Xtra's preview-derived, token-free CDN links - a VOD-only route;
   *   3. give up, leaving the page usable so another source can be chosen by hand.
   */
  private async handlePlaybackError(code: number): Promise<void> {
    const ladder: Quality[] = await this.ensureLadder();
    if (this.ladderSteps < MAX_LADDER_STEPS) {
      const fallback: Quality | undefined = this.nextLowerQuality(ladder);
      if (fallback !== undefined) {
        this.ladderSteps++;
        this.rememberFailedQuality();
        // A step down is not a last resort, so its own failure has to be able to
        // come back through here and continue downwards.
        this.fallbackState = 0;
        this.pinQuality(fallback);
        return;
      }
    }

    const switched: boolean = await this.fallbackToDirectUrl();
    this.fallbackState = switched ? 2 : 3;
    if (!switched) {
      this.failPlayback(code);
    }
  }

  /**
   * The rendition list the step down walks. Downloading the playlist races the
   * first failure, so an empty ladder is loaded once more before concluding that
   * there is nothing left to step down to.
   */
  private async ensureLadder(): Promise<Quality[]> {
    let ladder: Quality[] = this.qualityLadder();
    if (ladder.length === 0 && this.masterUrl.length > 0) {
      await this.loadQualities();
      ladder = this.qualityLadder();
    }
    return ladder;
  }

  /**
   * Opens a window during which playback errors are attributed to the source
   * being replaced. If the replacement never reaches playing, the window
   * expiring surfaces the failure instead of leaving the UI stuck loading.
   */
  private beginSourceGrace(): void {
    this.switchGrace = true;
    this.clearGraceTimer();
    this.graceTimer = setTimeout(() => {
      this.graceTimer = -1;
      this.switchGrace = false;
      const player: media.AVPlayer | undefined = this.player;
      if (!this.playing && player !== undefined && player.state === 'error') {
        // The replacement never came up, so its failure is treated like any
        // other - the ladder keeps walking down from there.
        this.onPlaybackError(this.lastErrorCode);
      }
    }, SOURCE_GRACE_MS);
  }

  private endSourceGrace(): void {
    this.switchGrace = false;
    this.clearGraceTimer();
  }

  private clearGraceTimer(): void {
    if (this.graceTimer !== -1) {
      clearTimeout(this.graceTimer);
      this.graceTimer = -1;
    }
  }

  private failPlayback(code: number): void {
    this.status = STATUS_ERROR;
    this.errorText = `Playback error ${code}.`;
    // The page stays usable: the bars are held open, because the quality sheet is
    // the only way to try a different rendition by hand - and by now the
    // automatic step down has already run out of renditions to try.
    this.showControls = true;
    this.clearHideTimer();
    this.stopPlaybackSession();
  }

  /** Builds Xtra's preview-derived links and restarts playback on one of them. */
  private async fallbackToDirectUrl(): Promise<boolean> {
    const pending: Promise<void> | undefined = this.metadataPromise;
    if (pending !== undefined) {
      await pending;
    }
    const qualities: DirectQuality[] =
      PlaybackRepository.directQualities(this.previewUrl, this.videoType, this.restrictedBitrates);
    if (qualities.length === 0) {
      return false;
    }
    this.directQualities = qualities;
    this.usingDirect = true;
    // A direct link carries its own rendition, so nothing is pinned to the usher
    // playlist any more.
    this.currentQualityName = '';
    const chosen: DirectQuality | undefined = this.preferredDirectQuality();
    if (chosen === undefined) {
      return false;
    }
    // This route is itself the answer to "which quality should it open at", so it
    // takes the wanted one straight away and the setting has no second switch to
    // make on top of it.
    this.defaultQualityApplied = true;
    this.selectedQuality = chosen.name;
    this.buildQualityOptions();
    hilog.info(DOMAIN, TAG, 'using preview-derived renditions (%{public}d)', qualities.length);
    this.status = STATUS_LOADING;
    this.errorText = '';
    this.restartWithUrl(chosen.url, 0);
    return true;
  }

  /**
   * The direct rendition to open the fallback on.
   *
   * The one the Me tab asks for when these links carry it, so a rescue does not
   * start out at the broadcaster's own source - the largest thing there is to
   * fetch, and not what a setting like 480p asked for. An automatic setting keeps
   * the source, which is what this route has always taken.
   */
  private preferredDirectQuality(): DirectQuality | undefined {
    const wanted: string = SettingsRepository.quality();
    if (wanted.length > 0) {
      const preferred: DirectQuality | undefined = this.directQualityOf(wanted);
      if (preferred !== undefined) {
        return preferred;
      }
    }
    const source: DirectQuality | undefined = this.findDirectQuality('source');
    return source !== undefined ? source : this.directQualities[0];
  }

  /** A direct rendition of a quality, matched on resolution. */
  private directQualityOf(wanted: string): DirectQuality | undefined {
    const source: boolean = wanted === SettingsRepository.SOURCE;
    const height: number = renditionHeight(wanted);
    for (let i = 0; i < this.directQualities.length; i++) {
      const quality: DirectQuality = this.directQualities[i];
      const matches: boolean = source
        ? isSourceRendition(quality.name) : renditionHeight(quality.name) === height;
      if (matches) {
        return quality;
      }
    }
    return undefined;
  }

  private findDirectQuality(name: string): DirectQuality | undefined {
    for (let i = 0; i < this.directQualities.length; i++) {
      if (this.directQualities[i].name === name) {
        return this.directQualities[i];
      }
    }
    return undefined;
  }

  /* ------------------------ now playing / library ------------------------ */

  /**
   * Publishes what is playing to the system: the media session's metadata, its
   * artwork, and the live view.
   *
   * Everything here is best effort. The media session always exists, while the
   * live view can be switched off in Settings or refused for want of a scenario
   * right; neither outcome may affect playback.
   */
  private async publishNowPlaying(): Promise<void> {
    const headline: string = this.title.length > 0 ? this.title : this.channelLogin;
    const session: PlaybackSession | undefined = this.playbackSession;
    if (session !== undefined) {
      session.updateMetadata(headline, this.channelLabel(), this.durationMs);
    }
    const avatar: image.PixelMap | undefined = await ImageLoader.load(this.channelImageURL, 96);
    if (session !== undefined && avatar !== undefined) {
      session.setArtwork(avatar);
    }
    // The live view gets a copy of its own at the size its capsule icon allows;
    // the media card above has no such budget and keeps the larger one.
    const capsuleAvatar: image.PixelMap | undefined =
      await ImageLoader.load(this.channelImageURL, CAPSULE_ICON_SIZE);
    LiveWindow.show(headline, this.channelLabel(), capsuleAvatar, this.isLive);
  }

  /** Second line of the media card and headline of the live view. */
  private channelLabel(): string {
    if (this.channelName.length > 0) {
      return this.channelName;
    }
    return this.channelLogin;
  }

  /**
   * The favourite record for what is playing.
   *
   * Built from the full video record when the metadata has arrived, and from the
   * player's own state otherwise, so a favourite can be added even if the
   * metadata query failed.
   */
  private favouriteEntry(): Favourite {
    const meta: Video | undefined = this.videoMeta;
    const entry: Favourite = meta !== undefined ? Favourite.fromVideo(meta) : new Favourite();
    entry.id = this.videoId;
    if (entry.title.length === 0) {
      entry.title = this.title;
    }
    if (entry.channelLogin.length === 0) {
      entry.channelLogin = this.channelLogin;
    }
    if (entry.channelName.length === 0) {
      entry.channelName = this.channelName;
    }
    if (entry.channelImageURL.length === 0) {
      entry.channelImageURL = this.channelImageURL;
    }
    if (entry.favouritedAt === 0) {
      entry.favouritedAt = Date.now();
    }
    return entry;
  }

  /**
   * The download record for what is playing, built the same way.
   *
   * Nothing about it is shared with the favourites: downloading a video does not
   * bookmark it, and bookmarking one does not download it.
   */
  private downloadEntry(): DownloadEntry {
    const meta: Video | undefined = this.videoMeta;
    const entry: DownloadEntry = meta !== undefined ? DownloadEntry.fromVideo(meta) : new DownloadEntry();
    entry.id = this.videoId;
    if (entry.title.length === 0) {
      entry.title = this.title;
    }
    if (entry.channelLogin.length === 0) {
      entry.channelLogin = this.channelLogin;
    }
    if (entry.channelName.length === 0) {
      entry.channelName = this.channelName;
    }
    if (entry.channelImageURL.length === 0) {
      entry.channelImageURL = this.channelImageURL;
    }
    if (entry.startedAt === 0) {
      entry.startedAt = Date.now();
    }
    return entry;
  }

  /** Adds or removes the favourite; nothing on disk is involved either way. */
  private toggleFavourite(): void {
    this.closeMenu();
    if (this.favourite) {
      FavouriteRepository.remove(this.videoId);
      this.favourite = false;
      return;
    }
    FavouriteRepository.addEntry(this.favouriteEntry());
    this.favourite = true;
    this.toast($r('app.string.favourite_added'));
  }

  /**
   * Download entry point: ask which quality to keep, then transfer it in the
   * background. Without a readable playlist there is nothing to choose from, so
   * the default rendition is taken straight away.
   */
  private openDownload(): void {
    this.closeMenu();
    if (!this.canDownload()) {
      return;
    }
    if (this.downloadRenditions().length === 0) {
      this.startDownload(undefined);
      return;
    }
    this.clearHideTimer();
    this.closeOthers(3);
    this.showDownload = true;
  }

  private closeDownload(): void {
    this.showDownload = false;
    this.scheduleHideTimer();
  }

  /** Live streams have nothing to store, and a local copy is already stored. */
  private canDownload(): boolean {
    return !this.isLive && this.videoId.length > 0 && this.localPath.length === 0
      && !DownloadRepository.isActive(this.videoId);
  }

  /** What the download sheet lists: one row per rendition that can be tried. */
  private downloadRenditions(): Quality[] {
    const renditions: Quality[] = [];
    const names: string[] = [];
    const candidates: Quality[] = this.downloadCandidates(undefined);
    for (let i = 0; i < candidates.length; i++) {
      const quality: Quality = candidates[i];
      if (names.indexOf(quality.name) >= 0) {
        continue;
      }
      names.push(quality.name);
      renditions.push(quality);
    }
    return renditions;
  }

  /** "audio_only" is the playlist's name for it; the sheet spells it out. */
  private renditionName(quality: Quality): string {
    return quality.name === 'audio_only' ? 'audio only' : quality.name;
  }

  /**
   * The renditions a download may use, in the order they will be tried.
   *
   * Both sources are needed. The usher master lists the broadcaster's own
   * renditions, but that request does not always succeed - playback itself ends
   * up on the CDN links derived from the storyboard in that case - so those are
   * offered too and the transfer simply takes the first one it can read.
   *
   * The derived links carry no bitrate of their own, so they borrow the one the
   * master gave for the same quality: the size a download is estimated at is then
   * the size the broadcaster actually streams, not a guess at the name.
   */
  private downloadCandidates(preferred: Quality | undefined): Quality[] {
    const candidates: Quality[] = [];
    if (preferred !== undefined) {
      candidates.push(preferred);
    }
    const ladder: Quality[] = this.qualityLadder();
    for (let i = 0; i < ladder.length; i++) {
      candidates.push(ladder[i]);
    }
    const derived: DirectQuality[] = PlaybackRepository.directQualities(
      this.previewUrl, this.videoType, this.restrictedBitrates);
    for (let i = 0; i < derived.length; i++) {
      const direct: DirectQuality = derived[i];
      candidates.push(new Quality(direct.name, this.ladderBandwidth(direct.name), '', 0,
        direct.name === 'audio_only', direct.name === 'source', direct.url));
    }
    if (preferred === undefined) {
      candidates.sort((a: Quality, b: Quality) => downloadRank(a.name) - downloadRank(b.name));
    }
    return candidates;
  }

  /** What the master playlist said this quality costs, 0 when it never listed it. */
  private ladderBandwidth(name: string): number {
    const ladder: Quality[] = this.qualityLadder();
    for (let i = 0; i < ladder.length; i++) {
      if (ladder[i].name === name && ladder[i].bandwidth > 0) {
        return ladder[i].bandwidth;
      }
    }
    return 0;
  }

  /**
   * Roughly what a rendition will cost on disk: bitrate times duration, marked
   * with a tilde because it is only ever an estimate.
   *
   * HLS advertises a rendition's peak bitrate, not the rate it averages, and a
   * stream that is quiet or static encodes well below its own ceiling - so the
   * file that arrives is often smaller than the sheet said. The exact size is
   * known when the transfer ends and is what the downloads list shows.
   */
  private estimatedSize(quality: Quality): string {
    if (this.durationMs <= 0) {
      return '';
    }
    const bitrate: number = quality.bandwidth > 0
      ? quality.bandwidth : DownloadRepository.nominalBitrate(quality.name);
    if (bitrate <= 0) {
      return '';
    }
    return `~${TwitchHelper.formatSize(bitrate / 8 * this.durationMs / 1000)}`;
  }

  /**
   * Starts the transfer.
   *
   * Nothing waits on it: the download runs under a background task and reports
   * itself through DownloadRepository, so this page (or the downloads list) can
   * show the progress and the app can be left while it finishes.
   */
  private startDownload(quality: Quality | undefined): void {
    this.closeDownload();
    if (!this.canDownload()) {
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const entry: DownloadEntry = this.downloadEntry();
    // The repository writes the record before it fetches anything, so the
    // finished file has an entry to attach to and the list shows the row from
    // the moment the transfer is queued. Favourites are untouched.
    //
    // The quality picked here is the one that will be fetched: a rendition the
    // user chose is never swapped for another, so "audio only" stays sound only.
    this.toast($r('app.string.download_started'));
    const picked: string = quality !== undefined ? quality.name : '';
    DownloadRepository.start(context, entry, this.downloadCandidates(quality), picked).then(() => {
      // The repository records the finished file itself, so a download resumed
      // from the list ends exactly like one started here.
      this.toast($r('app.string.download_done'));
    }, (error: Error) => {
      hilog.warn(DOMAIN, TAG, 'download failed: %{public}s', JSON.stringify(error));
      // Cancelling is not a failure worth a message; anything else is reported
      // as-is, because that text is the only clue to why a stream was refused.
      if (error.message !== 'cancelled') {
        this.toast(error.message.length > 0 ? error.message : 'Download failed');
      }
    });
  }

  @Builder
  downloadSheet() {
    Column() {
      Text($r('app.string.download_quality'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .padding({ left: 16, top: 16, bottom: 8 })

      List() {
        ForEach(this.downloadRenditions(), (quality: Quality) => {
          ListItem() {
            Row() {
              Text(this.renditionName(quality))
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
              Text(this.estimatedSize(quality))
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')
            .height(48)
            .padding({ left: 16, right: 16 })
            .onClick(() => {
              this.startDownload(quality);
            })
          }
        }, (quality: Quality) => quality.name)
      }
      .layoutWeight(1)
      .width('100%')

      Button('\u2715')
        .fontSize(14)
        .width('100%')
        .height(44)
        .backgroundColor(Color.Transparent)
        .fontColor($r('app.color.text_secondary'))
        .onClick(() => {
          this.closeDownload();
        })
    }
    .width('100%')
    .height('62%')
    .backgroundColor($r('app.color.surface'))
    .borderRadius({ topLeft: 16, topRight: 16 })
    .position({ x: 0, y: '38%' })
    .shadow({ radius: 16, color: '#000000', offsetY: -4 })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: '100%' }))
      .animation({ duration: 260, curve: Curve.FastOutSlowIn }))
  }

  private toast(message: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1600 });
    } catch (e) {
      hilog.debug(DOMAIN, TAG, 'toast unavailable');
    }
  }

  /* ---------------------------- controls ---------------------------- */

  private toggleControls(): void {
    if (this.showQuality || this.showMenu || this.showSpeed || this.showDownload) {
      // A tap on the video closes the overlay instead of toggling the bars.
      this.closeOverlays();
      this.scheduleHideTimer();
      return;
    }
    this.showControls = !this.showControls;
    if (this.showControls) {
      this.scheduleHideTimer();
    } else {
      this.clearHideTimer();
    }
  }

  /**
   * The popups and the download sheet are part of the control layer.
   *
   * While one is open the bars stay up (the auto-hide is suspended, and closing
   * the overlay hands the timer back), so the two never come apart - the overlays
   * used to outlive the bars they belong to: a popup is anchored to a button in
   * one of them, and the sheet is dismissed by the bars going away.
   */
  private openQuality(): void {
    this.clearHideTimer();
    this.closeOthers(0);
    this.showQuality = true;
  }

  private closeQuality(): void {
    this.showQuality = false;
    this.scheduleHideTimer();
  }

  private openMenu(): void {
    this.clearHideTimer();
    this.closeOthers(1);
    this.showMenu = true;
  }

  /**
   * Drops every overlay but `keep`, since they all belong to one layer and two
   * of them at once would leave the lower one stuck behind the upper one.
   * 0 = quality, 1 = menu, 2 = speed, 3 = download.
   */
  private closeOthers(keep: number): void {
    this.showQuality = keep === 0;
    this.showMenu = keep === 1;
    this.showSpeed = keep === 2;
    this.showDownload = keep === 3;
  }

  private closeMenu(): void {
    this.showMenu = false;
    this.scheduleHideTimer();
  }

  /** Drops whatever overlay is open, including when the controls leave. */
  private closeOverlays(): void {
    if (this.showQuality) {
      this.showQuality = false;
    }
    if (this.showMenu) {
      this.showMenu = false;
    }
    if (this.showSpeed) {
      this.showSpeed = false;
    }
    if (this.showDownload) {
      this.showDownload = false;
    }
  }

  private hideControls(): void {
    this.closeOverlays();
    this.showControls = false;
  }

  private scheduleHideTimer(): void {
    this.clearHideTimer();
    this.hideTimer = setTimeout(() => {
      // Both modes hide: every control sits in the bars now, and a tap brings
      // them back - inline playback would otherwise never see the picture.
      // An open overlay keeps them up; closing it re-arms this timer.
      if (this.playing && !this.showQuality && !this.showMenu && !this.showSpeed
        && !this.showDownload) {
        this.hideControls();
      }
    }, HIDE_CONTROLS_DELAY_MS);
  }

  private clearHideTimer(): void {
    if (this.hideTimer !== -1) {
      clearTimeout(this.hideTimer);
      this.hideTimer = -1;
    }
  }

  private toggleFullscreen(): void {
    this.fullscreen = !this.fullscreen;
    this.applyWindow(this.fullscreen);
    this.showControls = true;
    if (this.fullscreen) {
      this.scheduleHideTimer();
    }
  }

  private async applyWindow(fullscreen: boolean): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await Immersive.setFullscreen(context, fullscreen);
  }
}
