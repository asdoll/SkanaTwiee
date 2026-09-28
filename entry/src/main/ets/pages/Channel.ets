import { VideoPage } from '../model/Video';
import { ChannelParams } from '../model/Routes';
import { ChannelInfo } from '../model/ChannelInfo';
import { Immersive, Insets } from '../common/Immersive';
import { Nav } from '../common/Nav';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AuthRepository } from '../repository/AuthRepository';
import { ChannelRepository } from '../repository/ChannelRepository';
import { IntegrityRepository } from '../repository/IntegrityRepository';
import { VideoRepository } from '../repository/VideoRepository';
import { TwitchHelper } from '../util/TwitchHelper';
import { ImmersiveHeader } from '../view/ImmersiveHeader';
import { VideoList } from '../view/VideoList';

const LIVE_THUMB_WIDTH: number = 160;
const DOMAIN: number = 0x0000;
const TAG: string = 'Channel';

/**
 * Channel (user detail) page.
 *
 * The header carries the channel identity and the follow button; when the
 * channel is broadcasting, a live card sits above the video list so the stream
 * is always one tap away - including for channels that have no VODs at all.
 *
 * Follow/unfollow uses Twitch's own follow-button mutations, which take the
 * numeric user id, so the page loads UserChannelPage (identity, followers and
 * live state) before it can offer the button. Anonymous browsing still works;
 * the button is simply not drawn.
 */
@Component
export struct ChannelPage {
  @State login: string = '';
  @State displayName: string = '';
  /** Status-bar inset, so the header clears the clock. */
  @State topInset: number = 0;
  @State info: ChannelInfo = new ChannelInfo();
  @State loggedIn: boolean = false;
  @State isFollowing: boolean = false;
  @State followBusy: boolean = false;
  /** Last follow/unfollow failure, shown under the channel name. */
  @State followError: string = '';
  /** Bumped by pages/Login.ets when a fresh integrity signature lands. */
  @StorageLink('integrityVersion') @Watch('onIntegrityReady') integrityVersion: number = 0;
  /** True while the verification page is open on this page's behalf. */
  @State verifying: boolean = false;
  /** Set when a follow was refused for integrity and must be retried after capture. */
  private pendingFollow: boolean = false;

  aboutToAppear(): void {
    this.setupInsets();
  }

  private async setupInsets(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const insets: Insets = await Immersive.enable(context);
    this.topInset = this.getUIContext().px2vp(insets.top);
  }

  build() {
    NavDestination() {
      this.content()
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.onParamsReady(context);
    })
    .onShown(() => {
      this.retryPendingFollow();
    })
  }

  private onParamsReady(context: NavDestinationContext): void {
    const params: ChannelParams | undefined = context.pathInfo.param as ChannelParams | undefined;
    if (params !== undefined) {
      this.login = params.login !== undefined ? params.login : '';
      this.displayName = params.displayName !== undefined ? params.displayName : '';
    }
    this.loggedIn = AuthRepository.isLoggedIn();
    this.loadChannel();
  }

  private async loadChannel(): Promise<void> {
    if (this.login.length === 0) {
      return;
    }
    try {
      const info: ChannelInfo | undefined = await ChannelRepository.channelInfo(this.login);
      if (info !== undefined) {
        this.info = info;
        if (this.displayName.length === 0) {
          this.displayName = info.displayName;
        }
      }
    } catch (e) {
      // The video list below still works without the header details.
    }
    if (this.loggedIn) {
      this.isFollowing = await ChannelRepository.isFollowing(this.login);
    }
  }

  private async toggleFollow(): Promise<void> {
    if (this.followBusy || !this.loggedIn || this.info.id.length === 0) {
      return;
    }
    this.followBusy = true;
    const wanted: boolean = !this.isFollowing;
    try {
      if (wanted) {
        await ChannelRepository.follow(this.info.id, false);
      } else {
        await ChannelRepository.unfollow(this.info.id);
      }
      this.isFollowing = wanted;
      this.followError = '';
    } catch (e) {
      const error = e as Error;
      const message: string = error.message !== undefined ? error.message : 'Request failed';
      hilog.warn(DOMAIN, TAG, 'follow failed: %{public}s', message);
      if (IntegrityRepository.isIntegrityError(message)) {
        // Only a signature minted by Twitch's own page is accepted, so obtain one
        // and retry; the retry is driven by onIntegrityReady().
        IntegrityRepository.clearCaptured();
        this.pendingFollow = true;
        this.verifying = true;
        this.followError = '';
        Nav.openLoginVerify();
      } else {
        // A toast is easy to miss, so the reason also stays on screen.
        this.followError = message;
      }
    }
    this.followBusy = false;
  }

  /** Runs the follow that was waiting on a signature, once one has been captured. */
  private onIntegrityReady(): void {
    this.retryPendingFollow();
  }

  /**
   * Runs the follow that was waiting on a signature.
   *
   * Called both when the capture event lands and when this page comes back to
   * the front, so the retry happens whichever arrives first; the flag makes the
   * second call a no-op.
   */
  private retryPendingFollow(): void {
    if (!this.pendingFollow) {
      return;
    }
    this.pendingFollow = false;
    this.verifying = false;
    if (IntegrityRepository.hasCaptured()) {
      this.toggleFollow();
    }
  }

  private openLive(): void {
    if (this.info.live.channelLogin.length === 0) {
      return;
    }
    Nav.openLiveStream(this.info.live.channelLogin, this.info.live.title);
  }

  @Builder
  content() {
    Column() {
      ImmersiveHeader({ topInset: this.topInset, showBack: true }) {
        if (this.info.profileImageURL.length > 0) {
          Image(TwitchHelper.profileImage(this.info.profileImageURL))
            .width(32)
            .height(32)
            .borderRadius(16)
            .objectFit(ImageFit.Cover)
            .backgroundColor($r('app.color.surface_alt'))
            .margin({ left: 10 })
        }

        Column() {
          Text(this.displayName.length > 0 ? this.displayName : this.login)
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          if (this.info.followerCount > 0) {
            Row() {
              Text(TwitchHelper.formatCount(this.info.followerCount, true))
                .fontSize(12)
                .fontColor($r('app.color.text_muted'))
              Text(' ')
                .fontSize(12)
              Text($r('app.string.followers'))
                .fontSize(12)
                .fontColor($r('app.color.text_muted'))
            }
          } else {
            Text($r('app.string.channel_videos'))
              .fontSize(12)
              .fontColor($r('app.color.text_muted'))
          }

          if (this.followError.length > 0) {
            Text(this.followError)
              .fontSize(11)
              .fontColor($r('app.color.live'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 8 })

        if (this.loggedIn && this.info.id.length > 0) {
          this.followButton()
        }
      }

      if (this.info.isLive) {
        this.liveCard()
      }

      if (this.login.length > 0) {
        VideoList({
          reloadKey: this.login,
          contentBottomOffset: 16,
          loader: (after: string): Promise<VideoPage> => {
            return VideoRepository.channelVideos(this.login, after,
              VideoRepository.SORT_TIME, VideoRepository.DEFAULT_TYPES);
          }
        })
          .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  followButton() {
    Button(this.isFollowing ? $r('app.string.following') : $r('app.string.follow'))
      .fontSize(13)
      .height(32)
      .backgroundColor(this.isFollowing ? $r('app.color.surface_alt') : $r('app.color.accent'))
      .fontColor(this.isFollowing ? $r('app.color.text_primary') : Color.White)
      .enabled(!this.followBusy)
      .margin({ right: 12 })
      .onClick(() => {
        this.toggleFollow();
      })
  }

  /**
   * Compact live card: a 16:9 preview with the viewer count, next to the
   * broadcast title and category. Deliberately compact so the channel's VODs
   * keep most of the screen.
   */
  @Builder
  liveCard() {
    Row() {
      Stack({ alignContent: Alignment.TopStart }) {
        Image(TwitchHelper.streamThumbnail(this.info.live.thumbnailURL))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.surface_alt'))
          .alt($r('app.color.surface_alt'))

        Text($r('app.string.tab_live'))
          .fontSize(11)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.live'))
          .borderRadius(4)
          .padding({ left: 5, right: 5, top: 1, bottom: 1 })
          .margin({ left: 6, top: 6 })

        Row() {
          Text(TwitchHelper.formatCount(this.info.live.viewersCount, true))
            .fontSize(11)
            .fontColor($r('app.color.text_primary'))
          Text(' ')
            .fontSize(11)
          Text($r('app.string.viewers'))
            .fontSize(11)
            .fontColor($r('app.color.text_primary'))
        }
        .backgroundColor('#99000000')
        .borderRadius(4)
        .padding({ left: 4, right: 4, top: 1, bottom: 1 })
        .margin({ left: 6, bottom: 6 })
        .align(Alignment.BottomStart)
      }
      .width(LIVE_THUMB_WIDTH)
      .aspectRatio(16 / 9)
      .borderRadius(8)
      .clip(true)

      Column() {
        Text(this.info.live.title.length > 0 ? this.info.live.title : this.displayName)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        if (this.info.live.gameName.length > 0) {
          Text(this.info.live.gameName)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 4 })
        }

        if (TwitchHelper.formatUptime(this.info.live.createdAt).length > 0) {
          Row() {
            Text(TwitchHelper.formatUptime(this.info.live.createdAt))
              .fontSize(12)
              .fontColor($r('app.color.text_muted'))
            Text(' ')
              .fontSize(12)
            Text($r('app.string.uptime'))
              .fontSize(12)
              .fontColor($r('app.color.text_muted'))
          }
          .margin({ top: 4 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding(12)
    .margin({ left: 12, right: 12, bottom: 4 })
    .backgroundColor($r('app.color.surface'))
    .borderRadius(10)
    .onClick(() => {
      this.openLive();
    })
  }
}
