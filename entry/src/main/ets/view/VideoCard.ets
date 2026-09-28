import { FavouriteRepository } from '../repository/FavouriteRepository';
import { Video } from '../model/Video';
import { TwitchHelper } from '../util/TwitchHelper';

/**
 * A VOD row, ported from Xtra's res/layout/fragment_videos_list_item.xml:
 * 16:9 thumbnail with duration/type/views/date overlays, then avatar + title.
 *
 * The heart beside the title bookmarks the video without opening it, so the
 * whole card is not needed to keep something for later.
 */
@Component
export struct VideoCard {
  video: Video = new Video();
  showChannel: boolean = true;
  onOpen: (video: Video) => void = (video: Video) => {
  };
  onChannel: (video: Video) => void = (video: Video) => {
  };
  /** True while the video is favourited; kept in step by the repository. */
  @State favourite: boolean = false;
  /**
   * Bumped by FavouriteRepository on every change.
   *
   * Cards are built inside a lazy list and know nothing about each other, so
   * watching the counter is what keeps them all showing the same state -
   * including one favourited from the player or from another list.
   */
  @StorageLink('favouriteVersion') @Watch('onFavouritesChanged') favouriteVersion: number = 0;

  aboutToAppear(): void {
    this.favourite = FavouriteRepository.isFavourite(this.video.id);
  }

  onFavouritesChanged(): void {
    this.favourite = this.video.id.length > 0 && FavouriteRepository.isFavourite(this.video.id);
  }

  /** Adds the video to the favourites, or removes it again. */
  private toggleFavourite(): void {
    if (this.video.id.length === 0) {
      return;
    }
    this.favourite = FavouriteRepository.toggle(this.video);
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        Image(TwitchHelper.videoThumbnail(this.video.thumbnailURL))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.surface_alt'))
          .alt($r('app.color.surface_alt'))

        // duration, top-left
        Text(TwitchHelper.formatDuration(this.video.durationSeconds))
          .fontSize(12)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor('#99000000')
          .borderRadius(4)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .margin({ left: 8, top: 8 })

        // type badge, top-right
        this.typeBadge()

        // views, bottom-left
        Row() {
          Text(TwitchHelper.formatCount(this.video.viewCount, true))
            .fontSize(12)
            .fontColor($r('app.color.text_primary'))
          Text(' ')
            .fontSize(12)
          Text($r('app.string.views'))
            .fontSize(12)
            .fontColor($r('app.color.text_primary'))
        }
        .backgroundColor('#99000000')
        .borderRadius(4)
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .margin({ left: 8, bottom: 8 })
        .align(Alignment.BottomStart)
        .position({ x: 8, y: '90%' })

        // date, bottom-right
        Text(TwitchHelper.formatDate(this.video.createdAt))
          .fontSize(12)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor('#99000000')
          .borderRadius(4)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .position({ x: '62%', y: '90%' })
      }
      .width('100%')
      .aspectRatio(16 / 9)
      .borderRadius(8)
      .clip(true)

      Row() {
        if (this.showChannel && this.video.channelImageURL.length > 0) {
          Image(TwitchHelper.profileImage(this.video.channelImageURL))
            .width(36)
            .height(36)
            .borderRadius(18)
            .objectFit(ImageFit.Cover)
            .backgroundColor($r('app.color.surface_alt'))
            .onClick(() => {
              this.onChannel(this.video);
            })
        }

        Column() {
          Text(this.video.title)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          if (this.showChannel && this.video.channelName.length > 0) {
            Text(this.video.channelName)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ top: 4 })
              .onClick(() => {
                this.onChannel(this.video);
              })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: this.showChannel && this.video.channelImageURL.length > 0 ? 10 : 0 })

        if (this.video.id.length > 0) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph(this.favourite ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
              .fontSize(20)
              .fontColor([this.favourite ? $r('app.color.accent') : $r('app.color.text_muted')])
          }
          .width(40)
          .height(40)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.toggleFavourite();
          })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .margin({ top: 10 })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .onClick(() => {
      this.onOpen(this.video);
    })
  }

  @Builder
  typeBadge() {
    if (this.video.type === 'HIGHLIGHT') {
      this.badgeText($r('app.string.video_type_highlight'))
    } else if (this.video.type === 'UPLOAD') {
      this.badgeText($r('app.string.video_type_upload'))
    } else if (this.video.type === 'ARCHIVE') {
      this.badgeText($r('app.string.video_type_archive'))
    }
  }

  @Builder
  badgeText(label: Resource) {
    Text(label)
      .fontSize(12)
      .fontColor($r('app.color.text_primary'))
      .backgroundColor('#99000000')
      .borderRadius(4)
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .position({ x: '70%', y: 8 })
  }
}
