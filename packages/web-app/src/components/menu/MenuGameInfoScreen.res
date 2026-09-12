// The menu's **game info screen**: what a game *is*, reached from the "i" segment
// beside its row in the Games list. `Menu` puts the About footer under it.
//
// Its title is the game's name rather than a fixed caption, which is the one thing
// that tells this screen apart from the other three at a glance — and why the subject
// travels in `Menu`'s `screen` variant rather than in a props record built on every
// render (see `Menu.screen`).
//
// Top to bottom: a header whose **back** button returns to the main menu — where the
// "i" was tapped, rather than to the game itself — the board's numbers, and the link
// out to the rules in full. `<GameInfo>` decides all three; this file only places them.
//
// **Scope is deliberately short of the design.** The screenshot of the opening board,
// the paragraph describing play, and the "this game / Enter Seed" block below it are
// later passes (#427); what is here is the numbers and the reference, and the layout is
// a plain column so that adding them is an insertion rather than a rework.

%%raw(`import "./MenuGameInfoScreen.css"`)

type props = {
  info: GameInfo.t,
  onClose: unit => unit,
  onBackToMenu: unit => unit,
}

let make = ({info, onClose, onBackToMenu}) => <>
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
