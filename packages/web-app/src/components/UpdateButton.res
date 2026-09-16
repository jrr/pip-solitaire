// The **↻ Update** button: switch this tab to a build already downloaded and waiting
// (`Main`'s `Reload`, which hands the waiting service worker the go-ahead).
//
// **Two screens offer it, and it is one component so that they cannot drift.** The top
// bar's green pip is a notification, and the screen it opens — the main menu — is where
// its call to action has to be, one tap from the dot; the About screen offers the same
// button beside the build string it would replace, for a player who went looking rather
// than being told. What they share is not just the paint: it is the word, the title and
// the accessible name, which is the part that would quietly diverge if each screen spelt
// its own.
//
// What differs is the **shape**, and with it what *absence* means:
//
//   - `Band` — the main menu's, a full-width control at the top of the panel. Absent
//     until there is something to press, because a box reserved for it would sit as a
//     permanent gap under the title. The cost is that the sections below it shift down
//     the once an update lands while the menu is open; that beats a gap that is there
//     every time it hasn't.
//   - `Inline` — the About screen's, a short button at the end of the build row, and
//     *reserved* rather than absent when there's nothing to update: that row is two
//     lines of build string tall either way, so `visibility` lets the button come and go
//     without moving the controls under it. Never `hidden`/`display: none` here, which
//     collapses the box and brings the reflow back.

%%raw(`import "./UpdateButton.css"`)

type variant =
  | Band
  | Inline

type props = {
  variant: variant,
  // A newer build is installed and waiting. What `false` means is the variant's, above.
  visible: bool,
  onReload: unit => unit,
}

let classFor = (variant, ~visible) => {
  let shape = switch variant {
  | Band => "menu-update menu-update--band"
  | Inline => "menu-update menu-update--inline"
  }
  visible ? shape : shape ++ " menu-update--hidden"
}

let make = ({variant, visible, onReload}) =>
  switch (variant, visible) {
  // Nothing to reserve: see `Band` above.
  | (Band, false) => Html.empty
  | _ =>
    <button
      className={classFor(variant, ~visible)}
      onClick={_ => onReload()}
      type_="button"
      title="Update available — reload"
      ariaLabel="Update now — reload to the new version"
      // `visibility: hidden` already takes a reserved button out of the tab order and
      // out of pointer events; this mirrors it for assistive tech.
      ariaHidden={visible ? "false" : "true"}
    >
      {Html.string("↻ Update")}
    </button>
  }
