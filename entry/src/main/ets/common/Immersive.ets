import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'Immersive';

/** Raw system bar insets, in px as reported by the window manager. */
export class Insets {
  top: number = 0;
  bottom: number = 0;

  constructor(top: number, bottom: number) {
    this.top = top;
    this.bottom = bottom;
  }
}

const BARS_VISIBLE: Array<'status' | 'navigation'> = ['status', 'navigation'];
const BARS_HIDDEN: Array<'status' | 'navigation'> = [];

/**
 * Edge-to-edge (immersive) window handling.
 *
 * HarmonyOS keeps the main window out of the system bar areas by default, which
 * is why the bars can look detached from the content. Turning on the immersive
 * layout lets the app draw behind the status bar and the navigation indicator;
 * the caller then pads its own bars with the reported insets so nothing ends up
 * under the clock or the gesture handle.
 */
export class Immersive {
  /** Enables the edge-to-edge layout and reports the system bar insets (px). */
  static async enable(context: common.UIAbilityContext): Promise<Insets> {
    try {
      const win: window.Window = await window.getLastWindow(context);
      await win.setWindowLayoutFullScreen(true);
      const system: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const indicator: window.AvoidArea =
        win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      return new Insets(system.topRect.height, indicator.bottomRect.height);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'could not enable immersive layout');
      return new Insets(0, 0);
    }
  }

  /**
   * Switches between the inline (portrait, system bars visible) and full-screen
   * (landscape, system bars hidden) player presentations.
   */
  static async setFullscreen(context: common.UIAbilityContext, fullscreen: boolean): Promise<void> {
    try {
      const win: window.Window = await window.getLastWindow(context);
      await win.setWindowLayoutFullScreen(true);
      await win.setPreferredOrientation(fullscreen
        ? window.Orientation.LANDSCAPE
        : window.Orientation.PORTRAIT);
      await win.setWindowSystemBarEnable(fullscreen ? BARS_HIDDEN : BARS_VISIBLE);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'could not switch presentation');
    }
  }
}
