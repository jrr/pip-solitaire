// The menu's **main screen**, lifted out of `Menu` into its own pure
// component. What the pane shows when the menu opens; `Menu` puts the About
// footer under it.
//
// Top to bottom:
//   - the **title** ("Pip") beside the ✕;
//   - a **"new game"** section — the two ways to open a board that isn't this one:
//     **Random** (a seed the driver invents) and **Enter Seed**, which raises the
//     `<SeedDialog>` modal over the menu for a deal number to be typed into. The
//     split is which board you get, which is the question a player actually has;
//   - a **"this game"** section — what can be done with the deal already on the
//     table: **Restart** (re-deals the *same* seed to replay it) and **Share Seed**
//     (hands over a `?seed=` link to it). Which deal that is, the *heading* names —
//     "this game 24680" — so the number describes the section rather than one of the
//     two buttons under it, and both buttons stay the same size on every board;
//
//     Everything that re-deals — Random, Deal, Restart — calls the scene's hook for it
//     and closes the menu, so the board it opened is what you're looking at; on a scene
//     with no game (a demo) those hooks are no-ops. Share Seed is the odd one out: it
//     *keeps* the menu open, because the line under the buttons reporting where the
//     link went is the only confirmation there is, and it's the only game button that
//     ever renders *disabled* — on a board with no seed to name;
//   - a **"Games"** section — the games this build offers as top-level rows, FreeCell
//     among them. They arrive as `games`, a list of `MenuRow.entry` the
//     switcher's scene list is turned into, and are drawn here — data rather than a
//     node the switcher builds and this screen splices in (see `games` below);
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
  // The seed of the board on the table: the "this game" heading names it, and Share
  // Seed hands over a link to it. `None` is why that button greys out — a demo scene
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
  games: array<MenuRow.entry>,
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
  shareDealSeed,
  shareDealStatus,
  onShareDeal,
  games,
  onOpenSettings,
}) => <>
  <MenuHeader title="Pip" back=None onTitleTap=None onClose />
  <MenuSection label="new game" heading="new game">
    <div className="menu-buttons">
      <MenuGameButton label="Random" enabled=true onClick=onNewGame />
      <MenuGameButton label="Enter Seed" enabled=true onClick=onEnterSeed />
    </div>
  </MenuSection>
  // The heading carries the deal number, so the section says which board its two
  // buttons act on. A player can read it off (or dictate it) where no link can be
  // delivered at all — which is the far end of `SeedDialog`. Absent on a board with
  // no seed, where the line below says why.
  <MenuSection
    label="this game"
    heading="this game"
    headingValue=?{shareDealSeed->Option.map(seed => Int.toString(seed))}
  >
    <div className="menu-buttons">
      <MenuGameButton label="Restart" enabled=true onClick=onRestart />
      // Share Seed. The only game button that ever goes `disabled` — the
      // real attribute, so no click is emitted at all, with the handler guard behind
      // it as belt and braces — because a board with no seed has no link to hand out.
      <MenuGameButton
        label="Share Seed" enabled={shareDealSeed->Option.isSome} onClick=onShareDeal
      />
    </div>
    <p className="menu-share-line" ariaLive="polite">
      {Html.string(shareLine(~seed=shareDealSeed, ~status=shareDealStatus))}
    </p>
  </MenuSection>
  <MenuSection label="Games" heading="Games" tag=Nav>
    {games
    ->Array.map(entry =>
      <MenuRow
        label={entry.label} selected=?{entry.selected} onClick={entry.onSelect} key={entry.label}
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
