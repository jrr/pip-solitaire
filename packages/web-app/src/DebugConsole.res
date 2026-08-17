// The drop-down debug console (#271): a Quake-style panel that drops over the top of
// the board when you press `` ` ``, showing the lines the app already publishes
// through `DebugLog` (#213) — dispatch/result, auto-collect, the finish sweep, undo,
// win. The point is *reach*: the instrumentation was only readable with devtools
// docked, which rules out the installed PWA, a phone on the desk, and a screen-share.
// A key and a panel put it everywhere the game runs.
//
// Read-only, and desktop-only on purpose: a keypress is the only way in (see the
// issue — a touch affordance would need its own Debug-screen row or hidden gesture),
// and there's no command input yet. The seam for one is the panel's flex column: an
// input line would go in under the scrollback.
//
// It has a second shape (#275): ⇧` **docks** it into the discarded width beside the
// board instead of overlaying the top of it. Docking is a persisted mode rather than an
// automatic breakpoint — resize the window and a silent reversal would undo the choice
// you just made — and it's *refused* in a window too narrow for the board to give up the
// width (`ConsoleDock`, `TableScene.minStageWidth`). The layout of both shapes lives in
// the stylesheet; what this module does with the mode is take pointer events natively
// when docked rather than forwarding wheel turns by hand (see `apply` below).
//
// Two halves, split the way `Main` splits its own chrome:
//
//   - **the shell** is JSX (`make` below), rendered beside `<TopBar>`/`<Menu>` from
//     the chrome model, which is where open/closed lives — console state is dev
//     chrome, so it never touches `core`'s reducer;
//   - **the scrollback** is a plain `<ol>` this module owns and appends to,
//     spliced into the shell with `Html.node`. That's deliberate: `Html`'s reconciler
//     does a positional diff with no keys (#45), so a list that drops from the front
//     would re-patch every visible line on every new entry. Append one `<li>`, drop
//     one from the front, and the reconciler never has to look inside.
//
// The panel subscribes to `DebugLog` while it's open and unsubscribes when it closes,
// so a closed console costs exactly nothing (`DebugLog.enabled` is derived from the
// subscriber list). The scrollback it has already collected stays on screen — both the
// ring and the `<ol>` outlive a close — so reopening resumes rather than restarts.

// How many lines the panel keeps. A session's log is unbounded; the panel's view of it
// isn't — old lines fall off the front of both the ring and the `<ol>` together.
let capacity = 500

let scrollback = DebugLog.Ring.make(~capacity)

// --- DOM bindings the shared `WebDom` set doesn't carry ----------------------
// Scroll geometry, for the stick-to-bottom behaviour below.
@get external scrollTop: WebDom.element => float = "scrollTop"
@set external setScrollTop: (WebDom.element, float) => unit = "scrollTop"
@get external scrollHeight: WebDom.element => float = "scrollHeight"
@get external clientHeight: WebDom.element => float = "clientHeight"

// Where the panel is on screen, and what a wheel turn over it means — an *overlaid*
// panel takes no pointer events (see index.html), so scrolling it is done by hand below.
type box = {"top": float, "bottom": float, "left": float, "right": float}
@send external boxOf: WebDom.element => box = "getBoundingClientRect"

type wheelEvent
@get external deltaY: wheelEvent => float = "deltaY"
@get external clientX: wheelEvent => float = "clientX"
@get external clientY: wheelEvent => float = "clientY"

// --- The scrollback list ------------------------------------------------------
// Built once at module init and never rebuilt: the shell splices this exact node, and
// `Html`'s reconciler leaves a spliced node's subtree entirely alone.
let lines = WebDom.createElement("ol")
lines->WebDom.setAttribute("id", "debug-console-lines")
lines->WebDom.setAttribute("class", "debug-console__lines")

// Whether new lines should scroll themselves into view. True until the reader scrolls
// up to read something, false while they're up there, true again the moment they come
// back to the foot — so the log follows the game unless you've asked it not to.
let stickToBottom = ref(true)

// Slack for the "are we at the foot?" test: sub-pixel scroll positions (and a
// fractionally-tall last line) mean the numbers rarely land dead equal.
let bottomSlack = 4.

let atBottom = (el): bool => scrollHeight(el) -. scrollTop(el) -. clientHeight(el) <= bottomSlack

// One listener for every way the list can move — our own autoscroll included, which is
// what keeps `stickToBottom` true while the log is following the game.
lines->WebDom.addEventListener("scroll", () => stickToBottom := atBottom(lines))

// An *overlaid* scrollback takes no pointer events (it's a read-only HUD dropped over
// the playfield; see index.html), so a wheel turn over it lands on the board behind
// instead of scrolling the log. Nothing on the board reads `wheel`, so the panel picks
// it up from the window while it's overlaid and scrolls itself — reading back through
// history without the console ever taking input away from the game. `stickToBottom`
// follows from the `scroll` listener above. Docked (#275) the panel covers nothing and
// takes pointer events natively, so this is unbound there — left on, every turn would
// scroll the log twice.
let onWheel = (event: wheelEvent): unit => {
  let box = boxOf(lines)
  let x = clientX(event)
  let y = clientY(event)
  if x >= box["left"] && x <= box["right"] && y >= box["top"] && y <= box["bottom"] {
    setScrollTop(lines, scrollTop(lines) +. deltaY(event))
  }
}

// One entry as a list item: the label and its JSON payload in separate spans, which is
// the whole reason `DebugLog` publishes structured entries rather than finished
// strings — the panel styles them apart (and could filter on the label later).
let lineFor = (entry: DebugLog.entry): WebDom.element => {
  let item = WebDom.createElement("li")
  item->WebDom.setAttribute("class", "debug-console__line")

  let label = WebDom.createElement("span")
  label->WebDom.setAttribute("class", "debug-console__label")
  label->WebDom.setTextContent(entry.label)
  item->WebDom.appendChild(label)->ignore

  // `textContent`, not markup: a logged value is arbitrary game data and has no
  // business being parsed as HTML.
  entry.value->Option.forEach(json => {
    let value = WebDom.createElement("span")
    value->WebDom.setAttribute("class", "debug-console__value")
    value->WebDom.setTextContent(json)
    item->WebDom.appendChild(value)->ignore
  })

  item
}

// The subscriber itself: append the new line, drop the front one if the ring just
// overflowed (so the DOM stays exactly as long as the ring), and follow the foot when
// the reader hasn't scrolled away from it.
let append = (entry: DebugLog.entry): unit => {
  lines->WebDom.appendChild(lineFor(entry))->ignore
  switch DebugLog.Ring.push(scrollback, entry) {
  | Some(_dropped) =>
    lines
    ->WebDom.firstChild
    ->Nullable.toOption
    ->Option.forEach(first => lines->WebDom.removeChild(first)->ignore)
  | None => ()
  }
  if stickToBottom.contents {
    setScrollTop(lines, scrollHeight(lines))
  }
}

// --- Open / closed, overlaid / docked --------------------------------------------
// The subscription *is* the open state as far as `DebugLog` is concerned; `Main`'s
// model owns both flags and calls this as its post-update effect. Idempotent in every
// direction, so it can be called on any state change without checking first — which is
// what lets the two flags be reconciled together here rather than in two entry points
// that could disagree.
let subscription: ref<option<unit => unit>> = ref(None)
let wheelBound = ref(false)

let apply = (~open_: bool, ~dock: ConsoleDock.t): unit => {
  // The layout first, so the panel is already at its docked size when the scroll below
  // reads its height — and so the board starts reflowing into (or back out of) the dock
  // in the same frame the panel appears.
  ConsoleDock.reflect(~dock, ~open_)
  switch (open_, subscription.contents) {
  | (true, None) =>
    subscription := Some(DebugLog.subscribe(append))
    // A panel that's just come up shows the foot of the log, whatever the reader had
    // scrolled to last time. The shell is already visible by now — effects run after
    // the patch — so the scroll actually takes.
    stickToBottom := true
    setScrollTop(lines, scrollHeight(lines))
  | (false, Some(unsubscribe)) =>
    unsubscribe()
    subscription := None
  | (true, Some(_)) | (false, None) => ()
  }
  // The hand-forwarded wheel is the overlay's crutch alone (see `onWheel`): a docked
  // panel scrolls itself.
  switch (open_ && !ConsoleDock.isDocked(dock), wheelBound.contents) {
  | (true, false) =>
    WebDom.addWindowListener("wheel", onWheel)
    wheelBound := true
  | (false, true) =>
    WebDom.removeWindowListener("wheel", onWheel)
    wheelBound := false
  | (true, true) | (false, false) => ()
  }
}

// --- The key that opens it ------------------------------------------------------
type keyEvent
@get external code: keyEvent => string = "code"
@get external repeat: keyEvent => bool = "repeat"
@get external shiftKey: keyEvent => bool = "shiftKey"
@send external preventDefault: keyEvent => unit = "preventDefault"

// `` ` `` toggles, ⇧` docks or undocks (#275), Escape closes. Matched on `event.code`
// rather than `event.key` because backtick is a dead key on several layouts (and
// shifted into `~` on all of them): `code` names the physical key regardless, so the
// same finger works everywhere — and it's also what makes the shifted variant a
// *reading* of the same key rather than a second binding to keep in step. A held key
// repeats, which would strobe the panel — hence the `repeat` guard.
let installKeys = (~onToggle: unit => unit, ~onClose: unit => unit, ~onDock: unit => unit): unit =>
  WebDom.addWindowListener("keydown", (event: keyEvent) =>
    if !repeat(event) {
      switch code(event) {
      | "Backquote" =>
        // Nothing else in the app wants this key, and swallowing it keeps a
        // browser/extension shortcut from firing behind the panel.
        preventDefault(event)
        shiftKey(event) ? onDock() : onToggle()
      | "Escape" => onClose()
      | _ => ()
      }
    }
  )

// --- The shell ------------------------------------------------------------------
// A pure `props => vnode` in the `TopBar`/`Menu` mold (see `VersionBadge` for why the
// props record is spelled out by hand). `body` is the scrollback node above, handed in
// by `Main` the same way the menu is handed the switcher's rows.
type props = {
  open_: bool,
  body: Html.element,
}

let make = ({open_, body}) =>
  <section
    id="debug-console"
    hidden={!open_}
    attrs={[("aria-label", "Debug console"), ("aria-hidden", open_ ? "false" : "true")]}
  >
    {Html.node(body)}
    // The status line sits at the *foot*, under the scrollback: up top it would land
    // on the top bar's Menu button, which the panel drops over. It's also where a
    // typed-command prompt would go if one ever arrives (#91/#92) — the seam this
    // issue deliberately leaves open.
    <footer className="debug-console__status">
      <span className="debug-console__title"> {Html.string("debug console")} </span>
      <span className="debug-console__hint">
        {Html.string("` toggle · ⇧` dock · esc close")}
      </span>
    </footer>
  </section>
