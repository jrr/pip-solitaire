// The cascade on a surface: the backing store, the sprite sheet, the frame loop, and what
// a resize does to a run in flight. `Cascade` is the motion and knows nothing else; this is
// everything between those numbers and a canvas, owned once rather than once per caller —
// the board's victory needs all of it and the demo scene is only one of the two.
//
// The caller owns the surface and the settings, the player owns the mechanics: hand over a
// canvas and an `options`, hear back through `~onChange` (where the run is up to) and
// `~onLaunch` (a card, as it leaves). Nothing here reads a control or writes a status line.
//
// `docs/cascade.md` has the model, the ratio rule and the resize policy.

@val external requestAnimationFrame: (float => unit) => int = "requestAnimationFrame"
@val external cancelAnimationFrame: int => unit = "cancelAnimationFrame"

type rect = {left: float, top: float, width: float, height: float}
@send external boundingRect: WebDom.element => rect = "getBoundingClientRect"

// Small enough that a bounce is a bounce rather than a corner. Nothing about the drawing is
// keyed to it — that is `options.stampMs`, in the same simulated milliseconds.
let stepSeconds = 1. /. 120.
let stepMs = stepSeconds *. 1000.

// The most arrears one frame may work off: a backgrounded tab comes back owing seconds, and
// spending them is thousands of steps and a locked-up page. The run loses the time instead.
let maxCatchUpMs = 100.

// Where cards launch from. `Spread` is the demo's row of seats; `At` is a caller's own, in
// card-widths — a board's foundations are wherever the board put them, and a cascade that
// starts anywhere else starts by teleporting the cards.
type launchpad =
  | Spread(int)
  | At(array<(float, float)>)

// Every setting in one value, so adjusting one is the same operation as adjusting none
// (see `retune`).
type options = {
  // `None` deals what a won game leaves; a caller with real foundations to empty passes
  // their cards in the order they come off.
  cards: option<array<Deck.card>>,
  seed: int,
  // In CSS pixels — the sprite sheet's size, so changing it is a rebuild.
  cardWidth: float,
  launchpad: launchpad,
  knobs: Cascade.knobs,
  // Simulated time between one stamp of a card and the next, which is what the spacing of
  // the trail is made of. Neither the step nor the frame, deliberately: see the doc.
  stampMs: float,
  // Whether a blit is put on the device-pixel grid. On everywhere except where the point is
  // to see what it buys.
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

// `Building` and `Failed` are the sprite sheet's: it decodes asynchronously, and there is
// nothing to draw until it lands.
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

// What the player has been asked for, which outlives any one attempt at it: the sheet lands
// asynchronously and a resize can end a run, and both need to know which was wanted.
type intent =
  | Idle
  | Live
  | Pose(float) // seconds of simulated time to run before stopping

type t = {
  canvas: Canvas.t,
  onChange: status => unit,
  // Called once per card as the run puts it in the air, in launch order. Separate from
  // `onChange` because it has to be exact: `onChange` is a half-second heartbeat, and a
  // caller with real cards under the sprites — a board emptying its foundations — would
  // leave each one sitting on the table for up to half a second after its copy had left
  // it. The player still knows nothing about what a caller does with the card.
  onLaunch: Deck.card => unit,
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
  // number theirs. No request holds 0, so `detach` abandons everything in flight.
  mutable wanted: int,
  // What a build in flight is for, so a second ask can recognise the one it is already
  // waiting on (see `launch`).
  mutable buildingFor: option<(float, float)>,
  mutable runWhenBuilt: bool,
  // Held so it can be taken off again: removal wants the same value that was added.
  mutable resizeListener: unit => unit,
}

let ratio = () => CardRaster.displayPixelRatio()

let element = player => Canvas.element(player.canvas)

// The one thing a caller asks the player for rather than the other way round: a card size
// chosen to fit the stage has to be chosen before there is anything to run in it.
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
    // A sheet but nothing asked for yet: the gap between `attach` and the first `start`.
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

// The store in device pixels, the context scaled so everything else draws in CSS pixels.
// Assigning the store clears it and resets the transform, so the scale is reapplied here —
// and that clearing is why a resize ends a run.
let sizeStore = player => {
  let (cssWidth, cssHeight) = cssSize(player)
  let scale = ratio()
  player.canvas->Canvas.setPixelWidth(Math.round(cssWidth *. scale)->Float.toInt)
  player.canvas->Canvas.setPixelHeight(Math.round(cssHeight *. scale)->Float.toInt)
  Canvas.context2d(player.canvas)->Option.forEach(ctx => ctx->Canvas.scale(scale, scale))
}

// One stamp of the cards in flight, over whatever is already there — nothing is ever
// cleared, because the trail is the effect.
//
// The blit is 1:1 with the bitmap by construction: the sprite's device size back in CSS
// pixels, rather than the size it was asked for, so a card size the ratio doesn't divide
// evenly still copies pixel for pixel.
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

// Step and stamp are counted separately, so the trail's spacing is a distance a card has
// travelled rather than a number of steps the machine happened to take.
let advance = (player, ~stage) => {
  let launchedBefore = player.run.launched
  player.run = Cascade.step(player.run, ~knobs=player.options.knobs, ~stage, ~dt=stepSeconds)
  // A step can launch more than one card — a launch interval shorter than the step, or a
  // frame that owed several steps — so this is a range rather than a comparison.
  for i in launchedBefore to player.run.launched - 1 {
    player.run.cards->Array.get(i)->Option.forEach(player.onLaunch)
  }
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

  // Worth handing back: the whole premise of a canvas and a sprite sheet is that they hold
  // 60fps where a screenful of live SVGs would not.
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

// A fixed count of fixed steps and then nothing, so the picture is a pure function of the
// options, the seed and the box. The same `Cascade.step` the live loop calls: a still that
// ran its own simplified physics would be a picture of something the player doesn't do.
let runPose = (player, ~seconds) => {
  let stage = stageOf(player)
  let steps = Math.round(seconds /. stepSeconds)->Float.toInt
  for _ in 1 to steps {
    if !Cascade.isDone(player.run) {
      advance(player, ~stage)
    }
  }
}

// Start what was asked for over: wipe the surface (the only way there is), take the run
// back to its first card, then run or pose it.
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

// Whether the sheet in hand is the one a blit needs: this card size, at the ratio the store
// is sized at. Either disagreeing turns every blit into a resample and says nothing.
let spritesStale = player =>
  switch player.sprites {
  | None => true
  | Some(built) => built.cssWidth != player.options.cardWidth || built.pixelRatio != ratio()
  }

// Rasterize the deck at the size and ratio in force now. `~andRun` is what happens when it
// lands: a new card size wants the cascade that was asked for, and a rebuild forced by a
// ratio change on a run a resize already ended must not quietly start one.
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

// Do what the intent says, rasterizing first if the sheet can't serve it — unless a build
// for that very sheet is already in flight, which the ask can wait on rather than paying
// tens of milliseconds twice for the same 52 cards.
let launch = player =>
  switch (spritesStale(player), player.buildingFor) {
  | (false, _) => restart(player)
  | (true, Some(pending)) if pending == (player.options.cardWidth, ratio()) =>
    player.runWhenBuilt = true
  | (true, _) => build(player, ~andRun=true)
  }

// A live run, from the first card. Also the way back from a run that settled or was ended
// by a resize, which is why it is a restart rather than a resume.
let start = player => {
  player.intent = Live
  launch(player)
}

// The same cascade frozen at a fixed simulated time — no clock, so the picture is identical
// on every load. What a screenshot shoots and what a browser test compares two loads of.
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
    // `lastFrameAt` was dropped by `stop`, so the pause contributes no elapsed time and the
    // cascade carries on rather than jumping.
    switch player.intent {
    | Live => runLive(player)
    | Idle | Pose(_) => ()
    }
    notify(player)
  }

// New settings, mid-flight: a live run takes them on its next step, which is what makes a
// slider worth having. What can't be taken that way is a setting that isn't in the next
// step to begin with — a card size is a sheet, and a seed, a deck or a launchpad is a
// different cascade, so those restart. A still restarts whatever moved: it has already
// been drawn.
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

// A resize is a wipe, unasked for, so a live run *ends* here rather than being rescaled
// mid-flight — and if the ratio moved with it (a browser zoom is a resize), the sheet is
// rebuilt now, while nothing is in the air. A still is a pure function of the box, so it is
// simply drawn again.
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

// Nothing is drawn or rasterized until a caller asks for a run: a scene mounts detached,
// and the card size worth building at is often a question about a box that doesn't exist
// yet.
let attach = (
  ~canvas,
  ~options=defaults,
  ~onChange=(_: status) => (),
  ~onLaunch=(_: Deck.card) => (),
) => {
  let player = {
    canvas,
    onChange,
    onLaunch,
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
