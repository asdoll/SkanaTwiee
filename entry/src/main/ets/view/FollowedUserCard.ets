import { FollowedUser } from '../model/FollowedUser';
import { TwitchHelper } from '../util/TwitchHelper';

const VIDEO_THUMB_WIDTH: number = 112;

/**
 * A followed channel.
 *
 * Top line is the channel itself plus its live state (a red badge with the
 * viewer count and the game while it is broadcasting, "Offline" otherwise); the
 * bottom line is the most recent VOD it published. Each part is its own tap
 * target, so the live stream and the last video are both one tap away.
 *
 * Layout follows Xtra's res/layout/fragment_followed_channels_list_item.xml,
 * plus the latest-video row that Xtra only shows on the channel page.
 */
@Component
export struct FollowedUserCard {
  user: FollowedUser = new FollowedUser();
  /** Avatar or name tapped: open the channel. */
  onChannel: (user: FollowedUser) => void = (user: FollowedUser) => {
  };
  /** Live badge tapped: watch the broadcast. */
  onLive: (user: FollowedUser) => void = (user: FollowedUser) => {
  };
  /** Latest-video row tapped: play that VOD. */
  onVideo: (user: FollowedUser) => void = (user: FollowedUser) => {
  };

  build() {
    Column() {
      Row() {
        Image(TwitchHelper.profileImage(this.user.profileImageURL))
          .width(44)
          .height(44)
          .borderRadius(22)
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.surface_alt'))
          .alt($r('app.color.surface_alt'))
          .border({ width: 2, color: this.user.isLive ? $r('app.color.live') : '#00000000' })
          .onClick(() => {
            this.onChannel(this.user);
          })

        Column() {
          Text(this.user.displayName.length > 0 ? this.user.displayName : this.user.login)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .onClick(() => {
              this.onChannel(this.user);
            })

          if (this.user.isLive) {
            this.liveStatus()
          } else {
            Text($r('app.string.offline'))
              .fontSize(13)
              .fontColor($r('app.color.text_muted'))
              .maxLines(1)
              .width('100%')
              .margin({ top: 3 })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12 })
      }
      .width('100%')

      if (this.user.hasVideo) {
        this.latestVideo()
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
  }

  /** Red badge, viewer count and game; the whole row is the live tap target. */
  @Builder
  liveStatus() {
    Row() {
      Text($r('app.string.tab_live'))
        .fontSize(11)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.live'))
        .borderRadius(4)
        .padding({ left: 5, right: 5, top: 1, bottom: 1 })

      Text(TwitchHelper.formatCount(this.user.liveViewers, true))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .margin({ left: 6 })

      Text(' ')
        .fontSize(13)

      Text($r('app.string.viewers'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))

      if (this.user.liveGameName.length > 0) {
        Text(`\u00b7 ${this.user.liveGameName}`)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 6 })
          .layoutWeight(1)
      }
    }
    .width('100%')
    .margin({ top: 3 })
    .onClick(() => {
      this.onLive(this.user);
    })
  }

  /** Thumbnail plus title of the channel's newest VOD. */
  @Builder
  latestVideo() {
    Row() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Image(TwitchHelper.videoThumbnail(this.user.videoThumbnailURL))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.surface_alt'))
          .alt($r('app.color.surface_alt'))

        Text(TwitchHelper.formatDuration(this.user.videoDurationSeconds))
          .fontSize(11)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor('#99000000')
          .borderRadius(4)
          .padding({ left: 4, right: 4, top: 1, bottom: 1 })
          .margin({ right: 4, bottom: 4 })
      }
      .width(VIDEO_THUMB_WIDTH)
      .aspectRatio(16 / 9)
      .borderRadius(6)
      .clip(true)

      Column() {
        Text(this.user.videoTitle)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Text(this.videoMeta())
          .fontSize(12)
          .fontColor($r('app.color.text_muted'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 10 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ top: 10 })
    .onClick(() => {
      this.onVideo(this.user);
    })
  }

  /** "3d ago · Just Chatting" - date and category, both language-neutral. */
  private videoMeta(): string {
    const parts: string[] = [];
    const date: string = TwitchHelper.formatDate(this.user.videoCreatedAt);
    if (date.length > 0) {
      parts.push(date);
    }
    if (this.user.videoGameName.length > 0) {
      parts.push(this.user.videoGameName);
    }
    return parts.join(' \u00b7 ');
  }
}
