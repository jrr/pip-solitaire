// **Play a deal** — the way into a *named* board from inside the app, and the other
// half of Share Seed (#98).
//
// Share Seed puts a deal number into the world: a `?seed=` link, and the digits
// themselves on the button so they can be read aloud or typed. Until now there was
// nowhere to type them back *in*. A link works when a link can be followed, but an
// installed app is exactly the case where it often can't — iOS home-screen web apps
// can't claim URLs, so a friend's `?seed=` link opens a browser tab beside the
// installed game rather than the game — and then the number a player is looking at
// ("♣️♥️♠️♦️ Pip FreeCell #776701") has no way in. This is that way in. The debug
// console's `deal <n>` (#273) has always been able to do it; this is the same act,
// promoted out of developer chrome into the menu.
//
// **Why a dialog and not another row in the menu.** The menu's game section is a
// column of *commands* — one tap, one thing happens. This one needs an answer before
// it can act, and the answer needs a keyboard. A field living permanently in the menu
// would sit there focus-hungry and empty on every visit, for an action taken once in a
// hundred opens; the pane also already carries a screen stack (Main/Settings/Debug),
// and a screen is only reachable *through* the menu, whereas this wants to be
// openable from anywhere later (a win overlay's "play another", a `?seed=` link that
// didn't parse). So: a modal, the app's first — built out of the parts it already had.
//
// **The shape is the win overlay's** (`.win-overlay`/`.win-panel` in index.html): a
// scrim, a centred panel, an action row, and a status line whose height is reserved so
// text landing in it doesn't shove the buttons. What it borrows is the *geometry*, not
// the costume — the win panel's gold border means victory, so this takes the chrome's
// slate (`#0f1a2e` on `#22304a`) and `.menu-button` actions, and reads as menu family.
// Where it differs is placement: the win overlay lives *inside* `.table-board`, which
// isolates its own stacking context and is torn down on the next deal, while this is
// chrome — a sibling of the menu in the root context at `z-index: 30`, above the menu's
// 20 and the console's 15. Those numbers stay small and readable precisely because the
// board keeps its own (900/1000/100000) to itself.
//
// **The field is a real DOM node this module owns**, spliced in with `Html.node`,
// exactly like `DebugConsole`'s input line and for the same reason: `Html`'s
// reconciler does a positional diff with no keys (#45), so an `<input>` rendered as a
// vnode loses its caret, its selection and whatever was half-typed in it on every
// re-render — and a status line landing under it is a re-render. That also settles
// where the typed text lives: in the DOM, not in the chrome model, which only ever
// holds open/closed and the status line.
//
// Following `DebugConsole` again, the props are display state only and the *actions*
// are installed once (`setHandlers`): the keys are bound to the element at module init,
// long before any props exist, and having the buttons route through the same pair keeps
// one path in rather than two that can drift.

// --- The field ------------------------------------------------------------------
// Matched on `event.code` like the console's, so the physical key works whatever the
// layout calls it.
type keyEvent
@get external code: keyEvent => string = "code"
@get external repeat: keyEvent => bool = "repeat"
@send external preventDefault: keyEvent => unit = "preventDefault"
@send
external addKeyListener: (WebDom.element, string, keyEvent => unit) => unit = "addEventListener"
@get external value: WebDom.element => string = "value"
@set external setValue: (WebDom.element, string) => unit = "value"
@send external focus: WebDom.element => unit = "focus"
@send external blur: WebDom.element => unit = "blur"
@send external select: WebDom.element => unit = "select"

let input = WebDom.createElement("input")
input->WebDom.setAttribute("id", "deal-dialog-input")
input->WebDom.setAttribute("class", "deal-dialog__input")
// `text`, deliberately not `number`: a spinner is meaningless on a deal number (there
// is no "next" board), and a numeric input renders the value through the page's locale,
// which would put a thousands separator in the middle of a number whose whole job is to
// be transcribed exactly. `inputmode` is what actually matters on a phone — it asks for
// the digit keypad without any of that.
input->WebDom.setAttribute("type", "text")
input->WebDom.setAttribute("inputmode", "numeric")
input->WebDom.setAttribute("aria-label", "Deal number")
input->WebDom.setAttribute("placeholder", "776701")
// A deal number is not prose: nothing here should be autocorrected, capitalised, or
// completed from the browser's memory of other forms on other sites.
input->WebDom.setAttribute("autocomplete", "off")
input->WebDom.setAttribute("autocapitalize", "off")
input->WebDom.setAttribute("autocorrect", "off")
input->WebDom.setAttribute("spellcheck", "false")

// --- Reading what was typed --------------------------------------------------------

// What the field currently holds, as far as dealing a board is concerned.
type entry =
  | Blank // nothing typed — the player pressed Play on an empty field
  | Invalid // something typed, but it doesn't name a deal
  | Seed(int)

// The longest run of digits that still fits an int with room to spare. A deal number is
// six digits (`Main`'s `randomSeed` draws below 1,000,000), so this refuses nothing a
// player could have been given while keeping a pasted essay out of `Int.fromString`.
let maxDigits = 9

let isDigits = (s: string): bool =>
  s != "" &&
    s
    ->String.split("")
    ->Array.every(ch =>
      switch ch->String.codePointAt(0) {
      | Some(point) => point >= 48 && point <= 57
      | None => false
      }
    )

// Turn the raw field text into an `entry`.
//
// The leading `#` is stripped rather than rejected, and that's the one piece of
// leniency here worth arguing for: the victory share (`ShareLink.victoryMessage`) says
// "Pip FreeCell #776701", so `#776701` is precisely what a player copies out of the
// message they were sent. Refusing the app's own notation would be perverse.
//
// Everything else is strict — every remaining character must be a digit. It would be
// easy to lean on `Int.fromString` alone, but that is `parseInt`-shaped: it reads
// `12abc` as 12, and a dialog that silently deals a *different* board from the one
// named is worse than one that says it didn't understand.
//
// `Invalid` carries nothing, deliberately: the console echoes the rejected token back
// because its reply scrolls away from what was typed, but here the field is still on
// screen directly above the message, holding the very text being complained about.
// Repeating it would be noise — and unbounded noise, since nothing caps the length of
// something that isn't a number, which is exactly how a one-line status slot turns into
// a two-line one and shoves the buttons out from under the thumb reaching for them.
let readSeed = (text: string): entry => {
  let trimmed = text->String.trim
  let digits =
    trimmed->String.startsWith("#")
      ? trimmed->String.slice(~start=1, ~end=String.length(trimmed))->String.trim
      : trimmed
  if digits == "" {
    Blank
  } else if String.length(digits) <= maxDigits && isDigits(digits) {
    switch Int.fromString(digits) {
    | Some(seed) => Seed(seed)
    | None => Invalid
    }
  } else {
    Invalid
  }
}

// --- What the buttons and keys do --------------------------------------------------
// Installed once by `Main` (see `setHandlers`), for the same reason `DebugConsole`
// installs its runner: acting on a deal number means reaching the scene switcher and
// the board's re-deal hook, which this module has no business knowing about. Until
// then — and on a page where nothing installed them — Play and Enter are inert.
let submitHandler: ref<option<string => unit>> = ref(None)
let cancelHandler: ref<unit => unit> = ref(() => ())

let setHandlers = (~onSubmit: string => unit, ~onCancel: unit => unit): unit => {
  submitHandler := Some(onSubmit)
  cancelHandler := onCancel
}

// The raw text goes out, not a parsed seed: `readSeed`'s verdict decides both what
// happens *and* what the status line says, and both of those belong to the caller.
let submit = (): unit => submitHandler.contents->Option.forEach(run => run(input->value))
let cancel = (): unit => cancelHandler.contents()

// Enter plays, Escape cancels — the console's pairing, and the two a dialog owes a
// keyboard. A held key repeats, which would fire the deal over and over, hence the
// `repeat` guard.
input->addKeyListener("keydown", event =>
  if !repeat(event) {
    switch code(event) {
    | "Enter" | "NumpadEnter" =>
      preventDefault(event)
      submit()
    | "Escape" =>
      preventDefault(event)
      cancel()
    | _ => ()
    }
  }
)

// --- Open / closed -----------------------------------------------------------------
// The chrome model owns the flag; this is the post-update effect that makes it true of
// the live field, exactly as `DebugConsole.apply` is for the panel. Only the
// *transitions* do anything, so calling it on an unrelated update (a status line
// landing) can't clobber what's half-typed.
let showing = ref(false)

// Called with the deal on the table so the field can open **prefilled with it**, text
// selected. Two things fall out of that, both wanted: the field says what shape of
// thing goes in it without needing a caption, and the first keystroke replaces the
// selection, so a player typing a number they were given is never deleting first.
//
// Focus follows the dialog for the reason the console's does: opening it means you want
// to type at it, and closing must hand the keyboard back rather than leave a hidden
// field holding it. It runs inside the click's own task (the loop calls effects
// synchronously), so the gesture's transient activation is intact and a phone actually
// raises its keyboard.
let apply = (~open_: bool, ~seed: option<int>): unit => {
  switch (open_, showing.contents) {
  | (true, false) =>
    input->setValue(seed->Option.map(seed => Int.toString(seed))->Option.getOr(""))
    focus(input)
    select(input)
  | (false, true) =>
    blur(input)
    // Cleared on the way out, not on the way in: a dialog that reopens holding the
    // rejected text from last time is a dialog that reopens showing an error.
    input->setValue("")
  | (true, true) | (false, false) => ()
  }
  showing := open_
}

// --- The shell ---------------------------------------------------------------------
// A pure `props => vnode` in the `Menu`/`DebugConsole` mold (see `VersionBadge` for why
// the props record is spelled out by hand). `status` is the line under the field —
// why a deal wasn't dealt — and is otherwise empty; like the menu's share line it is
// always rendered, so the slot holds its height and a message can't shove the buttons
// down as it appears.
type props = {
  open_: bool,
  status: option<string>,
}

let make = ({open_, status}) =>
  <div
    id="deal-dialog"
    hidden={!open_}
    attrs={[
      ("role", "dialog"),
      ("aria-modal", "true"),
      ("aria-label", "Play a deal"),
      ("aria-hidden", open_ ? "false" : "true"),
    ]}
  >
    // Clicking away cancels, as it does on the menu's backdrop. It's a sibling of the
    // panel rather than its parent so a click *inside* the panel never reaches it.
    <div className="deal-dialog__backdrop" onClick={_ => cancel()} />
    <div className="deal-dialog__panel">
      <h2 className="deal-dialog__title"> {Html.string("Play a deal")} </h2>
      // The `#` is a plain sibling of the field, the same arrangement (and for the same
      // reason) as the console prompt's `>`: it marks what the digits are without
      // becoming part of the value, and a `::before` on an input isn't possible.
      <div className="deal-dialog__field">
        <span className="deal-dialog__hash" attrs={[("aria-hidden", "true")]}>
          {Html.string("#")}
        </span>
        {Html.node(input)}
      </div>
      <p className="deal-dialog__status" attrs={[("aria-live", "polite")]}>
        {Html.string(status->Option.getOr(""))}
      </p>
      <div className="deal-dialog__actions">
        <button className="menu-button" onClick={_ => cancel()} attrs={[("type", "button")]}>
          {Html.string("Cancel")}
        </button>
        <button
          className="menu-button deal-dialog__play"
          onClick={_ => submit()}
          attrs={[("type", "button")]}
        >
          {Html.string("Play")}
        </button>
      </div>
    </div>
  </div>
