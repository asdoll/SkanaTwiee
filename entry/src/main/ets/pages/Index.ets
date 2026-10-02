import { Immersive, Insets } from '../common/Immersive';
import { Nav, RouteName } from '../common/Nav';
import { common } from '@kit.AbilityKit';
import { hdsMaterial, HdsTabs, HdsTabsController } from '@kit.UIDesignKit';
import { StreamPage } from '../model/Stream';
import { FollowedUserPage } from '../model/FollowedUser';
import { TwitchUser } from '../model/TwitchUser';
import { UserSummaryPage } from '../model/UserSummary';
import { VideoPage } from '../model/Video';
import { AuthRepository } from '../repository/AuthRepository';
import { StreamRepository } from '../repository/StreamRepository';
import { UserRepository } from '../repository/UserRepository';
import { VideoRepository } from '../repository/VideoRepository';
import { TwitchHelper } from '../util/TwitchHelper';
import { FollowedUserList } from '../view/FollowedUserList';
import { IMMERSIVE_ROW_HEIGHT } from '../view/ImmersiveHeader';
import { StreamList } from '../view/StreamList';
import { SettingRow } from '../view/SettingRow';
import { TopTabBar } from '../view/TopTabBar';
import { UserList } from '../view/UserList';
import { VideoList } from '../view/VideoList';
import { AudioPlayerPage } from './AudioPlayer';
import { ChannelPage } from './Channel';
import { LibraryPage } from './Library';
import { LoginPage } from './Login';
import { PlayerPage } from './Player';
import { SettingsPage } from './Settings';

/* Bottom navigation: the app-level surfaces. */
const TAB_FOLLOWING: number = 0;
const TAB_SEARCH: number = 1;
const TAB_SETTINGS: number = 2;

/* Sections inside the Following header. */
const FOLLOWING_LIVE: number = 0;
const FOLLOWING_VIDEOS: number = 1;
const FOLLOWING_USERS: number = 2;

/* Sections inside the Search header. */
const SEARCH_LIVE: number = 0;
const SEARCH_VIDEOS: number = 1;
const SEARCH_USERS: number = 2;

/** Height of the search row the Search header carries under its section labels. */
const SEARCH_INPUT_HEIGHT: number = 56;
/// 悬浮页签栏高度与它到内容底部的留白
const BOTTOM_BAR_HEIGHT: number = 56;
const BOTTOM_BAR_GAP: number = 12;
/** How long the header takes to slide away or come back. */
const HEADER_ANIMATION_MS: number = 220;
/** Horizontal travel that turns a swipe on a list into a section change, in vp. */
const SECTION_SWIPE_DISTANCE: number = 60;
/** How long a section slide takes. */
const SECTION_ANIMATION_MS: number = 240;
/** How far a section slides in, as a percentage of its own width. */
const SECTION_SLIDE_PERCENT: number = 30;

/**
 * App shell.
 *
 * There is no app-level top bar: a section header lives on each page that needs
 * one, carries the 6.1 "immersive" look (gradient scrim + gradient blur, since
 * ArkUI's own material is API 26 while this device is 6.1), and slides away when
 * the content is scrolled down. The bottom bar is a floating HdsTabs whose
 * material comes from HDS.
 */
@Entry
@Component
struct Index {
  @State currentTab: number = TAB_FOLLOWING;
  @State followingSection: number = FOLLOWING_LIVE;
  @State searchSection: number = SEARCH_LIVE;
  /**
   * Direction of the section change in progress: 1 for the next section, -1 for
   * the previous one. The slide transition reads it, so it has to be set before
   * the section itself changes - a component plays the transition it was built
   * with, and the new section is only built once this has its new value.
   */
  @State sectionDirection: number = 1;
  /** True while the section header is translated off-screen. */
  @State headerHidden: boolean = false;
  @State loggedIn: boolean = false;
  @State user: TwitchUser = new TwitchUser();
  @State searchQuery: string = '';
  @State submittedQuery: string = '';

  /** System bar insets, so the immersive bars are never overdrawn by the clock. */
  @State topInset: number = 0;
  @State bottomInset: number = 0;
  @StorageLink('sessionVersion') @Watch('onSessionChanged') sessionVersion: number = 0;
  /** Changes after a follow/unfollow so the Following lists reload. */
  @StorageLink('followVersion') followVersion: number = 0;
  tabsController: HdsTabsController = new HdsTabsController();
  /** First visible row of the last scroll report, to derive the direction. */
  private lastFirstIndex: number = 0;

  aboutToAppear(): void {
    this.refreshAuth();
    this.setupImmersive();
  }

  private async setupImmersive(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const insets: Insets = await Immersive.enable(context);
    this.topInset = this.getUIContext().px2vp(insets.top);
    this.bottomInset = this.getUIContext().px2vp(insets.bottom);
  }

  /* --------------------------- header sizing --------------------------- */

  /** Header height on the Following page: status bar + section labels. */
  private followingHeaderHeight(): number {
    return this.topInset + IMMERSIVE_ROW_HEIGHT;
  }

  /** Header height on the Search page: it also carries the search row. */
  private searchHeaderHeight(): number {
    return this.topInset + IMMERSIVE_ROW_HEIGHT + SEARCH_INPUT_HEIGHT;
  }

  /** Space a list must leave so its last card clears the floating tab bar. */
  private listBottomOffset(): number {
    return BOTTOM_BAR_HEIGHT + this.bottomInset + BOTTOM_BAR_GAP * 2;
  }

  /** Height of the header on whichever tab is on screen. */
  private headerHeight(): number {
    return this.currentTab === TAB_SEARCH ? this.searchHeaderHeight() : this.followingHeaderHeight();
  }

  /* ---------------------------- header state ---------------------------- */

  /**
   * Hides the header once the list has scrolled away from its first row, and
   * brings it back as soon as the user scrolls up again or returns to the top.
   *
   * Direction comes from the first visible row rather than a per-frame delta:
   * the sign of `onScrollFrameBegin`'s offset is not the scroll direction, and
   * a whole row of hysteresis is a better guard against jitter anyway.
   */
  private onScrollFirstIndex(start: number): void {
    if (start <= 0) {
      this.lastFirstIndex = 0;
      this.setHeaderHidden(false);
      return;
    }
    if (start > this.lastFirstIndex) {
      this.setHeaderHidden(true);
    } else if (start < this.lastFirstIndex) {
      this.setHeaderHidden(false);
    }
    this.lastFirstIndex = start;
  }

  private setHeaderHidden(hidden: boolean): void {
    if (this.headerHidden === hidden) {
      return;
    }
    this.getUIContext().animateTo({
      duration: HEADER_ANIMATION_MS,
      curve: Curve.Friction
    }, () => {
      this.headerHidden = hidden;
    });
  }

  /** Snaps the header back into place, e.g. after switching tabs or sections. */
  private resetHeader(): void {
    this.lastFirstIndex = 0;
    this.headerHidden = false;
  }

  private selectFollowingSection(index: number): void {
    if (this.followingSection !== index) {
      this.followingSection = index;
      this.resetHeader();
    }
  }

  private selectSearchSection(index: number): void {
    if (this.searchSection !== index) {
      this.searchSection = index;
      this.resetHeader();
    }
  }

  /**
   * Moves one section along, in the direction the content was dragged: swiping
   * left brings the next section in and swiping right the previous one.
   *
   * The ends are a stop, not a wrap. The labels are in a fixed order, so carrying
   * the last one round to the first would make the header read as though the
   * swipe had gone backwards.
   */
  private switchSection(step: number): void {
    if (this.currentTab === TAB_FOLLOWING) {
      const next: number = this.followingSection + step;
      if (next >= FOLLOWING_LIVE && next <= FOLLOWING_USERS) {
        this.selectSectionByIndex(next);
      }
    } else if (this.currentTab === TAB_SEARCH) {
      const next: number = this.searchSection + step;
      if (next >= SEARCH_LIVE && next <= SEARCH_USERS) {
        this.selectSectionByIndex(next);
      }
    }
  }

  /**
   * Applies a section change, whether it was swiped to or tapped in the header.
   *
   * The direction is worked out here so the slide goes the way the label moved,
   * not the way the last swipe did: the transition is read when the section is
   * rebuilt, so it has to be set before the section itself changes.
   */
  private selectSectionByIndex(index: number): void {
    const current: number = this.currentTab === TAB_FOLLOWING
      ? this.followingSection : this.searchSection;
    if (index === current) {
      return;
    }
    this.sectionDirection = index > current ? 1 : -1;
    if (this.currentTab === TAB_FOLLOWING) {
      this.selectFollowingSection(index);
    } else {
      this.selectSearchSection(index);
    }
  }

  /**
   * The slide a section change plays.
   *
   * The section coming in slides in from the side the change went towards and the
   * one leaving fades. A slide-out would need the direction too, and a leaving
   * component plays the transition it was built with - the direction of the
   * change that brought *it* in, not this one - so it would slide the wrong way
   * the moment a swipe turns round.
   */
  private sectionTransition(): TransitionEffect {
    return TransitionEffect.asymmetric(
      TransitionEffect.OPACITY
        .combine(TransitionEffect.translate({ x: `${this.sectionDirection * SECTION_SLIDE_PERCENT}%` }))
        .animation({ duration: SECTION_ANIMATION_MS, curve: Curve.FastOutSlowIn }),
      TransitionEffect.OPACITY
        .animation({ duration: SECTION_ANIMATION_MS, curve: Curve.FastOutSlowIn })
    );
  }

  /** Turns a finished horizontal swipe into a section change, when it travelled far enough. */
  private onSectionSwipe(offsetX: number): void {
    if (offsetX <= -SECTION_SWIPE_DISTANCE) {
      this.switchSection(1);
    } else if (offsetX >= SECTION_SWIPE_DISTANCE) {
      this.switchSection(-1);
    }
  }

  private submitSearch(): void {
    this.submittedQuery = this.searchQuery;
  }

  /** Fires on login/logout, including when a destination page (e.g. Login) pops. */
  onSessionChanged(): void {
    this.refreshAuth();
  }

  onPageShow(): void {
    this.refreshAuth();
  }

  private refreshAuth(): void {
    this.loggedIn = AuthRepository.isLoggedIn();
    this.user = AuthRepository.currentUser();
  }

  build() {
    Navigation(Nav.stack) {
      this.shell()
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .navDestination(this.pageMap)
  }

  @Builder
  pageMap(name: string) {
    if (name === RouteName.PLAYER) {
      PlayerPage()
    } else if (name === RouteName.CHANNEL) {
      ChannelPage()
    } else if (name === RouteName.LOGIN) {
      LoginPage()
    } else if (name === RouteName.LIBRARY) {
      LibraryPage()
    } else if (name === RouteName.SETTINGS) {
      SettingsPage()
    } else if (name === RouteName.AUDIO) {
      AudioPlayerPage()
    }
  }

  @Builder
  shell() {
    Stack({ alignContent: Alignment.TopStart }) {
      // Content is full-bleed: lists scroll under both bars so the header has
      // something to blur and the floating bar has something to draw over.
      Column() {
        if (this.currentTab === TAB_FOLLOWING) {
          this.followingTab()
        } else if (this.currentTab === TAB_SEARCH) {
          this.searchTab()
        } else {
          // The Me tab is three fixed rows; it needs no scroll view, and one would
          // only serve to float them in the middle of the screen.
          this.settingsTab()
        }
      }
      .width('100%')
      .height('100%')

      // One header for both tabs that carry section labels. The Search page's
      // input is drawn from inside the header's slot rather than by a second
      // TopTabBar, so a tab switch can neither leave the slot empty nor bring the
      // bar back at the wrong height.
      if (this.currentTab === TAB_FOLLOWING || this.currentTab === TAB_SEARCH) {
        TopTabBar({
          labels: [
            $r('app.string.tab_live'),
            $r('app.string.videos'),
            $r('app.string.tab_users')
          ],
          index: this.currentTab === TAB_FOLLOWING ? this.followingSection : this.searchSection,
          topInset: this.topInset,
          // Only Search adds the input, which makes its header taller.
          extraHeight: this.currentTab === TAB_SEARCH ? SEARCH_INPUT_HEIGHT : 0,
          offsetY: this.headerHidden ? -this.headerHeight() : 0,
          visible: !this.headerHidden,
          onSelect: (index: number): void => {
            this.selectSectionByIndex(index);
          }
        }) {
          if (this.currentTab === TAB_SEARCH) {
            this.searchInput()
          }
        }
      }

      this.bottomTabs()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  /** Search row; the Search header renders it under its section labels. */
  @Builder
  searchInput() {
    Row() {
      // Bound to searchQuery: the header is rebuilt (tab switches, hide-on-scroll),
      // and an unbound TextInput would come back empty while the results stayed.
      TextInput({ placeholder: this.searchPlaceholder(), text: this.searchQuery })
        .placeholderColor($r('app.color.text_muted'))
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.surface_alt'))
        .height(38)
        .layoutWeight(1)
        .enterKeyType(EnterKeyType.Search)
        .onChange((value: string) => {
          this.searchQuery = value;
        })
        .onSubmit((enterKey: EnterKeyType) => {
          this.submitSearch();
        })

      Button($r('app.string.tab_search'))
        .fontSize(13)
        .height(38)
        .backgroundColor($r('app.color.accent'))
        .fontColor(Color.White)
        .margin({ left: 8 })
        .onClick(() => {
          this.submitSearch();
        })
    }
    .width('100%')
    .height(SEARCH_INPUT_HEIGHT)
    .padding({ left: 12, right: 12, bottom: 10 })
  }

  private searchPlaceholder(): Resource {
    if (this.searchSection === SEARCH_LIVE) {
      return $r('app.string.search_hint_live');
    }
    if (this.searchSection === SEARCH_USERS) {
      return $r('app.string.search_hint_users');
    }
    return $r('app.string.search_hint');
  }

  /**
   * Floating HDS tab bar. `systemMaterialEffect` is the HDS entry point for the
   * immersive material and is available from API 23, so it carries the 6.1
   * "光感" surface that ArkUI's systemMaterial cannot yet provide.
   *
   * The bar is driven as a pure bar (empty TabContent) so the app's own content
   * stays full-bleed underneath and shows through the material.
   */
  @Builder
  bottomTabs() {
    HdsTabs({ controller: this.tabsController }) {
      TabContent() {
      }
      .tabBar(this.tabBarItem(TAB_FOLLOWING, $r('sys.symbol.house_fill'), $r('app.string.tab_following')))

      TabContent() {
      }
      .tabBar(this.tabBarItem(TAB_SEARCH, $r('sys.symbol.magnifyingglass'), $r('app.string.tab_search')))

      TabContent() {
      }
      .tabBar(this.tabBarItem(TAB_SETTINGS, $r('sys.symbol.person_crop_circle_fill'), $r('app.string.tab_settings')))
    }
    .scrollable(false)
    .barOverlap(true)
    .barPosition(BarPosition.End)
    .vertical(false)
    .barHeight(BOTTOM_BAR_HEIGHT)
    .barFloatingStyle({
      barBottomMargin: this.bottomInset > 0 ? this.bottomInset : BOTTOM_BAR_GAP,
      adaptToHandedness: true,
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      }
    })
    .onTabBarClick((index: number) => {
      if (this.currentTab === index) {
        return;
      }
      this.currentTab = index;
      // The header belongs to the list that was scrolled, not to the tab being
      // opened. A Following or Search list scrolled far enough to slide it away
      // would otherwise leave the next tab without its bar at all - and, on
      // Search, without the only way to type a query.
      this.resetHeader();
    })
    .width('100%')
    .height('100%')
    .align(Alignment.Bottom)
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  tabBarItem(index: number, icon: Resource, label: Resource) {
    Column({ space: 2 }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([this.currentTab === index ? $r('app.color.accent') : $r('app.color.text_muted')])
      Text(label)
        .fontSize(10)
        .fontColor(this.currentTab === index ? $r('app.color.accent') : $r('app.color.text_muted'))
    }
  }

  /* ------------------------- following sections ------------------------- */

  @Builder
  followingTab() {
    Column() {
      if (!this.loggedIn) {
        this.loginPrompt($r('app.string.login_required'))
      } else if (this.followingSection === FOLLOWING_LIVE) {
        StreamList({
          reloadKey: `followed_live_${this.user.id}_${this.followVersion}`,
          contentTopOffset: this.followingHeaderHeight(),
          contentBottomOffset: this.listBottomOffset(),
          loader: (after: string): Promise<StreamPage> => {
            return StreamRepository.followedLiveStreams(after);
          },
          onScrollFirstIndex: (start: number): void => {
            this.onScrollFirstIndex(start);
          }
        })
          .layoutWeight(1)
          .transition(this.sectionTransition())
      } else if (this.followingSection === FOLLOWING_USERS) {
        FollowedUserList({
          reloadKey: `followed_users_${this.user.id}_${this.followVersion}`,
          contentTopOffset: this.followingHeaderHeight(),
          contentBottomOffset: this.listBottomOffset(),
          loader: (after: string): Promise<FollowedUserPage> => {
            return UserRepository.followedUsers(after);
          },
          onScrollFirstIndex: (start: number): void => {
            this.onScrollFirstIndex(start);
          }
        })
          .layoutWeight(1)
          .transition(this.sectionTransition())
      } else {
        VideoList({
          reloadKey: `followed_${this.user.id}_${this.followVersion}`,
          contentTopOffset: this.followingHeaderHeight(),
          contentBottomOffset: this.listBottomOffset(),
          loader: (after: string): Promise<VideoPage> => {
            return VideoRepository.followedVideos(after);
          },
          onScrollFirstIndex: (start: number): void => {
            this.onScrollFirstIndex(start);
          }
        })
          .layoutWeight(1)
          .transition(this.sectionTransition())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
    // A horizontal swipe moves between Live, Videos and Users. The lists keep
    // their vertical scroll: the pan only claims horizontal travel, so the two
    // never take the same drag.
    .gesture(
      PanGesture({ direction: PanDirection.Horizontal, distance: SECTION_SWIPE_DISTANCE })
        .onActionEnd((event: GestureEvent) => {
          this.onSectionSwipe(event.offsetX);
        })
    )
  }

  /* --------------------------- search sections --------------------------- */

  @Builder
  searchTab() {
    Column() {
      if (this.submittedQuery.length === 0) {
        this.hint()
      } else if (this.searchSection === SEARCH_LIVE) {
        StreamList({
          reloadKey: this.submittedQuery,
          contentTopOffset: this.searchHeaderHeight(),
          contentBottomOffset: this.listBottomOffset(),
          loader: (after: string): Promise<StreamPage> => {
            return StreamRepository.searchStreams(this.submittedQuery, after);
          },
          onScrollFirstIndex: (start: number): void => {
            this.onScrollFirstIndex(start);
          }
        })
          .layoutWeight(1)
          .transition(this.sectionTransition())
      } else if (this.searchSection === SEARCH_VIDEOS) {
        VideoList({
          reloadKey: this.submittedQuery,
          contentTopOffset: this.searchHeaderHeight(),
          contentBottomOffset: this.listBottomOffset(),
          loader: (after: string): Promise<VideoPage> => {
            return VideoRepository.searchVideos(this.submittedQuery, after);
          },
          onScrollFirstIndex: (start: number): void => {
            this.onScrollFirstIndex(start);
          }
        })
          .layoutWeight(1)
          .transition(this.sectionTransition())
      } else {
        UserList({
          reloadKey: this.submittedQuery,
          contentTopOffset: this.searchHeaderHeight(),
          contentBottomOffset: this.listBottomOffset(),
          loader: (after: string): Promise<UserSummaryPage> => {
            return UserRepository.searchUsers(this.submittedQuery, after);
          },
          onScrollFirstIndex: (start: number): void => {
            this.onScrollFirstIndex(start);
          }
        })
          .layoutWeight(1)
          .transition(this.sectionTransition())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
    // Same gesture as the Following page; the sections go Live, Videos, Users.
    .gesture(
      PanGesture({ direction: PanDirection.Horizontal, distance: SECTION_SWIPE_DISTANCE })
        .onActionEnd((event: GestureEvent) => {
          this.onSectionSwipe(event.offsetX);
        })
    )
  }

  /* ------------------------------- me ------------------------------- */

  /**
   * The Me tab: the two collections, and the way into the settings.
   *
   * What someone opens this tab for is what they saved and what they downloaded,
   * so those are the tab; the app's own settings - the account, the playback
   * defaults, the settings file - live on their own page (see pages/Settings.ets).
   */
  @Builder
  settingsTab() {
    Column() {
      this.accountCard()

      SettingRow({
        icon: $r('sys.symbol.heart_fill'),
        label: $r('app.string.favourites'),
        onTap: (): void => {
          Nav.openFavourites();
        }
      })
      SettingRow({
        icon: $r('sys.symbol.square_and_arrow_down'),
        label: $r('app.string.downloads'),
        onTap: (): void => {
          Nav.openDownloads();
        }
      })
      SettingRow({
        icon: $r('sys.symbol.gearshape_fill'),
        label: $r('app.string.settings'),
        onTap: (): void => {
          Nav.openSettings();
        }
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: this.topInset + 8, bottom: this.listBottomOffset() })
    .backgroundColor($r('app.color.background'))
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * Who is signed in, at the top of the Me tab.
   *
   * The account belongs here rather than behind the settings page: it is who the
   * tab is about, and without it the tab is three rows on an otherwise empty
   * screen.
   */
  @Builder
  accountCard() {
    Column() {
      if (this.loggedIn) {
        Row() {
          if (this.user.profileImageURL.length > 0) {
            Image(TwitchHelper.profileImage(this.user.profileImageURL))
              .width(48)
              .height(48)
              .borderRadius(24)
              .objectFit(ImageFit.Cover)
          }
          Column() {
            Text(this.user.displayName.length > 0 ? this.user.displayName : this.user.login)
              .fontSize(16)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
            Text(this.user.login.length > 0 ? `@${this.user.login}` : '')
              .fontSize(13)
              .fontColor($r('app.color.text_muted'))
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 12 })
        }
        .width('100%')

        Button($r('app.string.logout'))
          .fontSize(14)
          .width('100%')
          .backgroundColor($r('app.color.surface_alt'))
          .fontColor($r('app.color.text_primary'))
          .margin({ top: 16 })
          .onClick(() => {
            AuthRepository.logout();
            this.refreshAuth();
          })
      } else {
        Text($r('app.string.not_logged_in'))
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        Button($r('app.string.login'))
          .fontSize(15)
          .width('100%')
          .backgroundColor($r('app.color.accent'))
          .fontColor(Color.White)
          .margin({ top: 16 })
          .onClick(() => {
            this.openLogin();
          })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(12)
  }

  /* ------------------------------ shared ------------------------------ */
  @Builder
  loginPrompt(message: Resource) {
    Column() {
      Text(message)
        .fontSize(15)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
      Button($r('app.string.login'))
        .fontSize(15)
        .backgroundColor($r('app.color.accent'))
        .fontColor(Color.White)
        .margin({ top: 20 })
        .onClick(() => {
          this.openLogin();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(32)
  }

  /** Placeholder shown before a search has been submitted. */
  @Builder
  hint() {
    Column() {
      Text(this.searchPlaceholder())
        .fontSize(14)
        .fontColor($r('app.color.text_muted'))
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .transition(this.sectionTransition())
  }

  private openLogin(): void {
    Nav.openLogin();
  }
}