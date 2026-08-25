// The drop-down debug console (#271): a Quake-style panel that drops over the top of
// the board when you press `` ` ``, showing the lines the app already publishes
// through `DebugLog` (#213) — dispatch/result, auto-collect, the finish sweep, undo,
// win. The point is *reach*: the instrumentation was only readable with devtools
// docked, which rules out the installed PWA, a phone on the desk, and a screen-share.
// A key and a panel put it everywhere the game runs.
//
// Desktop-only on purpose: a keypress is the only way in (see the issue — a touch
// affordance would need its own Debug-screen row or hidden gesture).
//
// It isn't read-only any more (#273). Under the scrollback is an **input line**, and a
// command typed into it plays the game: the line is parsed by the grammar `core` shares
// with the CLI (`Command.parse`) and the result is pushed through the very `dispatch` a
// pointer drop uses, so a typed `move 8H 5` is the move a drag would have made — same
// auto-collect, same undo step, same save. This module owns the field, the echo and the
// ↑/↓ history; who *runs* a line is installed from outside (`setRunner`, see `Main`),
// because running one means reaching the board and the chrome, which the panel has no
// business knowing about.
//
// It has more shapes than one (#275): ⇧` steps the panel through four placements — over
// the top of the board, **docked** into the discarded width beside it, along the bottom,
// and over the whole window. The placement is persisted rather than derived from an
// automatic breakpoint — resize the window and a silent reversal would undo the choice
// you just made — and the side dock alone is *refused* in a window too narrow for the
// board to give up the width, which the cycle steps over rather than sticking on
// (`ConsoleDock`, `TableLayout.minStageWidth`). The layout of all four lives in the
// stylesheet; what this module does with the placement is take pointer events natively
// where the panel isn't covering a playable board, rather than forwarding wheel turns by
// hand (see `apply` below).
//
// Two halves, split the way `Main` splits its own chrome:
//
//   - **the shell** is JSX (`make` below), rendered beside `<TopBar>`/`<Menu>` from
//     the chrome model, which is where open/closed lives — console state is dev
//     chrome, so it never touches `core`'s reducer;
//   - **the scrollback** is a plain `<ol>` this module owns and appends to,
//     spliced into the shell with `Html.node`. That's deliberate, though no longer
//     for the reason it was: this used to say the runtime diffed unkeyed children
//     by position, so a list that drops from the front would re-patch every visible
//     line. Preact has keys, so that particular objection is gone — and the
//     arrangement stays anyway, because the real cost was never the re-patching but
//     the walk. Rendering the log as JSX means handing the diff up to 500 vnodes on
//     every entry, and entries arrive in bursts (an autoplay narrates every move).
//     Appending one `<li>` and dropping one from the front is work proportional to
//     what changed, and a spliced subtree is outside the diff entirely.
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
@get external scrollLeft: WebDom.element => float = "scrollLeft"
@set external setScrollLeft: (WebDom.element, float) => unit = "scrollLeft"
@get external clientHeight: WebDom.element => float = "clientHeight"

// Where the panel is on screen, and what a wheel turn over it means — an *overlaid*
// panel takes no pointer events (see DebugConsole.css), so scrolling it is done by hand below.
type box = {"top": float, "bottom": float, "left": float, "right": float}
@send external boxOf: WebDom.element => box = "getBoundingClientRect"

type wheelEvent
@get external deltaY: wheelEvent => float = "deltaY"
@get external deltaX: wheelEvent => float = "deltaX"
@get external clientX: wheelEvent => float = "clientX"
@get external clientY: wheelEvent => float = "clientY"

// The input line's side: what was typed, where the caret goes, and the keys that work
// it. Matched on `event.code` for the same reason the panel's own toggle is (see
// `installKeys` below) — the physical key, whatever the layout calls it.
type keyEvent
@get external code: keyEvent => string = "code"
@get external repeat: keyEvent => bool = "repeat"
@get external shiftKey: keyEvent => bool = "shiftKey"
@send external preventDefault: keyEvent => unit = "preventDefault"
@send
external addKeyListener: (WebDom.element, string, keyEvent => unit) => unit = "addEventListener"
@get external value: WebDom.element => string = "value"
@set external setValue: (WebDom.element, string) => unit = "value"
@send external focus: WebDom.element => unit = "focus"
@send external blur: WebDom.element => unit = "blur"

// --- The scrollback list ------------------------------------------------------
// Built once at module init and never rebuilt: the shell splices this exact node, and
// a spliced node's subtree sits outside the diff entirely (see `Html.node`).
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
// the playfield; see DebugConsole.css), so a wheel turn over it lands on the board behind
// instead of scrolling the log. Nothing on the board reads `wheel`, so the panel picks
// it up from the window while it's overlaid and scrolls itself — reading back through
// history without the console ever taking input away from the game. `stickToBottom`
// follows from the `scroll` listener above. Docked or full-window (#275) the panel takes
// pointer events natively — it covers nothing, or it covers everything — so this is
// unbound in those placements: left on, every turn would scroll the log twice.
//
// Both axes, because the log now carries lines wider than the panel: `print` draws a text
// board (#273) about 150 columns across, and the overlay is the shape that can't scroll
// itself. Forwarding only `deltaY` would leave the right-hand cascades of a printed board
// unreachable in the very shape the panel opens in.
let onWheel = (event: wheelEvent): unit => {
  let box = boxOf(lines)
  let x = clientX(event)
  let y = clientY(event)
  if x >= box["left"] && x <= box["right"] && y >= box["top"] && y <= box["bottom"] {
    setScrollTop(lines, scrollTop(lines) +. deltaY(event))
    setScrollLeft(lines, scrollLeft(lines) +. deltaX(event))
  }
}

// The class a span's ink is painted with. `core` names the *role* a run of characters
// plays and stops there (see `Render.ink`), which is what lets the terminal answer it in
// ANSI and this panel answer it in CSS — with colours picked for a dark log rather than
// for a terminal or for the light card faces the table draws (`Deck.suitColor`).
let inkClass = (ink: Render.ink): string =>
  switch ink {
  | Render.Plain => "debug-console__ink--plain"
  | Render.Suit(Rules.Red) => "debug-console__ink--red"
  | Render.Suit(Rules.Black) => "debug-console__ink--black"
  | Render.Title => "debug-console__ink--title"
  }

// A row `core` rendered as spans: one node per span, each classed by its ink. The line
// gets a modifier class of its own because the ordinary two-part line is a flex row with
// a gap between label and payload — a gap between *every* span of a board would put
// 0.5rem between each card and its frame and tear the drawing apart.
let renderedLine = (spans: Render.line): WebDom.element => {
  let item = WebDom.createElement("li")
  item->WebDom.setAttribute("class", "debug-console__line debug-console__line--rendered")
  spans->Array.forEach(span => {
    let node = WebDom.createElement("span")
    node->WebDom.setAttribute("class", inkClass(span.ink))
    // `textContent`, for the same reason the payload below uses it: a rendered board is
    // game data, not markup.
    node->WebDom.setTextContent(span.text)
    item->WebDom.appendChild(node)->ignore
  })
  item
}

// An ordinary entry: the label and its JSON payload in separate spans, which is the
// reason `DebugLog` publishes structured entries rather than finished strings — the
// panel styles them apart (and could filter on the label later).
let plainLineFor = (entry: DebugLog.entry): WebDom.element => {
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

// One entry as a list item, in whichever of the two shapes it arrived in.
let lineFor = (entry: DebugLog.entry): WebDom.element =>
  switch entry.spans {
  | Some(spans) => renderedLine(spans)
  | None => plainLineFor(entry)
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

// Empty the scrollback — the console's own `clear` verb (#273). Both halves go
// together, the ring and the `<ol>`, for the same reason `append` keeps them the same
// length: the DOM *is* the ring's view, and a view that outlived its model would start
// dropping the wrong lines.
let clear = (): unit => {
  DebugLog.Ring.clear(scrollback)
  WebDom.clear(lines)
  stickToBottom := true
}

// --- The input line (#273) --------------------------------------------------------
// A real `<input>` this module owns and splices into the shell, exactly like the
// scrollback above and for the same reason: unkeyed children are diffed by position
// (#45), and a re-created input is an input that loses its caret, its
// selection and whatever was half-typed in it every time a line arrives in the log.
//
// The panel is *keyboard* chrome — a physical key is the only way in — so this is
// wired to keys rather than to a submit button: Enter runs the line, ↑/↓ walk what's
// been run before, and the panel's own `` ` ``/Escape still close it from in here
// (they're bound on the window, and swallow the key before it can be typed).
let input = WebDom.createElement("input")
input->WebDom.setAttribute("id", "debug-console-input")
input->WebDom.setAttribute("class", "debug-console__input")
input->WebDom.setAttribute("type", "text")
input->WebDom.setAttribute("aria-label", "Debug console command")
input->WebDom.setAttribute("placeholder", "move 8H 5 · help")
// A console line is not prose: nothing here should be autocorrected, capitalised or
// completed from the browser's memory of other forms on other sites.
input->WebDom.setAttribute("autocomplete", "off")
input->WebDom.setAttribute("autocapitalize", "off")
input->WebDom.setAttribute("autocorrect", "off")
input->WebDom.setAttribute("spellcheck", "false")

// What's been run, oldest first, and where ↑/↓ currently sit in it. The cursor rests
// *past the end* while a fresh line is being typed, so the first ↑ recalls the last
// command rather than the one before it.
let recallCapacity = 100
let recalled: ref<array<string>> = ref([])
let recallCursor = ref(0)

let remember = (line: string): unit => {
  // A command repeated straight away isn't worth a second slot — ↑ should step back
  // through what was *done*, not through how many times the same key was pressed.
  let isRepeat = recalled.contents->Array.at(-1) == Some(line)
  if !isRepeat {
    recalled := Array.concat(recalled.contents, [line])
    if Array.length(recalled.contents) > recallCapacity {
      recalled.contents->Array.shift->ignore
    }
  }
  recallCursor := Array.length(recalled.contents)
}

// Step ↑ (`-1`) or ↓ (`+1`) through the recalled commands, putting the one landed on
// into the input. Walking off the end lands on an empty line — back where you were
// before you started reaching backwards — rather than sticking on the newest command.
let recall = (step: int): unit => {
  let count = Array.length(recalled.contents)
  if count > 0 {
    let next = recallCursor.contents + step
    let clamped = next < 0 ? 0 : next > count ? count : next
    recallCursor := clamped
    input->setValue(recalled.contents->Array.get(clamped)->Option.getOr(""))
  }
}

// Who actually runs a line. `Main` installs this at startup (see `setRunner`), because
// running a command means reaching the board's dispatch and the chrome's hooks — things
// this module has no business knowing about. Until then, and on a page where nothing
// installed one, Enter is inert.
let runner: ref<option<string => unit>> = ref(None)
let setRunner = (run: string => unit): unit => runner := Some(run)

// Put a line into the scrollback by publishing it, rather than by appending a node:
// the panel is a `DebugLog` subscriber, so this keeps the echo and its result in the
// same stream — and in the same order — as the `dispatch`/`result` lines the command
// itself provokes. (It also means the JS console sees a typed command, which is right:
// it's an interaction like any other.)
// `reply` is a *document* now (#282), not a string: `core` renders one for a board and
// `Render.text` makes a trivial one out of ordinary prose, so a printed board and a
// rejection travel one channel rather than two. A reply can be several rows (help is, a
// board very much is); each becomes its own entry, so the scrollback's one-node-per-line
// bookkeeping holds. An empty document says nothing, which is how a command whose result
// `DebugLog` already narrates stays quiet.
//
// Whether the rows are *painted* is decided for the document as a whole, not row by row.
// A document `core` inked — a board, which always carries at least its title's ink — is
// painted span by span; a document that is only words is published as plain messages,
// exactly as every reply was before this existed, so help listings and rejections keep
// the log's own voice rather than turning into furniture. Per-document rather than
// per-row because a board's blank separators and its row of empty foundation slots carry
// no ink of their own: judged individually they'd come out styled as prose, striping the
// drawing they belong to.
let inked = (reply: array<Render.line>): bool =>
  reply->Array.some(line =>
    line->Array.some((span: Render.span) => !Render.sameInk(span.ink, Render.Plain))
  )

let say = (reply: array<Render.line>): unit =>
  inked(reply)
    ? reply->Array.forEach(DebugLog.line)
    : reply->Array.forEach(line => DebugLog.message(Render.toPlain([line])))

// The same, for a line this module writes itself rather than one core rendered.
let sayText = (text: string): unit => say(Render.text(text))

// Run whatever is in the input: echo it above its result — that's what makes the log
// readable afterwards, since the result on its own doesn't say what was asked — then
// hand it to the runner and clear the field for the next one. A blank line is ignored
// entirely rather than echoed as an empty prompt.
let submit = (): unit => {
  let line = input->value->String.trim
  input->setValue("")
  if line != "" {
    remember(line)
    sayText("> " ++ line)
    runner.contents->Option.forEach(run => run(line))
  }
}

// The console's own half of the help listing, composed around the shared verbs
// (`Command.dealHelp`, `Command.boardHelp`) so the two front ends can't drift on what
// `moverun` — or now `deal` — does, while each still describes its own surface: a terminal
// has `print` and `games`, the panel has `clear`.
let helpText = () =>
  "Commands:\n" ++
  Command.renderHelp(
    Array.concat(
      Array.concat(Array.concat(Command.dealHelp, Command.boardHelp), Command.driverHelp),
      [("clear", "empty this scrollback"), ("help", "show this help")],
    ),
  ) ++
  "\n\n" ++
  Command.cardNote

input->addKeyListener("keydown", event =>
  switch code(event) {
  | "Enter" | "NumpadEnter" =>
    preventDefault(event)
    submit()
  | "ArrowUp" =>
    // Swallowed, or the caret would jump to the start of the line we just recalled.
    preventDefault(event)
    recall(-1)
  | "ArrowDown" =>
    preventDefault(event)
    recall(1)
  | _ => ()
  }
)

// --- Open / closed, and where the panel sits --------------------------------------
// The subscription *is* the open state as far as `DebugLog` is concerned; `Main`'s
// model owns both flags and calls this as its post-update effect. Idempotent in every
// direction, so it can be called on any state change without checking first — which is
// what lets the two flags be reconciled together here rather than in two entry points
// that could disagree.
let subscription: ref<option<unit => unit>> = ref(None)
let wheelBound = ref(false)

let apply = (~open_: bool, ~dock: ConsoleDock.t): unit => {
  // The layout first, so the panel is already at its placement's size when the scroll
  // below reads its height — and so the board starts reflowing into (or back out of) the
  // side dock in the same frame the panel appears.
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
  // Focus follows the panel (#273). Opening it means you want to type at it — there's
  // no other reason to press the key — and closing it must hand the keyboard back to
  // the page rather than leaving a hidden field holding it, which would swallow every
  // keystroke aimed at the game. Called on every apply, not just on the transitions
  // above, so a placement change (which arrives with the panel already open) leaves the
  // caret where it was rather than dropping it.
  open_ ? focus(input) : blur(input)
  // The hand-forwarded wheel is the overlays' crutch alone (see `onWheel`): a panel that
  // takes pointer events scrolls itself.
  switch (open_ && !ConsoleDock.takesPointerEvents(dock), wheelBound.contents) {
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
// `` ` `` toggles, ⇧` steps the panel round its four placements (#275), Escape closes.
// Matched on `event.code`
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
    ariaLabel="Debug console"
    ariaHidden={open_ ? "false" : "true"}
  >
    {Html.node(body)}
    // The prompt, under the scrollback (#273) — the seam #271 left open here. Spliced
    // like the scrollback rather than rendered as JSX, so the diff never touches
    // the live field (see `input` above). The `>` is a plain sibling: a `::before` on
    // the input itself isn't possible, and putting the caret behind a padded background
    // image is more machinery than a span.
    <div className="debug-console__prompt">
      <span className="debug-console__caret" ariaHidden="true"> {Html.string(">")} </span>
      {Html.node(input)}
    </div>
    // The status line sits at the *foot*, under the prompt: up top it would land on the
    // top bar's Menu button, which the panel drops over.
    <footer className="debug-console__status">
      // Just the panel's name: which of the four placements (#275) it's in is plain from
      // where it is, and each change already names itself in the log as it happens (see
      // `Main`'s ⇧` branch). A second copy here only crowded the status line — in the
      // 340px dock, the placement with the least room for it.
      <span className="debug-console__title"> {Html.string("debug console")} </span>
      <span className="debug-console__hint">
        {Html.string("enter run · ↑↓ history · ` toggle · ⇧` place · esc close")}
      </span>
    </footer>
  </section>
