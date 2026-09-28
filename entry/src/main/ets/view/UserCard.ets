import { UserSummary } from '../model/UserSummary';
import { TwitchHelper } from '../util/TwitchHelper';

/**
 * A channel row, ported from Xtra's res/layout/fragment_search_channels_list_item.xml:
 * avatar, name, follower count, and a LIVE marker on the right when the channel
 * is currently broadcasting.
 */
@Component
export struct UserCard {
  user: UserSummary = new UserSummary();
  onOpen: (user: UserSummary) => void = (user: UserSummary) => {
  };

  build() {
    Row() {
      Image(TwitchHelper.profileImage(this.user.profileImageURL))
        .width(44)
        .height(44)
        .borderRadius(22)
        .objectFit(ImageFit.Cover)
        .backgroundColor($r('app.color.surface_alt'))
        .alt($r('app.color.surface_alt'))

      Column() {
        Text(this.user.displayName.length > 0 ? this.user.displayName : this.user.login)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Row() {
          Text(TwitchHelper.formatCount(this.user.followerCount, true))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
          Text(' ')
            .fontSize(13)
          Text($r('app.string.followers'))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .margin({ top: 3 })
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })

      if (this.user.isLive()) {
        Column() {
          Text($r('app.string.tab_live'))
            .fontSize(12)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.live'))
            .borderRadius(4)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          Text(TwitchHelper.formatCount(this.user.viewersCount, true))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.End)
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .onClick(() => {
      this.onOpen(this.user);
    })
  }
}
