// The **About** footer at the foot of the Settings screen (`Menu` places it, and places
// it there alone): a row of two buttons — the update check (`refresh`) and the way to
// the About screen — over the build/version line (`<VersionBadge>`), which carries the
// green **↻ Update** button at its end when a new build is waiting.
//
// **The buttons come first and the build string under them.** The two controls are what
// a hand comes down here for; the version is what they are about, and a line of small
// grey type is a caption rather than something to reach past. It is also the half that
// grows — the Update button appears in it — so the things a thumb aims at sit above the
// part that changes.
//
// **No heading.** "About" as a caption over a build string says nothing the build string
// doesn't, and the screen this footer sits on is already titled. The band keeps its
// `aria-label`, which is the half of a heading that was doing work.
//
// **This footer must be the same height in every state.** It's anchored at
// the foot of the panel, so a footer that grows shoves everything above it. The
// Update button is therefore laid out at all times and hidden with *visibility*
// (`menu-update--hidden`) when there's nothing to update: it keeps its box and only
// fades in and out. Never hide it with `hidden`/`display: none`, which collapses the
// box and brings the reflow back. `AboutFooter_test` pins both halves.
//
// `visibility: hidden` also takes the reserved button out of the tab order and out
// of pointer events; `aria-hidden` mirrors that for assistive tech.
//
// `refresh` is a ready-made vnode (a `<RefreshControl>` button when a service-worker
// state is known, otherwise an empty node), so the footer stays a dumb layout and
// `Main` decides whether there's a check to offer. The About button beside it is
// unconditional: the screen it opens is there whatever the browser can tell us about
// this install.

%%raw(`import "./AboutFooter.css"`)

type props = {
  version: string,
  buildTime: string,
  updateVisible: bool,
  onReload: unit => unit,
  refresh: Html.vnode,
  onOpenAbout: unit => unit,
}

let make = ({version, buildTime, updateVisible, onReload, refresh, onOpenAbout}) =>
  <div className="menu-footer" ariaLabel="About">
    <div className="menu-footer__actions">
      {refresh}
      <button className="menu-button" onClick={_ => onOpenAbout()} type_="button">
        {Html.string("About")}
      </button>
    </div>
    <div className="menu-about__row">
      <VersionBadge version={version} buildTime={buildTime} />
      // Always in the row, reserved with `menu-update--hidden` when there's no update
      // to offer — see the size rule above. `aria-hidden` mirrors it for assistive tech.
      <button
        className={updateVisible
          ? "menu-update__button"
          : "menu-update__button menu-update--hidden"}
        onClick={_ => onReload()}
        type_="button"
        title="Update available — reload"
        ariaLabel="Update now — reload to the new version"
        ariaHidden={updateVisible ? "false" : "true"}
      >
        {Html.string("↻ Update")}
      </button>
    </div>
  </div>
