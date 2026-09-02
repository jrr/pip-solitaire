// The cascade on a surface: everything between `Cascade`'s numbers and a canvas that has
// to draw them, owned once instead of twice.
//
// `Cascade` is the motion and knows nothing else — no canvas, no clock. What is left over
// is not the demo scene's either, even though the demo scene is the only caller today:
// sizing a backing store, rasterizing 52 cards at the ratio that store was sized at, a
// fixed-step loop off `requestAnimationFrame`, stamping on an interval of *simulated*
// time, and what a resize does to a run already in flight. The victory overlay (#228)
// needs every one of those, and a second copy of them is how the two drift — a store
// sized at one ratio here and a sheet built at another there draws perfectly good cards,
// softer by the ratio between them, with nothing saying so.
//
// The split is: **the caller owns the surface and the settings, the player owns the
// mechanics.** A caller makes the canvas and puts it wherever its own layout wants it,
// then hands over an `options` — so the demo scene can hand over a new one on every
// slider drag (`retune`) while the victory overlay passes one literal and never speaks
// again. Nothing here reads a knob out of the DOM or writes a status line; what it knows
// it says through `~onChange`, and the caller decides whether that is a status line, a
// `data-` attribute or nothing at all.
//
// **Nothing is ever cleared.** The trail *is* the effect (#224), and it is why this is a
// canvas at all: per-frame cost tracks the cards in flight, not the length of the trail
// behind them. The one thing that wipes it is assigning the backing store, which a resize
// forces — see `resized` for what that costs a run and why it ends one.

// --- Bindings ----------------------------------------------------------------
// The frame clock in its timestamp form (a fixed-step loop needs the frame's own time,
// not a `unit`), and the element's own box. The canvas half is `Canvas`'s.

@val external requestAnimationFrame: (float => unit) => int = "requestAnimationFrame"
@val external cancelAnimationFrame: int => unit = "cancelAnimationFrame"

type rect = {left: float, top: float, width: float, height: float}
@send external boundingRect: WebDom.element => rect = "getBoundingClientRect"

// --- The mechanics' own numbers ----------------------------------------------

// The simulation's step, fixed, and small enough that a bounce is a bounce rather than a
// corner. Nothing about the *drawing* is keyed to it: how often a card is stamped is
// `options.stampMs`, counted in the same simulated milliseconds.
let stepSeconds = 1. /. 120.
let stepMs = stepSeconds *. 1000.

// The most arrears one frame may work off. A backgrounded tab comes back owing seconds;
// without this, working that off in one frame is thousands of steps and a locked-up page.
// The run loses the time instead, which is the right thing to lose.
let maxCatchUpMs = 100.

// --- What a caller passes in --------------------------------------------------

// Where cards launch from. `Spread` is a count of seats laid evenly across the top of the
// stage — a demo's stand-in for a row of foundations, and what lines the round-robin in
// `Cascade.step` up with the round-robin in `Cascade.foundationOrder`. `At` is the
// caller's own seats, in card-widths: a board's foundations are wherever the board put
// them, and a cascade that starts anywhere else starts by teleporting the cards.
type launchpad =
  | Spread(int)
  | At(array<(float, float)>)

// Every setting the player has, in one value, so that adjusting one is the same operation
// as adjusting none of them (see `retune`).
type options = {
  // The launch order. `None` deals what a won game leaves (`Cascade.foundationOrder`); a
  // caller with real foundations to empty passes their cards in the order they come off.
  cards: option<array<Deck.card>>,
  seed: int,
  // What a card is drawn at, in CSS pixels — the one place pixels enter (see `Cascade`),
  // and the sprite sheet's size, so changing it is a rebuild.
  cardWidth: float,
  launchpad: launchpad,
  knobs: Cascade.knobs,
  // How much *simulated* time passes between one stamp of a card and the next, which is
  // what the spacing of the trail is made of, since a faster card covers more ground
  // between two stamps. Deliberately neither the step nor the frame: stamping every step
  // paints a solid white sheet you cannot see a card in, and stamping every frame makes
  // the picture denser on a 120Hz display than on a 60Hz one, which is the one thing a
  // trail is not allowed to depend on.
  stampMs: float,
  // Whether a blit is put on the device-pixel grid. On everywhere except where the point
  // is to see what it buys — `Cascade.snapToDevice` has the argument.
  snap: bool,
}

let defaults = {
  cards: None,
  seed: 1,
  cardWidth: 90.,
  launchpad: Spread(4),
  knobs: Cascade.defaults,
  stampMs: 16.,
  snap: true,
}

// --- What a caller gets back --------------------------------------------------

// What the player is doing, for a caller that has somewhere to say so. `Building` and
// `Failed` are the sprite sheet's: it decodes asynchronously, and there is nothing to draw
// until it lands.
type phase =
  | Building
  | Failed(string)
  | Running
  | Settled // the last card has left the stage
  | Interrupted // a resize wiped the surface and ended the run
  | Posed // a fixed-time picture, drawn once and left

type status = {
  phase: phase,
  paused: bool,
  run: Cascade.t,
  stage: Cascade.stage,
  cssWidth: float,
  cssHeight: float,
  sprites: option<CardRaster.t>,
  fps: float,
}

// --- The player ---------------------------------------------------------------

// What the player has been asked for, which outlives any one attempt at it: the sheet
// lands asynchronously and a resize can end a run, and both need to know whether what was
// wanted was a live run or a still.
type intent =
  | Idle
  | Live
  | Pose(float) // seconds of simulated time to run before stopping

type t = {
  canvas: Canvas.t,
  onChange: status => unit,
  mutable options: options,
  mutable intent: intent,
  mutable run: Cascade.t,
  mutable sprites: option<CardRaster.t>,
  mutable failure: option<string>,
  mutable paused: bool,
  mutable interrupted: bool,
  mutable frame: option<int>,
  mutable lastFrameAt: option<float>,
  mutable carryMs: float,
  mutable sinceStamp: float,
  mutable framesSeen: int,
  mutable fpsSince: float,
  mutable fps: float,
  // The build whose result is still wanted, numbered as `RasterScene` and `TrailScene`
  // number theirs: a card-size change or a `detach` abandons whatever is in flight. No
  // request holds 0.
  mutable wanted: int,
  // The card size and ratio a build in flight is for, and what to do when it lands. Held
  // rather than closed over so a second ask can recognise the build it is already waiting
  // on — see `launch`.
  mutable buildingFor: option<(float, float)>,
  mutable runWhenBuilt: bool,
  // Held so it can be taken off again: `WebDom.removeWindowListener` wants the same value
  // that was added, and the closure wants the player it is stored on.
  mutable resizeListener: unit => unit,
}

let ratio = () => CardRaster.displayPixelRatio()

let element = player => Canvas.element(player.canvas)

// The surface's CSS box, measured now. The one thing a caller asks the player for rather
// than the other way round: a card size chosen to fit the stage (the demo scene's three)
// has to be chosen before there is anything to run in it.
let cssSize = player => {
  let box = boundingRect(element(player))
  (box.width, box.height)
}

let stageOf = player => {
  let (cssWidth, cssHeight) = cssSize(player)
  let cardWidth = player.options.cardWidth
  switch player.options.launchpad {
  | Spread(count) => Cascade.stageOf(~cssWidth, ~cssHeight, ~cardWidth, ~seats=count)
  | At(seats) =>
    let (width, height) = Cascade.arenaOf(~cssWidth, ~cssHeight, ~cardWidth)
    let stage: Cascade.stage = {width, height, seats}
    stage
  }
}

let phaseOf = player =>
  switch (player.failure, player.sprites) {
  | (Some(message), _) => Failed(message)
  | (None, None) => Building
  | (None, Some(_)) =>
    switch player.intent {
    // A sheet but nothing asked for yet, which is the gap between `attach` and the
    // caller's first `start` — still getting ready, because that is what it is.
    | Idle => Building
    | Pose(_) => Posed
    | Live =>
      if player.interrupted {
        Interrupted
      } else if Cascade.isDone(player.run) {
        Settled
      } else {
        Running
      }
    }
  }

let status = player => {
  let (cssWidth, cssHeight) = cssSize(player)
  {
    phase: phaseOf(player),
    paused: player.paused,
    run: player.run,
    stage: stageOf(player),
    cssWidth,
    cssHeight,
    sprites: player.sprites,
    fps: player.fps,
  }
}

let notify = player => player.onChange(status(player))

// The standard hi-dpi setup: the store in device pixels, the context scaled so everything
// below draws in CSS pixels. Assigning the store clears it and resets the transform, so
// the scale is reapplied here every time — and the clearing is exactly why a resize ends
// a run.
let sizeStore = player => {
  let (cssWidth, cssHeight) = cssSize(player)
  let scale = ratio()
  player.canvas->Canvas.setPixelWidth(Math.round(cssWidth *. scale)->Float.toInt)
  player.canvas->Canvas.setPixelHeight(Math.round(cssHeight *. scale)->Float.toInt)
  Canvas.context2d(player.canvas)->Option.forEach(ctx => ctx->Canvas.scale(scale, scale))
}

// One stamp of the cards in flight, over whatever is already there.
//
// The blit is 1:1 with the bitmap by construction: the sprite's device size back in CSS
// pixels, rather than the size it was *asked* for, so a card size the ratio doesn't divide
// evenly (90px at 1.25×) still copies pixel for pixel instead of resampling by a hair.
// With the corner snapped to the device grid, that leaves the whole card on whole device
// pixels.
let draw = player =>
  switch (Canvas.context2d(player.canvas), player.sprites) {
  | (Some(ctx), Some(built)) =>
    let scale = ratio()
    let cardWidth = player.options.cardWidth
    let place = value => player.options.snap ? Cascade.snapToDevice(value, ~ratio=scale) : value
    player.run.flying->Array.forEach(flyer =>
      switch CardRaster.get(built, flyer.card) {
      | Some(sprite) =>
        CardRaster.blit(
          ctx,
          sprite,
          ~x=place(flyer.x *. cardWidth),
          ~y=place(flyer.y *. cardWidth),
          ~width=sprite.pxWidth /. scale,
          ~height=sprite.pxHeight /. scale,
        )
      | None => ()
      }
    )
  | _ => ()
  }

let stop = player => {
  player.frame->Option.forEach(cancelAnimationFrame)
  player.frame = None
  player.lastFrameAt = None
}

// One step of the simulation, and a stamp if one has come due. The two are counted
// separately so the trail's spacing is a distance a card has travelled rather than a
// number of steps the machine happened to take.
let advance = (player, ~stage) => {
  player.run = Cascade.step(player.run, ~knobs=player.options.knobs, ~stage, ~dt=stepSeconds)
  player.sinceStamp = player.sinceStamp +. stepMs
  if player.sinceStamp >= player.options.stampMs {
    draw(player)
    player.sinceStamp = Math.max(player.sinceStamp -. player.options.stampMs, 0.)
  }
}

let rec tick = (player, now) => {
  let elapsed = switch player.lastFrameAt {
  | Some(previous) => Math.min(now -. previous, maxCatchUpMs)
  | None => 0.
  }
  player.lastFrameAt = Some(now)
  player.carryMs = player.carryMs +. elapsed

  let stage = stageOf(player)
  while player.carryMs >= stepMs && !Cascade.isDone(player.run) {
    advance(player, ~stage)
    player.carryMs = player.carryMs -. stepMs
  }

  // The frame rate is worth handing back: the whole premise of drawing this on a canvas
  // is that a sprite sheet holds 60fps where a screenful of live SVGs would not.
  player.framesSeen = player.framesSeen + 1
  if now -. player.fpsSince >= 500. {
    player.fps = Int.toFloat(player.framesSeen) *. 1000. /. (now -. player.fpsSince)
    player.framesSeen = 0
    player.fpsSince = now
    notify(player)
  }

  if Cascade.isDone(player.run) {
    stop(player)
    notify(player)
  } else {
    player.frame = Some(requestAnimationFrame(now => tick(player, now)))
  }
}

let runLive = player => {
  stop(player)
  player.carryMs = 0.
  player.framesSeen = 0
  player.fpsSince = 0.
  player.frame = Some(
    requestAnimationFrame(now => {
      player.fpsSince = now
      tick(player, now)
    }),
  )
}

// A fixed count of fixed steps, drawn as it goes, and then nothing — so the picture is a
// pure function of the options, the seed and the box. The same `Cascade.step` the live
// loop calls: a still that ran its own simplified physics would be a picture of something
// the player doesn't do.
let runPose = (player, ~seconds) => {
  let stage = stageOf(player)
  let steps = Math.round(seconds /. stepSeconds)->Float.toInt
  for _ in 1 to steps {
    if !Cascade.isDone(player.run) {
      advance(player, ~stage)
    }
  }
}

// Start whatever was asked for over: wipe the surface (the only way there is), take the
// run back to its first card, and then run it or pose it.
let restart = player => {
  stop(player)
  player.interrupted = false
  player.paused = false
  sizeStore(player)
  player.sinceStamp = 0.
  player.run = Cascade.make(~seed=player.options.seed, ~cards=?player.options.cards)
  switch player.intent {
  | Idle => ()
  | Live => runLive(player)
  | Pose(seconds) => runPose(player, ~seconds)
  }
  notify(player)
}

// Whether the sheet in hand is the one a blit needs: built for this card size, at the
// ratio the store is sized at. Either of those disagreeing turns every blit into a
// resample (see `CardRaster.displayPixelRatio`), which draws perfectly good cards and says
// nothing about it.
let spritesStale = player =>
  switch player.sprites {
  | None => true
  | Some(built) => built.cssWidth != player.options.cardWidth || built.pixelRatio != ratio()
  }

// Rasterize the deck at the size and the ratio in force now. `~andRun` is what happens
// when it lands: a new card size wants the cascade that was asked for, and a rebuild
// forced by a ratio change on a run a resize already ended must not quietly start one.
let build = (player, ~andRun) => {
  player.wanted = player.wanted + 1
  let mine = player.wanted
  let stillWanted = () => mine == player.wanted
  let pixelRatio = ratio()
  let cssWidth = player.options.cardWidth
  stop(player)
  player.sprites = None
  player.failure = None
  player.buildingFor = Some((cssWidth, pixelRatio))
  player.runWhenBuilt = andRun
  notify(player)
  CardRaster.build(~cssWidth, ~pixelRatio, Deck.allCards)
  ->Promise.thenResolve(built =>
    if stillWanted() {
      player.sprites = Some(built)
      player.buildingFor = None
      player.runWhenBuilt ? restart(player) : notify(player)
    }
  )
  ->Promise.catch(exn => {
    if stillWanted() {
      player.buildingFor = None
      player.failure = Some(
        switch exn->JsExn.fromException {
        | Some(e) => e->JsExn.message->Option.getOr("unknown error")
        | None => "unknown error"
        },
      )
      notify(player)
    }
    Promise.resolve()
  })
  ->ignore
}

// Do what the intent says, rasterizing first if the sheet in hand can't serve it — unless
// a build for that very sheet is already in flight, which the ask can simply wait on. The
// deck takes tens of milliseconds to rasterize, and a control moved inside that window
// would otherwise pay for it twice and hand back the same 52 cards.
let launch = player =>
  switch (spritesStale(player), player.buildingFor) {
  | (false, _) => restart(player)
  | (true, Some(pending)) if pending == (player.options.cardWidth, ratio()) =>
    player.runWhenBuilt = true
  | (true, _) => build(player, ~andRun=true)
  }

// --- What a caller does with one ----------------------------------------------

// A live run, from the first card. Also the way back from a run that settled or was ended
// by a resize, which is why it is a restart rather than a resume.
let start = player => {
  player.intent = Live
  launch(player)
}

// The same cascade frozen at a fixed simulated time: a fixed count of fixed steps, no
// clock, so the picture is identical on every load. What a screenshot shoots, and what a
// browser test can compare two loads of.
let pose = (player, ~seconds) => {
  player.intent = Pose(seconds)
  launch(player)
}

let pause = player =>
  if !player.paused {
    player.paused = true
    stop(player)
    notify(player)
  }

let resume = player =>
  if player.paused {
    player.paused = false
    // `lastFrameAt` was dropped by `stop`, so the pause itself contributes no elapsed time
    // and the cascade carries on rather than jumping.
    switch player.intent {
    | Live => runLive(player)
    | Idle | Pose(_) => ()
    }
    notify(player)
  }

// New settings, mid-flight. **A live run takes them on its next step** — which is what
// makes a slider worth having, and why the settings are handed over rather than read back
// out of the caller: a caller with nothing to adjust never calls this and gets the very
// same code path.
//
// What can't be taken that way is a setting that isn't in the next step to begin with: a
// card size is a sprite sheet, and a seed, a deck or a launchpad is a different cascade,
// so those restart. A still is the other exception, and it is total — it has already been
// drawn, so whatever moved, it has to be drawn again.
let retune = (player, options) => {
  let previous = player.options
  player.options = options
  let recast =
    options.cardWidth != previous.cardWidth ||
    options.seed != previous.seed ||
    options.cards != previous.cards ||
    options.launchpad != previous.launchpad
  switch (player.intent, recast) {
  | (Idle, _) => notify(player)
  | (_, true) => launch(player)
  | (Pose(_), false) => launch(player)
  | (Live, false) => notify(player)
  }
}

// A resize is a wipe, unasked for: the store has to follow the element's CSS size, and
// following it costs every pixel already drawn. So a live run *ends* here rather than
// being rescaled mid-flight — and if the ratio moved with it (a browser zoom is a resize),
// the sheet is rebuilt now, while nothing is in the air, which is this module's answer to
// #253: never under a card.
//
// A still loses nothing by a resize, because it is a pure function of the box, the seed
// and the options: it is simply drawn again, at the size the box is now.
let resized = player => {
  // A sheet that hasn't landed yet is not stale, it is unfinished — cancelling that build
  // to start the same one again is the one way to make a resize cost the cards twice.
  let stale = player.sprites->Option.isSome && spritesStale(player)
  let andRun = switch player.intent {
  | Pose(_) => true
  | Idle | Live => false
  }
  stop(player)
  switch player.intent {
  | Live => player.interrupted = true
  | Idle | Pose(_) => ()
  }
  sizeStore(player)
  switch (stale, player.intent) {
  | (true, _) => build(player, ~andRun)
  | (false, Pose(_)) => restart(player)
  | (false, Idle | Live) => notify(player)
  }
}

// Take a surface. Nothing is drawn and nothing is rasterized until the caller asks for a
// run — which is deliberate: a scene mounts detached, and the card size worth building at
// is often a question about a box that doesn't exist yet.
let attach = (~canvas, ~options=defaults, ~onChange=(_: status) => ()) => {
  let player = {
    canvas,
    onChange,
    options,
    intent: Idle,
    run: Cascade.make(~seed=options.seed, ~cards=?options.cards),
    sprites: None,
    failure: None,
    paused: false,
    interrupted: false,
    frame: None,
    lastFrameAt: None,
    carryMs: 0.,
    sinceStamp: 0.,
    framesSeen: 0,
    fpsSince: 0.,
    fps: 0.,
    wanted: 0,
    buildingFor: None,
    runWhenBuilt: false,
    resizeListener: () => (),
  }
  let listener = () => resized(player)
  player.resizeListener = listener
  WebDom.addWindowListener("resize", listener)
  player
}

// Everything a caller's own teardown can't reach: the frame loop, the `window` listener,
// and a build that would otherwise land in a dismantled scene.
let detach = player => {
  stop(player)
  player.intent = Idle
  player.wanted = 0
  player.buildingFor = None
  WebDom.removeWindowListener("resize", player.resizeListener)
}
