// The dimmed panel announcing a win: headline, time, tally, buttons, share status.
//
// It needs nothing of the board's closure, which is what lets it be a pure component
// rather than more of `TableScene`'s `mount` body; its stylesheet is `TableScene.css`,
// which owns the board it's raised over. **Raised once and torn down whole**, never
// diffed — that is how it stays a pure `props => vnode` despite having something on it
// that changes (see the status line below).

// `onShare` is called straight from the click with nothing awaited in front of it, so
// the gesture's transient activation survives into `navigator.share`. Affordable
// precisely because a victory shares the *deal*: nothing to compress between tap and
// sheet. It answers with the line to show.
type share = {onShare: unit => promise<string>}

type props = {
  // Its own element rather than another clause on the tally, because it's the one that
  // can be missing — a save written before the clock existed has no time to report,
  // and a line that sometimes reads "94 moves · 0 undos" and sometimes "4:07 · 94
  // moves · 0 undos" is harder to read at a glance than one that's sometimes absent.
  time: option<string>,
  tally: string,
  onNewGame: unit => unit,
  // `None` withholds the Share button entirely — a board with no deal number to name,
  // or a game the solver had a hand in. A shared victory is a claim about how you
  // played, so the button is not built rather than built and made to explain itself.
  // Deciding that is the caller's; this only knows whether it was handed one.
  share: option<share>,
}

let make = ({time, tally, onNewGame, share}) => {
  // Written into *after* the fact: the share resolves long after this vnode rendered,
  // and a panel raised through `Html.create` renders exactly once, so the node is
  // captured by a callback ref rather than re-rendered with new text. Safe even if the
  // panel is gone by then — the node is detached, and setting text on it shows nobody
  // anything.
  let statusLine: ref<option<Html.element>> = ref(None)

  let report = line => statusLine.contents->Option.forEach(el => el->WebDom.setTextContent(line))

  <div className="win-overlay">
    <div className="win-panel">
      <p className="win-panel__title"> {Html.string("You win!")} </p>
      {switch time {
      | Some(text) => <p className="win-panel__time"> {Html.string(text)} </p>
      | None => Html.empty
      }}
      <p className="win-panel__stats"> {Html.string(tally)} </p>
      // A row of their own, so a second button lands beside New Game rather than under
      // it and the panel stays as wide as its widest line.
      <div className="win-panel__actions">
        <button className="win-panel__button" type_="button" onClick={_ => onNewGame()}>
          {Html.string("New Game")}
        </button>
        {switch share {
        | Some({onShare}) =>
          <button
            className="win-panel__button win-panel__button--share"
            type_="button"
            onClick={_ => onShare()->Promise.thenResolve(report)->ignore}
          >
            {Html.string("Share")}
          </button>
        | None => Html.empty
        }}
      </div>
      // The only acknowledgement a desktop player gets, since the clipboard route
      // opens no OS sheet. It doesn't clear itself: the panel is torn down by the very
      // next thing the player does. Its height is reserved in CSS so the line landing
      // doesn't jostle the buttons, which is also why it's built only where there is a
      // share to report on.
      {switch share {
      | Some(_) =>
        <p
          className="win-panel__status"
          ariaLive="polite"
          ref={el => statusLine := el->Nullable.toOption}
        />
      | None => Html.empty
      }}
    </div>
  </div>
}
