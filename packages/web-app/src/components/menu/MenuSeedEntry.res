// "Enter seed": a deal number typed in, and the Deal button that opens it.
//
// The counterpart to Random above it — the same "new game", with the board named
// rather than invented — and the far end of Share Seed's link: a number read off
// somebody else's screen (or dictated over a phone) gets to the identical board
// with no URL in between, which is the whole reason the seed rides on the Share
// button as digits.
//
// **What's typed is not this component's to hold.** It arrives as `seed` and goes
// back out through `onSeed`, because a component under `components/` renders once
// into a host that is thrown away and so has nowhere to keep it (see the entry
// condition in `runtime/Html.res`). The chrome's model owns the text; this is a
// controlled field over it.
//
// **A deal number is read by `core`, not here.** `Command.dealNumber` is the same
// reading the typed `deal 24680` gets, digits-only so "12abc" opens no board —
// two readings would mean the console and the menu taking different vocabularies
// for the same number. It also settles the button: nothing to deal is a real
// `disabled`, so an empty field's Deal is inert rather than a press that quietly
// does nothing.

%%raw(`import "./MenuSeedEntry.css"`)

type props = {
  // The text in the field, as the model holds it — not necessarily a number.
  seed: string,
  onSeed: string => unit,
  // Called only with a number `core` accepts, so a caller has no parse to repeat.
  onDeal: int => unit,
}

let make = ({seed, onSeed, onDeal}) => {
  let number = Command.dealNumber(String.trim(seed))
  // A `<form>`, so Enter deals: the field is one input and a button, and on a
  // phone the keyboard's Go key is the only submit within reach without
  // dismissing the keyboard first. `preventDefault` because the browser's own
  // idea of submitting is to navigate away.
  <form
    className="menu-seed"
    ariaLabel="Enter seed"
    onSubmit={event => {
      Html.preventDefault(event)
      number->Option.forEach(onDeal)
    }}
  >
    <input
      className="menu-seed__field"
      type_="text"
      // Digits are all this takes, so ask a phone for the number pad — and turn
      // off every helper that assumes prose: a deal number is not a word, and
      // nothing this device has been told about other forms on other sites
      // applies to it.
      inputMode="numeric"
      autocomplete="off"
      ariaLabel="Deal number"
      placeholder="deal number"
      value={seed}
      onInput={event => onSeed(Html.inputValue(event))}
    />
    <button className="menu-button menu-seed__deal" type_="submit" disabled={number->Option.isNone}>
      {Html.string("Deal")}
    </button>
  </form>
}
