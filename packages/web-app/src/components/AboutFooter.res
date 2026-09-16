// The **About** footer at the foot of the Settings screen (`Menu` places it, and places
// it there alone): the way through to the About screen, over the build string that
// screen is about (`<VersionBadge>`).
//
// **The button comes first and the build string under it.** The button is what a hand
// comes down here for; the version is a caption on it — enough to tell at a glance which
// build is installed, and set as small as that job allows, because the screen behind the
// button is where it is the subject (`MenuAboutScreen`).
//
// **No heading.** "About" as a caption over a build string says nothing the build string
// doesn't, and the screen this footer sits on is already titled. The band keeps its
// `aria-label`, which is the half of a heading that was doing work.
//
// **Nothing here may change height.** It's anchored at the foot of the panel, so a
// footer that grows shoves everything above it — which is why the update controls that
// come and go (the check, which is absent until a service-worker state is known, and the
// ↻ Update button, which is only sometimes offered) are on the About screen rather than
// in here. What is left is two elements that are always exactly themselves.

%%raw(`import "./AboutFooter.css"`)

type props = {
  version: string,
  buildTime: string,
  onOpenAbout: unit => unit,
}

let make = ({version, buildTime, onOpenAbout}) =>
  <div className="menu-footer" ariaLabel="About">
    <button className="menu-button" onClick={_ => onOpenAbout()} type_="button">
      {Html.string("About")}
    </button>
    <VersionBadge version={version} buildTime={buildTime} />
  </div>
