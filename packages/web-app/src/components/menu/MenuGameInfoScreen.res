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
// "i" was tapped, rather than to the game itself — the game in a paragraph, a still of
// the opening board, the board's numbers, the choice of which board of its family this
// is, and the link out to the rules in full. `<GameInfo>` decides the paragraph, the
// numbers and the link, `BoardPreview` the still and `<MenuVariantPicker>` the choice;
// this file only places them.
//
// **The paragraph is the lede**, above the picture rather than below the picker, and
// that is the one placement the two rules below leave for it: the still has to sit on
// the numbers and the numbers on the picker, so prose between any of them would come
// between a thing and its caption. It answers "what is this game" before the screen
// shows one, which is the order a reader who tapped an "i" is reading in.
//
// **The still comes next**, above the numbers, because it is what the numbers are
// counting: eight columns and four cells are easier to read off a board than off a
// line. It is the opening board of deal #1 in the table's own markup, not a screenshot,
// so it follows the picker's choice and the card design with no asset to regenerate.
//
// **The picker sits directly under the numbers** because the numbers are what it
// changes: picking Mini takes eight cascades to four and 52 cards to 20, on the line
// immediately above it. The link out stays last, being the way off this screen.
//
// **Scope is deliberately short of the design.** The "this game / Enter Seed" block is a
// later pass; the layout is a plain column so that adding it is an insertion rather than
// a rework.

%%raw(`import "./MenuGameInfoScreen.css"`)

type props = {
  info: GameInfo.t,
  // The other boards of this game's family, where the menu is offering more than one of
  // them — which Spiderette pack, which FreeCell size. `None` on a game that is a game
  // on its own, and that is a screen with no such section at all rather than a section
  // holding the one choice there is to make.
  variants?: MenuVariantPicker.props,
  // Sloppy placement, as the player has it set: the still's cards lie as the table's
  // do, tilted or square.
  tilt: bool,
  onClose: unit => unit,
  onBackToMenu: unit => unit,
}

let make = ({info, ?variants, tilt, onClose, onBackToMenu}) => <>
  <MenuHeader
    title={info.name}
    back={Some({label: "Back to menu", onClick: onBackToMenu})}
    onTitleTap=None
    onClose
  />
  <div className="menu-screen">
    // The game in prose, for a reader who has played a solitaire game or two. One
    // paragraph for the whole family (`GameInfo.description`), so the picker below
    // changes the board and the numbers and never the words.
    {switch info.description {
    | Some(text) =>
      <MenuSection label="how it plays">
        <p className="game-info__prose"> {Html.string(text)} </p>
      </MenuSection>
    | None => Html.empty
    }}
    // The opening board, on a mat of its own. What a reader hears instead is the game's
    // name: the still is the board, and nothing the numbers below don't say.
    //
    // The mat is one size for the whole family (`info.previewBox`), so the picker below
    // redraws the board without moving itself and everything under it down the panel.
    <MenuSection label="preview" modifier="game-info__preview">
      {BoardPreview.make(
        ~label={info.name ++ ", as dealt"},
        ~tilt,
        ~box=info.previewBox,
        info.opening,
      )}
    </MenuSection>
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
      // It is *drawn* as one too (`game-info__link`): a line of underlined text rather
      // than a full-width control box, because it leaves the app, and a control the
      // size of "Restart" would offer it as though it were one of the game's own.
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
