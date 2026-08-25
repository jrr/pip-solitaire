// The win overlay (#121): a dimmed panel over the board announcing the win, with a
// New Game button to play on — and, when the driver has a deal number to hand out, a
// Share button beside it (#264).
//
// **Lifted out of `TableScene`'s `mount` body (#319).** It was ~115 lines of
// `createElement` / `setAttribute` / `appendChild` in the middle of a 1,989-line
// function, and it is one of the two cuts that issue names as not needing the
// board's closure: it wants the tally, the timing and a couple of callbacks, and
// nothing at all about `nodes` or `zones`. Which makes it a component in exactly the
// sense #307 gave the menu — and its stylesheet (`TableScene.css`) was already
// sitting beside it.
//
// The panel is **raised once and torn down whole**, never diffed: `TableScene` builds
// it with `Html.create` (as it already does for all 52 cards) and removes the node
// when a win is undone out of, or when the board it belongs to is rebuilt. That's why
// it can stay a pure `props => vnode` despite having something that changes on screen
// — see the status line below.
//
// Top to bottom: the headline, the time it took, the tally, the buttons, and the
// share status. Each of the two optional pieces is optional for its own reason,
// spelled out on its field.
//
// A component is just a `props => vnode` function (see `VersionBadge` for why the
// record is spelled out by hand).

// The victory share (#264), offered only when the driver has a deal to hand out.
//
// `onShare` is called straight from the click with nothing awaited in front of it, so
// the gesture's transient activation survives into `navigator.share` (see
// `ShareLink.deliver`). That's affordable precisely because a victory shares the
// *deal*: a `?seed=` link is built from a number, with no compression standing
// between the tap and the sheet. It answers with the line to show.
type share = {onShare: unit => promise<string>}

type props = {
  // How long it took (#302), between the headline and the tally: the biggest of the
  // three numbers to look at, since it's the one you'd say out loud. Its own element
  // rather than another clause on the tally line, because it's the one that can be
  // missing — a game restored from a save written before the clock existed has no
  // time to report, and a line that sometimes reads "94 moves · 0 undos" and
  // sometimes "4:07 · 94 moves · 0 undos" is harder to read at a glance than a line
  // that's sometimes simply not there.
  time: option<string>,
  // What the game cost (#289): every move made and every undo taken.
  tally: string,
  // Re-deal and play on. `TableScene` builds a fresh board, which tears this panel
  // down with the rest of the old one.
  onNewGame: unit => unit,
  // `None` withholds the Share button entirely — on a board with no deal number to
  // name (a posed `?state=` position, or a game landed from a `#g=` link), and on a
  // game the solver had a hand in (#291). A shared victory is a claim about how you
  // played, and "I typed `autoplay`" isn't one worth passing on, so the button is
  // simply not built rather than built and made to explain itself. Deciding that is
  // the caller's: this component only knows whether it was handed one.
  share: option<share>,
}

let make = ({time, tally, onNewGame, share}) => {
  // The status line is written into *after* the fact: the share resolves long after
  // this vnode was rendered, and a panel raised through `Html.create` renders exactly
  // once (see `Html.create` — there is no re-render to hold state for), so the node
  // is captured by a callback ref rather than re-rendered with new text.
  //
  // Writing into it is safe even if the panel has been torn down by the time the
  // share resolves (an undo out of the win, a New Game): the node is detached by
  // then, and setting text on it changes nothing anyone sees.
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
      // The buttons sit in a row of their own, so a second one lands beside New Game
      // rather than under it and the panel stays as wide as its widest line.
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
      // Where the link went — the only acknowledgement a desktop player gets, since
      // the clipboard route opens no OS sheet. Unlike the menu's, it doesn't clear
      // itself: the panel is torn down by the very next thing the player does, so
      // there's no stale state for a timer to save us from. Its height is reserved in
      // CSS (see TableScene.css) so the line landing doesn't jostle the buttons above
      // it — which is also why it's only rendered where there's a share to report on.
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
