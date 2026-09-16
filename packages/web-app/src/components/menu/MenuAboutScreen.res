// The menu's **About screen**: what the app is, on its own screen one tap below the main
// menu, beside Settings rather than under it.
//
// **It says the app's name in its own body rather than in the header bar.** Every other
// screen is named for what it holds — Settings, Debug, a game — and its header says so;
// this one is about the app, so the name is the content, under the app's own icon and at
// a size the header bar has no room for. That is why `<MenuHeader>` is given no title
// here: the wordmark *is* the screen's heading, and a second one in the bar would name
// it twice.
//
// Top to bottom: the icon, the wordmark, one line of copy, the link to the source it was
// built from, and — pushed to the foot of the panel — the build this browser is running
// with the one control that acts on it. All of it is centred: the screen is a single
// centred column, art to build string, which is what lets the block at the foot stand
// with no caption over it and still read as part of this page rather than as a band that
// lost its label.
//
// **The build sits at the foot** rather than under the masthead: it is the screen's
// footnote, and the masthead reads as one thing with air under it rather than with a
// second block pressed against it. That placement is also what makes the ↻ Update band's
// arrival free — see below.
//
// **The build is the screen's other subject.** The version and build time the Settings
// footer prints as a quiet caption are set out here at a size to read off a phone at
// arm's length and quote into a bug report — which is what a build string is for, and
// the reason it stays selectable. Both update controls are with them: the check that
// asks whether a newer build exists, and the ↻ Update that switches to one already
// waiting. They are two halves of one job, and a check made on this screen would
// otherwise report its find somewhere the player isn't.
//
// **It wears no caption.** Every other band in the panel is headed or labelled because it
// holds rows to pick between; this one is a string and a button at the foot of a short
// screen, and a "BUILD" caption over a mono number tells a reader nothing the number
// hasn't. What finds it is the position and the face: it is the only mono type on the
// screen and the only control. The band keeps its `aria-label`, which is the half of a
// heading that was doing work.
//
// **The block offers one control, and which one is whichever is worth offering.** A build
// already downloaded and waiting is installed, not checked for again — so the ↻ Update
// button takes the check's own slot rather than standing over it. The slot is a fixed
// box (MenuAboutScreen.css), so the swap moves nothing.
//
// What that costs: a check that finds something turns the button under the reader's
// thumb into a reload. The two are a different colour and a different word, and the
// install lands a beat later than the check it followed — `onNeedRefresh` fires when the
// new worker has finished installing, not when the check resolves — so the swap is not
// inside a double tap. A misfire reloads to a board the save restores, which is why this
// is a cost rather than a refusal.
//
// `refresh` is a ready-made vnode, empty until a service-worker state has been detected
// (`Main`), which is why the slot can be empty while the build string is not.

%%raw(`import "./MenuAboutScreen.css"`)

type props = {
  version: string,
  buildTime: string,
  // A newer build is downloaded and waiting to be switched to.
  updateVisible: bool,
  onReload: unit => unit,
  // The update check (`RefreshControl`), or an empty node on a build where the browser
  // can tell us nothing about updates.
  refresh: Html.vnode,
  onClose: unit => unit,
  onBackToMenu: unit => unit,
}

// The screen's one line of copy, and it sets a **tone** rather than describing anything:
// what the app does is what the games list and the board behind this menu are already
// saying, and a feature sentence here would only be saying it worse.
//
// **First person, deliberately.** The line under it is a person's repository, which is
// what gives the "I" a referent — and an app that is one person's habit rather than a
// product is the fact worth setting the reader up with. Keep it a single sentence: it is
// the only thing between the name and the link, and a second one would make it a
// paragraph to read rather than a line to take in.
let blurb = "I made this for myself but I hope you like it too."

// The repository this build was made from. A real link out, like the game info screen's:
// a new tab, because the app is a PWA and following a link in place would tear down a
// board mid-play, and `rel` so the opened page can't reach back through `window.opener`.
let repo = "jrr/pip-solitaire"
let repoUrl = "https://github.com/" ++ repo

// GitHub's own mark, as Octicons draws it (`mark-github-16`, MIT). Inline like the top
// bar's undo glyph and for the same reason: a file to fetch is a file that can be
// missing, and `currentColor` lets it take the link's colour in every state.
let markGithub = "M6.766 11.328c-2.063-.25-3.516-1.734-3.516-3.656 0-.781.281-1.625.75-2.188-.203-.515-.172-1.609.063-2.062.625-.078 1.468.25 1.968.703.594-.187 1.219-.281 1.985-.281.765 0 1.39.094 1.953.265.484-.437 1.344-.765 1.969-.687.218.422.25 1.515.046 2.047.5.593.766 1.39.766 2.203 0 1.922-1.453 3.375-3.547 3.64.531.344.89 1.094.89 1.954v1.625c0 .468.391.734.86.547C13.781 14.359 16 11.53 16 8.03 16 3.61 12.406 0 7.984 0 3.563 0 0 3.61 0 8.031a7.88 7.88 0 0 0 5.172 7.422c.422.156.828-.125.828-.547v-1.25c-.219.094-.5.156-.75.156-1.031 0-1.64-.562-2.078-1.609-.172-.422-.36-.672-.719-.719-.187-.015-.25-.093-.25-.187 0-.188.313-.328.625-.328.453 0 .844.281 1.25.86.313.452.64.655 1.031.655s.641-.14 1-.5c.266-.265.47-.5.657-.656"

// The app's art at a size worth looking at: the very vnode the PWA icons are rasterized
// from (`IconArt`, `scripts/generate/icons.mjs`), not a picture of it. Vector, so it is
// sharp at any size; drawn rather than fetched, like the top bar's undo glyph and the
// mark on the link below — and, being the same source, it cannot fall out of step with
// the icon on the home screen the way a second copy could.
//
// The *cards alone* (`IconArt.cards`): no rounded square, because this panel is already
// a dark rounded box and a second one around the fan reads as a sticker of the app stuck
// onto the app — and framed to the fan, so there is no dead margin around the art to
// centre.
//
// It carries a `<defs>` id of its own, `cardShadow`, and inlining it makes that
// document-wide. Nothing else in the app declares an SVG id, so it is unique here; a
// second inline copy on one screen would not be.
let icon = <div className="about-icon" ariaHidden="true"> {IconArt.cards()} </div>

let make = ({version, buildTime, updateVisible, onReload, refresh, onClose, onBackToMenu}) => <>
  <MenuHeader back={Some({label: "Back to menu", onClick: onBackToMenu})} onTitleTap=None onClose />
  <div className="menu-screen">
    // The icon, the name, what it is, and where it came from: one band, because a reader
    // takes them in as one thing. Unnamed — the wordmark is the heading inside it, and an
    // `aria-label` over the top would be the app's name a third time.
    <MenuSection modifier="about-hero">
      {icon}
      // The app's own wordmark, which is the header's title one size up: same gradient,
      // same weight, borrowed by class so the two can't drift (`MenuHeader.css`).
      <h1 className="menu-title about-wordmark"> {Html.string("Pip")} </h1>
      <p className="about-blurb"> {Html.string(blurb)} </p>
      <a className="about-link" href={repoUrl} target="_blank" rel="noopener noreferrer">
        <svg className="about-link__mark" viewBox="0 0 16 16" ariaHidden="true" focusable="false">
          <path d={markGithub} fill="currentColor" />
        </svg>
        <span className="about-link__name"> {Html.string(repo)} </span>
      </a>
    </MenuSection>
    // The build in hand and the two ways to move off it, at the foot of the panel
    // (`menu-section--bottom`). Named "build" rather than "updates": the string is what a
    // reader came down here for — which build this is — and both controls act on it.
    <MenuSection label="build" modifier="menu-section--bottom">
      // The build string over its one control, the three of them centred on each other.
      <div className="about-build">
        <div>
          <div className="about-build__version"> {Html.string(version)} </div>
          <div className="about-build__time"> {Html.string(BuildStamp.format(buildTime))} </div>
        </div>
        {updateVisible ? <UpdateButton onReload /> : refresh}
      </div>
    </MenuSection>
  </div>
</>
