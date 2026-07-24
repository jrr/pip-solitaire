// The **About** footer that sits at the foot of both menu screens (#165/#191),
// lifted out of `Menu` into its own pure component so its states can be exercised
// in isolation (#201): the build/version line (`<VersionBadge>`) and, beside it,
// the green **Update** button that activates a waiting service-worker build.
//
// **The size story (#201).** This footer used to stack a "A new version is
// available" note and a full-width **Update now** button *under* the version line,
// rendered with `hidden` (`display: none`) when no update waited — so the footer
// collapsed most of the time and expanded when an update arrived, shoving
// everything above it. It's now a single row: the version line on the left, a
// short **↻ Update** button on the right. The button is always laid out and hidden
// with *visibility* (`menu-update--hidden`) when there's nothing to update, so it
// keeps its box and the row is the same height in both states — only the button
// fades in and out. `AboutFooter_test` pins that invariant.
//
// `visibility: hidden` also takes the reserved button out of the tab order and out
// of pointer events; `aria-hidden` mirrors that for assistive tech.
//
// A component is just a `props => vnode` function (see `VersionBadge` for why the
// record is spelled out by hand).
type props = {
  version: string,
  buildTime: string,
  updateVisible: bool,
  onReload: unit => unit,
}

let make = ({version, buildTime, updateVisible, onReload}) =>
  <div className="menu-footer" attrs={[("aria-label", "About")]}>
    <h2 className="menu-section__heading"> {Html.string("About")} </h2>
    <div className="menu-about__row">
      <VersionBadge version={version} buildTime={buildTime} />
      // The Update button stays in the row at all times so it never reflows;
      // `--hidden` reserves its space with `visibility: hidden` when there's no
      // update to offer, and `aria-hidden` mirrors that for assistive tech.
      <button
        className={updateVisible
          ? "menu-update__button"
          : "menu-update__button menu-update--hidden"}
        onClick={_ => onReload()}
        attrs={[
          ("type", "button"),
          ("title", "Update available — reload"),
          ("aria-label", "Update now — reload to the new version"),
          ("aria-hidden", updateVisible ? "false" : "true"),
        ]}
      >
        {Html.string("↻ Update")}
      </button>
    </div>
  </div>
