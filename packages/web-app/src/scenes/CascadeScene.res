// The `cascade` scene: the victory animation's motion, with no game and no board under
// it — the step that answers whether the thing in issue #224 actually looks good. That is
// a question about feel, so **every number that decides how it feels is on screen**:
// gravity, the sideways throw, the launch interval and how far apart the trail is stamped
// are sliders, not constants you rebuild to change — and the two a card can differ in,
// its throw and its bounce, are a pair each: the value, and the ± the deck is scattered
// over (see `Cascade.knobs`).
//
// The motion is `Cascade` and the machinery that draws it is `CascadePlayer`. What is left
// here is the surface, the chrome, and one `options` handed over on every drag — the same
// value the victory overlay will pass once and never touch, which is what keeps this scene
// a tuning instrument for the real animation rather than a rehearsal of it.
//
// Three things here are not feel at all — they are the scene's own claims, put where an
// eye can check them:
//
// **The card size (40 / 90 / 140px)** is the claim that the motion is in card-widths. A
// cascade that reads the same at all three is one whose gravity means something on a
// phone; one tuned in pixels turns into a slow drift at 40 and a plummet at 140.
//
// **The device-pixel snap** can be turned off, which is the only way to see what it buys.
// What an unsnapped blit looks like is not blur: a sub-pixel scale acts about the centre,
// so the card's two ends move in opposite directions and it reads as the ends disagreeing.
// Worth knowing by sight, because the natural diagnosis sends you into the rasterizer
// instead of the compositor. `Cascade.snapToDevice` is the fix and the arithmetic is
// pinned in `Cascade_test`; the toggle is how you see it.
//
// **Pose** (`?cascade=pose`) is the player's still: the same cascade to the pixel on every
// load. That is what the screenshot report shoots and what the browser suite compares two
// loads of; a live run has the display's own timing in it and no two are identical.
//
// The launch interval here is deliberately **not** the C/P staggered-flight model in
// `docs/animation-timing.md` — see that page's note on the cascade for why the four board
// movers time themselves that way and this doesn't.

%%raw(`import "./CascadeScene.css"`)

// --- Bindings ----------------------------------------------------------------
// The scene mounts detached, so the overlay has no box until it is in the document and
// laid out; the first card size is chosen a frame later. The value of a range input is
// the only other thing here that isn't `WebDom`'s.
@val external requestAnimationFrame: (unit => unit) => int = "requestAnimationFrame"

@get external inputValue: WebDom.element => string = "value"

// --- The scene's own numbers --------------------------------------------------

// What a card is drawn at, in CSS pixels, smallest first. Three sizes rather than a
// slider because the question they answer is "does this read the same at a phone's card
// and a desktop's", which wants two extremes and the middle, and each change rebuilds
// 52 sprites.
let cardSizes = [40., 90., 140.]

// How much room a cascade wants, in card-widths. Below about this the arena is narrower
// than a card's flight and every trail runs into the far wall at once, which is a
// picture of a small stage rather than of the motion.
let minArenaCards = 8.

// The size to *open* on: the largest that leaves an arena worth watching, so a phone
// gets the 40px card and a desktop the 90px one without anyone touching a control. The
// buttons still say what they say — this only decides where the scene starts, and only
// once, at the first layout. (A board has this for free: its cards are already scaled
// to its stage, which is what the integration will hand over.)
let fitCardSize = (~stageWidth) =>
  cardSizes
  ->Array.filter(size => stageWidth /. size >= minArenaCards)
  ->Array.at(-1)
  ->Option.getOr(cardSizes->Array.getUnsafe(0))

// How far a posed cascade is run, **in cards rather than in seconds**. A still wants a
// stage with a certain amount on it — enough that the trails have crossed and started
// to overlap, short of the point where they paint it white — and that is a number of
// cards, not an elapsed time. Counting in seconds meant a still that emptied out the
// moment the launch interval was dragged, since the same 3.5s went from eighteen cards
// to five.
let poseCards = 16.
let poseSeconds = (knobs: Cascade.knobs) => poseCards *. knobs.launchMs /. 1000.

// --- The mode ----------------------------------------------------------------

// Live, or the frozen deterministic pose. Parsed from `?cascade=`; anything else reads
// as `None` and leaves the scene's own default (live) alone.
type mode =
  | Live
  | Pose

let modeFromString = value =>
  switch value {
  | "live" => Some(Live)
  | "pose" => Some(Pose)
  | _ => None
  }

// --- Formatting ---------------------------------------------------------------

let whole = value => Math.round(value)->Float.toInt->Int.toString
let tenth = value => (Math.round(value *. 10.) /. 10.)->Float.toString
let hundredth = value => (Math.round(value *. 100.) /. 100.)->Float.toString

let make = (~mode=Live, ~seed as initialSeed=1): Scene.t => {
  id: "cascade",
  label: "Cascade",
  kind: Demo,
  mount: container => {
    let el = (tag, className) => {
      let node = WebDom.createElement(tag)
      node->WebDom.setAttribute("class", className)
      node
    }

    // ---- DOM ----
    let scene = el("div", "cascade-scene")
    container->WebDom.appendChild(scene)->ignore

    let toolbar = el("div", "cascade-toolbar")
    scene->WebDom.appendChild(toolbar)->ignore

    let knobBar = el("div", "cascade-knobs")
    scene->WebDom.appendChild(knobBar)->ignore

    let status = el("p", "cascade-status")
    scene->WebDom.appendChild(status)->ignore

    // The stage is framed with an inset `box-shadow` rather than a border, and the
    // overlay reads its *own* rect — see CascadeScene.css for the trap that avoids.
    let stage = el("div", "cascade-stage")
    scene->WebDom.appendChild(stage)->ignore

    let overlay = Canvas.make()
    let overlayEl = Canvas.element(overlay)
    overlayEl->WebDom.setAttribute("class", "cascade-overlay")
    stage->WebDom.appendChild(overlayEl)->ignore

    // ---- The settings the controls edit ----
    // One ref per control, gathered into the player's `options` whenever one moves. The
    // controls own these and nothing else: what a new value *does* — take effect on the
    // next step, rebuild a sheet, redraw a still — is `CascadePlayer.retune`'s to decide,
    // so the answer is the same one the victory overlay would get.
    let knobs = ref(Cascade.defaults)
    let stampMs = ref(CascadePlayer.defaults.stampMs)
    let cardWidth = ref(CascadePlayer.defaults.cardWidth)
    let seed = ref(initialSeed)
    let snap = ref(true)

    let options = () => {
      ...CascadePlayer.defaults,
      seed: seed.contents,
      cardWidth: cardWidth.contents,
      knobs: knobs.contents,
      stampMs: stampMs.contents,
      snap: snap.contents,
    }

    let refresh = ref(() => ())

    let player = CascadePlayer.attach(~canvas=overlay, ~options=options(), ~onChange=_ =>
      refresh.contents()
    )

    // What the mode asks for, and the only place the two differ: a run, or the still.
    // Also what Replay means, in either.
    let perform = () =>
      switch mode {
      | Live => CascadePlayer.start(player)
      | Pose => CascadePlayer.pose(player, ~seconds=poseSeconds(knobs.contents))
      }

    // ---- Controls ----
    let button = (~parent, ~className, ~label) => {
      let node = el("button", className)
      node->WebDom.setAttribute("type", "button")
      node->WebDom.setTextContent(label)
      parent->WebDom.appendChild(node)->ignore
      node
    }

    let replayButton = button(~parent=toolbar, ~className="cascade-action", ~label="Replay")
    let seedButton = button(~parent=toolbar, ~className="cascade-action", ~label="Next seed")
    let pauseButton = button(~parent=toolbar, ~className="cascade-action", ~label="Pause")
    let sizeButtons =
      cardSizes->Array.map(size => (
        size,
        button(~parent=toolbar, ~className="cascade-toggle", ~label=`${Float.toString(size)}px`),
      ))
    let snapButton = button(~parent=toolbar, ~className="cascade-toggle", ~label="device snap")

    // A knob: its name, a range input, and the value it is at. The readout is beside
    // the slider because a slider alone says "somewhere in the middle", and what you
    // want to leave this scene with is a number to put in the source.
    //
    // `~wide` is for a readout that says more than its own number: the row is sized for
    // the longest string it can hold, so dragging one doesn't shove the knobs beside it
    // along the row.
    //
    // **Every readout is repainted on every drag**, not just the one being dragged: a ±
    // knob reads out the band it makes, which is a fact about its neighbour's value too,
    // and a row that only refreshes when *it* moves shows a band the run isn't using.
    let redraws = []
    let knob = (~label, ~min, ~max, ~step, ~value, ~format, ~onChange, ~wide=false) => {
      let row = el("label", "cascade-knob")
      // On the row as well as the input, so a reader — a test, or an eye down the
      // list — can name a knob's *readout* rather than counting rows to it.
      row->WebDom.setAttribute("data-knob", label)
      let name = el("span", "cascade-knob__label")
      name->WebDom.setTextContent(label)
      let input = WebDom.createElement("input")
      input->WebDom.setAttribute("type", "range")
      input->WebDom.setAttribute("min", Float.toString(min))
      input->WebDom.setAttribute("max", Float.toString(max))
      input->WebDom.setAttribute("step", Float.toString(step))
      input->WebDom.setAttribute("value", Float.toString(value))
      input->WebDom.setAttribute("data-knob", label)
      let readout = el(
        "span",
        wide ? "cascade-knob__value cascade-knob__value--wide" : "cascade-knob__value",
      )
      readout->WebDom.setTextContent(format(value))
      row->WebDom.appendChild(name)->ignore
      row->WebDom.appendChild(input)->ignore
      row->WebDom.appendChild(readout)->ignore
      knobBar->WebDom.appendChild(row)->ignore
      let paint = () =>
        Float.fromString(inputValue(input))->Option.forEach(current =>
          readout->WebDom.setTextContent(format(current))
        )
      redraws->Array.push(paint)
      input->WebDom.addEventListener("input", () =>
        Float.fromString(inputValue(input))->Option.forEach(next => {
          onChange(next)
          redraws->Array.forEach(repaint => repaint())
          CascadePlayer.retune(player, options())
        })
      )
    }

    // Gravity, in the unit gravity is quoted in. A card-width is 2.5 inches of card
    // (`Cascade.metresPerCardWidth`), so the physics' card-widths per second squared is
    // an acceleration like any other and there is no reason to make anyone read it in
    // card-widths. The share of a g rides along because it is the only number that says
    // *how far from real* a setting is at a glance, and this scene is where that is
    // decided: 9.81 is on the slider, a drag away, rather than a rebuild away.
    knob(
      ~label="gravity",
      ~min=0.2,
      ~max=12.,
      ~step=0.05,
      ~value=Cascade.toMetric(knobs.contents.gravity),
      ~wide=true,
      ~format=value => `${hundredth(value)} m/s² · ${hundredth(value /. Cascade.earthGravity)} g`,
      ~onChange=value => knobs := {...knobs.contents, gravity: Cascade.fromMetric(value)},
    )
    // A ± knob reads out the band it makes, not just the number it is: the span is what
    // you are actually choosing, and computing it in your head from the row above is the
    // arithmetic this scene exists to save you.
    let spread = (~centre, ~variance, ~unit) =>
      `± ${hundredth(variance)} · ${hundredth(centre -. variance)}–${hundredth(
          centre +. variance,
        )}${unit}`

    knob(
      ~label="bounciness",
      ~min=0.,
      ~max=0.95,
      ~step=0.01,
      ~value=knobs.contents.bounciness,
      // A bare fraction: the share of its falling speed a card keeps off the floor, so
      // 0 lands dead and 1 would come back up to where it fell from. Stops short of 1
      // because a card that keeps everything never settles and never leaves.
      ~format=hundredth,
      ~onChange=value => knobs := {...knobs.contents, bounciness: value},
    )
    knob(
      ~label="bouncinessVariance",
      ~min=0.,
      ~max=0.4,
      ~step=0.01,
      ~value=knobs.contents.bouncinessVariance,
      ~wide=true,
      ~format=variance => spread(~centre=knobs.contents.bounciness, ~variance, ~unit=""),
      ~onChange=value => knobs := {...knobs.contents, bouncinessVariance: value},
    )
    // The sideways throw, in metres per second for the same reason as gravity — and it
    // has to reach as far as gravity does. Falling three times faster and being thrown no
    // harder is a cascade that lands in a heap under the foundations, so a range that
    // reaches earth gravity has to reach a throw that crosses a table: 3 m/s is about a
    // card flicked hard, and roughly what 9.81 wants.
    knob(
      ~label="speed",
      ~min=0.,
      ~max=3.,
      ~step=0.05,
      ~value=Cascade.toMetric(knobs.contents.speed),
      ~format=value => `${hundredth(value)} m/s`,
      ~onChange=value => knobs := {...knobs.contents, speed: Cascade.fromMetric(value)},
    )
    knob(
      ~label="speedVariance",
      ~min=0.,
      ~max=1.,
      ~step=0.05,
      ~value=Cascade.toMetric(knobs.contents.speedVariance),
      ~wide=true,
      ~format=variance =>
        spread(~centre=Cascade.toMetric(knobs.contents.speed), ~variance, ~unit=" m/s"),
      ~onChange=value => knobs := {...knobs.contents, speedVariance: Cascade.fromMetric(value)},
    )
    // The interval between two cards, and what a deck of them costs: one card per
    // interval is the whole cascade's length, and at the top of this range that is most
    // of two minutes — the number worth having in front of you *while* you drag rather
    // than after a run has taken that long. `cards × interval` rather than the
    // `cards - 1` the launches actually span, because the last card still has the stage
    // to cross after it leaves, which takes about the interval back.
    knob(
      ~label="launchInterval",
      ~min=20.,
      ~max=2000.,
      ~step=10.,
      ~value=knobs.contents.launchMs,
      ~wide=true,
      ~format=value => {
        let cards = Array.length(CascadePlayer.status(player).run.cards)
        `${whole(value)} ms · ${Int.toString(cards)} cards in ${tenth(
            value *. Int.toFloat(cards) /. 1000.,
          )}s`
      },
      ~onChange=value => knobs := {...knobs.contents, launchMs: value},
    )
    knob(
      ~label="trail",
      ~min=8.,
      ~max=120.,
      ~step=4.,
      ~value=stampMs.contents,
      ~format=value => `${whole(value)} ms`,
      ~onChange=value => stampMs := value,
    )

    // ---- What the chrome says ----
    refresh :=
      (
        () => {
          let state = CascadePlayer.status(player)
          sizeButtons->Array.forEach(((size, node)) =>
            node->WebDom.setAttribute(
              "class",
              size == cardWidth.contents ? "cascade-toggle cascade-toggle--on" : "cascade-toggle",
            )
          )
          snapButton->WebDom.setAttribute(
            "class",
            snap.contents ? "cascade-toggle cascade-toggle--on" : "cascade-toggle",
          )
          pauseButton->WebDom.setTextContent(state.paused ? "Resume" : "Pause")
          // Pausing a pose would pause nothing: there is no loop to stop.
          switch mode {
          | Live => pauseButton->WebDom.removeAttribute("disabled")
          | Pose => pauseButton->WebDom.setAttribute("disabled", "")
          }
          scene->WebDom.setAttribute("data-seed", Int.toString(seed.contents))
          scene->WebDom.setAttribute("data-card", Float.toString(cardWidth.contents))
          scene->WebDom.setAttribute("data-ratio", hundredth(CardRaster.displayPixelRatio()))
          scene->WebDom.setAttribute("data-snap", snap.contents ? "on" : "off")

          // No `data-cascade` until there is a cascade — the browser suite and the
          // screenshot report both wait on this attribute appearing.
          switch state.phase {
          | Building
          | Failed(_) =>
            scene->WebDom.removeAttribute("data-cascade")
          | Running => scene->WebDom.setAttribute("data-cascade", "running")
          | Settled => scene->WebDom.setAttribute("data-cascade", "settled")
          | Interrupted => scene->WebDom.setAttribute("data-cascade", "ended")
          | Posed => scene->WebDom.setAttribute("data-cascade", "posed")
          }

          status->WebDom.setTextContent(
            switch (state.phase, state.sprites) {
            | (Failed(message), _) => `couldn't build sprites — ${message}`
            | (_, None) => "rasterizing 52 cards…"
            | (_, Some(built)) =>
              let counts =
                `${Int.toString(state.run.launched)}/${Int.toString(
                    Array.length(state.run.cards),
                  )} launched · ` ++
                `${Int.toString(Array.length(state.run.flying))} in flight`
              let pace = switch state.phase {
              | Posed => `posed at ${tenth(poseSeconds(knobs.contents))}s`
              | Interrupted => "resized — the run ended, the store was wiped"
              | Building
              | Failed(_)
              | Running
              | Settled =>
                `${whole(state.fps)} fps`
              }
              `seed ${Int.toString(seed.contents)} · ` ++
              `${whole(cardWidth.contents)}px card @${hundredth(built.pixelRatio)}× · ` ++
              // The arena three ways: what the browser laid out, what the physics sees,
              // and how big a table that is. The last one is what makes a gravity in
              // m/s² mean anything — 4 across a third of a metre is a different picture
              // from 4 across a room.
              `stage ${whole(state.cssWidth)}×${whole(state.cssHeight)} css = ${tenth(
                  state.stage.width,
                )}×${tenth(state.stage.height)} cards = ${hundredth(
                  Cascade.toMetric(state.stage.width),
                )}×${hundredth(Cascade.toMetric(state.stage.height))} m · ` ++
              `${counts} · ${pace}`
            },
          )
        }
      )

    // ---- Wiring ----
    replayButton->WebDom.addEventListener("click", () => perform())
    seedButton->WebDom.addEventListener("click", () => {
      seed := seed.contents + 1
      CascadePlayer.retune(player, options())
    })
    pauseButton->WebDom.addEventListener("click", () =>
      CascadePlayer.status(player).paused
        ? CascadePlayer.resume(player)
        : CascadePlayer.pause(player)
    )
    sizeButtons->Array.forEach(((size, node)) =>
      node->WebDom.addEventListener("click", () =>
        if size != cardWidth.contents {
          cardWidth := size
          CascadePlayer.retune(player, options())
        }
      )
    )
    snapButton->WebDom.addEventListener("click", () => {
      snap := !snap.contents
      // Live, the change shows on the next stamp and the trail keeps what it has —
      // which is the comparison worth having, both kinds of edge in one picture.
      CascadePlayer.retune(player, options())
    })

    // The overlay has no box until the scene is in the document and laid out — which is
    // also the first moment a card size can be chosen to fit it, so the run waits for the
    // frame rather than racing it and rasterizing 52 cards at a size the stage turns out
    // to have no room for.
    refresh.contents()
    requestAnimationFrame(() => {
      let (stageWidth, _) = CascadePlayer.cssSize(player)
      cardWidth := fitCardSize(~stageWidth)
      CascadePlayer.retune(player, options())
      perform()
    })->ignore

    // ---- Teardown ----
    // The container's `clear` takes the stage and the canvas; the frame loop, the
    // `window` listener and an in-flight build are what it can't reach, and what
    // `detach` is for.
    () => CascadePlayer.detach(player)
  },
}
