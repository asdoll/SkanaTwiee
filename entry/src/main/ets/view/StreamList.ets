import { Stream, StreamPage } from '../model/Stream';
import { PagedDataSource, PagedLoader } from '../util/PagedDataSource';
import { Nav } from '../common/Nav';
import { StreamCard } from './StreamCard';

const STATUS_LOADING: number = 0;
const STATUS_CONTENT: number = 1;
const STATUS_EMPTY: number = 2;
const STATUS_ERROR: number = 3;

/**
 * Paged live-stream list, the Live counterpart of VideoList.
 *
 * Tapping a row opens the player with the channel login (live playback), while
 * tapping the channel name opens the channel's VOD list.
 */
@Component
export struct StreamList {
  /** Change this (e.g. to the submitted query) to reload from the first page. */
  @Prop @Watch('onReloadKeyChanged') reloadKey: string = '';
  /** Space kept free at each end of the scroll range for the immortal bars. */
  @Prop contentTopOffset: number = 0;
  @Prop contentBottomOffset: number = 0;
  /** Rows to draw when the list is empty. */
  emptyMessage: Resource = $r('app.string.no_streams');
  loader: PagedLoader<Stream> = (after: string): Promise<StreamPage> => Promise.resolve(StreamPage.empty());
  /** Index of the first visible row; 0 means the list is back at the top. */
  onScrollFirstIndex: (start: number) => void = (start: number) => {
  };
  @State status: number = STATUS_LOADING;
  @State loadingMore: boolean = false;
  @State noMore: boolean = false;
  /** Owned by the Refresh component, which drives it during the pull gesture. */
  @State refreshing: boolean = false;
  /** True while the pull is being dragged, before it is released. */
  @State pulling: boolean = false;
  private ds: PagedDataSource<Stream> | undefined = undefined;

  aboutToAppear(): void {
    this.ds = new PagedDataSource<Stream>(this.loader);
    this.startLoad();
  }

  onReloadKeyChanged(): void {
    if (this.ds !== undefined) {
      this.startLoad();
    }
  }

  private startLoad(): Promise<void> {
    return this.load(true);
  }

  /**
   * Pull-to-refresh keeps the list where it is: the Refresh spinner already
   * reports progress, so the centered loading state is skipped and only the
   * data is replaced.
   */
  private async onPullRefresh(): Promise<void> {
    await this.load(false);
    this.refreshing = false;
  }

  private async load(showSpinner: boolean): Promise<void> {
    const ds: PagedDataSource<Stream> | undefined = this.ds;
    if (ds === undefined) {
      return;
    }
    if (showSpinner) {
      this.status = STATUS_LOADING;
    }
    this.noMore = false;
    await ds.refresh();
    this.noMore = !ds.hasMorePages();
    this.refreshStatus();
  }

  private async loadMore(): Promise<void> {
    const ds: PagedDataSource<Stream> | undefined = this.ds;
    if (ds === undefined || ds.isLoading() || !ds.hasMorePages()) {
      return;
    }
    this.loadingMore = true;
    await ds.loadMore();
    this.loadingMore = false;
    this.noMore = !ds.hasMorePages();
    this.refreshStatus();
  }

  private refreshStatus(): void {
    const ds: PagedDataSource<Stream> | undefined = this.ds;
    if (ds === undefined) {
      return;
    }
    if (ds.isEmpty()) {
      this.status = ds.hasFailed() ? STATUS_ERROR : STATUS_EMPTY;
    } else {
      this.status = STATUS_CONTENT;
    }
  }

  private openStream(stream: Stream): void {
    if (stream.channelLogin.length === 0) {
      return;
    }
    Nav.openLiveStream(stream.channelLogin, stream.title);
  }

  private openChannel(stream: Stream): void {
    if (stream.channelLogin.length === 0) {
      return;
    }
    Nav.openChannel(stream.channelLogin, stream.channelName);
  }

  build() {
    Stack() {
      if (this.status === STATUS_LOADING) {
        this.centeredLoading()
      } else if (this.status === STATUS_EMPTY) {
        this.centeredMessage(this.emptyMessage, false)
      } else if (this.status === STATUS_ERROR) {
        this.centeredMessage($r('app.string.load_failed'), true)
      } else {
        this.content()
      }

      if (this.pulling || this.refreshing) {
        this.pullIndicator()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  content() {
    Refresh({
      refreshing: $$this.refreshing,
      // The built-in indicator is laid out in the pull gap, whose top edge is the
      // top of the screen - behind the immersive header - so it cannot be
      // positioned. An empty builder removes it; build() draws our own instead.
      builder: (): void => {
        this.hiddenIndicator()
      }
    }) {
      this.list()
    }
    .width('100%')
    .height('100%')
    .onStateChange((state: RefreshStatus) => {
      this.pulling = !this.refreshing
        && (state === RefreshStatus.Drag || state === RefreshStatus.OverDrag);
    })
    .onRefreshing(() => {
      this.onPullRefresh();
    })
  }

  /** A placeholder with no size: it suppresses the default indicator. */
  @Builder
  hiddenIndicator() {
    Column()
      .width(0)
      .height(0)
  }

  /**
   * Pull indicator, pinned below the immersive header.
   *
   * An overlay rather than the Refresh component's own indicator, so it stays put
   * instead of sliding out from under the header and travelling down with the pull.
   */
  @Builder
  pullIndicator() {
    Column() {
      LoadingProgress()
        .width(28)
        .height(28)
        .color($r('app.color.accent'))
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.contentTopOffset + 16 })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Start)
    .hitTestBehavior(HitTestMode.Transparent)
  }

  /** The list itself; content() wraps it so it can also be pulled down. */
  @Builder
  list() {
    List() {
      if (this.ds !== undefined) {
        LazyForEach(this.ds, (stream: Stream) => {
          ListItem() {
            StreamCard({
              stream: stream,
              onOpen: (item: Stream) => {
                this.openStream(item);
              },
              onChannel: (item: Stream) => {
                this.openChannel(item);
              }
            })
          }
        }, (stream: Stream) => stream.key())
      }
      ListItem() {
        this.footer()
      }
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .cachedCount(3)
    .contentStartOffset(this.contentTopOffset)
    .contentEndOffset(this.contentBottomOffset)
    .onReachEnd(() => {
      this.loadMore();
    })
    .onScrollIndex((start: number, end: number, center: number) => {
      this.onScrollFirstIndex(start);
    })
  }

  @Builder
  footer() {
    Row() {
      if (this.loadingMore) {
        LoadingProgress()
          .width(24)
          .height(24)
          .color($r('app.color.accent'))
        Text($r('app.string.loading'))
          .fontSize(13)
          .fontColor($r('app.color.text_muted'))
          .margin({ left: 8 })
      } else if (this.noMore) {
        Text($r('app.string.no_more'))
          .fontSize(13)
          .fontColor($r('app.color.text_muted'))
      }
    }
    .width('100%')
    .height(56)
    .justifyContent(FlexAlign.Center)
  }

  /** Initial load: an animation rather than a word, so nothing looks stuck. */
  @Builder
  centeredLoading() {
    Column() {
      LoadingProgress()
        .width(40)
        .height(40)
        .color($r('app.color.accent'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  centeredMessage(message: Resource, showRetry: boolean) {
    Column() {
      Text(message)
        .fontSize(15)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
      if (showRetry) {
        Button($r('app.string.retry'))
          .fontSize(14)
          .backgroundColor($r('app.color.surface_alt'))
          .fontColor($r('app.color.text_primary'))
          .margin({ top: 16 })
          .onClick(() => {
            this.startLoad();
          })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(24)
  }
}
