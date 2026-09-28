import { Stream } from '../model/Stream';
import { TwitchHelper } from '../util/TwitchHelper';

/**
 * A live stream row, ported from Xtra's res/layout/fragment_streams_list_item.xml:
 * 16:9 preview with the viewer count and uptime in the corners, then the channel
 * avatar next to the broadcast title, channel name and game.
 */
@Component
export struct StreamCard {
  stream: Stream = new Stream();
  onOpen: (stream: Stream) => void = (stream: Stream) => {
  };
  onChannel: (stream: Stream) => void = (stream: Stream) => {
  };

  build() {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        Image(TwitchHelper.streamThumbnail(this.stream.thumbnailURL))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.surface_alt'))
          .alt($r('app.color.surface_alt'))

        // channel avatar over the preview, top-left
        if (this.stream.channelImageURL.length > 0) {
          Image(TwitchHelper.profileImage(this.stream.channelImageURL))
            .width(36)
            .height(36)
            .borderRadius(18)
            .objectFit(ImageFit.Cover)
            .border({ width: 2, color: $r('app.color.live') })
            .margin({ left: 8, top: 8 })
        }

        // viewers, bottom-left
        Row() {
          Text(TwitchHelper.formatCount(this.stream.viewersCount, true))
            .fontSize(12)
            .fontColor($r('app.color.text_primary'))
          Text(' ')
            .fontSize(12)
          Text($r('app.string.viewers'))
            .fontSize(12)
            .fontColor($r('app.color.text_primary'))
        }
        .backgroundColor('#99000000')
        .borderRadius(4)
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .position({ x: 8, y: '90%' })

        // uptime, bottom-right
        if (TwitchHelper.formatUptime(this.stream.createdAt).length > 0) {
          Row() {
            Text(TwitchHelper.formatUptime(this.stream.createdAt))
              .fontSize(12)
              .fontColor($r('app.color.text_primary'))
            Text(' ')
              .fontSize(12)
            Text($r('app.string.uptime'))
              .fontSize(12)
              .fontColor($r('app.color.text_primary'))
          }
          .backgroundColor('#99000000')
          .borderRadius(4)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .position({ x: '62%', y: '90%' })
        }
      }
      .width('100%')
      .aspectRatio(16 / 9)
      .borderRadius(8)
      .clip(true)

      Row() {
        Column() {
          Text(this.stream.title)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .onClick(() => {
              this.onOpen(this.stream);
            })

          if (this.stream.channelName.length > 0) {
            Text(this.stream.channelName)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ top: 4 })
              .onClick(() => {
                this.onChannel(this.stream);
              })
          }

          if (this.stream.gameName.length > 0) {
            Text(this.stream.gameName)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ top: 4 })
          }

          if (this.stream.tags.length > 0) {
            Text(this.stream.tags.join(' \u00b7 '))
              .fontSize(12)
              .fontColor($r('app.color.text_muted'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ top: 6 })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .margin({ top: 10 })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .onClick(() => {
      this.onOpen(this.stream);
    })
  }
}
