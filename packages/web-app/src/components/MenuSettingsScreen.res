// The menu's **Settings screen** (#191): the player-facing preferences, the toggles
// a player can flip mid-game. `Menu` puts the About footer under it.
//
// **This is the codebase's first child Elm loop (#308), and the worked example the
// decision was recorded with** — see the "Component state" row in the ROADMAP. Every
// other component under `components/` is a pure `props => vnode` whose state lives in
// `Main`'s single model. That's still the default. This screen is the exception
// because it had visibly outgrown it: six switches, each declared in `Main`'s model,
// re-declared on `Menu.props`, re-declared again here, and re-declared once more on
// the row — four declarations per switch, and `Menu` in the middle paying six lines
// apiece purely to hand them through.
//
// So this file owns them instead. It has its own `model` / `msg` / `update`, and
// `Main` embeds the model in its own as one field and maps this module's messages up
// through a single `SettingsMsg` constructor. There is still exactly one
// `Html.mount` in the app — this is composition, not a nested mount (which is what
// `Board.res` does, and why that one needs an owned subtree and a `.js` shell). What
// it costs is that `Main` still physically holds the state, just namespaced; what it
// buys is that nothing between `Main` and the switch has to name it, and `update` is
// a pure function testable on its own, exactly like `core`'s `Reducer`.
//
// **The model is a mirror, not the truth.** Every flag here is a copy of something
// that really lives elsewhere: `Preferences` in localStorage, the live `options` /
// tilt refs the board reads at each move, the document-root attribute the notch CSS
// keys off. This screen holds a copy so the switch can render in the right position,
// and its `update` is what keeps the copy and the truth in step — which is why every
// branch below pairs a model change with the effect that writes it through. Read a
// setting's *value* from its real home, never from here.
//
// The layout, top to bottom:
//   - a header with a **back** button (`onBackToMenu`, returns to the main menu) and
//     the ✕ (`onClose`, still closes the whole menu). Its title doubles as the
//     hidden-options tap target — see `<MenuHeader>` for why that handler is
//     attached here and nowhere else;
//   - the preference toggles (#139), one per row with a one-line description under
//     its label; no section heading — the "Settings" title in the header already
//     names them;
//   - a **Debug** nav row (`onOpenDebug`) that opens the Debug screen — the debug
//     tools moved off Settings entirely onto their own screen so the player
//     preferences stand alone. That screen's own two switches are still `Main`'s
//     (see `<MenuDebugScreen>`); it's the next candidate, not part of this example.
//
// Its content flows from the *top*: the panel grows the space *below* the sections
// (the `.menu-screen` wrapper takes the slack) so the footer still hugs the foot,
// but the settings no longer float in the middle under an empty header.

// --- Model -------------------------------------------------------------------
// The switch positions, and the run of taps that reveals the hidden ones. Mirrors,
// every one of them — see the note above.
type model = {
  autoCollect: bool,
  // "Sloppy placement" (#65) — the slight resting-card tilt, for players who'd
  // rather see cards stacked dead-square.
  cardTilt: bool,
  // "Wiggle Waggle" (#235): not a bool — its `Motion.state` decides both the switch
  // position and the problem-only subtitle (see `<MenuWiggleRow>`).
  wiggle: Motion.state,
  // "Display content around notch" (#204) — whether the landscape rail may ride out
  // into the corner wings beside the notch; off clamps every control inside the safe
  // area.
  notchDisplay: bool,
  // The hidden settings and the run of taps that reveals them (`HiddenOptions`).
  // `revealed` is persisted; the tap count is session state, cleared on the way out
  // of the Settings screen (`forgetTaps`) so a half-finished run can't be resumed
  // later. A hidden row says nothing about whether its setting is *on*: hiding
  // leaves it running.
  hidden: HiddenOptions.t,
}

type msg =
  | ToggleAutoCollect // the Auto-collect switch (#139)
  | ToggleCardTilt // the hand-placed-tilt switch (#65)
  | ToggleNotchDisplay // the "Display content around screen notch" switch (#204)
  | WiggleOff // Wiggle Waggle turned off (#235) — stop listening, square up
  | WiggleResolved(Motion.state) // a motion-permission request resolved to a new state (#235)
  | TitleTapped // a tap on the screen's title — ten reveal the hidden settings

// The opening state, read straight from storage. The screen seeds its own mirrors
// rather than being handed them, which is the whole point of it owning them — adding
// a switch is a field here and a row below, and `Main` is not involved.
//
// `Main` does read `wiggle` back off the returned model, because the *board's* shake
// subscription has to open in the same state this switch does (see `shakeActive`
// there). That's the one value in here with a second reader, and it reads the mirror
// rather than recomputing it precisely so the two can't disagree.
let init = () => {
  autoCollect: Preferences.load().autoCollect,
  cardTilt: Preferences.loadCardTilt(),
  wiggle: Motion.initialState(~wantsShake=Preferences.loadWantsShake()),
  notchDisplay: Preferences.loadNotchDisplay(),
  hidden: HiddenOptions.initial(~revealed=Preferences.loadRevealHidden()),
}

// --- Effects -----------------------------------------------------------------
// The impure handles this screen's effects reach through, built once by `Main` and
// passed to `update`. Everything a switch can do *on its own* — persist itself
// (`Preferences`), publish the shared motion state (`Motion.current`), set the
// document-root notch attribute (`NotchDisplay`) — it does directly, because those
// are leaf modules this file can just call. What's left here is the four things only
// the chrome has: the two live preference refs the board reads at each move, the
// board's relayout, and its shake subscription.
//
// Deliberately *not* one field per switch. It's a list of chrome capabilities, not a
// list of settings: a new preference toggle that only has to remember itself adds
// nothing to it, and that's what keeps this from being the prop drilling it replaced.
type env = {
  // Write the driver-preference ref the board reads live (#139), so a flip changes
  // the board's behaviour on the very next move rather than at the next rebuild.
  setAutoCollect: bool => unit,
  // The same for the presentation-only tilt ref (#65).
  setCardTilt: bool => unit,
  // Re-lay the board out, so a tilt change appears at once rather than on the next
  // move. A no-op on a scene with no board.
  relayout: unit => unit,
  // Start or stop the board listening for shakes (#235), and remember which for the
  // board that mounts next.
  setShake: bool => unit,
}

// --- Update ------------------------------------------------------------------
// A pure state transition plus a post-patch effect, the same shape `Main`'s own
// `update` has — `Main` threads the effect straight back out to the loop, so a
// message that starts here runs its effect exactly when a message that starts there
// would.
let update = (~env, msg, model) =>
  switch msg {
  | ToggleAutoCollect =>
    let autoCollect = !model.autoCollect
    (
      {...model, autoCollect},
      () => {
        env.setAutoCollect(autoCollect)
        Preferences.saveAutoCollect(autoCollect)
      },
    )
  | ToggleCardTilt =>
    let cardTilt = !model.cardTilt
    (
      {...model, cardTilt},
      () => {
        env.setCardTilt(cardTilt)
        Preferences.saveCardTilt(cardTilt)
        // Relayout so the tilt appears (or clears) immediately, not just on the next
        // move.
        env.relayout()
      },
    )
  | ToggleNotchDisplay =>
    let notchDisplay = !model.notchDisplay
    (
      {...model, notchDisplay},
      () => {
        // Reflect the flip onto the document root so the CSS wing-placement rules
        // switch off/on at once, and persist it so the choice survives a reload.
        NotchDisplay.setEnabled(notchDisplay)
        Preferences.saveNotchDisplay(notchDisplay)
      },
    )
  // Wiggle Waggle turned off (#235): stop listening and square the board back up
  // (`setShake(false)` does both), persist the flipped-off intent, and drop the
  // shared state to `Off`. Snapping the mess back is the deliberate way out — a
  // hidden square-up gesture can't be the only one (#236).
  | WiggleOff => (
      {...model, wiggle: Motion.Off},
      () => {
        Motion.current := Motion.Off
        Preferences.saveWantsShake(false)
        env.setShake(false)
      },
    )
  // A motion-permission request resolved (#235). `On` — granted or ungated: start
  // listening and persist the intent so the next launch resumes. `Blocked` — the OS
  // refused: the switch snaps back to off (its subtitle explains why) and we stop;
  // crucially we *don't* persist a false intent, so a grant revoked behind us (the
  // saved intent still `true`) keeps re-asking on future launches rather than giving
  // up. `Unavailable`/`Off` just reflect the state.
  | WiggleResolved(state) => (
      {...model, wiggle: state},
      () => {
        Motion.current := state
        switch state {
        | Motion.On =>
          Preferences.saveWantsShake(true)
          env.setShake(true)
        | Blocked => env.setShake(false)
        | Unavailable(_) | Off => ()
        }
      },
    )
  // A tap on the title (`HiddenOptions`): every tenth flips the settings that aren't
  // ready to be found yet into or out of view, and persists that so the gesture is
  // performed once per device rather than once per launch. Hiding them again leaves
  // whatever they switched on running — see `HiddenOptions` for why that's deliberate.
  //
  // Only taps that arrive *while this screen is showing* count, and that guard stays
  // with `Main`: the same green `menu-title` heads all three screens, so "only
  // Settings unlocks" is a fact about which screen is up, which this module has no
  // view of (see `SettingsMsg` there).
  | TitleTapped =>
    let hidden = HiddenOptions.tap(model.hidden)
    (
      {...model, hidden},
      // Only the tap that actually flipped the reveal is worth persisting; the other
      // nine in a run just move the counter.
      HiddenOptions.revealChanged(~before=model.hidden, ~after=hidden)
        ? () => Preferences.saveRevealHidden(hidden.revealed)
        : Html.noEffect,
    )
  }

// Abandon a part-finished run of reveal taps — the way out of the Settings screen,
// and every other screen change (`Main` calls this from all five). It isn't a message
// because it isn't something this screen did: the counter spans one uninterrupted
// visit, and it's `Main` that knows a visit ended.
//
// An already-clear model is returned physically unchanged, so it can't force a
// re-render on its own (see `Html.mount`'s equality check).
let forgetTaps = model => {
  let hidden = HiddenOptions.reset(model.hidden)
  hidden === model.hidden ? model : {...model, hidden}
}

// --- View --------------------------------------------------------------------
// Two props where there were thirteen: the model to draw and the conduit to send
// messages back through. What's left beside them is the pane's *navigation* — where
// the back button and the ✕ go, and what opening Debug does — which is `Menu`'s
// business rather than this screen's, so it stays a callback (`Main`'s `onOpenDebug`
// also kicks off the share-link encode, which has nothing to do with settings).
type props = {
  model: model,
  dispatch: msg => unit,
  onClose: unit => unit,
  onBackToMenu: unit => unit,
  onOpenDebug: unit => unit,
}

let make = ({model, dispatch, onClose, onBackToMenu, onOpenDebug}) => <>
  <MenuHeader
    title="Settings"
    back={Some({label: "Back to menu", onClick: onBackToMenu})}
    onTitleTap={Some(() => dispatch(TitleTapped))}
    onClose
  />
  <div className="menu-screen">
    <div className="menu-section" attrs={[("aria-label", "Settings")]}>
      <MenuToggleRow
        label="Auto-collect"
        desc="Send cards to the foundations for you as soon as they're ready."
        on={model.autoCollect}
        onToggle={() => dispatch(ToggleAutoCollect)}
      />
      <MenuToggleRow
        label="Sloppy placement"
        desc="Cards don't line up perfectly."
        on={model.cardTilt}
        onToggle={() => dispatch(ToggleCardTilt)}
      />
      {
        // "Wiggle Waggle" (#235) sits below "Sloppy placement" but is *not* nested
        // under it — the two are independent settings. It's hidden until the Settings
        // title has been tapped ten times (`HiddenOptions`) — not ready to be found by
        // a player yet, but reachable on a test device. Ten more taps hide the row
        // again *without* stopping the shake, so an absent row here doesn't mean the
        // board is sitting still.
        model.hidden.revealed
          ? <MenuWiggleRow
              state={model.wiggle}
              onToggle={() =>
                // The single chance to ask (#235): flip *on* asks for the motion grant
                // under this real click's transient activation — iOS won't prompt
                // without it and remembers a denial per origin. This stays in the view
                // rather than becoming an effect of a `WiggleTapped` message because
                // it's a fact about the click, not about the model. Flip *off* just
                // stops. An `Unavailable` switch has nothing to grant, so a tap is
                // inert.
                switch model.wiggle {
                | Motion.Unavailable(_) => ()
                | On => dispatch(WiggleOff)
                | Off | Blocked =>
                  Motion.requestAccess()
                  ->Promise.thenResolve(state => dispatch(WiggleResolved(state)))
                  ->ignore
                }}
            />
          : Html.array([])
      }
      <MenuToggleRow
        label="Display content around notch"
        desc="Let the controls reach into the corners beside the camera notch."
        on={model.notchDisplay}
        onToggle={() => dispatch(ToggleNotchDisplay)}
      />
    </div>
    <nav className="menu-section" attrs={[("aria-label", "More")]}>
      <MenuNavRow label="Debug" onClick=onOpenDebug />
    </nav>
  </div>
</>
