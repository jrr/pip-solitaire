// Debug logging (#213): a developer aid narrating every UI↔Core interaction — the
// moves the board dispatches into `core`'s reducer and the Ok/Error results it hands
// back, auto-collect, the finish sweep, undo, and each board (re)deal.
//
// A line is *published*, not printed: `log`/`message` build a structured `entry` and
// hand it to whoever is **subscribed**. There are two subscribers today, and they want
// the same traffic in different places:
//
//   - the **JS console** (`setConsoleEnabled`, driven by the Debug screen's "Console
//     logging" switch, #213) — it renders each entry to a prefixed line with `format`;
//   - the **drop-down debug console** (#271, `DebugConsole`) — the in-app panel, which
//     keeps its own bounded scrollback (`Ring` below) so the instrumentation is
//     readable without devtools docked: in the installed PWA, on a phone, mid-demo.
//
// Structured entries rather than pre-formatted strings are what let those two differ:
// the console flattens `{label, value}` into one string, while the panel styles the
// label apart from its JSON payload (and could filter on it later).
//
// `enabled` is *derived* from whether anyone is listening, which keeps the property
// this module has always had — with nothing subscribed, every `log`/`message`
// short-circuits before stringifying anything, so the instrumentation is free when it
// isn't wanted. Both subscribers are opt-in (a switch, a keypress), so the shipped
// default is still silent.
//
// Scope note: only the *discrete, state-affecting* interactions are logged. The
// continuous per-frame legality queries a drag fires (`canDrop`/`canMoveRun` on every
// `pointermove`, and the pervasive `GameState` read helpers the layout calls) are
// deliberately left out — logging them would bury the useful lines under hundreds of
// per-drag entries. "Every UI↔Core interaction" here means every move the UI asks
// core to make and every board rebuild, not every read.

// One narrated interaction. `seq` counts every entry the app has published (so a
// reader can see where the scrollback was trimmed), `time` is the wall clock at
// publication, and `value` is the payload already rendered to compact JSON — `None`
// for a message-only line, and also for a value that can't be stringified (a cycle, a
// function), which logs its label alone.
type entry = {
  seq: int,
  time: float,
  label: string,
  value: option<string>,
  // A line `core` rendered as a document rather than as text (#282): the ink-tagged
  // spans a board's row is made of, for a subscriber that can paint them. `None` for
  // every ordinary line, and *additional* to `label` rather than instead of it —
  // `label` always carries the plain text, so a subscriber that doesn't understand
  // spans (the JS console, and any test) still shows the row.
  spans: option<Render.line>,
}

// Every console line carries this prefix so the app's own logs stand out from a page's
// other console noise and can be filtered on.
let prefix = "[pip]"

// --- Subscribers -------------------------------------------------------------
// A plain module-level list, like the other debug singletons (see CutoutDebug). Each
// subscriber carries an id so `subscribe`'s returned thunk can drop exactly its own
// — identity on the function would break the moment a caller subscribed twice.
type subscriber = {id: int, notify: entry => unit}

let subscribers: ref<array<subscriber>> = ref([])
let nextId = ref(0)

// Listen to every entry from now on; the returned thunk unsubscribes (idempotent — a
// second call is a no-op, since the id is already gone).
let subscribe = (notify: entry => unit): (unit => unit) => {
  let id = nextId.contents
  nextId := id + 1
  subscribers := Array.concat(subscribers.contents, [{id, notify}])
  () => subscribers := subscribers.contents->Array.filter(s => s.id != id)
}

// Whether anything is listening — the gate `log`/`message` check before doing any
// work. Derived rather than set: there's no way for the flag and the subscribers to
// disagree.
let enabled = (): bool => Array.length(subscribers.contents) > 0

// --- Publishing --------------------------------------------------------------
let seq = ref(0)

let publish = (~label: string, ~value: option<string>, ~spans: option<Render.line>=?): unit => {
  seq := seq.contents + 1
  let entry = {seq: seq.contents, time: Date.now(), label, value, spans}
  // Iterate a snapshot: a subscriber that unsubscribes (or subscribes) while being
  // notified must not disturb the walk over the list it was called from.
  subscribers.contents->Array.forEach(s => s.notify(entry))
}

// Narrate one interaction: a short `label` and the value in play (an action, a moved
// card list, …), rendered as compact JSON so a core action/result/card is inspectable.
// A no-op unless something is listening, so call sites needn't guard — and the JSON
// stringification only runs when the line will actually be seen.
let log = (label: string, value: 'a): unit =>
  if enabled() {
    publish(~label, ~value=JSON.stringifyAny(value))
  }

// A message-only line, for an interaction with no payload worth printing.
let message = (label: string): unit =>
  if enabled() {
    publish(~label, ~value=None)
  }

// One row of a document `core` rendered (#282) — a board's line, or a line of ordinary
// reply text, which is the same thing with everything inked plain. The row's plain text
// goes in `label` as usual, so this is a `message` that happens to carry the spans it was
// flattened from: every existing subscriber keeps working, and one that can paint them
// picks them up.
let line = (spans: Render.line): unit =>
  if enabled() {
    publish(~label=Render.toPlain([spans]), ~value=None, ~spans)
  }

// --- Rendering ---------------------------------------------------------------
// Flatten an entry into one prefixed console line: the label, then its JSON payload.
// The panel doesn't use this — it keeps the two apart so it can style them apart.
let format = (entry: entry): string =>
  switch entry.value {
  | Some(json) => `${prefix} ${entry.label} ${json}`
  | None => `${prefix} ${entry.label}`
  }

// --- The JS console subscriber ------------------------------------------------
// The Debug screen's "Console logging" switch, expressed as a subscription: on
// subscribes the console, off drops it. Idempotent in both directions, so seeding it
// from the persisted preference at startup and flipping it later go through the same
// door.
let consoleOff: ref<option<unit => unit>> = ref(None)

let setConsoleEnabled = (on: bool): unit =>
  switch (on, consoleOff.contents) {
  | (true, None) => consoleOff := Some(subscribe(entry => Console.log(format(entry))))
  | (false, Some(unsubscribe)) =>
    unsubscribe()
    consoleOff := None
  | (true, Some(_)) | (false, None) => ()
  }

// --- A bounded scrollback ------------------------------------------------------
// What a viewer subscribes *with*: the last `capacity` entries, oldest dropped first.
// The panel (#271) holds one of these and mirrors it into the DOM, so the bound is
// what stops a long session's log from growing without limit.
//
// `push` hands back whichever entry fell off the front (`None` while there's still
// room), which is exactly what a view rendering one node per entry needs in order to
// drop the same number of nodes it gained.
module Ring = {
  type t = {capacity: int, entries: array<entry>}

  let make = (~capacity: int): t => {capacity, entries: []}

  let push = (ring: t, entry: entry): option<entry> => {
    ring.entries->Array.push(entry)
    Array.length(ring.entries) > ring.capacity ? ring.entries->Array.shift : None
  }

  let entries = (ring: t): array<entry> => ring.entries->Array.copy
  let length = (ring: t): int => Array.length(ring.entries)

  // Drop everything, keeping the ring itself — what the console's `clear` verb (#273)
  // does to the scrollback. In place rather than by handing back a fresh ring, because
  // the panel holds this one and a view rendering a ring it no longer shares would
  // start trimming against the wrong length.
  let clear = (ring: t): unit =>
    ring.entries->Array.splice(~start=0, ~remove=Array.length(ring.entries), ~insert=[])
}
