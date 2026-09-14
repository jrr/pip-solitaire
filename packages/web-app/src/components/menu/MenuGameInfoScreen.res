// The menu's **game info screen**: what a game *is*, reached from the "i" beside its
// row in the Games list. `Menu` puts the About footer under it.
//
// Its title is the game's name rather than a fixed caption, which is the one thing
// that tells this screen apart from the other three at a glance — and why the subject
// travels in `Menu`'s `screen` variant rather than in a props record built on every
// render (see `Menu.screen`). The name is the one a player calls the game by, so a board
// of a family is headed by the family (`GameInfo.nameOf`): which of them this is, the
// picker below says.
//
// Top to bottom: a header whose **back** button returns to the main menu — where the
// "i" was tapped, rather than to the game itself — the board's numbers, the choice of
// which board of its family this is, and the link out to the rules in full. `<GameInfo>`
// decides the numbers and the link and `<MenuVariantPicker>` the choice; this file only
// places them.
//
// **The picker sits directly under the numbers** because the numbers are what it
// changes: picking Mini takes eight cascades to four and 52 cards to 20, on the line
// immediately above it. The link out stays last, being the way off this screen.
//
// **Scope is deliberately short of the design.** The screenshot of the opening board,
// the paragraph describing play, and the "this game / Enter Seed" block below it are
// later passes; the layout is a plain column so that adding them is an insertion rather
// than a rework.

%%raw(`import "./MenuGameInfoScreen.css"`)

type props = {
  info: GameInfo.t,
  // The other boards of this game's family, where the menu is offering more than one of
  // them — which Spiderette pack, which FreeCell size. `None` on a game that is a game
  // on its own, and that is a screen with no such section at all rather than a section
  // holding the one choice there is to make.
  variants?: MenuVariantPicker.props,
  onClose: unit => unit,
  onBackToMenu: unit => unit,
}

let make = ({info, ?variants, onClose, onBackToMenu}) => <>
  <MenuHeader
    title={info.name}
    back={Some({label: "Back to menu", onClick: onBackToMenu})}
    onTitleTap=None
    onClose
  />
  <div className="menu-screen">
    // The board's shape in one line. Labelled but unheaded: the numbers name
    // themselves, and a caption over them would say "numbers" twice.
    <MenuSection label="numbers">
      <p className="game-info__numbers"> {Html.string(GameInfo.numbers(info))} </p>
    </MenuSection>
    // The family's boards, headed with the word for what they vary in — "PACK", "SIZE" —
    // which is the picker's own (`GameVariant.nounFor`) and so names the group without
    // this screen knowing which families there are.
    {switch variants {
    | Some(picker) =>
      <MenuSection label={picker.noun} heading={picker.noun}>
        {MenuVariantPicker.make(picker)}
      </MenuSection>
    | None => Html.empty
    }}
    <MenuSection label="reference">
      // A real link rather than a button that navigates, so it can be opened in a new
      // tab, long-pressed, or copied — all the things a reader expects of a link out.
      // `target="_blank"` keeps the game on the table: the app is a PWA, and following
      // a link in place would tear down a board mid-play. `rel` is what stops the
      // opened page from reaching back through `window.opener`.
      <a
        className="game-info__link" href={info.reference} target="_blank" rel="noopener noreferrer"
      >
        {Html.string("Read the rules on Wikipedia")}
      </a>
    </MenuSection>
  </div>
</>
