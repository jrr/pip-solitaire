// The menu's **About screen**: what this build *is*, on its own screen a level below
// Settings, reached from the About button in that screen's footer.
//
// **It is the build's screen.** The version and build time the footer prints as a quiet
// caption are the subject here, set large enough to read off a phone held at arm's
// length and to quote in a bug report — which is what a build string is for, and the
// reason it stays selectable. The two update controls are here with them: the check
// that asks whether a newer build exists, and the ↻ Update that switches to one already
// waiting. They are two halves of one job and belong on one screen, or a check made on
// this screen would report its find somewhere the player isn't.
//
// **The ↻ Update button rides the version's own row** rather than standing under the
// check: that row is two lines of build string tall either way, which is the room the
// button needs to come and go in without moving the check below it (`<UpdateButton>`,
// whose `Inline` shape this is, and which the main menu offers as a band).
//
// `refresh` is a ready-made vnode, empty until a service-worker state has been detected
// (`Main`), which is why the check can be absent while the ↻ Update button is only ever
// invisible.

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
  onBackToSettings: unit => unit,
}

// The repository this build was made from. A real link out, like the game info screen's:
// a new tab, because the app is a PWA and following a link in place would tear down a
// board mid-play, and `rel` so the opened page can't reach back through `window.opener`.
let repo = "jrr/pip-solitaire"
let repoUrl = "https://github.com/" ++ repo

// GitHub's own mark, as Octicons draws it (`mark-github-16`, MIT). Inline like the top
// bar's undo glyph and for the same reason: a file to fetch is a file that can be
// missing, and `currentColor` lets it take the link's colour in every state.
let markGithub = "M6.766 11.328c-2.063-.25-3.516-1.734-3.516-3.656 0-.781.281-1.625.75-2.188-.203-.515-.172-1.609.063-2.062.625-.078 1.468.25 1.968.703.594-.187 1.219-.281 1.985-.281.765 0 1.39.094 1.953.265.484-.437 1.344-.765 1.969-.687.218.422.25 1.515.046 2.047.5.593.766 1.39.766 2.203 0 1.922-1.453 3.375-3.547 3.64.531.344.89 1.094.89 1.954v1.625c0 .468.391.734.86.547C13.781 14.359 16 11.53 16 8.03 16 3.61 12.406 0 7.984 0 3.563 0 0 3.61 0 8.031a7.88 7.88 0 0 0 5.172 7.422c.422.156.828-.125.828-.547v-1.25c-.219.094-.5.156-.75.156-1.031 0-1.64-.562-2.078-1.609-.172-.422-.36-.672-.719-.719-.187-.015-.25-.093-.25-.187 0-.188.313-.328.625-.328.453 0 .844.281 1.25.86.313.452.64.655 1.031.655s.641-.14 1-.5c.266-.265.47-.5.657-.656"

let make = ({version, buildTime, updateVisible, onReload, refresh, onClose, onBackToSettings}) => <>
  <MenuHeader
    title="About"
    back={Some({label: "Back to settings", onClick: onBackToSettings})}
    onTitleTap=None
    onClose
  />
  <div className="menu-screen">
    // The build, and the button that replaces it. Labelled but unheaded: a caption
    // reading "version" over a version number says it twice.
    <MenuSection label="version">
      <div className="about-build">
        <div>
          <div className="about-build__version"> {Html.string("v" ++ version)} </div>
          <div className="about-build__time">
            {Html.string(VersionBadge.formatBuildTime(buildTime))}
          </div>
        </div>
        <UpdateButton variant=UpdateButton.Inline visible={updateVisible} onReload />
      </div>
    </MenuSection>
    <MenuSection label="updates"> {refresh} </MenuSection>
    <MenuSection label="source">
      <a className="about-link" href={repoUrl} target="_blank" rel="noopener noreferrer">
        <svg className="about-link__mark" viewBox="0 0 16 16" ariaHidden="true" focusable="false">
          <path d={markGithub} fill="currentColor" />
        </svg>
        <span className="about-link__name"> {Html.string(repo)} </span>
      </a>
    </MenuSection>
  </div>
</>
