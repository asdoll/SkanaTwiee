import { IMMERSIVE_ROW_HEIGHT, ImmersiveHeader } from './ImmersiveHeader';

const SECTION_TEXT_SIZE: number = 15;
const INDICATOR_WIDTH: number = 18;
const INDICATOR_HEIGHT: number = 3;

/**
 * Section labels for a page, drawn inside the shared immersive header.
 *
 * The surface itself is ImmersiveHeader, so the scrim, the status-bar inset and
 * the hide-on-scroll translation behave exactly like every other header in the
 * app. The bar owns its own section labels so the Following and Search screens
 * can carry different sets, and an optional `extra` row (the Search input) sits
 * under them on the same surface.
 */
@Component
export struct TopTabBar {
  /** Section labels, in display order. */
  labels: Resource[] = [];
  /** Currently selected section. */
  @Prop index: number = 0;
  @Prop topInset: number = 0;
  /** 0 while shown, negative while hidden above the screen. */
  @Prop offsetY: number = 0;
  /** Height of the extra slot below the labels; 0 when the page has none. */
  @Prop extraHeight: number = 0;
  @Prop visible: boolean = true;
  onSelect: (index: number) => void = (index: number) => {
  };

  @Builder
  defaultExtra() {
  }

  /** Page-specific row under the labels, e.g. the search input. */
  @BuilderParam extra: () => void = this.defaultExtra;

  /** Total height the bar occupies, including the status bar. */
  totalHeight(): number {
    return this.topInset + IMMERSIVE_ROW_HEIGHT + this.extraHeight;
  }

  build() {
    ImmersiveHeader({
      topInset: this.topInset,
      rowHeight: IMMERSIVE_ROW_HEIGHT + this.extraHeight,
      offsetY: this.offsetY,
      visible: this.visible
    }) {
      Column() {
        Row() {
          ForEach(this.labels, (label: Resource, position: number) => {
            this.tabItem(label, position)
          }, (label: Resource, position: number) => position.toString())
        }
        .width('100%')
        .height(IMMERSIVE_ROW_HEIGHT)

        this.extra()
      }
      .width('100%')
    }
  }

  @Builder
  tabItem(label: Resource, position: number) {
    Column() {
      Text(label)
        .fontSize(SECTION_TEXT_SIZE)
        .fontWeight(this.index === position ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.index === position ? $r('app.color.accent') : $r('app.color.text_secondary'))

      Row() {
      }
      .width(INDICATOR_WIDTH)
      .height(INDICATOR_HEIGHT)
      .borderRadius(INDICATOR_HEIGHT / 2)
      .backgroundColor(this.index === position ? $r('app.color.accent') : Color.Transparent)
      .margin({ top: 5 })
    }
    .height(IMMERSIVE_ROW_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 14, right: 14 })
    .onClick(() => {
      this.onSelect(position);
    })
  }
}
