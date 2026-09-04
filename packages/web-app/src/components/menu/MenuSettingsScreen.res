// The menu's **Settings screen**: the player-facing preferences, the toggles a player
// can flip mid-game. `Menu` puts the About footer under it.
//
// **This screen owns its own state.** Its `model`, `msg` and `update` live here, and
// the driver embeds the model as one field and maps the messages up through a single
// constructor (`Main`'s `SettingsMsg`) — so a seventh switch is a row, a field, a
// message and an `update` branch, all in this file, and nothing at all in `Main`.
// `update` is a pure function of `(env, msg, model)` returning the next model and an
// effect, which is what lets it be unit-tested the way `core`'s `Reducer` is.
//
// **None of these fields is the real value.** Auto-collect is read off the shared
// `Options` ref at each move, the tilt at each relayout, the victory flag at the moment
// a game is won; the notch preference is a document-root attribute the CSS reads; all
// of them are persisted. What's held here is the mirror the switch draws itself from,
// and the write-through in `update` is what keeps it honest — which is the half that
// can stop working with nothing on screen to show it, so
// `browser-tests/settings-reach.spec.mjs` pins each switch to storage, to the board and
// to the document root.
//
// Its content flows from the *top*: the panel grows the space *below* the sections
// (the `.menu-screen` wrapper takes the slack), which keeps the footer hugging the foot
// without letting the settings float in the middle of the pane under an empty header.
// Top to bottom:
//   - a header with a **back** button (`onBackToMenu`, returns to the main menu) and
//     the ✕ (`onClose`, still closes the whole menu). Its title doubles as the
//     hidden-options tap target — see `<MenuHeader>` for why that handler is
//     attached here and nowhere else;
//   - the preference toggles, one per row with a one-line description under
//     its label; no section heading — the "Settings" title in the header already
//     names them;
//   - a **Debug** nav row (`onOpenDebug`) that opens the Debug screen — the debug
//     tools live on a screen of their own so the player preferences stand alone here.

// --- What the screen holds ----------------------------------------------------
type model = {
  autoCollect: bool,
  // "Sloppy placement" — the slight resting-card tilt, for players who'd
  // rather see cards stacked dead-square.
  cardTilt: bool,
  // "Wiggle Waggle": not a bool — its `Motion.state` decides both the switch
  // position and which of the two lines the subtitle carries (see `<MenuWiggleRow>`).
  wiggle: Motion.state,
  // The *intent* behind the switch above, which is what's persisted and what the next
  // launch opens on. It's a field of its own because an OS refusal must leave a saved
  // `true` alone: a grant revoked behind us has to keep re-asking on future launches
  // rather than give up. Holding the intent apart from the live state is what lets the
  // write-through stay a plain snapshot of this record.
  wantsShake: bool,
  // "Victory animation" — a plain persisted flag, and the second of the hidden
  // settings. A win with it on plays the cascade before raising the panel; off, or
  // under reduced motion, the panel goes up alone.
  victoryAnimation: bool,
  // "Display content around notch" — whether the landscape rail may ride out
  // into the corner wings beside the notch; off clamps every control inside the safe
  // area.
  notchDisplay: bool,
  // The hidden settings and the run of taps that reveals them (`HiddenOptions`). Today
  // the hidden rows are Wiggle Waggle and Victory animation. A hidden row says nothing
  // about whether its setting is *on*: hiding leaves it running.
  hidden: HiddenOptions.t,
}

type msg =
  | ToggleAutoCollect
  | ToggleCardTilt
  | WiggleOff // the Wiggle Waggle switch turned off — stop listening, square up
  | WiggleResolved(Motion.state) // a motion-permission request resolved to a new state
  | ToggleVictoryAnimation
  | ToggleNotchDisplay
  | TitleTapped // a tap on this screen's title — every ten flip the hidden settings

// --- The reach out of the screen ----------------------------------------------
// What a flip asks of the board already on the table, which is the reach that can't be
// had by writing a value down somewhere and waiting to be read.
type request =
  | Relayout // re-lay the resting cards, so a tilt change shows now rather than next move
  | ShakeStart
  | ShakeStop

// The handles a component can't reach from the inside. Four entries because they are
// *kinds* of reach — the shared refs, the live board, the document root, storage — and a
// seventh switch picks from them rather than adding a fifth. Three of the four take the
// whole model, so what a setting's write-through *is* stays one line in the writer
// instead of a branch in here.
type env = {
  // The live values the board reads at the moment of use, and the app-wide motion
  // state the debug scene reads. Idempotent: it publishes the snapshot it's given, so
  // any branch that changed one of them can simply hand over the new model.
  publish: model => unit,
  // The board on the table, when there is one. `Main` resolves that; a demo scene has
  // none and the request is dropped.
  board: request => unit,
  // The document root, for a setting the CSS reads off an attribute rather than the
  // board reading a ref.
  root: model => unit,
  // Storage, again as a snapshot: which key a setting lives under is `Preferences`'
  // business, not a branch here.
  persist: model => unit,
}

// The env the app runs on, wired to the handles only the driver has: the refs the
// board reads live, and a way through to the board itself. It's a value rather than a
// set of calls inlined into `update` so that the tests can hand over a recording env
// and read back which kinds of reach a flip actually used.
let liveEnv = (
  ~options: ref<Options.t>,
  ~tiltEnabled: ref<bool>,
  ~victoryAnimation: ref<bool>,
  ~shakeActive: ref<bool>,
  ~board: request => unit,
): env => {
  publish: model => {
    options := {...options.contents, autoCollect: model.autoCollect}
    tiltEnabled := model.cardTilt
    victoryAnimation := model.victoryAnimation
    // Settings is the owner of the app-wide motion state (see `Motion.current`): the
    // debug Motion scene shows it, and the board listens only while `shakeActive`.
    shakeActive := Motion.isOn(model.wiggle)
    Motion.current := model.wiggle
  },
  board,
  root: model => NotchDisplay.setEnabled(model.notchDisplay),
  persist: model => {
    Preferences.saveAutoCollect(model.autoCollect)
    Preferences.saveCardTilt(model.cardTilt)
    Preferences.saveWantsShake(model.wantsShake)
    Preferences.saveVictoryAnimation(model.victoryAnimation)
    Preferences.saveNotchDisplay(model.notchDisplay)
    Preferences.saveRevealHidden(model.hidden.revealed)
  },
}

// The state the screen opens in, read from where each setting actually lives rather
// than handed down. The motion state is computed instead of loaded: what a device and
// origin can do outranks whatever intent was saved, and asking for the grant is
// deferred to a real user gesture (`Motion.initialState`).
let init = (): model => {
  let wantsShake = Preferences.loadWantsShake()
  {
    autoCollect: Preferences.load().autoCollect,
    cardTilt: Preferences.loadCardTilt(),
    wiggle: Motion.initialState(~wantsShake),
    wantsShake,
    victoryAnimation: Preferences.loadVictoryAnimation(),
    notchDisplay: Preferences.loadNotchDisplay(),
    hidden: HiddenOptions.initial(~revealed=Preferences.loadRevealHidden()),
  }
}

// Whether the board should be listening for shakes in this state. The driver arms its
// first-tap permission resume on it, that tap being where a grant carried over from a
// previous launch is re-confirmed.
let listening = (model: model) => Motion.isOn(model.wiggle)

// A visit to this screen begun or ended: abandon a part-finished run of reveal taps, so
// the count only ever spans one uninterrupted visit. Returns the model physically
// unchanged when there's nothing to abandon, which is what lets the driver's loop skip
// the re-render (see `Html.mount`'s equality check).
let freshVisit = (model: model) => {
  let hidden = HiddenOptions.reset(model.hidden)
  hidden === model.hidden ? model : {...model, hidden}
}

let update = (env: env, msg, model) =>
  switch msg {
  | ToggleAutoCollect =>
    let model = {...model, autoCollect: !model.autoCollect}
    (
      model,
      () => {
        env.publish(model)
        env.persist(model)
      },
    )
  | ToggleCardTilt =>
    let model = {...model, cardTilt: !model.cardTilt}
    (
      model,
      () => {
        env.publish(model)
        env.persist(model)
        // The board is already laid out with the old tilt drawn into it, so ask for the
        // cards again rather than letting the flip wait for the next move.
        env.board(Relayout)
      },
    )
  // Wiggle Waggle turned off: stop listening and square the board back up (the board's
  // `stop` does both). Snapping the mess back is the deliberate way out — a hidden
  // square-up gesture can't be the only one.
  | WiggleOff =>
    let model = {...model, wiggle: Motion.Off, wantsShake: false}
    (
      model,
      () => {
        env.publish(model)
        env.persist(model)
        env.board(ShakeStop)
      },
    )
  // A motion-permission request resolved. `On` — granted or ungated: start listening,
  // and the intent is now on, so the next launch resumes. `Blocked` — the OS refused:
  // the switch snaps back to off (its subtitle explains why) and we stop, while the
  // saved intent stays exactly as it was. `Unavailable`/`Off` just reflect the state.
  | WiggleResolved(state) =>
    let model = {
      ...model,
      wiggle: state,
      wantsShake: switch state {
      | Motion.On => true
      | Blocked | Unavailable(_) | Off => model.wantsShake
      },
    }
    (
      model,
      () => {
        env.publish(model)
        env.persist(model)
        switch state {
        | Motion.On => env.board(ShakeStart)
        | Blocked => env.board(ShakeStop)
        | Unavailable(_) | Off => ()
        }
      },
    )
  // Nothing to ask of the board: this decides what the *next* victory does, and there
  // is no victory on the table to redecorate.
  | ToggleVictoryAnimation =>
    let model = {...model, victoryAnimation: !model.victoryAnimation}
    (
      model,
      () => {
        env.publish(model)
        env.persist(model)
      },
    )
  // The one setting the board never reads: it reaches the page as a document-root
  // attribute the CSS wing-placement rules key off, so reflecting it is the whole of
  // the change.
  | ToggleNotchDisplay =>
    let model = {...model, notchDisplay: !model.notchDisplay}
    (
      model,
      () => {
        env.root(model)
        env.persist(model)
      },
    )
  // Every tenth tap flips the settings that aren't ready to be found yet into or out of
  // view, and persists that so the gesture is performed once per device rather than once
  // per launch. Hiding them again leaves whatever they switched on running — see
  // `HiddenOptions` for why that's deliberate, and what it costs.
  | TitleTapped =>
    let hidden = HiddenOptions.tap(model.hidden)
    let next = {...model, hidden}
    (
      next,
      // Only the tap that actually flipped the reveal is worth persisting; the other
      // nine in a run just move the counter.
      HiddenOptions.revealChanged(~before=model.hidden, ~after=hidden)
        ? () => env.persist(next)
        : Html.noEffect,
    )
  }

// --- The screen itself ---------------------------------------------------------
type props = {
  // The state above, and the way back up to the loop that holds it: `Main` maps these
  // messages through one constructor. What a switch *does* is `update`'s business a few
  // lines up, rather than a handler the driver passes in per row.
  model: model,
  dispatch: msg => unit,
  onClose: unit => unit,
  onBackToMenu: unit => unit,
  onOpenDebug: unit => unit,
}

// The Wiggle Waggle tap, and the one thing on this screen that can't simply be a
// message: turning it *on* has to ask for the motion grant under this real click's
// transient activation — iOS won't prompt without one and remembers a denial per origin,
// so there is exactly one chance to ask. The answer arrives back as `WiggleResolved`.
// Turning it off just stops, and an `Unavailable` switch has nothing to grant, so a tap
// there is inert.
let askMotion = (state, dispatch) =>
  switch state {
  | Motion.Unavailable(_) => ()
  | On => dispatch(WiggleOff)
  | Off | Blocked =>
    Motion.requestAccess()->Promise.thenResolve(state => dispatch(WiggleResolved(state)))->ignore
  }

let make = ({model, dispatch, onClose, onBackToMenu, onOpenDebug}) => <>
  <MenuHeader
    title="Settings"
    back={Some({label: "Back to menu", onClick: onBackToMenu})}
    onTitleTap={Some(() => dispatch(TitleTapped))}
    onClose
  />
  <div className="menu-screen">
    <MenuSection label="Settings">
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
        // The hidden settings sit below "Sloppy placement" but are *not* nested
        // under it — each is an independent setting. They're hidden until the Settings
        // title has been tapped ten times (`HiddenOptions`) — not ready to be found by
        // a player yet, but reachable on a test device. Ten more taps hide the rows
        // again *without* turning either off, so an absent row here doesn't mean its
        // setting is off — Wiggle Waggle can still be jostling a board with no switch
        // on screen to stop it.
        model.hidden.revealed
          ? <>
              <MenuWiggleRow
                state={model.wiggle} onToggle={() => askMotion(model.wiggle, dispatch)}
              />
              <MenuToggleRow
                label="Victory animation"
                desc="Celebrate a win with an animation."
                on={model.victoryAnimation}
                onToggle={() => dispatch(ToggleVictoryAnimation)}
              />
            </>
          : Html.empty
      }
      <MenuToggleRow
        label="Display content around notch"
        desc="Let the controls reach into the corners beside the camera notch."
        on={model.notchDisplay}
        onToggle={() => dispatch(ToggleNotchDisplay)}
      />
    </MenuSection>
    <MenuSection label="More" tag=Nav>
      <MenuNavRow label="Debug" onClick=onOpenDebug />
    </MenuSection>
  </div>
</>
