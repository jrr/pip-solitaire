// What the solver's unasked thinking is doing, where a tester can see it: a dot and a
// one-line caption in the bottom-left corner, toggled from the Debug screen ("Thinking
// indicator", persisted as `pip.thinkingDot`, default off), and a line in the debug log at
// every change.
//
// **It says what the search found**, which the game itself never does — whether a board is
// winnable is #410's question, and it stays behind this debug switch until that is
// answered. What each colour means:
//
//   amber, pulsing — thinking; the caption counts the board's allowance spent so far
//   green          — winnable: a line is known
//   red            — not winnable: every line was tried
//   purple         — the search filled its memory: no verdict
//   grey           — the allowance went by with no answer: no verdict
//   ring           — nothing yet, paused, or a board the solver can't read
//
// "known" in a green caption is a board answered by the re-root alone, with no position
// grown: a move along a line already found. A count is what the board had to search.

@val @scope("document") external body: WebDom.element = "body"

type animation
@send external animate: (WebDom.element, array<{..}>, {..}) => animation = "animate"
@send external cancel: animation => unit = "cancel"

let seconds = (ms: float) => Command.duration(ms)

// How much of the board's answer was searched for rather than looked up.
let searched = (~grew: int) => grew == 0 ? "known" : `+${Command.thousands(grew)} positions`

// The caption beside the dot: as short as will still say it.
let caption = (report: Thinker.report): string =>
  switch report {
  | Thinker.Thinking({ms}) => `thinking · ${seconds(ms)}`
  | Answered({verdict: Winnable, grew, ms, asked}) =>
    `winnable · ${searched(~grew)}${asked ? " · asked" : ` · ${seconds(ms)}`}`
  | Answered({verdict: Unwinnable}) => "no win · proved"
  | Answered({verdict: OutOfRoom}) => "memory full · no verdict"
  | Answered({verdict: Unreadable}) => "can't read this board"
  | Spent({ms}) => `gave up · ${seconds(ms)} · no verdict`
  | Stopped(_) => "paused"
  | Idle => "waiting"
  }

// The report as a sentence: the dot's tooltip and the debug log's line alike. `None`
// for `Idle`, which is a new board rather than anything worth a line.
let sentence = (report: Thinker.report): option<string> => {
  let verdict = (v: Thinker.verdict) =>
    switch v {
    | Winnable => "winnable — a line is known"
    | Unwinnable => "not winnable — every line was tried"
    | OutOfRoom => "no verdict — the search filled its memory"
    | Unreadable => "no verdict — not a board the solver reads"
    }
  switch report {
  | Thinker.Thinking({ms: 0.}) => Some("think ahead: thinking about this board")
  | Thinking({ms}) => Some(`think ahead: thinking about this board (${seconds(ms)} so far)`)
  | Answered({verdict: v, ms, positions, grew, asked}) =>
    Some(
      `think ahead: ${verdict(v)}${asked ? ", settled when Solve was asked" : ""} — ${grew == 0
          ? "answered by the re-root alone"
          : `${Command.thousands(grew)} positions grown for this board`}, ${seconds(
          ms,
        )} unasked, ${Command.thousands(positions)} in the search`,
    )
  | Spent({ms, positions, grew}) =>
    Some(
      `think ahead: no verdict — gave up after ${seconds(ms)} unasked, ${Command.thousands(
          grew,
        )} positions grown for this board, ${Command.thousands(positions)} in the search`,
    )
  | Stopped({why}) => Some(`think ahead: paused — ${why}`)
  | Idle => None
  }
}

let corner = "position:fixed;z-index:2147483646;pointer-events:none;display:flex;align-items:center;gap:6px;left:calc(env(safe-area-inset-left) + 8px);bottom:calc(env(safe-area-inset-bottom) + 8px);font:11px/1.4 system-ui,sans-serif;"

let dotBase = "width:10px;height:10px;border-radius:50%;box-sizing:border-box;flex:none;"

let label = "color:#e8e8e8;background:rgba(0,0,0,0.5);padding:1px 6px;border-radius:6px;white-space:nowrap;"

let look = (report: Thinker.report): string =>
  switch report {
  | Thinker.Thinking(_) => "background:#f5a623;"
  | Answered({verdict: Winnable}) => "background:#2ecc71;"
  | Answered({verdict: Unwinnable}) => "background:#e74c3c;"
  | Answered({verdict: OutOfRoom}) => "background:#9b59b6;"
  | Spent(_) => "background:#8a8a8a;"
  | Answered({verdict: Unreadable}) | Stopped(_) | Idle => "border:2px solid #8a8a8a;opacity:0.7;"
  }

type parts = {box: WebDom.element, dot: WebDom.element, text: WebDom.element}

let parts: ref<option<parts>> = ref(None)
let pulse: ref<option<animation>> = ref(None)
let shown = ref(false)
let last = ref(Thinker.Idle)

// `fresh` is a change of kind, which is the only time the pulse starts or stops: started
// again on every chunk it would stutter.
let draw = (~fresh: bool) =>
  parts.contents->Option.forEach(({box, dot, text}) => {
    box->WebDom.setAttribute("style", corner ++ (shown.contents ? "" : "display:none;"))
    box->WebDom.setAttribute(
      "title",
      sentence(last.contents)->Option.getOr("think ahead: nothing to think about yet"),
    )
    dot->WebDom.setAttribute("style", dotBase ++ look(last.contents))
    text->WebDom.setAttribute("style", label)
    text->WebDom.setTextContent(caption(last.contents))
    if fresh {
      pulse.contents->Option.forEach(cancel)
      pulse :=
        switch last.contents {
        | Thinker.Thinking(_) if shown.contents =>
          Some(
            dot->animate(
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
    }
  })

let setVisible = (visible: bool) => {
  shown := visible
  if visible && Option.isNone(parts.contents) {
    let box = WebDom.createElement("div")
    box->WebDom.setAttribute("id", "thinking-dot")
    let dot = WebDom.createElement("span")
    let text = WebDom.createElement("span")
    text->WebDom.setAttribute("class", "thinking-dot__caption")
    box->WebDom.appendChild(dot)->ignore
    box->WebDom.appendChild(text)->ignore
    body->WebDom.appendChild(box)->ignore
    parts := Some({box, dot, text})
  }
  draw(~fresh=true)
}

// Every report `Thinker` makes, whether or not the dot is showing. The caption follows
// each one, so the seconds tick on while a board is thought about; the log line is said
// only when the kind of report changes, since an unasked think goes out every quarter
// second.
let heard = (report: Thinker.report) => {
  let same = switch (last.contents, report) {
  | (Thinker.Thinking(_), Thinker.Thinking(_)) => true
  | _ => false
  }
  last := report
  if !same {
    sentence(report)->Option.forEach(DebugLog.message)
  }
  draw(~fresh=!same)
}
