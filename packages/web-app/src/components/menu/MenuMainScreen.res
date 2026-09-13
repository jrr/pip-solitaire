// The menu's **main screen**, lifted out of `Menu` into its own pure
// component. What the pane shows when the menu opens; `Menu` puts the About
// footer under it.
//
// Top to bottom:
//   - the **title** ("Pip") beside the ✕;
//   - a **"this game"** section — what can be done with the deal already on the
//     table: **Restart** (re-deals the *same* seed to replay it) and **Share**
//     (hands over a `?seed=` link to it). Which deal that is, the *heading* names —
//     "FreeCell #24680" — so the game and its number describe the section rather than
//     one of the two buttons under it, and both buttons stay the same size on every
//     board. It leads, because the board it is about is the one already on the screen;
//   - a **"new game"** section — headed with the question it answers, "Don't like
//     it?" — the two ways to open a board that isn't this one: **New Deal** (a seed
//     the driver invents) and **Enter Seed**, which raises the `<SeedDialog>` modal
//     over the menu for a deal number to be typed into. The split is which board you
//     get, which is the question a player actually has;
//
//     Everything that re-deals — New Deal, Deal, Restart — calls the scene's hook for
//     it and closes the menu, so the board it opened is what you're looking at; on a
//     scene with no game (a demo) those hooks are no-ops. Share is the odd one out: it
//     *keeps* the menu open, because the line under the buttons reporting where the
//     link went is the only confirmation there is, and it's the only game button that
//     ever renders *disabled* — on a board with no seed to name;
//   - a **"Games"** section — the games this build offers as top-level rows, FreeCell
//     and Simple Simon today. They arrive as `games`, a list of `MenuGameRow.props` the
//     switcher's scene list is turned into, and are drawn here — data rather than a
//     node the switcher builds and this screen splices in (see `games` below). A row is
//     the game's name, and — behind the Game info flag — an "i" beside it that opens
//     what that game is;
//   - --- the space between top and bottom grows here (`menu-section--bottom`) ---
//   - a single **Settings** button (`onOpenSettings`) low in the menu, just above the
//     About footer — it takes over the pane with the Settings screen.
//
// The screen renders as a fragment (header + sections, no wrapper), so the panel's
// flex column still sees the sections directly and `--bottom`'s `margin-top: auto`
// keeps pushing the Settings button to the foot.

%%raw(`import "./MenuMainScreen.css"`)

type props = {
  onClose: unit => unit,
  onNewGame: unit => unit,
  // "Enter Seed" — raise the seed dialog. The typing and the dealing are that
  // modal's, and it is raised over this screen rather than placed in it, so all this
  // screen holds of the feature is the button that asks for it.
  onEnterSeed: unit => unit,
  onRestart: unit => unit,
  // The game the board on the table is a board of — "FreeCell" — which heads the
  // section whose two buttons act on it, in front of that board's deal number. `None`
  // on a scene that is no game at all (a demo), where the heading says what the
  // section is instead of which game it is about.
  gameName: option<string>,
  // The seed of the board on the table: the "this game" heading names it, and Share
  // hands over a link to it. `None` is why that button greys out — a demo scene
  // has no seed, and neither does a game restored from a save written before seeds
  // were kept. The seed is passed rather than a bare bool so the section can *name*
  // it: a share is easier to trust when you can see the number going out.
  shareDealSeed: option<int>,
  // The transient line under the buttons reporting where the link went.
  shareDealStatus: option<string>,
  onShareDeal: unit => unit,
  // The games to list, in order, with `selected` on whichever one is showing. Data
  // rather than the switcher's own DOM: the scene it has mounted is a value
  // the chrome holds, so the highlight moves the way every other row's state does —
  // through the diff, on the next render.
  //
  // A `<MenuGameRow>`'s own props rather than a `MenuRow.entry`, because a game's row
  // carries one thing the other lists' rows don't: the "i" that opens its info screen,
  // absent while the feature flag is off.
  games: array<MenuGameRow.props>,
  onOpenSettings: unit => unit,
}

// The line under the "this game" buttons. It reports what became of a share ("Link
// copied to clipboard.") or, on a board with nothing to share, why the button is
// greyed out — and is otherwise *empty*, the seed itself riding on the heading.
//
// Empty, but always rendered: the slot holds its height (`min-height`, see
// MenuMainScreen.css) so the confirmation appears and clears without shoving the
// sections below it. That reflow is the whole reason the line is unconditional
// rather than a node that comes and goes.
let shareLine = (~seed: option<int>, ~status: option<string>): string =>
  switch (status, seed) {
  | (Some(status), _) => status
  | (None, None) => "No seed for this board."
  | (None, Some(_)) => ""
  }

let make = ({
  onClose,
  onNewGame,
  onEnterSeed,
  onRestart,
  gameName,
  shareDealSeed,
  shareDealStatus,
  onShareDeal,
  games,
  onOpenSettings,
}) => <>
  <MenuHeader title="Pip" back=None onTitleTap=None onClose />
  // The heading carries the game and its deal number, so the section says which board
  // its two buttons act on. A player can read the number off (or dictate it) where no
  // link can be delivered at all — which is the far end of `SeedDialog`. Absent on a
  // board with no seed, where the line below says why.
  //
  // The accessible name stays "this game" whichever game that is: it is the group's
  // standing name — what these controls act on — rather than the changing thing the
  // visible heading reports.
  <MenuSection
    label="this game"
    heading={gameName->Option.getOr("this game")}
    headingValue=?{shareDealSeed->Option.map(seed => Int.toString(seed))}
  >
    <div className="menu-buttons">
      <MenuGameButton label="Restart" enabled=true onClick=onRestart />
      // Share. The only game button that ever goes `disabled` — the
      // real attribute, so no click is emitted at all, with the handler guard behind
      // it as belt and braces — because a board with no seed has no link to hand out.
      <MenuGameButton label="Share" enabled={shareDealSeed->Option.isSome} onClick=onShareDeal />
    </div>
    <p className="menu-share-line" ariaLive="polite">
      {Html.string(shareLine(~seed=shareDealSeed, ~status=shareDealStatus))}
    </p>
  </MenuSection>
  // A question rather than a caption, and the one a player is asking when they reach
  // for either of these: the typographic apostrophe, since this is prose the menu says
  // out loud rather than a label naming a control.
  <MenuSection label="new game" heading="Don’t like it?">
    <div className="menu-buttons">
      <MenuGameButton label="New Deal" enabled=true onClick=onNewGame />
      <MenuGameButton label="Enter Seed" enabled=true onClick=onEnterSeed />
    </div>
  </MenuSection>
  <MenuSection label="Games" heading="Games" tag=Nav>
    {games
    ->Array.map(game =>
      <MenuGameRow
        label={game.label}
        selected={game.selected}
        onSelect={game.onSelect}
        onInfo=?{game.onInfo}
        key={game.label}
      />
    )
    ->Html.array}
  </MenuSection>
  <MenuSection modifier="menu-section--bottom">
    <button className="menu-button" onClick={_ => onOpenSettings()} type_="button">
      {Html.string("Settings")}
    </button>
  </MenuSection>
</>
