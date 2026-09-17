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
// "i" was tapped, rather than to the game itself — a still of the opening board, the
// board's numbers, the game in a paragraph, the link out to the game's Wikipedia article,
// and last the choice of which board of its family this is. `<GameInfo>` decides the
// numbers, the paragraph and the link, `BoardPreview` the still and `<MenuVariantPicker>`
// the choice; this file only places them.
//
// **The description runs from what a reader takes in at a glance to what they have to
// read**, and the one control comes after all of it: a picture, the numbers counting
// what is in the picture, the paragraph saying how it plays, the page to go on reading
// on. The picker is the only control on a screen that is otherwise all description, so
// it sits under the description rather than in it — and a reader going down the screen
// reads in one direction, with nothing to step back over.
//
// **What that costs is the picker's feedback.** Picking Mini takes eight cascades to
// four and 52 cards to 20 on the numbers line, which is now three items above the thumb
// that did it rather than one line up. Keeping the box the still is drawn in fixed
// (`GameInfo.previewBox`) is what makes that affordable: the numbers stay exactly where
// they were, so the change up there is a change of digits and not of position.
//
// **The still comes first**, above the numbers, because it is what the numbers are
// counting: eight columns and four cells are easier to read off a board than off a
// line. It is the opening board of deal #1 in the table's own markup, not a screenshot,
// so it follows the picker's choice and the card design with no asset to regenerate.
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
    action=Html.empty
    onTitleTap=None
    onClose
  />
  <div className="menu-screen">
    // The opening board, on a mat of its own. What a reader hears instead is the game's
    // name: the still is the board, and nothing the numbers below don't say.
    //
    // The mat is one size for the whole family (`info.previewBox`), so a pick at the foot
    // of the screen redraws the board without moving the numbers, the paragraph and the
    // link between them and it.
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
    <MenuSection label="reference">
      // A real link rather than a button that navigates, so it can be opened in a new
      // tab, long-pressed, or copied — all the things a reader expects of a link out.
      // It is *drawn* as one too (`game-info__link`): a line of underlined text rather
      // than a full-width control box, because it leaves the app, and a control the
      // size of "Restart" would offer it as though it were one of the game's own.
      //
      // Whether it asks for a tab of its own is `LinkOut`'s answer and not this
      // screen's — the app is a PWA and the answer differs by platform. `rel` is what
      // stops the opened page from reaching back through `window.opener`.
      <a
        className="game-info__link"
        href={info.reference}
        target=?{LinkOut.target()}
        rel="noopener noreferrer"
      >
        {Html.string(GameInfo.referenceLabel(info))}
      </a>
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
  </div>
</>
