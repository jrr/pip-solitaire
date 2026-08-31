// "Enter seed": the deal number a player types, on a panel raised over everything.
//
// The far end of Share Seed. That button puts a number on screen precisely so it can
// be carried somewhere else — read off a screenshot, dictated over a phone — and this
// is where it comes back in.
//
// **A modal rather than a row in the menu.** Typing is the whole of what this asks
// for, and on a phone the keyboard that arrives to do it covers most of the slide-over
// panel a field would have sat in. Raised over the screen instead, it wears the win
// overlay's dimmed-panel look — the `--panel-*` tokens in `styles/base.css` — so the
// two moments the app stops to hold a conversation read as one shape.
//
// **What's typed is not this component's to hold.** It arrives as `seed` and goes back
// out through `onSeed`, because a component under `components/` renders once into a
// host that is thrown away and so has nowhere to keep it (see the entry condition in
// `runtime/Html.res`). The chrome's model owns the text; this is a controlled field
// over it.
//
// **A deal number is read by `core`, not here.** `Command.dealNumber` is the same
// reading the typed `deal 24680` gets, digits-only so "12abc" opens no board — two
// readings would mean the console and the menu taking different vocabularies for the
// same number. It also settles the button: nothing to deal is a real `disabled`, so an
// empty field's Deal is inert rather than a press that quietly does nothing.

%%raw(`import "./SeedDialog.css"`)

type props = {
  // The text in the field, as the model holds it — not necessarily a number.
  seed: string,
  onSeed: string => unit,
  // Called only with a number `core` accepts, so a caller has no parse to repeat.
  onDeal: int => unit,
  // Backdrop and Cancel, which are the same answer: leave the board alone. The dialog
  // is raised over the menu it was opened from and that menu is still there
  // underneath, so dismissing puts the player back where they pressed Enter Seed.
  onCancel: unit => unit,
}

let make = ({seed, onSeed, onDeal, onCancel}) => {
  let number = Command.dealNumber(String.trim(seed))
  <div id="seed-dialog" role="dialog" ariaModal="true" ariaLabel="Enter seed">
    <div className="seed-dialog__backdrop" onClick={_ => onCancel()} />
    // The panel *is* the form, so Enter deals: on a phone the keyboard's Go key is the
    // only submit within reach without dismissing the keyboard first, and it sits
    // where the eye already is. `preventDefault` because the browser's own idea of
    // submitting is to navigate away.
    <form
      className="seed-dialog__panel"
      onSubmit={event => {
        Html.preventDefault(event)
        number->Option.forEach(onDeal)
      }}
    >
      <p className="seed-dialog__title"> {Html.string("Enter seed")} </p>
      <p className="seed-dialog__hint"> {Html.string("Type a deal number to open that board.")} </p>
      <input
        className="seed-dialog__field"
        type_="text"
        // Digits are all this takes, so ask a phone for the number pad — and turn off
        // every helper that assumes prose: a deal number is not a word, and nothing
        // this device has been told about other forms on other sites applies to it.
        inputMode="numeric"
        autocomplete="off"
        ariaLabel="Deal number"
        placeholder="deal number"
        value={seed}
        onInput={event => onSeed(Html.inputValue(event))}
        // Focused as the panel mounts. A modal raised for the sole purpose of being
        // typed into that arrives unfocused costs a tap, and on a phone that tap is
        // what brings the keyboard up. Preact calls a ref again whenever the callback's
        // identity changes — every keystroke's re-render, here — which is harmless:
        // focusing the element that already has focus does nothing at all.
        ref={el => el->Nullable.toOption->Option.forEach(WebDom.focus)}
      />
      // Deal is the primary of the two and sits on the right, where the thumb that
      // just finished typing is; Cancel takes the panel's slate so the eye lands on
      // the action first, the way Share does beside New Game on the win panel.
      <div className="seed-dialog__actions">
        <button
          className="seed-dialog__button seed-dialog__button--cancel"
          type_="button"
          onClick={_ => onCancel()}
        >
          {Html.string("Cancel")}
        </button>
        <button className="seed-dialog__button" type_="submit" disabled={number->Option.isNone}>
          {Html.string("Deal")}
        </button>
      </div>
    </form>
  </div>
}
