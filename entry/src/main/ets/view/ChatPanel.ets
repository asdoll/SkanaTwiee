import { ChatMessage } from '../model/ChatMessage';
import { ChatToken, ChatText } from '../util/ChatText';
import { Emote, EmoteRepository } from '../repository/EmoteRepository';

const EMOTE_SIZE: number = 22;
/** Height of the message rows; the list scrolls back through history. */
const ROW_PADDING: number = 6;

/**
 * The comments panel under the player.
 *
 * Live and replay share it: a replay simply has no input, because a VOD's chat
 * happened in the past. Messages arrive already filtered by the caller - the
 * replay hands them over as playback reaches them - so this only renders.
 */
@Component
export struct ChatPanel {
  /**
   * The caller's own array, shared rather than copied.
   *
   * A plain member would have been captured once at construction and a @Prop
   * copies; @Link is what keeps this pointing at the list the caller appends to.
   * `version` is bumped alongside so the list redraws.
   */
  @Link lines: ChatMessage[];
  @Prop @Watch('onVersionChanged') version: number = 0;
  /** True for live chat, which can also send. */
  @Prop canSend: boolean = false;
  /** Channel id, for the picker's channel emote set. */
  @Prop channelId: string = '';
  /** '' when chat is fine, otherwise what to tell the user. */
  @Prop statusText: string = '';

  onSend: (text: string) => void = (text: string) => {
  };
  @State emotes: Emote[] = [];
  @State showEmotes: boolean = false;
  @State draft: string = '';
  private scroller: Scroller = new Scroller();
  private lastCount: number = 0;

  onVersionChanged(): void {
    if (this.lines.length !== this.lastCount) {
      this.lastCount = this.lines.length;
      // Live chat reads best pinned to the newest line.
      this.scroller.scrollEdge(Edge.Bottom);
    }
  }

  aboutToAppear(): void {
    this.loadEmotes();
  }

  private async loadEmotes(): Promise<void> {
    this.emotes = await EmoteRepository.load(this.channelId);
  }

  build() {
    Column() {
      if (this.statusText.length > 0) {
        Text(this.statusText)
          .fontSize(12)
          .fontColor($r('app.color.text_muted'))
          .width('100%')
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      }

      List({ scroller: this.scroller }) {
        ForEach(this.lines, (item: ChatMessage) => {
          ListItem() {
            this.row(item)
          }
        }, (item: ChatMessage) => item.key())
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      if (this.canSend) {
        this.input()
      }

      if (this.showEmotes) {
        this.emotePicker()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  row(item: ChatMessage) {
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
      Text(item.userName.length > 0 ? item.userName : item.userLogin)
        .fontSize(13)
        .fontColor(item.color.length > 0 ? `#${item.color}` : $r('app.color.accent'))
        .padding({ right: 6 })

      ForEach(ChatText.tokenize(item), (token: ChatToken) => {
        if (token.isEmote()) {
          Image(EmoteRepository.imageUrl(token.emoteId))
            .width(EMOTE_SIZE)
            .height(EMOTE_SIZE)
            .objectFit(ImageFit.Contain)
            .draggable(false)
        } else {
          Text(token.text)
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
        }
      }, (token: ChatToken, index: number) => `${item.key()}-${index}`)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: ROW_PADDING, bottom: ROW_PADDING })
  }

  @Builder
  input() {
    Row() {
      TextInput({ placeholder: $r('app.string.chat_hint'), text: this.draft })
        .placeholderColor($r('app.color.text_muted'))
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.surface_alt'))
        .height(38)
        .layoutWeight(1)
        .onChange((value: string) => {
          this.draft = value;
        })
        .onSubmit(() => {
          this.submit();
        })

      this.iconButton($r('sys.symbol.face_smiling'), () => {
        this.showEmotes = !this.showEmotes;
      })

      this.iconButton($r('sys.symbol.paperplane_fill'), () => {
        this.submit();
      })
    }
    .width('100%')
    .padding({ left: 10, right: 6, top: 6, bottom: 6 })
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  iconButton(symbol: Resource, onTap: () => void) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(symbol)
        .fontSize(20)
        .fontColor([$r('app.color.text_primary')])
    }
    .width(38)
    .height(38)
    .backgroundColor(Color.Transparent)
    .onClick(() => {
      onTap();
    })
  }

  private submit(): void {
    const text: string = this.draft;
    if (text.trim().length === 0) {
      return;
    }
    this.onSend(text);
    this.draft = '';
  }

  /** Emotes are inserted by name: Twitch's server resolves them on the way out. */
  @Builder
  emotePicker() {
    Column() {
      if (this.emotes.length === 0) {
        Text($r('app.string.no_emotes'))
          .fontSize(13)
          .fontColor($r('app.color.text_muted'))
          .width('100%')
          .padding(16)
      } else {
        Scroll() {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.emotes, (emote: Emote) => {
              Image(EmoteRepository.imageUrl(emote.id))
                .width(32)
                .height(32)
                .objectFit(ImageFit.Contain)
                .margin(6)
                .draggable(false)
                .onClick(() => {
                  this.append(emote.name);
                })
            }, (emote: Emote) => emote.id)
          }
          .width('100%')
        }
        .height(132)
        .width('100%')
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: '100%' }))
      .animation({ duration: 220, curve: Curve.FastOutSlowIn }))
  }

  private append(name: string): void {
    const separator: string = this.draft.length > 0 && !this.draft.endsWith(' ') ? ' ' : '';
    this.draft = `${this.draft}${separator}${name}`;
  }
}
