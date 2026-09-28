import { Nav } from '../common/Nav';

/** Height of the header's content row, excluding the status bar. */
export const IMMERSIVE_ROW_HEIGHT: number = 44;
const BLUR_RADIUS: number = 15;
const FRACTION_STOPS: [number, number][] = [[0, 0], [0.8, 0.2], [1, 0.4], [1, 1]];

/**
 * The app's immersive header, used by every page that has one.
 *
 * ArkUI's own system material (`uiMaterial` / `systemMaterial`) is API 26 while
 * HarmonyOS 6.1 devices are API 23~25, so the 6.1 look is built here from a
 * gradient scrim plus `linearGradientBlur`, and HDS covers the bottom bar. The
 * scrim paints behind the status bar, so callers never have to offset anything:
 * pass the status-bar inset as `topInset` and the header reserves it.
 *
 * The slot is filled with a trailing closure, which keeps the recipe in one
 * place while letting each page put whatever it needs in the row (section
 * labels, a title, a search field).
 */
@Component
export struct ImmersiveHeader {
  /** Status-bar inset; the scrim paints behind the clock. */
  @Prop topInset: number = 0;
  /** Height of the content row, excluding the status bar. */
  @Prop rowHeight: number = IMMERSIVE_ROW_HEIGHT;
  /** 0 while shown, negative while slid away. */
  @Prop offsetY: number = 0;
  /** Fades the header out; `translate` alone leaves its shadow behind. */
  @Prop visible: boolean = true;
  /** Draws a back chevron that pops the navigation stack. */
  showBack: boolean = false;

  @Builder
  defaultContent() {
  }

  @BuilderParam content: () => void = this.defaultContent;

  /** Total height the header occupies, including the status bar. */
  totalHeight(): number {
    return this.topInset + this.rowHeight;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.scrim()

      Column() {
        Row() {
          if (this.showBack) {
            this.backButton()
          }
          this.content()
        }
        .width('100%')
        .height(this.rowHeight)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding({ top: this.topInset })
    }
    .width('100%')
    .height(this.totalHeight())
    .translate({ y: this.offsetY })
    .opacity(this.visible ? 1 : 0)
  }

  /** Gradient layer: look only, never a hit target. */
  @Builder
  scrim() {
    Column() {
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      direction: GradientDirection.Bottom,
      colors: [
        [$r('app.color.top_bar_mask_start'), 0],
        [$r('app.color.top_bar_mask_mid'), 0.8],
        [$r('app.color.top_bar_mask_end'), 0.95],
        [$r('app.color.top_bar_mask_end'), 1]
      ]
    })
    .linearGradientBlur(BLUR_RADIUS, {
      fractionStops: FRACTION_STOPS,
      direction: GradientDirection.Top
    })
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  backButton() {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      Text('\u2039')
        .fontSize(24)
        .fontColor($r('app.color.text_primary'))
    }
    .width(36)
    .height(36)
    .backgroundColor(Color.Transparent)
    .margin({ left: 6 })
    .onClick(() => {
      Nav.back();
    })
  }
}
