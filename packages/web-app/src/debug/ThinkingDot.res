// What the solver's unasked thinking is doing, where a tester can see it: a dot in the
// bottom-left corner, toggled from the Debug screen ("Thinking indicator", persisted as
// `pip.thinkingDot`, default off), and a line in the debug log at every change.
//
// It shows *activity*, never a result: amber and pulsing while a think is out, green once
// the board is settled, grey once its allowance went by unanswered, an empty ring
// otherwise. Green says the search has said all it will — a line, a proof or a full
// budget alike — so even switched on it tells a player nothing about the board, which is
// the line `docs/solver-next.md` § Thinking between asks draws.

@val @scope("document") external body: WebDom.element = "body"

type animation
@send external animate: (WebDom.element, array<{..}>, {..}) => animation = "animate"
@send external cancel: animation => unit = "cancel"

// The report as a sentence: the dot's tooltip and the debug log's line alike. `None`
// for `Idle`, which is a new board rather than anything worth a line.
let sentence = (report: Thinker.report): option<string> =>
  switch report {
  | Thinker.Thinking => Some("think ahead: thinking about this board")
  | Answered({how, ms, positions, asked}) =>
    Some(
      `think ahead: ${how}${asked ? " when Solve was asked" : ""} — ${Command.duration(
          ms,
        )} unasked, ${Command.thousands(positions)} positions`,
    )
  | Spent({ms, positions}) =>
    Some(
      `think ahead: no answer in this board's ${Command.duration(
          ms,
        )} — stopped at ${Command.thousands(positions)} positions`,
    )
  | Stopped({why}) => Some(`think ahead: stopped — ${why}`)
  | Idle => None
  }

let base = "position:fixed;z-index:2147483646;pointer-events:none;width:10px;height:10px;border-radius:50%;box-sizing:border-box;left:calc(env(safe-area-inset-left) + 8px);bottom:calc(env(safe-area-inset-bottom) + 8px);"

let look = (report: Thinker.report): string =>
  switch report {
  | Thinker.Thinking => "background:#f5a623;"
  | Answered(_) => "background:#2ecc71;"
  | Spent(_) => "background:#8a8a8a;"
  | Stopped(_) | Idle => "border:2px solid #8a8a8a;opacity:0.7;"
  }

let dot: ref<option<WebDom.element>> = ref(None)
let pulse: ref<option<animation>> = ref(None)
let shown = ref(false)
let last = ref(Thinker.Idle)

let draw = () =>
  dot.contents->Option.forEach(el => {
    el->WebDom.setAttribute(
      "style",
      base ++ look(last.contents) ++ (shown.contents ? "" : "display:none;"),
    )
    el->WebDom.setAttribute(
      "title",
      sentence(last.contents)->Option.getOr("think ahead: nothing to think about yet"),
    )
    pulse.contents->Option.forEach(cancel)
    pulse :=
      switch last.contents {
      | Thinker.Thinking if shown.contents =>
        Some(
          el->animate(
            [{"opacity": 1.}, {"opacity": 0.35}],
            {
              "duration": 700,
              "iterations": Float.Constants.positiveInfinity,
              "direction": "alternate",
            },
          ),
        )
      | _ => None
      }
  })

let setVisible = (visible: bool) => {
  shown := visible
  if visible && Option.isNone(dot.contents) {
    let el = WebDom.createElement("div")
    el->WebDom.setAttribute("id", "thinking-dot")
    body->WebDom.appendChild(el)->ignore
    dot := Some(el)
  }
  draw()
}

// Every report `Thinker` makes, whether or not the dot is showing: the log line is said
// for a change of state only, since an unasked think goes out every quarter second.
let heard = (report: Thinker.report) => {
  let changed = switch (last.contents, report) {
  | (Thinker.Thinking, Thinker.Thinking) => false
  | _ => true
  }
  last := report
  if changed {
    sentence(report)->Option.forEach(DebugLog.message)
    draw()
  }
}
