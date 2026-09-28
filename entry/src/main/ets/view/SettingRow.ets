/**
 * One tappable row of a settings list: a symbol, a label, and the chevron that
 * says it goes somewhere.
 *
 * The Me tab lists the collections this way and the settings page lists what it
 * configures the same way, so the row lives here; where a row leads is the
 * page's business.
 */
@Component
export struct SettingRow {
  @Prop icon: Resource = $r('sys.symbol.gearshape_fill');
  @Prop label: Resource = $r('app.string.settings');
  onTap: () => void = () => {
  };

  build() {
    Row() {
      SymbolGlyph(this.icon)
        .fontSize(18)
        .fontColor([$r('app.color.accent')])
      Text(this.label)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: 10 })
        .layoutWeight(1)
      Text('\u203a')
        .fontSize(18)
        .fontColor($r('app.color.text_muted'))
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(12)
    .margin({ top: 12 })
    .onClick(() => {
      this.onTap();
    })
  }
}
