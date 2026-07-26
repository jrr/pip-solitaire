// Debug console logging (#213): a developer aid, gated behind the Debug-settings
// "Console logging" toggle. When on, the app narrates every UI↔Core interaction —
// the moves the board dispatches into `core`'s reducer and the Ok/Error results it
// hands back, auto-collect, the finish sweep, undo, and each board (re)deal — to the
// browser's JS console, so `core`'s traffic can be watched live without a debugger.
// Off (the shipped default), every `log`/`message` short-circuits before formatting
// anything, so the instrumentation is free when it isn't wanted.
//
// The toggle flips `enabled` (see Main's ToggleDebugLog), seeded at startup from the
// persisted preference (Preferences.loadDebugLog) so a developer who left logging on
// still sees it after a reload. Lines are written through `sink` — the console in the
// running app, swapped in the tests to capture them and assert the gate.
//
// Scope note: only the *discrete, state-affecting* interactions are logged. The
// continuous per-frame legality queries a drag fires (`canDrop`/`canMoveRun` on every
// `pointermove`, and the pervasive `GameState` read helpers the layout calls) are
// deliberately left out — logging them would bury the useful lines under hundreds of
// per-drag entries. "Every UI↔Core interaction" here means every move the UI asks
// core to make and every board rebuild, not every read.

// Whether logging is currently on. A plain module-level ref, like the other debug
// singletons (see CutoutDebug); Main seeds it at startup and flips it on toggle.
let enabled = ref(false)
let setEnabled = (on: bool) => enabled := on

// Every line carries this prefix so the app's own logs stand out from a page's other
// console noise and can be filtered on.
let prefix = "[pip]"

// Where a line goes once it clears the gate: the browser console in the running app.
// A test points it at a buffer to assert what would (and wouldn't) be logged.
let sink: ref<string => unit> = ref(line => Console.log(line))

// Render `label` and its `value` into one line: the value as compact JSON so a core
// action/result/card prints its fields inspectably. A value that can't be stringified
// (a cycle, a function) logs its label alone.
let format = (label: string, value: 'a): string =>
  switch JSON.stringifyAny(value) {
  | Some(json) => `${prefix} ${label} ${json}`
  | None => `${prefix} ${label}`
  }

// Narrate one interaction: a short `label` and the value in play (an action, a moved
// card list, …). A no-op unless logging is on, so call sites needn't guard — and the
// JSON formatting only runs when the line will actually be shown.
let log = (label: string, value: 'a): unit =>
  if enabled.contents {
    sink.contents(format(label, value))
  }

// A message-only line, for an interaction with no payload worth printing.
let message = (label: string): unit =>
  if enabled.contents {
    sink.contents(`${prefix} ${label}`)
  }
