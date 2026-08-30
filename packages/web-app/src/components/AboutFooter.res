// The **About** footer that sits at the foot of both menu screens: one
// row holding the build/version line (`<VersionBadge>`) and, at its end, the green
// **↻ Update** button that activates a waiting service-worker build — with the
// update-check slot (`refresh`) below it, so the build info and the update check
// read as one "About" block.
//
// **This footer must be the same height in both states.** It's anchored at
// the foot of the panel, so a footer that grows shoves everything above it. The
// Update button is therefore laid out at all times and hidden with *visibility*
// (`menu-update--hidden`) when there's nothing to update: it keeps its box and only
// fades in and out. Never hide it with `hidden`/`display: none`, which collapses the
// box and brings the reflow back. `AboutFooter_test` pins both halves.
//
// `visibility: hidden` also takes the reserved button out of the tab order and out
// of pointer events; `aria-hidden` mirrors that for assistive tech.
//
// `refresh` is a ready-made vnode (a `<RefreshControl>` when a service-worker state
// is known, otherwise an empty node), so the footer stays a dumb layout and `Menu`
// decides whether there's a button to show.
//
// A component is just a `props => vnode` function (see `VersionBadge` for why the
// record is spelled out by hand).

// This component's stylesheet, in the `components` layer (see src/styles/index.css).
%%raw(`import "./AboutFooter.css"`)

type props = {
  version: string,
  buildTime: string,
  updateVisible: bool,
  onReload: unit => unit,
  refresh: Html.vnode,
}

let make = ({version, buildTime, updateVisible, onReload, refresh}) =>
  <div className="menu-footer" ariaLabel="About">
    <h2 className="menu-section__heading"> {Html.string("About")} </h2>
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
    {refresh}
  </div>
