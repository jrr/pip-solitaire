// The `cascade` scene: the victory animation's motion, with no game and no board
// under it — the step that answers whether the thing in issue #224 actually looks
// good. That is a question about feel, so **every number that decides how it feels is
// on screen**: gravity, restitution, the horizontal speed range, the launch interval
// and how far apart the trail is stamped are sliders, not constants you rebuild to
// change. The physics they drive is `Cascade`, which knows nothing about canvases; this
// file is the surface it is drawn on and the controls that tune it.
//
// Three things here are not feel at all — they are the scene's own claims, put where an
// eye can check them:
//
// **The card size (40 / 90 / 140px)** is the claim that the motion is in card-widths.
// A cascade that reads the same at all three is one whose gravity means something on a
// phone; one tuned in pixels turns into a slow drift at 40 and a plummet at 140.
//
// **The device-pixel snap** can be turned off, which is the only way to see what it
// buys. Under the overlay's `ctx.scale(ratio, ratio)` an unsnapped blit is resampled on
// every frame at any fractional ratio — browser zoom reaches 1.5 and 3.75 — and what
// that looks like is not blur: a sub-pixel scale acts about the centre, so the card's
// two ends move in opposite directions and it reads as the ends disagreeing. Worth
// knowing by sight, because the natural diagnosis sends you into the rasterizer instead
// of the compositor. `Cascade.snapToDevice` is the fix and the arithmetic is pinned in
// `Cascade_test`; the toggle is how you see it.
//
// **Pose** (`?cascade=pose`) runs a fixed number of fixed-size steps and stops, so the
// picture is a pure function of the seed and the knobs — the same cascade, to the
// pixel, on every load. That is what the screenshot report shoots and what the browser
// suite compares two loads of; a live run has the display's own timing in it and no two
// are identical.
//
// **Nothing is ever cleared.** The trail *is* the effect (#224), and it is why this is
// a canvas at all: per-frame cost tracks the cards in flight, not the length of the
// trail behind them.
//
// Two mechanics are inherited from the `trail` scene rather than re-argued here: the
// backing store is `css × CardRaster.displayPixelRatio()` and the sprites are built at
// that same one number, and **assigning `canvas.width` wipes the surface** — so a
// resize *ends* the run rather than rescaling it mid-flight. A ratio change usually
// arrives as a resize (browser zoom), which is this scene's answer to #253's open
// question: sprites are rebuilt when the run ends and the ratio has moved, never under
// a card in flight.
//
// The launch interval here is deliberately **not** the C/P staggered-flight model in
// `docs/animation-timing.md` — see that page's note on the cascade for why the four
// board movers time themselves that way and this doesn't.

%%raw(`import "./CascadeScene.css"`)

// --- Bindings ----------------------------------------------------------------
// The frame clock, the element's own box, and the value of a range input. Everything
// else the scene touches is `WebDom`'s or `Canvas`'s.

// The timestamp form: a fixed-step loop needs the frame's own time, not a `unit`.
@val external requestAnimationFrame: (float => unit) => int = "requestAnimationFrame"
@val external cancelAnimationFrame: int => unit = "cancelAnimationFrame"

type rect = {left: float, top: float, width: float, height: float}
@send external boundingRect: WebDom.element => rect = "getBoundingClientRect"

@get external inputValue: WebDom.element => string = "value"

// --- The scene's own numbers --------------------------------------------------

// What a card is drawn at, in CSS pixels, smallest first. Three sizes rather than a
// slider because the question they answer is "does this read the same at a phone's card
// and a desktop's", which wants two extremes and the middle, and each change rebuilds
// 52 sprites.
let cardSizes = [40., 90., 140.]
let defaultCardSize = 90.

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

// The simulation's step, fixed, and small enough that a bounce is a bounce rather than
// a corner. Nothing about the *drawing* is keyed to it: how often a card is stamped is
// its own interval below.
let stepSeconds = 1. /. 120.
let stepMs = stepSeconds *. 1000.

// How much *simulated* time passes between one stamp of a card and the next — which is
// what the spacing of the trail is made of, since a faster card covers more ground
// between two stamps. Deliberately neither the step nor the frame: stamping every step
// paints a solid white sheet you cannot see a card in, and stamping every frame makes
// the picture denser on a 120Hz display than on a 60Hz one, which is the one thing a
// trail is not allowed to depend on.
let defaultStampMs = 32.

// The most arrears one frame may work off. A backgrounded tab comes back owing
// seconds; without this, working that off in one frame is thousands of steps and a
// locked-up page. The run loses the time instead, which is the right thing to lose.
let maxCatchUpMs = 100.

// How far a posed cascade is run. Far enough that a dozen cards have launched and the
// first trails have crossed the stage; short enough that the trails are still arcs
// rather than a stage painted white, which is what the picture is for.
let poseSeconds = 3.5

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

    // ---- State ----
    let knobs = ref(Cascade.defaults)
    let stampMs = ref(defaultStampMs)
    let cardWidth = ref(defaultCardSize)
    let seed = ref(initialSeed)
    let snap = ref(true)
    let paused = ref(false)
    let cache: ref<option<CardRaster.t>> = ref(None)
    let error: ref<option<string>> = ref(None)
    let run = ref(Cascade.make(~seed=initialSeed))
    // Nothing may be drawn before the scene has a box to draw in: it mounts detached,
    // so the first rect arrives a frame later (see the `requestAnimationFrame` at the
    // bottom).
    let laidOut = ref(false)
    // Set when a resize has ended a run, so the status says why the cascade stopped
    // rather than looking like one that finished.
    let interrupted = ref(false)
    let frame: ref<option<int>> = ref(None)
    let lastFrameAt: ref<option<float>> = ref(None)
    let carryMs = ref(0.)
    let sinceStamp = ref(0.)
    let framesSeen = ref(0)
    let fpsSince = ref(0.)
    let fps = ref(0.)
    // The build whose result is still wanted, numbered as `RasterScene` and
    // `TrailScene` number theirs: a card-size change or an unmount abandons whatever is
    // in flight. No request holds 0.
    let wanted = ref(0)

    let ratio = () => CardRaster.displayPixelRatio()

    let refresh = ref(() => ())

    // ---- The surface ----
    // The standard hi-dpi setup: the store in device pixels, the context scaled so
    // everything below draws in CSS pixels. Assigning the store clears it and resets
    // the transform, so the scale is reapplied here every time — and the clearing is
    // exactly why a resize ends a run.
    let sizeStore = () => {
      let box = boundingRect(overlayEl)
      let scale = ratio()
      overlay->Canvas.setPixelWidth(Math.round(box.width *. scale)->Float.toInt)
      overlay->Canvas.setPixelHeight(Math.round(box.height *. scale)->Float.toInt)
      Canvas.context2d(overlay)->Option.forEach(ctx => ctx->Canvas.scale(scale, scale))
    }

    let stageNow = () => {
      let box = boundingRect(overlayEl)
      Cascade.stageOf(~cssWidth=box.width, ~cssHeight=box.height, ~cardWidth=cardWidth.contents)
    }

    // One frame of the cascade, stamped over whatever is already there.
    //
    // The blit is 1:1 with the bitmap by construction: the sprite's device size back in
    // CSS pixels, rather than the size it was *asked* for, so a card size the ratio
    // doesn't divide evenly (90px at 1.25×) still copies pixel for pixel instead of
    // resampling by a hair. With the corner snapped to the device grid, that leaves the
    // whole card on whole device pixels.
    let drawRun = () =>
      switch (Canvas.context2d(overlay), cache.contents) {
      | (Some(ctx), Some(built)) =>
        let scale = ratio()
        let place = value => snap.contents ? Cascade.snapToDevice(value, ~ratio=scale) : value
        run.contents.flying->Array.forEach(flyer =>
          switch CardRaster.get(built, flyer.card) {
          | Some(sprite) =>
            CardRaster.blit(
              ctx,
              sprite,
              ~x=place(flyer.x *. cardWidth.contents),
              ~y=place(flyer.y *. cardWidth.contents),
              ~width=sprite.pxWidth /. scale,
              ~height=sprite.pxHeight /. scale,
            )
          | None => ()
          }
        )
      | _ => ()
      }

    // ---- The loop ----
    let stop = () => {
      frame.contents->Option.forEach(cancelAnimationFrame)
      frame := None
      lastFrameAt := None
    }

    // One step of the simulation, and a stamp if one has come due. The two are counted
    // separately so the trail's spacing is a distance a card has travelled rather than
    // a number of steps the machine happened to take.
    let advance = stage => {
      run := Cascade.step(run.contents, ~knobs=knobs.contents, ~stage, ~dt=stepSeconds)
      sinceStamp := sinceStamp.contents +. stepMs
      if sinceStamp.contents >= stampMs.contents {
        drawRun()
        sinceStamp := Math.max(sinceStamp.contents -. stampMs.contents, 0.)
      }
    }

    let rec tick = now => {
      let elapsed = switch lastFrameAt.contents {
      | Some(previous) => Math.min(now -. previous, maxCatchUpMs)
      | None => 0.
      }
      lastFrameAt := Some(now)
      carryMs := carryMs.contents +. elapsed

      let stage = stageNow()
      while carryMs.contents >= stepMs && !Cascade.isDone(run.contents) {
        advance(stage)
        carryMs := carryMs.contents -. stepMs
      }

      // The frame rate is worth showing: this scene's whole premise is that a canvas
      // and a sprite sheet hold 60fps where a screenful of live SVGs would not.
      framesSeen := framesSeen.contents + 1
      if now -. fpsSince.contents >= 500. {
        fps := Int.toFloat(framesSeen.contents) *. 1000. /. (now -. fpsSince.contents)
        framesSeen := 0
        fpsSince := now
        refresh.contents()
      }

      if Cascade.isDone(run.contents) {
        stop()
        refresh.contents()
      } else {
        frame := Some(requestAnimationFrame(tick))
      }
    }

    let start = () => {
      stop()
      carryMs := 0.
      framesSeen := 0
      fpsSince := 0.
      frame :=
        Some(
          requestAnimationFrame(now => {
            fpsSince := now
            tick(now)
          }),
        )
    }

    // The pose: a fixed count of fixed steps, drawn as it goes, then nothing. Same
    // `Cascade.step` the live loop calls — a pose that ran its own simplified physics
    // would be a picture of something the scene doesn't do.
    let pose = () => {
      let stage = stageNow()
      let steps = Math.round(poseSeconds /. stepSeconds)->Float.toInt
      for _ in 1 to steps {
        if !Cascade.isDone(run.contents) {
          advance(stage)
        }
      }
    }

    // Start the cascade over: wipe the surface (the only way there is), take the run
    // back to its first card, and either run it or pose it. A no-op until there are
    // sprites to draw and a box to draw them in — both arrive asynchronously, and
    // whichever lands second calls this.
    let restart = () => {
      if laidOut.contents && cache.contents->Option.isSome {
        stop()
        interrupted := false
        paused := false
        sizeStore()
        sinceStamp := 0.
        run := Cascade.make(~seed=seed.contents)
        switch mode {
        | Live => start()
        | Pose => pose()
        }
      }
      refresh.contents()
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
    let knob = (~label, ~min, ~max, ~step, ~value, ~format, ~onChange, ~wide=false) => {
      let row = el("label", "cascade-knob")
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
      input->WebDom.addEventListener("input", () =>
        Float.fromString(inputValue(input))->Option.forEach(next => {
          readout->WebDom.setTextContent(format(next))
          onChange(next)
          // A live run takes the new number on its next step — which is the point of
          // tuning by ear. A pose has already been drawn, so it has to be drawn again.
          switch mode {
          | Live => refresh.contents()
          | Pose => restart()
          }
        })
      )
    }

    knob(
      ~label="gravity",
      ~min=4.,
      ~max=80.,
      ~step=1.,
      ~value=knobs.contents.gravity,
      ~format=value => `${tenth(value)} cw/s²`,
      ~onChange=value => knobs := {...knobs.contents, gravity: value},
    )
    knob(
      ~label="restitution",
      ~min=0.,
      ~max=0.95,
      ~step=0.01,
      ~value=knobs.contents.restitution,
      ~format=hundredth,
      ~onChange=value => knobs := {...knobs.contents, restitution: value},
    )
    knob(
      ~label="slowest",
      ~min=0.,
      ~max=12.,
      ~step=0.1,
      ~value=knobs.contents.minSpeed,
      ~format=value => `${tenth(value)} cw/s`,
      // The range is a range: dragging one end past the other would otherwise ask for
      // a negative span, which `Cascade.spawn` floors at zero — a silent collapse to a
      // single speed rather than the two ends swapping visibly.
      ~onChange=value =>
        knobs := {
            ...knobs.contents,
            minSpeed: value,
            maxSpeed: Math.max(knobs.contents.maxSpeed, value),
          },
    )
    knob(
      ~label="fastest",
      ~min=0.,
      ~max=12.,
      ~step=0.1,
      ~value=knobs.contents.maxSpeed,
      ~format=value => `${tenth(value)} cw/s`,
      ~onChange=value =>
        knobs := {
            ...knobs.contents,
            maxSpeed: value,
            minSpeed: Math.min(knobs.contents.minSpeed, value),
          },
    )
    // The interval between two cards, and what a deck of them costs: one card per
    // interval is the whole cascade's length, and at the top of this range that is most
    // of two minutes — the number worth having in front of you *while* you drag rather
    // than after a run has taken that long. `cards × interval` rather than the
    // `cards - 1` the launches actually span, because the last card still has the stage
    // to cross after it leaves, which takes about the interval back.
    knob(
      ~label="launch",
      ~min=20.,
      ~max=2000.,
      ~step=10.,
      ~value=knobs.contents.launchMs,
      ~wide=true,
      ~format=value => {
        let cards = Array.length(run.contents.cards)
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
          pauseButton->WebDom.setTextContent(paused.contents ? "Resume" : "Pause")
          // Pausing a pose would pause nothing: there is no loop to stop.
          switch mode {
          | Live => pauseButton->WebDom.removeAttribute("disabled")
          | Pose => pauseButton->WebDom.setAttribute("disabled", "")
          }
          scene->WebDom.setAttribute("data-seed", Int.toString(seed.contents))
          scene->WebDom.setAttribute("data-card", Float.toString(cardWidth.contents))
          scene->WebDom.setAttribute("data-ratio", hundredth(ratio()))
          scene->WebDom.setAttribute("data-snap", snap.contents ? "on" : "off")

          let state = switch (error.contents, cache.contents) {
          | (Some(_), _) => None
          | (None, None) => None
          | (None, Some(_)) =>
            switch mode {
            | Pose => Some("posed")
            | Live =>
              if interrupted.contents {
                Some("ended")
              } else if Cascade.isDone(run.contents) {
                Some("settled")
              } else {
                Some("running")
              }
            }
          }
          switch state {
          | Some(value) => scene->WebDom.setAttribute("data-cascade", value)
          | None => scene->WebDom.removeAttribute("data-cascade")
          }

          status->WebDom.setTextContent(
            switch (error.contents, cache.contents) {
            | (Some(message), _) => `couldn't build sprites — ${message}`
            | (None, None) => "rasterizing 52 cards…"
            | (None, Some(built)) =>
              let box = boundingRect(overlayEl)
              let stage = stageNow()
              let counts =
                `${Int.toString(run.contents.launched)}/${Int.toString(
                    Array.length(run.contents.cards),
                  )} launched · ` ++
                `${Int.toString(Array.length(run.contents.flying))} in flight`
              let pace = switch mode {
              | Pose => `posed at ${tenth(poseSeconds)}s`
              | Live =>
                interrupted.contents
                  ? "resized — the run ended, the store was wiped"
                  : `${whole(fps.contents)} fps`
              }
              `seed ${Int.toString(seed.contents)} · ` ++
              `${whole(cardWidth.contents)}px card @${hundredth(built.pixelRatio)}× · ` ++
              `stage ${whole(box.width)}×${whole(box.height)} css = ${tenth(stage.width)}×${tenth(
                  stage.height,
                )} cards · ` ++
              `${counts} · ${pace}`
            },
          )
        }
      )

    // ---- Building the sprites ----
    // At the ratio the store is sized at, which is the one number both ends of a blit
    // have to agree on (see `CardRaster.displayPixelRatio`). A card-size change
    // rebuilds: a sprite scaled to a size it wasn't rasterized at is the resample this
    // whole approach exists to avoid.
    //
    // `~andRun` is what happens when it lands: a new card size wants the cascade that
    // was asked for, and a rebuild forced by a ratio change on an *ended* run must not
    // quietly start one — the run ended, and Replay is how it comes back.
    let build = (~andRun) => {
      wanted := wanted.contents + 1
      let mine = wanted.contents
      let stillWanted = () => mine == wanted.contents
      stop()
      cache := None
      error := None
      refresh.contents()
      CardRaster.build(~cssWidth=cardWidth.contents, ~pixelRatio=ratio(), Deck.allCards)
      ->Promise.thenResolve(built =>
        if stillWanted() {
          cache := Some(built)
          andRun ? restart() : refresh.contents()
        }
      )
      ->Promise.catch(exn => {
        if stillWanted() {
          error :=
            Some(
              switch exn->JsExn.fromException {
              | Some(e) => e->JsExn.message->Option.getOr("unknown error")
              | None => "unknown error"
              },
            )
          refresh.contents()
        }
        Promise.resolve()
      })
      ->ignore
    }

    // ---- Wiring ----
    replayButton->WebDom.addEventListener("click", () => restart())
    seedButton->WebDom.addEventListener("click", () => {
      seed := seed.contents + 1
      restart()
    })
    pauseButton->WebDom.addEventListener("click", () => {
      paused := !paused.contents
      if paused.contents {
        stop()
      } else {
        // `lastFrameAt` is dropped by `stop`, so the pause itself contributes no
        // elapsed time and the cascade resumes rather than jumping.
        start()
      }
      refresh.contents()
    })
    sizeButtons->Array.forEach(((size, node)) =>
      node->WebDom.addEventListener("click", () =>
        if size != cardWidth.contents {
          cardWidth := size
          build(~andRun=true)
        }
      )
    )
    snapButton->WebDom.addEventListener("click", () => {
      snap := !snap.contents
      // Live, the change shows on the next stamp and the trail keeps what it has —
      // which is the comparison worth having, both kinds of edge in one picture.
      switch mode {
      | Live => refresh.contents()
      | Pose => restart()
      }
    })

    // A resize is a wipe, unasked for: the store has to follow the element's CSS size,
    // and following it costs every pixel already drawn. So a live run *ends* here
    // rather than being rescaled mid-flight — and if the ratio moved with it (a browser
    // zoom is a resize), the sprites are rebuilt now, while nothing is in the air,
    // which is this scene's answer to #253: never under a card.
    //
    // A pose loses nothing by a resize, because it is a pure function of the box and
    // the seed: it is simply drawn again, at the size the box is now.
    let onResize = () => {
      let stale = cache.contents->Option.mapOr(false, built => built.pixelRatio != ratio())
      stop()
      switch mode {
      | Live => interrupted := true
      | Pose => ()
      }
      sizeStore()
      switch (stale, mode) {
      | (true, _) => build(~andRun=mode == Pose)
      | (false, Pose) => restart()
      | (false, Live) => refresh.contents()
      }
    }
    WebDom.addWindowListener("resize", onResize)

    // The scene mounts detached, so the overlay has no box until it is in the document
    // and laid out — which is also the first moment a card size can be chosen to fit
    // it, so the build waits for the frame rather than racing it and rasterizing 52
    // cards at a size the stage turns out to have no room for.
    refresh.contents()
    requestAnimationFrame(_ => {
      laidOut := true
      cardWidth := fitCardSize(~stageWidth=boundingRect(overlayEl).width)
      sizeStore()
      build(~andRun=true)
    })->ignore

    // ---- Teardown ----
    // The container's `clear` takes the stage and the canvas; the frame loop, the
    // `window` listener and an in-flight build are what it can't reach.
    () => {
      stop()
      wanted := 0
      WebDom.removeWindowListener("resize", onResize)
    }
  },
}
