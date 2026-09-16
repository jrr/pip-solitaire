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
// **Whether to offer it at all is the placing screen's**, and neither reserves a box for
// it: on the main menu it is a band that leads the panel when a build is waiting and is
// simply not there otherwise, and on the About screen it takes the update check's own
// slot — a build already downloaded is installed, not checked for again. This file is
// only the button, which is the half that would quietly diverge if each screen spelt its
// own words.

%%raw(`import "./UpdateButton.css"`)

type props = {onReload: unit => unit}

let make = ({onReload}) =>
  <button
    className="menu-update"
    onClick={_ => onReload()}
    type_="button"
    title="Update available — reload"
    ariaLabel="Update now — reload to the new version"
  >
    {Html.string("↻ Update")}
  </button>
