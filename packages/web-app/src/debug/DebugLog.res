// A developer aid narrating every UI↔Core interaction: the moves the board dispatches
// into the reducer and the results it gets back, auto-collect, the finish sweep, undo,
// each board deal.
//
// A line is *published*, not printed — `log`/`message` build a structured `entry` and
// hand it to whoever is **subscribed**, which today is the JS console
// (`setConsoleEnabled`) and the in-app drop-down panel (`DebugConsole`). Keeping
// entries structured rather than pre-formatted is what lets the two differ: the
// console flattens `{label, value}` into a string, the panel styles them apart.
//
// **`enabled` is derived from whether anyone is listening**, so with nothing
// subscribed every call short-circuits before stringifying anything and the
// instrumentation is free. Both subscribers are opt-in, so the shipped default is
// silent.
//
// Only *discrete, state-affecting* interactions are logged. The per-frame legality
// queries a drag fires are deliberately left out; logging those would bury the useful
// lines under hundreds of per-drag entries.

// `seq` counts every entry ever published, so a reader can see where the scrollback
// was trimmed. `value` is the payload already rendered to compact JSON — `None` for a
// message-only line, and also for a value that can't be stringified, which logs its
// label alone.
type entry = {
  seq: int,
  time: float,
  label: string,
  value: option<string>,
  // The ink-tagged spans a board's row is made of, for a subscriber that can paint
  // them. *Additional* to `label` rather than instead of it — `label` always carries
  // the plain text, so a subscriber that doesn't understand spans still shows the row.
  spans: option<Render.line>,
}

// Carried on every console line, so the app's logs stand out from a page's other noise
// and can be filtered on.
let prefix = "[pip]"

// --- Subscribers -------------------------------------------------------------
// Each carries an id so `subscribe`'s returned thunk can drop exactly its own —
// identity on the function would break the moment a caller subscribed twice.
type subscriber = {id: int, notify: entry => unit}

let subscribers: ref<array<subscriber>> = ref([])
let nextId = ref(0)

// The returned thunk unsubscribes, and is idempotent: a second call finds the id gone.
let subscribe = (notify: entry => unit): (unit => unit) => {
  let id = nextId.contents
  nextId := id + 1
  subscribers := Array.concat(subscribers.contents, [{id, notify}])
  () => subscribers := subscribers.contents->Array.filter(s => s.id != id)
}

// Derived rather than set, so the flag and the subscribers can't disagree.
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

// A no-op unless something is listening, so call sites needn't guard and the JSON
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

// A `message` that also carries the spans its text was flattened from, so a subscriber
// that can paint them picks them up and every other one keeps working.
let line = (spans: Render.line): unit =>
  if enabled() {
    publish(~label=Render.toPlain([spans]), ~value=None, ~spans)
  }

// The console's flattening. The panel doesn't use it — it keeps label and payload
// apart so it can style them apart.
let format = (entry: entry): string =>
  switch entry.value {
  | Some(json) => `${prefix} ${entry.label} ${json}`
  | None => `${prefix} ${entry.label}`
  }

// The Debug screen's "Console logging" switch as a subscription. Idempotent in both
// directions, so seeding it from the persisted preference at startup and flipping it
// later go through the same door.
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
// The last `capacity` entries, oldest dropped first — what stops a long session's log
// growing without limit. `push` hands back whatever fell off the front, which is what
// a view rendering one node per entry needs in order to drop as many as it gained.
module Ring = {
  type t = {capacity: int, entries: array<entry>}

  let make = (~capacity: int): t => {capacity, entries: []}

  let push = (ring: t, entry: entry): option<entry> => {
    ring.entries->Array.push(entry)
    Array.length(ring.entries) > ring.capacity ? ring.entries->Array.shift : None
  }

  let entries = (ring: t): array<entry> => ring.entries->Array.copy
  let length = (ring: t): int => Array.length(ring.entries)

  // In place rather than handing back a fresh ring: the panel holds this one, and a
  // view rendering a ring it no longer shares would trim against the wrong length.
  let clear = (ring: t): unit =>
    ring.entries->Array.splice(~start=0, ~remove=Array.length(ring.entries), ~insert=[])
}
