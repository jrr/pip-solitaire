// How much the solver may hold on this device (`Solver.tier`), chosen once per load —
// and corrected by the one memory-pressure signal a browser offers: finding, on load,
// that the last solve never finished. The ladder of choices and why it is this one is
// `docs/solver-next.md` § Memory; the three numbers are `Solver.capOf`.
//
// **The setting wins, and the reload lowers whatever was in force.** The tier is the
// memory setting where one is made (`Options.memory`), and otherwise the device's reading
// held under a stored ceiling. A solve that took the tab down lowers the ceiling — or, if
// the setting chose the tier, the setting — so the next load holds less, persistently.
// Making the setting clears the ceiling: it is the player's say over the guess.

// --- The reading -------------------------------------------------------------

// Where the order of tiers is needed: a ceiling is "at most".
let rank = (tier: Solver.tier): int =>
  switch tier {
  | Solver.Small => 0
  | Solver.Medium => 1
  | Solver.Large => 2
  }

let atMost = (tier: Solver.tier, ceiling: option<Solver.tier>): Solver.tier =>
  switch ceiling {
  | Some(ceiling) if rank(ceiling) < rank(tier) => ceiling
  | _ => tier
  }

// An Apple touch device: an iPhone, or an iPad — which reports itself as a Mac, and is
// told from one by having more than one touch point. Nothing else is read off the user
// agent.
let appleTouch = (~userAgent: string, ~maxTouchPoints: int): bool =>
  (userAgent->String.includes("Macintosh") || userAgent->String.includes("iPhone")) &&
    maxTouchPoints > 1

// `deviceMemory` where the browser gives one, in gigabytes. It rounds and stops at 8, so
// 8 means "8 or more" and is where the large tier starts. Without it, an Apple touch device
// is small — it is the platform that kills a tab without warning and exposes no figure —
// and anything else is medium.
let tierOf = (
  ~deviceMemory: option<float>,
  ~userAgent: string,
  ~maxTouchPoints: int,
): Solver.tier =>
  switch deviceMemory {
  | Some(gb) if gb >= 8. => Solver.Large
  | Some(gb) if gb >= 4. => Solver.Medium
  | Some(_) => Solver.Small
  | None => appleTouch(~userAgent, ~maxTouchPoints) ? Solver.Small : Solver.Medium
  }

// The navigator, guarded the way `LinkOut`'s is: a static render has none at all.
let deviceMemory: unit => Nullable.t<float> = %raw(`() =>
  typeof navigator !== "undefined" && typeof navigator.deviceMemory === "number"
    ? navigator.deviceMemory
    : undefined
`)
let userAgent: unit => string = %raw(`() =>
  typeof navigator !== "undefined" ? String(navigator.userAgent) : ""
`)
let maxTouchPoints: unit => int = %raw(`() =>
  typeof navigator !== "undefined" ? navigator.maxTouchPoints | 0 : 0
`)

let detected = (): Solver.tier =>
  tierOf(
    ~deviceMemory=deviceMemory()->Nullable.toOption,
    ~userAgent=userAgent(),
    ~maxTouchPoints=maxTouchPoints(),
  )

// --- What a crash leaves behind ------------------------------------------------

@val @scope("localStorage") external getItem: string => Nullable.t<string> = "getItem"
@val @scope("localStorage") external setItem: (string, string) => unit = "setItem"
@val @scope("localStorage") external removeItem: string => unit = "removeItem"

// Set while a solve runs, and the ceiling a solve that never finished left.
let solvingKey = "pip.solving"
let ceilingKey = "pip.memoryCeiling"

// Every touch guarded, as `Preferences`' are: storage can throw outright, and a device
// that can't keep the flag just never learns from a crash.
let read = key =>
  try getItem(key)->Nullable.toOption catch {
  | _ => None
  }
let write = (key, value) =>
  try setItem(key, value) catch {
  | _ => ()
  }
let remove = key =>
  try removeItem(key) catch {
  | _ => ()
  }

let ceiling = (): option<Solver.tier> => read(ceilingKey)->Option.flatMap(Solver.parseTier)
let clearCeiling = () => remove(ceilingKey)

// The tier in force: the setting's, or the device's reading under the ceiling.
let tier = (~memory: option<Solver.tier>): Solver.tier =>
  switch memory {
  | Some(chosen) => chosen
  | None => detected()->atMost(ceiling())
  }

// A solve starts and ends. **Ends includes being let go of**, and so does the page going
// away — a tab closed or reloaded mid-solve is not a tab the solve took down, and
// `pagehide` is the one event a page that is being put away rather than killed still gets.
let started = () => write(solvingKey, "true")
let ended = () => remove(solvingKey)

let installed = ref(false)
let install: (unit => unit) => unit = %raw(`(ended) => {
  if (typeof window !== "undefined") window.addEventListener("pagehide", () => ended())
}`)

// What the last load's solve left: `Some` when it never finished, which is read as the
// tab having been taken down by it. The tier then drops a step — the setting, where the
// setting chose it, and the stored ceiling otherwise — and the flag is cleared, so this
// answers once per crash. The pair is the tier the solve ran at and the one now in force;
// a small tier that crashed stays small, and says so.
type dropped = {from: Solver.tier, to: Solver.tier}

let recover = (~memory: option<Solver.tier>): (option<Solver.tier>, option<dropped>) => {
  if !installed.contents {
    installed := true
    install(ended)
  }
  switch read(solvingKey) {
  | Some("true") =>
    ended()
    let from = tier(~memory)
    let to = Solver.lower(from)
    switch memory {
    | Some(_) => (Some(to), Some({from, to}))
    | None =>
      write(ceilingKey, Solver.tierName(to))
      (memory, Some({from, to}))
    }
  | _ => (memory, None)
  }
}

// The once-per-crash sentence. It names the tier both ways round, and how to undo it.
let say = ({from, to}: dropped): string =>
  from == to
    ? `The last solve closed the page, most likely by running out of memory. The solver is already holding the least it can here (${Solver.tierName(
          to,
        )}).`
    : `The last solve closed the page, most likely by running out of memory, so the solver will hold less from now on: ${Solver.tierName(
          to,
        )} rather than ${Solver.tierName(
          from,
        )}. Type \`set memory\` in the console to choose for yourself.`
