import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Const } from '../common/Const';
import { Nav } from '../common/Nav';
import { AuthRepository } from '../repository/AuthRepository';
import { IntegrityRepository } from '../repository/IntegrityRepository';
import { LoginParams } from '../model/Routes';
import { TwitchUser } from '../model/TwitchUser';

const DOMAIN: number = 0x0000;
const TAG: string = 'Login';
const POLL_INTERVAL_MS: number = 2000;
const MAX_POLLS: number = 150;
/** The homepage makes gql calls of its own, so it mints a signature reliably. */
const HOME_FALLBACK_DELAY_MS: number = 4000;
/**
 * How many times the home page may be swapped in for the signature run.
 *
 * Bounded because the swap exists only to let Twitch mint the integrity
 * signature on a gql call of its own; while nobody is signed in it never does,
 * and re-loading the page every few seconds leaves the WebView reloading for
 * ever instead of settling on something the user can read.
 */
const MAX_HOME_LOADS: number = 3;

/**
 * Twitch login, and the place an integrity signature is obtained.
 *
 * Xtra intercepts the Authorization header that twitch.tv itself sends to
 * gql.twitch.tv/gql while the user is signed in. ArkWeb exposes outgoing request
 * headers through WebResourceRequest.getRequestHeader(), so the same headers are
 * read here: the OAuth token from Authorization signs the user in, and the
 * Client-Integrity signature is the one thing Twitch accepts on follow/unfollow
 * (Xtra's IntegrityDialog.kt).
 *
 * The stored session is written into the auth-token cookie before the page
 * loads, which is how Xtra signs its WebView in without a password prompt. When
 * the page is opened only to capture the signature, it closes itself as soon as
 * one arrives.
 */
@Component
export struct LoginPage {
  private controller: webview.WebviewController = new webview.WebviewController();
  @State statusKey: string = 'waiting';
  @State errorDetail: string = '';
  /** Set by the route when the page only has to mint an integrity signature. */
  @State forVerification: boolean = false;
  @State signatureCaptured: boolean = false;
  private captured: boolean = false;
  private busy: boolean = false;
  private polls: number = 0;
  private timerId: number = -1;
  private fallbackTimerId: number = -1;
  /** The auth-token cookie is written once, before the first load. */
  private cookieApplied: boolean = false;
  /** Home-page swaps used to chase the integrity signature; see scheduleFallback. */
  private homeLoads: number = 0;

  aboutToAppear(): void {
    this.schedulePoll();
  }

  aboutToDisappear(): void {
    this.stopPoll();
    this.stopFallback();
  }

  build() {
    NavDestination() {
      this.content()
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      const params: LoginParams | undefined = context.pathInfo.param as LoginParams | undefined;
      if (params !== undefined) {
        this.forVerification = params.verify === true;
      }
      this.applySessionCookie();
    })
  }

  /**
   * Signs the page in from the stored token, the way Xtra's IntegrityDialog does.
   * The web engine only exists once a Web component does, so this is retried from
   * the first onPageEnd when it is too early.
   *
   * Returns true only when a cookie was written *just now*, because that is the
   * one case that needs the page reloaded for the cookie to take effect. Signed
   * out (nothing to write) returns false: treating that as "written" is what used
   * to load the Twitch home page the instant the sign-in form appeared, before
   * anyone could type in it.
   */
  private applySessionCookie(): boolean {
    if (this.cookieApplied) {
      return false;
    }
    const token: string = AuthRepository.token();
    if (token.length === 0) {
      // Nothing to sign in with; the form is what the user needs to see.
      this.cookieApplied = true;
      return false;
    }
    try {
      webview.WebCookieManager.configCookieSync('https://www.twitch.tv',
        `${Const.AUTH_TOKEN_COOKIE}=${token}`);
      this.cookieApplied = true;
      return true;
    } catch (e) {
      hilog.debug(DOMAIN, TAG, 'cookie write deferred');
      return false;
    }
  }

  /**
   * Reads the Client-Integrity signature Twitch's page puts on its own gql calls,
   * together with the device id it was issued for: the two are only valid as a
   * pair, so both are kept.
   */
  private captureIntegrity(request: WebResourceRequest): void {
    if (request === undefined) {
      return;
    }
    const url: string = request.getRequestUrl();
    if (url === undefined || url.indexOf(Const.GQL_HOST) < 0) {
      return;
    }
    const headers: Header[] = request.getRequestHeader();
    if (headers === undefined) {
      return;
    }
    let integrity: string = '';
    let deviceId: string = '';
    for (let i = 0; i < headers.length; i++) {
      const key: string = headers[i].headerKey;
      const value: string = headers[i].headerValue;
      if (key === undefined || value === undefined) {
        continue;
      }
      const name: string = key.toLowerCase();
      if (name === Const.HEADER_INTEGRITY.toLowerCase()) {
        integrity = value;
      } else if (name === Const.HEADER_DEVICE_ID.toLowerCase()) {
        deviceId = value;
      }
    }
    if (integrity.length === 0) {
      return;
    }
    IntegrityRepository.saveCaptured(integrity, deviceId);
    this.signatureCaptured = true;
    hilog.info(DOMAIN, TAG, 'integrity signature captured');
    if (this.forVerification) {
      this.stopPoll();
      this.stopFallback();
      Nav.back();
    }
  }

  private scheduleFallback(): void {
    // Only the verification run swaps the home page in. When the user is signing
    // in, the form stays where it is until it yields a token - swapping it out
    // under their fingers is what made the page look like it was reloading for
    // ever.
    if (!this.forVerification || this.fallbackTimerId !== -1
      || this.homeLoads >= MAX_HOME_LOADS) {
      return;
    }
    this.fallbackTimerId = setTimeout(() => {
      this.fallbackTimerId = -1;
      if (this.signatureCaptured || this.captured || this.homeLoads >= MAX_HOME_LOADS) {
        return;
      }
      this.homeLoads++;
      this.loadHome();
    }, HOME_FALLBACK_DELAY_MS);
  }

  private stopFallback(): void {
    if (this.fallbackTimerId !== -1) {
      clearTimeout(this.fallbackTimerId);
      this.fallbackTimerId = -1;
    }
  }

  private loadHome(): void {
    try {
      this.controller.loadUrl(Const.TWITCH_HOME_URL);
    } catch (e) {
      hilog.debug(DOMAIN, TAG, 'home load failed');
    }
  }

  @Builder
  content() {
    Column() {
      Row() {
        Text($r('app.string.login'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Button($r('app.string.login'))
          .fontSize(13)
          .backgroundColor($r('app.color.accent'))
          .fontColor(Color.White)
          .enabled(!this.captured)
          .onClick(() => {
            this.tryCapture();
          })
      }      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .backgroundColor($r('app.color.surface'))

      Divider()
        .color($r('app.color.divider'))

      Text(this.statusText())
        .fontSize(12)
        .fontColor($r('app.color.text_muted'))
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })

      if (this.errorDetail.length > 0) {
        Text(this.errorDetail)
          .fontSize(12)
          .fontColor($r('app.color.live'))
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 8 })
      }

      Web({ src: Const.TWITCH_LOGIN_URL, controller: this.controller })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(false)
        .imageAccess(true)
        .zoomAccess(true)
        .layoutWeight(1)
        .width('100%')
        .onInterceptRequest((event) => {
          if (event !== undefined) {
            this.captureIntegrity(event.request);
          }
          // Not intercepted: the page loads normally.
          return null;
        })
        .onPageEnd(() => {
          if (this.applySessionCookie()) {
            // A stored session was just written into the cookie jar, so the page
            // has to be loaded again to pick it up.
            this.loadHome();
            this.scheduleFallback();
            return;
          }
          this.scheduleFallback();
          this.tryCapture();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  private statusText(): string {
    if (this.forVerification) {
      return this.signatureCaptured
        ? 'Verified. Returning\u2026'
        : 'Verifying with Twitch\u2026';
    }
    if (this.captured) {
      return 'Signed in. Returning\u2026';
    }
    switch (this.statusKey) {
      case 'checking':
        return 'Checking credentials\u2026';
      case 'waiting':
        return 'Sign in to Twitch in the page below.';
      default:
        return 'Sign in to Twitch in the page below.';
    }
  }

  private schedulePoll(): void {
    this.timerId = setTimeout(() => {
      this.tryCapture();
      if (!this.captured && this.polls < MAX_POLLS) {
        this.schedulePoll();
      }
    }, POLL_INTERVAL_MS);
  }

  private stopPoll(): void {
    if (this.timerId !== -1) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
  }

  private async tryCapture(): Promise<void> {
    // Verification only waits for the signature, which arrives on its own.
    if (this.forVerification || this.captured || this.busy) {
      return;
    }
    this.polls++;
    this.busy = true;
    this.statusKey = 'checking';
    try {
      const token: string = await this.readToken();
      if (token.length === 0) {
        this.statusKey = 'waiting';
        return;
      }
      const user: TwitchUser | undefined = await AuthRepository.save(token, Const.GQL_WEB_CLIENT_ID);
      if (user === undefined) {
        this.errorDetail = 'Twitch rejected the token; try signing in again.';
        this.statusKey = 'waiting';
        return;
      }
      this.captured = true;
      this.errorDetail = '';
      this.stopPoll();
      Nav.back();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'capture failed: %{public}s', JSON.stringify(e));
      this.statusKey = 'waiting';
    } finally {
      this.busy = false;
    }
  }

  private async readToken(): Promise<string> {
    // 1. localStorage["auth-token"], the way the Twitch web app persists it.
    try {
      const script: string = '(function(){try{var t=window.localStorage.getItem("auth-token");'
        + 'if(t){return String(t);}}catch(e){}'
        + 'try{var m=document.cookie.match(/(?:^|;\\s*)auth-token=([^;]+)/);'
        + 'if(m){return decodeURIComponent(m[1]);}}catch(e){}'
        + 'return "";})()';
      const raw: string = await this.controller.runJavaScript(script);
      const token: string = LoginPage.stripQuotes(raw);
      if (token.length > 0) {
        return token;
      }
    } catch (e) {
      hilog.debug(DOMAIN, TAG, 'localStorage read failed');
    }

    // 2. Fallback: the auth-token cookie.
    try {
      const cookies: string = webview.WebCookieManager.fetchCookieSync(Const.TWITCH_HOME_URL);
      return LoginPage.tokenFromCookies(cookies);
    } catch (e) {
      return '';
    }
  }

  private static tokenFromCookies(cookies: string): string {
    const parts: string[] = cookies.split(';');
    for (let i = 0; i < parts.length; i++) {
      const part: string = parts[i].trim();
      if (part.startsWith('auth-token=')) {
        return part.substring('auth-token='.length);
      }
    }
    return '';
  }

  private static stripQuotes(value: string): string {
    let out: string = value.trim();
    if (out.length >= 2 && out.startsWith('"') && out.endsWith('"')) {
      out = out.substring(1, out.length - 1);
    }
    out = out.replace('\\"', '"');
    if (out === 'null' || out === 'undefined') {
      return '';
    }
    return out;
  }
}
