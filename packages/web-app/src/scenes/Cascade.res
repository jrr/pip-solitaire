// The cascade's motion: a run is a value and `step` is the only thing that moves it — no
// canvas, no DOM, no clock, which is what lets `Cascade_test` check it without a browser.
// Card-widths and seconds throughout; pixels and metres are conversions at the edges.
//
// `docs/cascade.md` is the model — the units, the integration, the aim, the spreads. Read
// it before retuning.

let cardHeight = CardArt.aspect

// A card-width is a real length (`CardArt.widthMetres`), so a gravity can be read in m/s².
// For people: the simulation never leaves card-widths.
let metresPerCardWidth = CardArt.widthMetres
let toMetric = value => value *. metresPerCardWidth
let fromMetric = value => value /. metresPerCardWidth
let earthGravity = 9.80665

// `bounciness` and `bounces` are the card's own, drawn at launch, so it keeps what it left
// with. `bounces` is what the table has left to give this card, floor and sides out of the
// one purse: at zero nothing catches it any more and it leaves whichever way it was going.
type flyer = {
  card: Deck.card,
  x: float,
  y: float,
  vx: float,
  vy: float,
  bounciness: float,
  bounces: int,
}

// Seats are top-left corners, taken in turn — a board's foundations, when a board is
// calling.
type stage = {width: float, height: float, seats: array<(float, float)>}

// The feel, all of it, on sliders in `CascadeScene`: whether a cascade looks right is not
// a question source can answer. Each ± is the band its value is drawn from.
type knobs = {
  gravity: float, // card-widths / s²
  bounciness: float, // the share of falling speed a bounce keeps
  bouncinessVariance: float,
  numBounces: int, // how many times the table catches a card before letting it through
  numBouncesVariance: int,
  speed: float, // horizontal launch speed, card-widths / s
  speedVariance: float,
  launchMs: float, // between one card leaving and the next
}

// Dragged out of the scene, and written in the unit its sliders read.
let defaults = {
  gravity: fromMetric(4.),
  bounciness: 0.8,
  bouncinessVariance: 0.15,
  numBounces: 3,
  numBouncesVariance: 2,
  speed: fromMetric(0.4),
  speedVariance: fromMetric(0.1),
  launchMs: 750.,
}

// `cards` is the launch order and never changes; `launched` is how far into it we are.
type t = {
  rng: int,
  cards: array<Deck.card>,
  launched: int,
  flying: array<flyer>,
  sinceLaunch: float, // seconds since the last card went
  retired: int,
}

// Long enough that an ordinary stutter passes through unaltered, short enough that a card
// moves a fraction of its own width in one.
let maxStep = 0.05

// The next PRNG state, and a float in [0, 1).
let draw = (state: int) => {
  let next = Cards.xorshift(state)
  (next, Int.toFloat(next->Int.bitwiseAnd(0x7fffffff)) /. 2147483648.)
}

// Which suit ended up on which foundation — the one thing a finished game varies, so the
// one thing the seed picks. A one-rank deck shuffled is exactly a permutation of the four.
let foundationSuits = (~seed) =>
  Cards.shuffle(~deck={suits: Cards.suits, ranks: [Deck.Ace]}, ~seed)->Array.map(card => card.suit)

// The deck in the order a won game gives it up: four A→K foundations taken from the top,
// one pile at a time, so the aces go last. Same round-robin `step` seats a card by, which
// is what keeps a suit falling from its own foundation.
let foundationOrder = (~seed): array<Deck.card> => {
  let suits = foundationSuits(~seed)
  Cards.ranks
  ->Array.toReversed
  ->Array.flatMap(rank => suits->Array.map((suit): Deck.card => {suit, rank}))
}

let make = (~seed: int, ~cards: option<array<Deck.card>>=?) => {
  rng: Cards.seedState(seed),
  cards: cards->Option.getOr(foundationOrder(~seed)),
  launched: 0,
  flying: [],
  sinceLaunch: 0.,
  retired: 0,
}

// The card's *top* when it rests on the bottom of the stage. Never above the ceiling, so a
// stage shorter than a card still has a floor a card can be put on.
let floorOf = (stage: stage) => Math.max(stage.height -. cardHeight, 0.)

// The card's *left* when it rests against the right-hand wall; the left-hand one is 0. Never
// left of that, so a stage narrower than a card still has two walls a card can be between.
let rightWallOf = (stage: stage) => Math.max(stage.width -. 1., 0.)

// `value ± variance`, uniform, one draw. Clamped because a spread can be wider than its
// value: a negative speed would be a direction, and a bounciness over 1 never comes down.
let scatter = (~value, ~variance, ~low, ~high, unit) =>
  Math.min(Math.max(value +. (unit *. 2. -. 1.) *. variance, low), high)

// The integer twin, for a band that is a count of whole things: every number in it is
// equally likely. Rounding a scattered float instead would give the two ends half the
// weight of every number between them, which for `5 ± 3` is a visible lean off the ends.
let scatterCount = (~value, ~variance, unit) => {
  let low = Math.Int.max(value - variance, 0)
  let span = Math.Int.max(value + variance, low) - low + 1
  low + Math.Int.min(Float.toInt(unit *. Int.toFloat(span)), span - 1)
}

// Nothing is thrown upwards, so every card traces the same parabola family and the picture
// reads as one cascade rather than 52 throws. Which way is a fair coin, whatever room the
// seat has each way: the near wall a card is thrown at turns it back rather than taking it
// off the table a card-width from its seat.
let spawn = (rng, ~knobs, ~card, ~seat) => {
  let (rng, speedDraw) = draw(rng)
  let (rng, sideDraw) = draw(rng)
  let (rng, bounceDraw) = draw(rng)
  let (rng, countDraw) = draw(rng)
  let (seatX, seatY) = seat
  let speed = scatter(
    ~value=knobs.speed,
    ~variance=knobs.speedVariance,
    ~low=0.,
    ~high=Float.Constants.positiveInfinity,
    speedDraw,
  )
  let bounciness = scatter(
    ~value=knobs.bounciness,
    ~variance=knobs.bouncinessVariance,
    ~low=0.,
    ~high=1.,
    bounceDraw,
  )
  let bounces = scatterCount(~value=knobs.numBounces, ~variance=knobs.numBouncesVariance, countDraw)
  let rightward = sideDraw < 0.5
  (rng, {card, x: seatX, y: seatY, vx: rightward ? speed : -.speed, vy: 0., bounciness, bounces})
}

// The floor is caught by position rather than by reflecting the overshoot, so no step size
// can tunnel a card through it. What does put a card through it is running out of bounces:
// the floor stops catching that card and it falls out of the bottom of the stage.
//
// A contact spends a bounce only if it sends the card back up. A floor with no give holds
// the card where it landed instead of jittering it a bounce a frame into the cellar — which
// is what a bounciness of zero has to keep looking like.
let offFloor = (flyer, ~stage) => {
  let floor = floorOf(stage)
  if flyer.y >= floor && flyer.vy > 0. && flyer.bounces > 0 {
    let rebound = -.flyer.vy *. flyer.bounciness
    {
      ...flyer,
      y: floor,
      vy: rebound,
      bounces: rebound < 0. ? flyer.bounces - 1 : flyer.bounces,
    }
  } else {
    flyer
  }
}

// The sides, caught the same way and spent out of the same purse: a card is turned back while
// it has a bounce to spend and goes over the side once it hasn't, which is what leaves a way
// out of a box with walls on it.
//
// What a wall does *not* do is hold a card it can't turn back. The floor can, because gravity
// is what put the card there; a card held by a dead wall is resting on a floor that won't drop
// it with no speed left to carry it anywhere, and a cascade whose last card never leaves never
// ends. So at zero bounciness the card slides straight out over the side.
let offWalls = (flyer, ~stage) => {
  let rebound = -.flyer.vx *. flyer.bounciness
  let right = rightWallOf(stage)
  if flyer.bounces <= 0 {
    flyer
  } else if flyer.x <= 0. && flyer.vx < 0. && rebound > 0. {
    {...flyer, x: 0., vx: rebound, bounces: flyer.bounces - 1}
  } else if flyer.x >= right && flyer.vx > 0. && rebound < 0. {
    {...flyer, x: right, vx: rebound, bounces: flyer.bounces - 1}
  } else {
    flyer
  }
}

let advance = (flyer, ~knobs, ~stage, ~dt) => {
  let vy = flyer.vy +. knobs.gravity *. dt
  {...flyer, x: flyer.x +. flyer.vx *. dt, y: flyer.y +. vy *. dt, vy}
  ->offFloor(~stage)
  ->offWalls(~stage)
}

// The whole card, so it doesn't blink out with an edge still showing — downwards as well as
// sideways, because a card out of bounces leaves whichever way it was already going.
let hasLeft = (flyer, ~stage: stage) =>
  flyer.x +. 1. < 0. || flyer.x > stage.width || flyer.y > stage.height

let isDone = run => run.launched == Array.length(run.cards) && Array.length(run.flying) == 0

// Move what is in the air, drop what has left, launch what has come due. `dt` is clamped
// here rather than trusted: a tab returning from the background hands over seconds.
let step = (run, ~knobs, ~stage, ~dt) => {
  let dt = Math.min(Math.max(dt, 0.), maxStep)
  // A zero interval would spin the loop below forever.
  let interval = Math.max(knobs.launchMs, 1.) /. 1000.

  let flying =
    run.flying
    ->Array.map(flyer => advance(flyer, ~knobs, ~stage, ~dt))
    ->Array.filter(flyer => !hasLeft(flyer, ~stage))
  let retired = run.retired + (Array.length(run.flying) - Array.length(flying))

  let rng = ref(run.rng)
  let launched = ref(run.launched)
  let sinceLaunch = ref(run.sinceLaunch +. dt)
  let seats = Array.length(stage.seats)
  let total = Array.length(run.cards)

  // The first card leaves on the first step — waiting an interval for it reads as the
  // scene not having started. After that the remainder is carried, so a launch rate
  // faster than the frame rate still comes out right.
  while launched.contents < total && (launched.contents == 0 || sinceLaunch.contents >= interval) {
    let card = run.cards->Array.getUnsafe(launched.contents)
    let seat = seats == 0 ? (0., 0.) : stage.seats->Array.getUnsafe(mod(launched.contents, seats))
    let (next, flyer) = spawn(rng.contents, ~knobs, ~card, ~seat)
    rng := next
    flying->Array.push(flyer)
    launched := launched.contents + 1
    sinceLaunch := (launched.contents == 1 ? 0. : sinceLaunch.contents -. interval)
  }

  {
    rng: rng.contents,
    cards: run.cards,
    launched: launched.contents,
    flying,
    sinceLaunch: sinceLaunch.contents,
    retired,
  }
}

// --- Card-widths from pixels ---------------------------------------------------

// Clear of the top edge, high enough that the first fall is most of the stage.
let seatTop = 0.12

// The demo's stand-in for a row of foundations: `count` seats evenly across the top.
let spreadSeats = (~width, ~count) =>
  Array.fromInitializer(~length=count, index => (
    width *. Int.toFloat(index + 1) /. Int.toFloat(count + 1) -. 0.5,
    seatTop,
  ))

// A CSS-pixel box in card-widths — the one conversion in the model. Separate from the
// stage it usually becomes, because a caller whose seats are its own still measures its
// arena by this and no other arithmetic.
let arenaOf = (~cssWidth, ~cssHeight, ~cardWidth) => {
  let scale = Math.max(cardWidth, 1.)
  (cssWidth /. scale, cssHeight /. scale)
}

let stageOf = (~cssWidth, ~cssHeight, ~cardWidth, ~seats=4) => {
  let (width, height) = arenaOf(~cssWidth, ~cssHeight, ~cardWidth)
  {width, height, seats: spreadSeats(~width, ~count=seats)}
}

// A CSS coordinate onto the device-pixel grid, so a blit is a copy rather than a resample
// (`docs/cascade.md`). Snap the drawing, never the simulation: a quantised position feeds
// back into the next bounce.
let snapToDevice = (value, ~ratio) => ratio > 0. ? Math.round(value *. ratio) /. ratio : value
