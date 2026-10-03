// A driver *preference* record: the flags that tune how a driver behaves
// *around* the pure reducer — deliberately not board state. This is the toggle
// seam a future settings screen flips: a single record both drivers read,
// so wiring a UI control later sets one field here and nothing else changes.
//
// It is **not** `GameState`. Auto-collect is a preference, not "where cards rest",
// so it stays out of the immutable snapshot (which stays purely about the board)
// and is threaded into the drivers' post-move step instead.
//
// `autoCollect`: after each accepted move, automatically send every card
// that is *safe* to play (`Reducer.isSafeToCollect`) home to its foundation, so a
// player never has to click the obvious ones — the behaviour most FreeCell apps
// have on by default. Gated entirely by this flag: `autoCollect: false` is an
// exact no-op, the board left exactly as the reducer returned it.
//
// `allowColumnReorder`: a **house rule** for our variant — may the player
// pull a cascade column out and drop it into the gap between two others, the rest
// sliding over (a `Reducer.MoveColumn`)? Strict FreeCell doesn't sanction moving
// whole columns around, so it's opt-in, defaulting *on* for our game. The board has no
// gesture for it yet, so its switch is among the hidden settings. Gated exactly like
// `autoCollect`: when off, a driver never dispatches the reorder, so it's an exact no-op.
//
// `allowFoundationReturn`: a **house rule** — may a card that has gone home be
// taken back off its foundation and played again ("worrying back")? Strict FreeCell
// says a card played home stays home, and so does the solver, which never plans a
// move off a foundation; this game has always allowed it, so it defaults *on*. It
// answers the moves out of a *playable* foundation only: a `Sealed` one (Simple
// Simon's) is refused by the reducer whatever this says. Gated like
// `allowColumnReorder`, before the reducer (`Session.dispatch`).
//
// `allowDealWithEmptyColumns`: a **house rule** for the games that deal from a stock —
// may a row be dealt while a column stands empty? Spider refuses it, and so does this
// game by default, so it's opt-in. Unlike the two above it *loosens* a board rule, so it
// can't be a gate in front of the reducer: `Session.dispatch` hands it to the reducer,
// which waives that one refusal (`Reducer.dealRefusal`). The solver plays the standard
// game regardless, and its plans stay legal under either.
//
// `memory`: how much the solver may hold (`Solver.tier`), over whatever the driver would
// choose for itself — `None` leaves it to the driver: the web app's reading of the
// device, the CLI's `Medium`. The one setting that isn't on or off.
//
// `thinking`: may the solver think about the board between asks, unasked, so a Solve
// finds its answer already warm? Only a driver with another thread to think on acts on
// it — the web app's `Thinker`, behind a Debug-screen switch that also shows what the
// thinking found; the CLI thinks only when asked whatever this says. Off by default: it
// is a developer's setting until what a player may be shown of it is decided (#410).
type t = {
  autoCollect: bool,
  allowColumnReorder: bool,
  allowFoundationReturn: bool,
  allowDealWithEmptyColumns: bool,
  memory: option<Solver.tier>,
  thinking: bool,
}

// The shipped default: auto-collect on, the two house rules the game has always played
// by allowed, and the deal kept to the standard game.
let default = {
  autoCollect: true,
  allowColumnReorder: true,
  allowFoundationReturn: true,
  allowDealWithEmptyColumns: false,
  memory: None,
  thinking: false,
}

// --- Addressing a flag by name -----------------------------------------------
// The fields above, as a value a *command* can name: what `set autocollect off` sets.
// The settings are a closed set, and which ones exist is knowable from the text alone,
// so this lives here beside the record rather than in either front end — and the shared
// parser can hand over a typed setting instead of a string each driver re-checks.
//
// It's also the only way to reach `allowColumnReorder` from the CLI, and from a web
// menu whose hidden settings haven't been revealed.
type setting =
  | AutoCollect
  | ColumnReorder
  | FoundationReturn
  | EmptyColumnDeal
  | Memory
  | Thinking

let all = [AutoCollect, ColumnReorder, FoundationReturn, EmptyColumnDeal, Memory, Thinking]

// The canonical name of a setting — what `set` takes and what a listing shows.
let name = (s: setting): string =>
  switch s {
  | AutoCollect => "autocollect"
  | ColumnReorder => "reorder"
  | FoundationReturn => "worryback"
  | EmptyColumnDeal => "gapdeal"
  | Memory => "memory"
  | Thinking => "thinking"
  }

let parse = (token: string): option<setting> =>
  switch token->String.toLowerCase {
  | "autocollect" | "auto-collect" | "collect" => Some(AutoCollect)
  | "reorder" | "columnreorder" | "movecol" => Some(ColumnReorder)
  | "worryback" | "worry" | "takeback" => Some(FoundationReturn)
  | "gapdeal" | "emptydeal" | "dealempty" => Some(EmptyColumnDeal)
  | "memory" | "mem" | "tier" => Some(Memory)
  | "thinking" | "think" | "thinkahead" => Some(Thinking)
  | _ => None
  }

// The value half. A flag is on or off; `memory` is a tier, or `auto` for the driver's own.
type value =
  | Flag(bool)
  | Tier(option<Solver.tier>)

// What counts as on and off. Generous about spelling, because a flag refused over `true`
// vs `on` teaches nothing.
let parseFlag = (token: string): option<bool> =>
  switch token->String.toLowerCase {
  | "on" | "true" | "yes" | "1" => Some(true)
  | "off" | "false" | "no" | "0" => Some(false)
  | _ => None
  }

// A value of the kind `s` takes, or `None` — so a value can't reach `apply` on a setting
// of the other kind from a typed line.
let parseValue = (s: setting, token: string): option<value> =>
  switch s {
  | Memory =>
    switch token->String.toLowerCase {
    | "auto" | "device" => Some(Tier(None))
    | other => Solver.parseTier(other)->Option.map(tier => Tier(Some(tier)))
    }
  | AutoCollect | ColumnReorder | FoundationReturn | EmptyColumnDeal | Thinking =>
    parseFlag(token)->Option.map(on => Flag(on))
  }

// What a setting's values are, in words, for a refusal.
let spellings = (s: setting): string =>
  switch s {
  | Memory => "small, medium, large or auto"
  | AutoCollect | ColumnReorder | FoundationReturn | EmptyColumnDeal | Thinking => "on or off"
  }

let read = (o: t, s: setting): value =>
  switch s {
  | AutoCollect => Flag(o.autoCollect)
  | ColumnReorder => Flag(o.allowColumnReorder)
  | FoundationReturn => Flag(o.allowFoundationReturn)
  | EmptyColumnDeal => Flag(o.allowDealWithEmptyColumns)
  | Memory => Tier(o.memory)
  | Thinking => Flag(o.thinking)
  }

// A value of the other kind changes nothing (`parseValue` never makes one).
let apply = (o: t, ~setting: setting, ~value: value): t =>
  switch (setting, value) {
  | (AutoCollect, Flag(on)) => {...o, autoCollect: on}
  | (ColumnReorder, Flag(on)) => {...o, allowColumnReorder: on}
  | (FoundationReturn, Flag(on)) => {...o, allowFoundationReturn: on}
  | (EmptyColumnDeal, Flag(on)) => {...o, allowDealWithEmptyColumns: on}
  | (Memory, Tier(memory)) => {...o, memory}
  | (Thinking, Flag(on)) => {...o, thinking: on}
  | (AutoCollect | ColumnReorder | FoundationReturn | EmptyColumnDeal | Thinking, Tier(_))
  | (Memory, Flag(_)) => o
  }

let say = (value: value): string =>
  switch value {
  | Flag(on) => on ? "on" : "off"
  | Tier(Some(tier)) => Solver.tierName(tier)
  | Tier(None) => "auto"
  }

// Every setting and its value, as rows for a front end to render (`Command.renderHelp`
// aligns them, the same way it aligns the help listing).
let rows = (o: t): array<(string, string)> => all->Array.map(s => (name(s), say(read(o, s))))
