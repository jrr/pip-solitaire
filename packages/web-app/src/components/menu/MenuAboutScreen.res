// The menu's **About screen**: what the app is, on its own screen a level below
// Settings. It is reached from the About button beside the update check, which is where
// the build string it will explain already sits.
//
// **Deliberately empty.** What is here is the screen and the way in and out of it — a
// header whose back button returns to Settings rather than to the main menu, since
// Settings is where the button was — and the copy is the next pass. An empty
// `.menu-screen` rather than no element at all, so the first paragraph added to it lands
// in the column every other screen writes into, with the panel's gaps and its scroll
// already arranged around it.
type props = {
  onClose: unit => unit,
  onBackToSettings: unit => unit,
}

let make = ({onClose, onBackToSettings}) => <>
  <MenuHeader
    title="About"
    back={Some({label: "Back to settings", onClick: onBackToSettings})}
    onTitleTap=None
    onClose
  />
  <div className="menu-screen" />
</>
