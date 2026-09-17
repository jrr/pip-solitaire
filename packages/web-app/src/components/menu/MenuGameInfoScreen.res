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
// family's boards to look at it as, the board's numbers, the game in a paragraph, and
// the link out to the game's Wikipedia article. `<GameInfo>` decides the numbers, the
// paragraph and the link, `BoardPreview` the still and `<MenuVariantPicker>` the boards;
// this file only places them.
//
// **The picker sits directly under the still, because the still is what it changes.**
// A tap on Mini redraws the board a thumb's height above the thumb that did it, and the
// numbers on the line just below go from eight cascades to four in the same glance:
// everything a pick moves is within reach of the finger, and everything below — the
// paragraph and the link — is the family's and holds still. What makes that hold is
// the box the still is drawn in being one size for the whole family
// (`GameInfo.previewBox`): the picker never moves under the thumb, and the numbers
// change digits, not position.
//
// **It is unheaded.** The picker is the one control on a screen that is otherwise all
// description, and it sits between a picture and that picture's caption; a "PACK" or
// "SIZE" over it would break the still from its numbers with a word the marks already
// say. The word survives as the section's accessible name (`picker.noun`), where it
// names the group without drawing anything.
//
// **The still comes first**, because it is what the numbers are counting: eight
// columns and four cells are easier to read off a board than off a line. It is the
// opening board of deal #1 in the table's own markup, not a screenshot, so it follows
// the picker and the card design with no asset to regenerate.
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

// Wikipedia's W — the Linux Libertine letter their wordmark is set in, as Simple Icons
// traces it (`wikipedia`, package CC0-1.0). Inlined like the About screen's GitHub mark
// and the top bar's undo glyph: a file to fetch is a file that can be missing, and
// `currentColor` lets it take the link's ink. A dependency on the pack would be three
// thousand brand icons carried for one path, and an update to it could only ever change
// this one letter.
//
// **Not the file Commons calls "Wikipedia's W.svg"**, which is the obvious place to
// reach for and the wrong letter: public domain, genuine, and *retired*. It is Hoefler
// Text, the W of the logo before the 2010 redesign, and its middle apex stops short of
// the cap height where the live one reaches it with a serif on top. What is here matches
// the wordmark en.wikipedia.org serves today, to a third of a percent on proportions.
//
// **The serifs survive the size**, which is the reason to take the real letter rather
// than approximate it: at the size this is drawn the brackets and slabs still read as
// serifs, and they are what makes it a W from an encyclopedia rather than a W. It is also
// what tells the mark from the app's own icons, which are all one monoline weight.
//
// Using the mark to link to Wikipedia is a use the Wikimedia Foundation's trademark
// policy allows without a licence, and it is the *linking* that it allows — so this glyph
// belongs inside the `<a>` and has no business anywhere else in the app.
let markWikipedia = "M12.09 13.119c-.936 1.932-2.217 4.548-2.853 5.728-.616 1.074-1.127.931-1.532.029-1.406-3.321-4.293-9.144-5.651-12.409-.251-.601-.441-.987-.619-1.139-.181-.15-.554-.24-1.122-.271C.103 5.033 0 4.982 0 4.898v-.455l.052-.045c.924-.005 5.401 0 5.401 0l.051.045v.434c0 .119-.075.176-.225.176l-.564.031c-.485.029-.727.164-.727.436 0 .135.053.33.166.601 1.082 2.646 4.818 10.521 4.818 10.521l.136.046 2.411-4.81-.482-1.067-1.658-3.264s-.318-.654-.428-.872c-.728-1.443-.712-1.518-1.447-1.617-.207-.023-.313-.05-.313-.149v-.468l.06-.045h4.292l.113.037v.451c0 .105-.076.15-.227.15l-.308.047c-.792.061-.661.381-.136 1.422l1.582 3.252 1.758-3.504c.293-.64.233-.801.111-.947-.07-.084-.305-.22-.812-.24l-.201-.021c-.052 0-.098-.015-.145-.051-.045-.031-.067-.076-.067-.129v-.427l.061-.045c1.247-.008 4.043 0 4.043 0l.059.045v.436c0 .121-.059.178-.193.178-.646.03-.782.095-1.023.439-.12.186-.375.589-.646 1.039l-2.301 4.273-.065.135 2.792 5.712.17.048 4.396-10.438c.154-.422.129-.722-.064-.895-.197-.172-.346-.273-.857-.295l-.42-.016c-.061 0-.105-.014-.152-.045-.043-.029-.072-.075-.072-.119v-.436l.059-.045h4.961l.041.045v.437c0 .119-.074.18-.209.18-.648.03-1.127.18-1.443.421-.314.255-.557.616-.736 1.067 0 0-4.043 9.258-5.426 12.339-.525 1.007-1.053.917-1.503-.031-.571-1.171-1.773-3.786-2.646-5.71l.053-.036z"

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
    // The mat is one size for the whole family (`info.previewBox`), so a pick on the
    // control under it redraws the board without moving that control, or anything
    // below it.
    <MenuSection label="preview" modifier="game-info__preview">
      {BoardPreview.make(
        ~label={info.name ++ ", as dealt"},
        ~tilt,
        ~box=info.previewBox,
        info.opening,
      )}
    </MenuSection>
    // The family's boards, named for a screen reader with the word for what they vary
    // in — "pack", "size" — which is the picker's own (`GameVariant.nounFor`) and so
    // names the group without this screen knowing which families there are. No visible
    // heading: see the header.
    {switch variants {
    | Some(picker) =>
      <MenuSection label={picker.noun}> {MenuVariantPicker.make(picker)} </MenuSection>
    | None => Html.empty
    }}
    // The board's shape in one line. Labelled but unheaded: the numbers name
    // themselves, and a caption over them would say "numbers" twice.
    <MenuSection label="numbers">
      <p className="game-info__numbers"> {Html.string(GameInfo.numbers(info))} </p>
    </MenuSection>
    // The game in prose, for a reader who has played a solitaire game or two. One
    // paragraph for the whole family (`GameInfo.description`), so the picker above
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
      //
      // **The mark carries it alone.** Everything the words used to say is already on
      // the screen: which game this is, in the title, and what it plays like, in the
      // paragraph over the link. What was left to say is that there is a page about it,
      // and that is the one thing a mark says faster than a line of text can.
      //
      // Which leaves the mark carrying the link's whole name, so it is written where a
      // reader who can't see it will still be given it: `aria-label` for a screen
      // reader, `title` for a pointer that rests on it. `GameInfo.referenceLabel` is
      // that name, and it stays the sentence it would have been on screen — "Spider on
      // Wikipedia" — rather than shrinking to "Wikipedia", because the article a
      // Spiderette goes to is worth knowing *before* the trip.
      //
      // Whether it asks for a tab of its own is `LinkOut`'s answer and not this
      // screen's — the app is a PWA and the answer differs by platform. `rel` is what
      // stops the opened page from reaching back through `window.opener`.
      <a
        className="game-info__link"
        href={info.reference}
        target=?{LinkOut.target()}
        rel="noopener noreferrer"
        ariaLabel={GameInfo.referenceLabel(info)}
        title={GameInfo.referenceLabel(info)}
      >
        <span className="game-info__badge">
          <svg className="game-info__mark" viewBox="0 0 24 24" ariaHidden="true" focusable="false">
            <path d={markWikipedia} fill="currentColor" />
          </svg>
        </span>
      </a>
    </MenuSection>
  </div>
</>
