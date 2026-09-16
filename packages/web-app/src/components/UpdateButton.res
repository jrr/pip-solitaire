// The **↻ Update** button: switch this tab to a build already downloaded and waiting
// (`Main`'s `Reload`, which hands the waiting service worker the go-ahead).
//
// **Two screens offer it, and it is one component so that they cannot drift.** The top
// bar's green pip is a notification, and the screen it opens — the main menu — is where
// its call to action has to be, one tap from the dot; the About screen offers the same
// button over the build string it would replace, for a player who went looking rather
// than being told. What they share is not just the paint: it is the word, the title and
// the accessible name, which is the part that would quietly diverge if each screen spelt
// its own.
//
// **Absent until there is something to press**, on both. A reserved box would be a
// permanent gap — under the title on one screen and under the heading on the other — and
// it would be there every time there was no update, which is almost always. What that
// costs is that the band's arrival moves the rows around it the once; both screens place
// it where that is affordable. On the main menu it leads, so the sections below shift
// down; on the About screen it sits inside a block anchored to the foot of the panel, so
// the block grows *upward* and the control under it — the update check — doesn't move at
// all.

%%raw(`import "./UpdateButton.css"`)

type props = {
  // A newer build is installed and waiting. `false` renders nothing at all.
  visible: bool,
  onReload: unit => unit,
}

let make = ({visible, onReload}) =>
  visible
    ? <button
        className="menu-update"
        onClick={_ => onReload()}
        type_="button"
        title="Update available — reload"
        ariaLabel="Update now — reload to the new version"
      >
        {Html.string("↻ Update")}
      </button>
    : Html.empty
