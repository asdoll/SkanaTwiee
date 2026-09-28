/**
 * Metrics shared by every menu of choices in the app: the player's quality and
 * rate menus, and the Me tab's playback defaults.
 */
/** Width of a menu card. */
export const MENU_WIDTH: number = 240;
/** Height of one row in a menu. */
export const MENU_ROW_HEIGHT: number = 46;
/** Taller than this and a menu scrolls instead of growing further. */
export const MENU_LIST_MAX_HEIGHT: number = 320;

/** What a bound popup reports when it opens or closes. */
export interface PopupStateParam {
  isVisible: boolean;
}

/** A menu's rows, up to the point where it has to scroll instead. */
export function menuListHeight(rows: number): number {
  const height: number = rows * MENU_ROW_HEIGHT;
  return height > MENU_LIST_MAX_HEIGHT ? MENU_LIST_MAX_HEIGHT : height;
}

/**
 * One row of a menu of choices: the label, and a tick on the one in use.
 *
 * A menu is the same list of one-of-these rows wherever it is opened, so the row
 * itself is shared; the card and what happens on a tap stay with the page.
 */
@Component
export struct MenuChoice {
  @Prop label: string = '';
  @Prop selected: boolean = false;
  onTap: () => void = () => {
  };

  build() {
    Row() {
      Text(this.label)
        .fontSize(15)
        .fontColor(this.selected ? $r('app.color.accent') : $r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (this.selected) {
        Text('\u2713')
          .fontSize(16)
          .fontColor($r('app.color.accent'))
          .margin({ left: 6 })
      }
    }
    .width('100%')
    .height(MENU_ROW_HEIGHT)
    .padding({ left: 14, right: 14 })
    .onClick(() => {
      this.onTap();
    })
  }
}
