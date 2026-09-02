// The `cascade` scene: the victory animation with no game and no board under it, and every
// number that decides how it feels on a slider — because whether a cascade looks right is
// not a question source can answer. What a control *does* is `CascadePlayer.retune`'s to
// decide, so this scene is a tuning instrument for the real animation rather than a
// rehearsal of it.
//
// Three controls are claims rather than feel, put where an eye can check them: the card
// size (the motion is in card-widths, so it should read the same at 40px and 140px),
// `whole pixels` (off is the only way to see what the snap buys), and the pose.
//
// `docs/cascade.md` has the model, the knobs and the URL parameters.

%%raw(`import "./CascadeScene.css"`)

// The scene mounts detached, so the overlay has no box until it is laid out; the first card
// size is chosen a frame later.
@val external requestAnimationFrame: (unit => unit) => int = "requestAnimationFrame"

@get external inputValue: WebDom.element => string = "value"

// Two extremes and the middle, in CSS pixels, smallest first. Not a slider: each change
// rebuilds 52 sprites.
let cardSizes = [40., 90., 140.]

// Below about this the arena is narrower than a card's flight and every trail runs into the
// far wall at once, which is a picture of a small stage rather than of the motion.
let minArenaCards = 8.

// The size to *open* on: the largest that leaves an arena worth watching, so a phone gets
// the 40px card without anyone touching a control. Only where the scene starts, and only at
// the first layout.
let fitCardSize = (~stageWidth) =>
  cardSizes
  ->Array.filter(size => stageWidth /. size >= minArenaCards)
  ->Array.at(-1)
  ->Option.getOr(cardSizes->Array.getUnsafe(0))

// How far a posed cascade is run, in cards rather than seconds: a still wants a certain
// amount on the stage, and counting in seconds empties it the moment the launch interval
// is dragged.
let poseCards = 16.
let poseSeconds = (knobs: Cascade.knobs) => poseCards *. knobs.launchMs /. 1000.

// Parsed from `?cascade=`; anything else leaves the scene's own default alone.
type mode =
  | Live
  | Pose

let modeFromString = value =>
  switch value {
  | "live" => Some(Live)
  | "pose" => Some(Pose)
  | _ => None
  }

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

    let stage = el("div", "cascade-stage")
    scene->WebDom.appendChild(stage)->ignore

    let overlay = Canvas.make()
    let overlayEl = Canvas.element(overlay)
    overlayEl->WebDom.setAttribute("class", "cascade-overlay")
    stage->WebDom.appendChild(overlayEl)->ignore

    // ---- The settings the controls edit ----
    // One ref per control, gathered into the player's `options` whenever one moves.
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

    // The only place the two modes differ, and what Replay means in either.
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
    // Named for the state it produces, where the source names the mechanism
    // (`Cascade.snapToDevice`): a chip that names a topic leaves a reader working out which
    // way "on" points.
    let snapButton = button(~parent=toolbar, ~className="cascade-toggle", ~label="whole pixels")

    // A knob: its name, a range input, and the value it is at — a slider alone says
    // "somewhere in the middle", and what you want to leave with is a number to put in the
    // source. `~wide` sizes a row for the longest string its readout can hold, so dragging
    // doesn't shove the knobs beside it along.
    //
    // Every readout repaints on every drag, not just the one being dragged: a ± reads out
    // the band it makes, which is a fact about its neighbour's value too.
    let redraws = []
    let knob = (~label, ~min, ~max, ~step, ~value, ~format, ~onChange, ~wide=false) => {
      let row = el("label", "cascade-knob")
      // On the row as well as the input, so a reader can name a knob's *readout*.
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

    // In m/s², with its share of a g beside it: the only number that says how far from real
    // a setting is, and 9.81 is on the slider rather than a rebuild away.
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

    // The band a ± makes, which is what you are actually choosing.
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
      // Short of 1, because a card that keeps everything never settles and never leaves.
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
    // Reaches 3 m/s — about a card flicked hard — because the range has to reach as far as
    // gravity's does: falling three times faster and thrown no harder is a cascade that
    // lands in a heap under the foundations.
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
    // What a deck costs at that interval, because at the top of this range it is most of
    // two minutes — worth having in front of you while you drag rather than after a run has
    // taken that long.
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
              // The arena three ways: what the browser laid out, what the physics sees, and
              // how big a table that is — which is what makes a gravity in m/s² mean
              // anything.
              `seed ${Int.toString(seed.contents)} · ` ++
              `${whole(cardWidth.contents)}px card @${hundredth(built.pixelRatio)}× · ` ++
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
      // Live, the trail keeps what it has, which is the comparison worth having: both kinds
      // of edge in one picture.
      CascadePlayer.retune(player, options())
    })

    // The overlay has no box until the scene is laid out — which is also the first moment a
    // card size can be chosen to fit it, so the run waits a frame rather than rasterizing 52
    // cards at a size the stage turns out to have no room for.
    refresh.contents()
    requestAnimationFrame(() => {
      let (stageWidth, _) = CascadePlayer.cssSize(player)
      cardWidth := fitCardSize(~stageWidth)
      CascadePlayer.retune(player, options())
      perform()
    })->ignore

    // The container's `clear` takes the stage and the canvas; the frame loop, the `window`
    // listener and an in-flight build are what `detach` is for.
    () => CascadePlayer.detach(player)
  },
}
