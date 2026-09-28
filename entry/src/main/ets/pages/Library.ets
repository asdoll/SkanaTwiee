import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Immersive, Insets } from '../common/Immersive';
import { Nav } from '../common/Nav';
import { AudioParams, LibraryParams, SECTION_DOWNLOADS } from '../model/Routes';
import { DownloadEntry } from '../model/DownloadEntry';
import { Favourite } from '../model/Favourite';
import { DownloadProgress, DownloadRepository } from '../repository/DownloadRepository';
import { FavouriteRepository } from '../repository/FavouriteRepository';
import { TwitchHelper } from '../util/TwitchHelper';

const DOMAIN: number = 0x0000;
const TAG: string = 'Library';
const THUMBNAIL_WIDTH: number = 148;

/**
 * One row of either list.
 *
 * Favourites and downloads are separate collections with separate stores, but a
 * row of either shows the same things - a picture, a title, a channel - so both
 * are copied into this shape and drawn by one builder. The download-only fields
 * stay empty for a favourite.
 */
class LibraryItem {
  id: string = '';
  title: string = '';
  channelName: string = '';
  channelLogin: string = '';
  thumbnailURL: string = '';
  durationSeconds: number = 0;
  /** Download-only; empty on a favourite. */
  filePath: string = '';
  fileSize: number = 0;
  audioOnly: boolean = false;
  /** Download-only: true once the media is actually on the device. */
  downloaded: boolean = false;
  /** When the entry was added, which is what the list is sorted by. */
  at: number = 0;
}

/**
 * The local collections.
 *
 * One page and two lists: the favourites, which are bookmarks and nothing else,
 * and the downloads, which are files on this device. Neither reads the other's
 * store, so a row can never be in the wrong list, and deleting one never touches
 * the other.
 */
@Component
export struct LibraryPage {
  @State section: number = 0;
  @State entries: LibraryItem[] = [];
  @State topInset: number = 0;
  /**
   * Transfers in flight, copied out of the repository on every progress report.
   *
   * The transfer runs outside this page, so holding it here is what makes a row
   * move while it downloads - a lookup into the repository would never change.
   */
  @State transfers: DownloadProgress[] = [];
  /** Bumped by FavouriteRepository on every change. */
  @StorageLink('favouriteVersion') @Watch('onFavouritesChanged') favouriteVersion: number = 0;
  /** Bumped by DownloadRepository on every change, progress included. */
  @StorageLink('downloadVersion') @Watch('onDownloadsChanged') downloadVersion: number = 0;

  aboutToAppear(): void {
    this.setupInsets();
    this.transfers = DownloadRepository.activeTransfers();
    this.reload();
  }

  onFavouritesChanged(): void {
    this.reload();
  }

  onDownloadsChanged(): void {
    this.transfers = DownloadRepository.activeTransfers();
    // A transfer that has just started adds a row, and one that has finished
    // turns it into a playable entry.
    this.reload();
  }

  build() {
    NavDestination() {
      Column() {
        this.header()

        if (this.entries.length === 0) {
          Column() {
            Text(this.emptyLabel())
              .fontSize(14)
              .fontColor($r('app.color.text_muted'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List() {
            ForEach(this.entries, (entry: LibraryItem) => {
              ListItem() {
                this.row(entry)
              }
            }, (entry: LibraryItem) => entry.id)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 12, right: 12, bottom: 24 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background'))
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      const params: LibraryParams | undefined = context.pathInfo.param as LibraryParams | undefined;
      if (params !== undefined) {
        this.section = params.section;
      }
      this.reload();
    })
  }

  private async setupInsets(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const insets: Insets = await Immersive.enable(context);
    this.topInset = this.getUIContext().px2vp(insets.top);
  }

  /**
   * The list for this section, newest first: the favourites out of their own
   * store, or the downloads out of theirs.
   *
   * The downloads include what is still arriving, since an entry only gains a
   * file when the transfer ends and a download you cannot see is a download you
   * cannot pause.
   */
  private reload(): void {
    const entries: LibraryItem[] = [];
    if (this.section === SECTION_DOWNLOADS) {
      const downloads: DownloadEntry[] = DownloadRepository.listed();
      for (let i = 0; i < downloads.length; i++) {
        const entry: DownloadEntry = downloads[i];
        const item: LibraryItem = new LibraryItem();
        item.id = entry.id;
        item.title = entry.title;
        item.channelName = entry.channelName;
        item.channelLogin = entry.channelLogin;
        item.thumbnailURL = entry.thumbnailURL;
        item.durationSeconds = entry.durationSeconds;
        item.filePath = entry.filePath;
        item.fileSize = entry.fileSize;
        item.audioOnly = entry.audioOnly;
        item.downloaded = entry.downloaded;
        item.at = entry.startedAt;
        entries.push(item);
      }
    } else {
      const favourites: Favourite[] = FavouriteRepository.all();
      for (let i = 0; i < favourites.length; i++) {
        const entry: Favourite = favourites[i];
        const item: LibraryItem = new LibraryItem();
        item.id = entry.id;
        item.title = entry.title;
        item.channelName = entry.channelName;
        item.channelLogin = entry.channelLogin;
        item.thumbnailURL = entry.thumbnailURL;
        item.durationSeconds = entry.durationSeconds;
        item.at = entry.favouritedAt;
        entries.push(item);
      }
    }
    entries.sort((a: LibraryItem, b: LibraryItem) => b.at - a.at);
    this.entries = entries;
  }

  private title(): Resource {
    return this.section === SECTION_DOWNLOADS
      ? $r('app.string.downloads') : $r('app.string.favourites');
  }

  private emptyLabel(): Resource {
    return this.section === SECTION_DOWNLOADS
      ? $r('app.string.no_downloads') : $r('app.string.no_favourites');
  }

  @Builder
  header() {
    Column() {
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

        Text(this.title())
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 8 })
          .layoutWeight(1)
      }
      .width('100%')
      .margin({ bottom: 6 })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: this.topInset + 8 })
  }

  @Builder
  row(entry: LibraryItem) {
    Row() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Image(TwitchHelper.videoThumbnail(entry.thumbnailURL))
          .width(THUMBNAIL_WIDTH)
          .aspectRatio(16 / 9)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.surface_alt'))

        if (entry.durationSeconds > 0) {
          Text(TwitchHelper.formatDuration(entry.durationSeconds))
            .fontSize(11)
            .fontColor(Color.White)
            .backgroundColor('#CC000000')
            .borderRadius(4)
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .margin({ right: 4, bottom: 4 })
        }
      }
      .width(THUMBNAIL_WIDTH)

      Column() {
        Text(entry.title)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Text(entry.channelName.length > 0 ? entry.channelName : entry.channelLogin)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .margin({ top: 4 })
          .width('100%')

        if (this.isActiveTransfer(entry.id)) {
          Column() {
            Row() {
              Text(this.isPausedTransfer(entry.id)
                ? $r('app.string.download_paused') : $r('app.string.downloading'))
                .fontSize(11)
                .fontColor($r('app.color.accent'))
              Text(this.transferDetail(entry.id))
                .fontSize(11)
                .fontColor($r('app.color.text_muted'))
                .margin({ left: 6 })
                .layoutWeight(1)
            }
            .width('100%')

            Progress({ value: this.downloadPercent(entry.id), total: 100, type: ProgressType.Linear })
              .color($r('app.color.accent'))
              .width('100%')
              .margin({ top: 4 })
          }
          .width('100%')
          .margin({ top: 4 })
        } else if (entry.downloaded) {
          Row() {
            Text(entry.audioOnly ? $r('app.string.audio_only') : $r('app.string.downloaded'))
              .fontSize(11)
              .fontColor($r('app.color.accent'))
            Text(TwitchHelper.formatSize(entry.fileSize))
              .fontSize(11)
              .fontColor($r('app.color.text_muted'))
              .margin({ left: 6 })
          }
          .margin({ top: 4 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })

      if (this.isActiveTransfer(entry.id)) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph(this.isPausedTransfer(entry.id)
            ? $r('sys.symbol.play_fill') : $r('sys.symbol.pause_fill'))
            .fontSize(18)
            .fontColor([$r('app.color.accent')])
        }
        .width(36)
        .height(36)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.togglePause(entry);
        })
      }

      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(18)
          .fontColor([$r('app.color.text_muted')])
      }
      .width(36)
      .height(36)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.confirmDelete(entry);
      })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .onClick(() => {
      this.open(entry);
    })
  }

  /**
   * A downloaded entry plays from disk - in the audio player when it holds sound
   * only - and a favourite is streamed again. A download still transferring is
   * not playable yet; a favourite is playable whatever else is going on.
   *
   * Which player a download opens in is the file's own business: whether it was
   * stored as sound only is recorded when the transfer finishes, from the
   * rendition that actually answered, so the two always agree.
   */
  private open(entry: LibraryItem): void {
    if (this.isActiveTransfer(entry.id)) {
      return;
    }
    if (entry.downloaded) {
      if (entry.audioOnly) {
        Nav.openAudioPlayer(new AudioParams(entry.filePath, entry.title,
          entry.channelName.length > 0 ? entry.channelName : entry.channelLogin,
          entry.thumbnailURL, entry.durationSeconds));
        return;
      }
      Nav.openDownloadedVideo(entry.id, entry.filePath, entry.title, entry.channelLogin);
      return;
    }
    Nav.openPlayer(entry.id, entry.title, entry.channelLogin);
  }

  /** Stops a transfer between segments, or picks it up again. */
  private togglePause(entry: LibraryItem): void {
    if (!this.isPausedTransfer(entry.id)) {
      DownloadRepository.pause(entry.id);
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    DownloadRepository.resume(context, entry.id).then(() => {
    }, (error: Error) => {
      hilog.warn(DOMAIN, TAG, 'resume failed: %{public}s', JSON.stringify(error));
    });
  }

  private transferOf(videoId: string): DownloadProgress | undefined {
    for (let i = 0; i < this.transfers.length; i++) {
      if (this.transfers[i].videoId === videoId) {
        return this.transfers[i];
      }
    }
    return undefined;
  }

  /**
   * True when this row is a transfer to follow.
   *
   * Only the downloads list shows transfers: a favourite is a bookmark and stays
   * a plain row even while the same video is being downloaded underneath it, so
   * the two lists never look alike.
   */
  private isActiveTransfer(videoId: string): boolean {
    return this.section === SECTION_DOWNLOADS && this.transferOf(videoId) !== undefined;
  }

  private isPausedTransfer(videoId: string): boolean {
    const progress: DownloadProgress | undefined = this.transferOf(videoId);
    return progress !== undefined && progress.paused;
  }

  private downloadPercent(videoId: string): number {
    const progress: DownloadProgress | undefined = this.transferOf(videoId);
    return progress !== undefined ? progress.percent : 0;
  }

  /** "42% · 1.2 MB/s", or the phase once the media is complete. */
  private transferDetail(videoId: string): string {
    const progress: DownloadProgress | undefined = this.transferOf(videoId);
    if (progress === undefined) {
      return '';
    }
    if (progress.phase === 'comments') {
      return 'comments';
    }
    const rate: string = progress.bytesPerSecond > 0
      ? `${TwitchHelper.formatSize(progress.bytesPerSecond)}/s` : '';
    return rate.length > 0 ? `${progress.percent}% \u00b7 ${rate}` : `${progress.percent}%`;
  }

  /**
   * The two lists mean two different things by "delete": dropping a favourite
   * leaves every file alone, and removing a download leaves every favourite
   * alone. Neither reaches into the other's store.
   */
  private confirmDelete(entry: LibraryItem): void {
    const section: number = this.section;
    try {
      this.getUIContext().showAlertDialog({
        title: $r('app.string.delete'),
        message: entry.title,
        primaryButton: {
          value: $r('app.string.cancelled'),
          action: () => {
          }
        },
        secondaryButton: {
          value: $r('app.string.delete'),
          action: () => {
            this.delete(section, entry.id);
          }
        }
      });
    } catch (e) {
      // Without a dialog the entry still has to be removable.
      this.delete(section, entry.id);
    }
  }

  private delete(section: number, id: string): void {
    if (section === SECTION_DOWNLOADS) {
      DownloadRepository.removeDownload(id);
      return;
    }
    FavouriteRepository.remove(id);
  }
}
