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

// **How long a stamp stays on the canvas** — one length of time, said in whichever unit
// the person deciding it is actually thinking in. They are not four settings: each says
// the same kind of thing and converts to the same seconds (`persistenceSeconds`) through
// the launch schedule, from which a fade rate is derived at the moment of use.
//
// Which unit you want depends on what you want held constant when the run is not the one
// you tuned on — a short deck's victory, or the demo's launch-interval slider:
//
//   `Cards`     the picture. Nine cards of trail is nine streaks on the stage whether
//               the deck is 52 or 16, because it is the launch *rate* that decides how
//               much is in the air at once. The default, for that reason.
//   `Fraction`  the story. A third of the run is a third of it on any deck, so a board
//               with a quarter of the cards still empties the same way.
//   `Seconds`   the clock and nothing else — how long, in a unit no other knob can move
//               underneath you.
//   `Forever`   the Windows 3.1 original: nothing fades, and a long run ends a white
//               sheet with a few cards somewhere in it. Kept because it is what the
//               fade is *against*, and one tap away when you want to see that.
type persistence =
  | Forever
  | Seconds(float)
  | Cards(float)
  | Fraction(float)

// **What the fade waits for before it is taken.** It is never taken continuously — the
// surface is filled or it isn't, so the trail sinks in steps whatever this says. All
// that is chosen here is when a step falls due.
type step =
  // A share worth having. A fade spent in shares much below a tenth is mostly taken back
  // by the rounding in `Canvas.dim`, so what is owed is saved up until it is worth this
  // much — which also decides how often the surface is filled, and so what the fade costs
  // to run. `docs/cascade.md` has both halves.
  | Coin(float)
  // The seats coming round: every card thrown since the last step is left at the strength
  // it went on at, and the whole surface drops a step as the next round starts. What
  // stands out is then the round just thrown rather than the stamp just laid — on a board,
  // where the seats are foundations emptied rank by rank, that is a rank of cards at a
  // time. The steps are as long as a round, which is the point and also the thing to
  // watch: two rounds of persistence is a run that half-empties in front of you.
  | Layer

// How the trail is dimmed: how long a stamp lasts, and what takes it off. Not larger and
// smaller versions of each other — the first is how long the trail is, the second is what
// the fade costs and how steppy it looks getting there.
type fade = {
  persistence: persistence,
  step: step,
}

// The coin the fade was tuned at, named because two callers start their own control at
// it and neither should have to take a variant apart to find it.
let defaultCoin = 0.1

// Nine cards of trail, taken off in tenths: 6.8 seconds at the default launch interval,
// which is where the scene's sliders were dragged to.
let defaultFade = {persistence: Cards(9.), step: Coin(defaultCoin)}

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
  // Whether the trail is kept off the seats that still have cards to launch. A question
  // about the caller's *surface*, not about taste: a board's seats are piles that have
  // not left yet — real cards, under the canvas — and a fading trail silting up over them
  // reads as dirt on the pile rather than as a card that flew past. The demo's seats have
  // nothing under them, so clearing there would cut card-shaped holes in its own trail.
  // Off unless a caller says there is something to keep clear. See `clearSeats`.
  keepSeatsClear: bool,
  // How much notice a card gets before it leaves, in simulated milliseconds. A caller
  // with a real pile puts the card out then (`~onReady`) and takes it away as it goes
  // (`~onLaunch`), so a seat holds a card just long enough to be seen thrown rather than
  // holding the whole pile for the run to smear a trail over. See `armedBy`.
  readyMs: float,
  // How the trail behind the cards is dimmed (see `fade` above). Two numbers rather than
  // a knob and a constant because the debug menu tunes both on a live board.
  fade: fade,
}

let defaults = {
  cards: None,
  seed: 1,
  cardWidth: 90.,
  launchpad: Spread(4),
  knobs: Cascade.defaults,
  stampMs: 16.,
  snap: true,
  keepSeatsClear: false,
  readyMs: 250.,
  fade: defaultFade,
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
  // …and the other half of the same idea: a card is *put out* on its seat this long
  // before it leaves (`options.readyMs`), which is a caller's cue to show it. Every card
  // is announced this way before it launches, the first one per seat included.
  onReady: Deck.card => unit,
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
  // How many cards have been put out on their seats — see `armedBy`. Ahead of
  // `run.launched` by whatever is waiting to go, and what `clearSeats` reads to know
  // which seats have a card sitting on them.
  mutable armed: int,
  // Simulated time the fade has not been paid for yet — see `dim`.
  mutable fadeOwedMs: float,
  // Which round of the seats the fade was last taken in, so `Layer` can tell that one has
  // gone by. Kept up to date whatever the step is, so switching to `Layer` mid-run starts
  // from where the fade actually is rather than from the round the run began in.
  mutable paidLayer: int,
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

// What a stretch of simulated time takes off the surface, from the rate a second of it is
// asked for at. A share of what is left, rather than a fixed amount, is the only fade that
// treats every moment alike: whatever is on the surface loses `rate` of itself per
// simulated second, however many stamps that second is made of, so the trail knob changes
// the spacing and not the length.
let fadeShare = (~rate, ~ms) =>
  rate <= 0. ? 0. : 1. -. Math.pow(1. -. Math.min(rate, 1.), ~exp=ms /. 1000.)

// How long the deck takes to leave, in seconds: one card per `launchMs`. The *schedule*
// rather than the physics — the last card is still falling for a second or two after
// this — which is what makes it a number that can be had before the run starts.
let runSeconds = (~launchMs, ~cards) => launchMs *. Int.toFloat(cards) /. 1000.

// The one conversion: whichever unit a persistence is said in, as the seconds it comes
// to. `Forever` is infinity rather than a case every caller has to answer, which is what
// lets the rate below fall out of the same arithmetic as the rest.
let persistenceSeconds = (persistence, ~launchMs, ~cards) =>
  switch persistence {
  | Forever => infinity
  | Seconds(seconds) => Math.max(seconds, 0.)
  | Cards(count) => Math.max(count, 0.) *. launchMs /. 1000.
  | Fraction(share) => Math.max(share, 0.) *. runSeconds(~launchMs, ~cards)
  }

// The same length of time, said in the unit of `like` — what a unit picker does. Nine
// cards and 6.8 seconds are one setting, so changing which unit it is written in must
// not change the animation; the constructor handed in carries no number of its own, only
// the choice of unit.
//
// `Forever` has no length to convert, so leaving it lands on the default in the chosen
// unit rather than on an infinity no slider could show.
let sameIn = (persistence, ~like, ~launchMs, ~cards) => {
  let seconds = persistenceSeconds(persistence, ~launchMs, ~cards)
  let settled = Float.isFinite(seconds)
    ? seconds
    : persistenceSeconds(defaultFade.persistence, ~launchMs, ~cards)
  switch like {
  | Forever => Forever
  | Seconds(_) => Seconds(settled)
  | Cards(_) => Cards(launchMs <= 0. ? 0. : settled *. 1000. /. launchMs)
  | Fraction(_) =>
    let whole = runSeconds(~launchMs, ~cards)
    Fraction(whole <= 0. ? 0. : settled /. whole)
  }
}

// **What "gone" means.** An exponential fade never reaches nothing, so a persistence has
// to be measured to a line, and this is it: a stamp is spent once it is down to a
// hundredth of the strength it went on at. Below that it is a smudge the table's own
// colour swallows — and in practice `Canvas.dim`'s floor has taken it before then.
//
// A definition rather than a tuned number: move it and every persistence means a
// different length, which is the one way to make all four units wrong at once.
let spentAt = 0.01

// The rate a persistence comes to — the share of itself the surface gives up per second
// of simulated time, which is what `fadeShare` asks for. Zero seconds takes everything at
// the first stamp (no trail at all), and `Forever` falls out as a rate of zero with no
// case of its own: `spentAt` to the power of nothing is one.
let fadeRate = (~seconds) => seconds <= 0. ? 1. : 1. -. Math.pow(spentAt, ~exp=1. /. seconds)

// How often the fade comes due, in seconds — the stretch whose share is one coin, and
// never oftener than a stamp, which is the only moment it is ever paid at. One
// full-surface fill this often is the whole of what a fade costs to run, so this is the
// number to read a coin by.
let fadePayment = (~rate, ~coin, ~stampMs) =>
  if rate <= 0. {
    infinity
  } else {
    let owed =
      coin <= 0. ? 0. : Math.log(1. -. Math.min(coin, 1.)) /. Math.log(1. -. Math.min(rate, 1.))
    Math.max(owed, stampMs /. 1000.)
  }

// How many cards are out on their seats: one per seat to begin with — a board's piles
// show their tops — and after that, every card whose launch is within `readyMs`. It only
// ever grows, which is what lets a caller be told about each card exactly once.
let armedBy = (~launched, ~cards, ~seats, ~sinceLaunchMs, ~launchMs, ~readyMs) => {
  let ahead = launchMs <= 0. ? 0 : Float.toInt((sinceLaunchMs +. readyMs) /. launchMs)
  Math.Int.min(cards, Math.Int.max(launched + ahead, Math.Int.min(seats, cards)))
}

// Whether a card is sitting on seat `seat` right now. `Cascade` deals its seats
// round-robin — card `i` leaves seat `i mod seats` — so the first index at or after
// `launched` that lands on this seat is out if it has been armed.
let seatIsOccupied = (~launched, ~armed, ~seats, ~seat) =>
  seats > 0 && launched + mod(mod(seat - launched, seats) + seats, seats) < armed

// Which time round the seats a run is in. `Cascade` deals them in order, so every `seats`
// launches is one round — and on a board, whose piles are taken a slot at a time, one
// round is one rank: all four Kings, then all four Queens.
let layerOf = (~launched, ~seats) => seats <= 0 ? 0 : launched / seats

// Wipe the trail off the seats with a card sitting on them. It is taken after the fade and
// before the stamp, so the card going down *this* instant is drawn whole over the seat it
// is leaving, and only the history behind it is cleared.
//
// Erasing rather than re-drawing the pile: what sits under a board's seat is the real
// resting card, so clearing shows it with the drop shadow and the hand-placed angle
// (`docs/card-tilt.md`) that a square unrotated sprite would have to imitate — and
// imitate a couple of degrees out. The cost is a rect per loaded seat per stamp, against
// the fade's own full-surface fill.
let clearSeats = player =>
  if player.options.keepSeatsClear {
    Canvas.context2d(player.canvas)->Option.forEach(ctx => {
      let stage = stageOf(player)
      let seats = Array.length(stage.seats)
      let cardWidth = player.options.cardWidth
      stage.seats->Array.forEachWithIndex(((x, y), seat) =>
        if seatIsOccupied(~launched=player.run.launched, ~armed=player.armed, ~seats, ~seat) {
          ctx->Canvas.clearRect(
            x *. cardWidth,
            y *. cardWidth,
            cardWidth,
            cardWidth *. CardArt.aspect,
          )
        }
      )
    })
  }

// The fade owed for the simulated time since it was last paid, left to accrue until the
// step says take it. It is taken just before a stamp, so what goes down after it — this
// card, or this whole rank of them — is on the surface at full strength.
//
// What is owed is a *share*, so accruing changes only when the fade lands and never how
// much of it lands: a stretch of simulated time is worth the same whether it is taken in
// one step or in ten (`fadeShare` compounds, which is what makes that true).
//
// The rect is the backing store's own size read back in CSS pixels rather than the
// element's box: the same rectangle, without a layout read per stamp.
let dim = (player, ~seats) => {
  let {persistence, step} = player.options.fade
  // Derived here rather than held, so a persistence counted in cards or in runs follows
  // the launch interval while it is being dragged — and so `Cards(9)` is nine cards on a
  // short deck's victory as much as on a full one.
  let rate = fadeRate(
    ~seconds=persistenceSeconds(
      persistence,
      ~launchMs=player.options.knobs.launchMs,
      ~cards=Array.length(player.run.cards),
    ),
  )
  player.fadeOwedMs = player.fadeOwedMs +. player.options.stampMs
  let share = fadeShare(~rate, ~ms=player.fadeOwedMs)
  let layer = layerOf(~launched=player.run.launched, ~seats)
  let due = switch step {
  | Coin(coin) => share >= coin
  | Layer => layer > player.paidLayer
  }

  // `> 0.` as well as the step: a rate of zero owes nothing, and a coin of zero would
  // otherwise buy a full-surface fill every stamp that takes nothing off.
  if share > 0. && due {
    player.fadeOwedMs = 0.
    player.paidLayer = layer
    Canvas.context2d(player.canvas)->Option.forEach(ctx => {
      let scale = ratio()
      Canvas.dim(
        ctx,
        ~width=Int.toFloat(Canvas.pixelWidth(player.canvas)) /. scale,
        ~height=Int.toFloat(Canvas.pixelHeight(player.canvas)) /. scale,
        ~share,
      )
    })
  }
}

// One stamp of the cards in flight, over whatever is already there — the surface is never
// cleared, only faded, because the trail is the effect.
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

  // Put out whatever is now within `readyMs` of going, *before* announcing what has gone:
  // a card armed and launched in the same step has to be put out and taken away in that
  // order, or a caller showing it would be showing a card that has already left.
  let armedNow = armedBy(
    ~launched=player.run.launched,
    ~cards=Array.length(player.run.cards),
    ~seats=Array.length(stage.seats),
    ~sinceLaunchMs=player.run.sinceLaunch *. 1000.,
    ~launchMs=player.options.knobs.launchMs,
    ~readyMs=player.options.readyMs,
  )
  for i in player.armed to armedNow - 1 {
    player.run.cards->Array.get(i)->Option.forEach(player.onReady)
  }
  player.armed = armedNow

  // A step can launch more than one card — a launch interval shorter than the step, or a
  // frame that owed several steps — so this is a range rather than a comparison.
  for i in launchedBefore to player.run.launched - 1 {
    player.run.cards->Array.get(i)->Option.forEach(player.onLaunch)
  }
  player.sinceStamp = player.sinceStamp +. stepMs
  if player.sinceStamp >= player.options.stampMs {
    dim(player, ~seats=Array.length(stage.seats))
    clearSeats(player)
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
  player.fadeOwedMs = 0.
  player.paidLayer = 0
  player.armed = 0
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
  ~onReady=(_: Deck.card) => (),
) => {
  let player = {
    canvas,
    onChange,
    onLaunch,
    onReady,
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
    fadeOwedMs: 0.,
    paidLayer: 0,
    armed: 0,
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
